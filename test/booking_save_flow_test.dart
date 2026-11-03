import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:my_first_app/dialogs/booking_dialog.dart';
import 'package:my_first_app/models/customer.dart';
import 'package:my_first_app/models/room.dart';
import 'package:my_first_app/services/hotel_data_buffer.dart';
import 'package:my_first_app/stores/customer_store.dart';
import 'package:my_first_app/theme/app_theme.dart';

void main() {
  setUp(() {
    HotelDataBuffer.clearSession();
    CustomerStore.customers.clear();
  });
  tearDown(() {
    HotelDataBuffer.clearSession();
    CustomerStore.customers.clear();
  });
  testWidgets(
    'photos finish before booking; failure preserves the form for retry',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final photo = base64Encode(img.encodePng(img.Image(width: 2, height: 2)));
      CustomerStore.customers.add(
        Customer(
          mobile: '9000000000',
          guestName: 'Test Guest',
          idType: 'Test ID',
          idNumber: 'TEST123',
          idFrontPhotoPath: photo,
          idBackPhotoPath: photo,
        ),
      );
      final room = Room(
        roomNumber: 101,
        roomType: 'Standard',
        normalRent: 1500,
      );
      final photoUpload = Completer<void>();
      var attempts = 0, roomSaves = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => unawaited(
                  showBookingDialog(
                    context,
                    room,
                    prepareGuests: () async {
                      attempts++;
                      if (attempts == 1) {
                        await photoUpload.future;
                        throw StateError('Photo upload failed. Retry.');
                      }
                    },
                    saveBooking: (draft) async {
                      roomSaves++;
                      expect(attempts, 2);
                      expect(draft.status, 'BOOKED');
                      room.copyFrom(draft);
                    },
                  ),
                ),
                child: const Text('Book'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm booking'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid 10-digit guest mobile number.'),
        findsAtLeastNWidgets(1),
      );
      final mobile = find.widgetWithText(TextFormField, 'Mobile Number *');
      await tester.ensureVisible(mobile);
      await tester.enterText(mobile, '9000000000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm booking'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(attempts, 1);
      expect(roomSaves, 0);
      expect(room.status, 'EMPTY');
      expect(find.text('Saving guest ID photos…'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Close sheet',
              ),
            )
            .onPressed,
        isNull,
      );
      photoUpload.complete();
      await tester.pumpAndSettle();
      expect(find.text('Photo upload failed. Retry.'), findsAtLeastNWidgets(1));
      expect(room.status, 'EMPTY');
      expect(find.widgetWithText(TextFormField, 'Test Guest'), findsOneWidget);
      await tester.tap(find.text('Confirm booking'));
      await tester.pumpAndSettle();
      expect(roomSaves, 1);
      expect(room.status, 'BOOKED');
      expect(find.text('Book Room 101'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

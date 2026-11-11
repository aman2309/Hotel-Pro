import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_first_app/dialogs/booking_view_dialog.dart';
import 'package:my_first_app/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:my_first_app/dialogs/booking_slip_dialog.dart';
import 'package:my_first_app/models/room.dart';
import 'package:my_first_app/models/customer.dart';
import 'package:my_first_app/stores/customer_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('booking PDF builds with ID photos and many guests', () async {
    final photo = base64Encode(img.encodeJpg(img.Image(width: 24, height: 16)));
    CustomerStore.customers.add(
      Customer(
        mobile: '9999999999',
        guestName: 'Test Guest',
        idType: 'Aadhaar',
        idNumber: '1234',
        idFrontPhotoPath: photo,
        idBackPhotoPath: photo,
      ),
    );
    addTearDown(CustomerStore.customers.clear);
    final room = Room(
      roomNumber: 101,
      roomType: 'Deluxe',
      normalRent: 1500,
      guestName: 'Test Guest',
      mobile: '9999999999',
    );
    room.extraGuests = List.generate(
      8,
      (i) => {
        'name': 'Guest $i',
        'mobile': '',
        'idNumber': '1234',
        'idFrontPhoto': photo,
        'idBackPhoto': photo,
      },
    );
    final bytes = await buildBookingSlipPdf(room);
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    await File('/tmp/hotel-booking-photos-test.pdf').writeAsBytes(bytes);
  });
  test(
    'current and future booking exports are separate and native print/share receive PDFs',
    () async {
      final room = Room(
        roomNumber: 101,
        roomType: 'Deluxe',
        normalRent: 987654,
        guestName: 'CURRENT_ONLY_GUEST',
        mobile: '9999999999',
        futureBooking: true,
        futureGuestName: 'FUTURE_ONLY_GUEST',
        futureMobile: '8888888888',
      );
      final current = await buildBookingSlipPdf(room, showFutureBooking: false);
      final future = await buildBookingSlipPdf(room, showFutureBooking: true);
      await File('/tmp/hotel-current-booking-test.pdf').writeAsBytes(current);
      await File('/tmp/hotel-future-booking-test.pdf').writeAsBytes(future);
      final calls = <String>[];
      const channel = MethodChannel('net.nfet.printing');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'sharePdf') {
          final bytes = (call.arguments as Map)['doc'] as Uint8List;
          expect(ascii.decode(bytes.take(4).toList()), '%PDF');
        }
        if (call.method == 'printPdf') {
          final args = call.arguments as Map;
          final completed = Completer<void>();
          // Simulate the Android print service completing its dialog.
          messenger.handlePlatformMessage(
            'net.nfet.printing',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('onCompleted', {
                'job': args['job'],
                'completed': true,
              }),
            ),
            (_) => completed.complete(),
          );
          await completed.future;
        }
        return 1;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await shareBookingSlip(room, showFutureBooking: false);
      await printBookingSlip(room, showFutureBooking: true);
      expect(calls, containsAll(['sharePdf', 'printPdf']));
    },
  );

  test('bad ID bytes do not break the booking PDF', () async {
    final guest = Customer(
      mobile: '7777777777',
      guestName: 'Bad photo',
      idType: 'Aadhaar',
      idNumber: '1234',
      idFrontPhotoPath: base64Encode(List.filled(100, 1)),
    );
    CustomerStore.customers.add(guest);
    addTearDown(CustomerStore.customers.clear);
    final bytes = await buildBookingSlipPdf(
      Room(
        roomNumber: 102,
        roomType: 'Deluxe',
        normalRent: 1000,
        guestName: guest.guestName,
        mobile: guest.mobile,
      ),
      showFutureBooking: false,
    );
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
  });

  testWidgets(
    'future booking print view keeps photos and excludes current guest and room rent',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final room = Room(
        roomNumber: 101,
        roomType: 'Deluxe',
        normalRent: 987654,
        guestName: 'Current guest',
        mobile: '9999999999',
        futureBooking: true,
        futureGuestName: 'Future guest',
        futureMobile: '8888888888',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => unawaited(
                  showBookingViewDialog(context, room, showFutureBooking: true),
                ),
                child: const Text('View booking'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('View booking'));
      await tester.pumpAndSettle();
      expect(find.text('Room Rent'), findsNothing);
      expect(find.textContaining('987654'), findsNothing);
      await tester.ensureVisible(find.text('Preview'));
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.text('Room 101 Booking Slip'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BookingSlipDialog),
          matching: find.text('Future guest'),
        ),
        findsOneWidget,
      );
      expect(find.text('Current guest'), findsNothing);
      expect(find.text('AADHAAR FRONT'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BookingSlipDialog),
          matching: find.text('Send PDF'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('single ID photo exports as a printable PDF', () async {
    final bytes = await buildGuestPhotoPdf(
      'ID FRONT PHOTO',
      Uint8List.fromList(img.encodeJpg(img.Image(width: 32, height: 20))),
    );
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
  });
}

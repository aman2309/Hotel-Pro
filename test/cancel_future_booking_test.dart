import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/dialogs/cancel_future_booking_sheet.dart';
import 'package:my_first_app/models/room.dart';

void main() {
  test('clearing a future reservation preserves any ongoing stay', () {
    for (final status in ['EMPTY', 'BOOKED', 'CLEANING', 'CLOSED']) {
      final room = Room(
        roomNumber: 101,
        roomType: 'Standard',
        normalRent: 1000,
        status: status,
        guestName: 'Current guest',
        advance: 500,
        futureBooking: true,
        futureGuestName: 'Future guest',
        futureMobile: '9000000000',
        futureBookingDate: DateTime(2030),
        futureBookingEnd: DateTime(2030, 1, 2),
        futureAdvance: 200,
        futureDays: 1,
        futureExtraGuests: [
          {'name': 'Extra guest'},
        ],
      );
      room.clearFutureBooking();
      final restored = Room.fromJson(room.toJson());
      expect(restored.futureBooking, isFalse);
      expect(restored.futureGuestName, isEmpty);
      expect(restored.futureMobile, isEmpty);
      expect(restored.futureBookingDate, isNull);
      expect(restored.futureBookingEnd, isNull);
      expect(restored.futureAdvance, 0);
      expect(restored.futureDays, 0);
      expect(restored.futureExtraGuests, isEmpty);
      expect(restored.status, status);
      expect(restored.guestName, 'Current guest');
      expect(restored.advance, 500);
    }
  });
  testWidgets(
    'cancellation needs explicit confirmation and shows advance information',
    (tester) async {
      final room = Room(
        roomNumber: 101,
        roomType: 'Standard',
        normalRent: 1000,
        futureBooking: true,
        futureGuestName: 'Future guest',
        futureAdvance: 200,
      );
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showCancelFutureBookingSheet(context, room);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Arrange any refund separately.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Keep booking'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(room.futureBooking, isTrue);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel future booking'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

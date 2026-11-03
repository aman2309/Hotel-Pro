import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/models/room.dart';
import 'package:my_first_app/models/bill_record.dart';
import 'package:my_first_app/utils/stay_duration.dart';
import 'package:my_first_app/widgets/live_stay_duration.dart';

void main() {
  final start = DateTime.utc(2026, 11, 3, 8);
  test(
    'elapsed uses total hours and minutes, including stays longer than a day',
    () {
      expect(
        stayDurationLabel(
          start,
          now: start.add(const Duration(hours: 2, minutes: 15)),
        ),
        '2 hr 15 min',
      );
      expect(
        stayDurationLabel(
          start,
          now: start.add(const Duration(hours: 27, minutes: 3)),
        ),
        '27 hr 3 min',
      );
      expect(
        stayDurationLabel(start, now: start.subtract(const Duration(hours: 1))),
        '0 hr 0 min',
      );
      expect(stayDurationLabel(null), '-');
    },
  );
  test(
    'checkout freezes room and bill durations after serialization/reinstall',
    () {
      final end = start.add(const Duration(hours: 3, minutes: 42));
      final room = Room(
        roomNumber: 101,
        roomType: 'Standard',
        normalRent: 1500,
        bookingTime: start,
        checkoutTime: end,
        status: 'CLEANING',
      );
      expect(
        Room.fromJson(
          room.toJson(),
        ).stayDurationLabel(start.add(const Duration(days: 30))),
        '3 hr 42 min',
      );
      final bill = BillRecord.fromJson({
        'bookingTime': start.toIso8601String(),
        'checkoutTime': end.toIso8601String(),
      });
      expect(bill.finalStayMinutes, 222);
      expect(bill.toJson()['stayDurationMinutes'], 222);
      expect(
        BillRecord.fromJson(
          bill.toJson(),
        ).stayDurationLabel(start.add(const Duration(days: 90))),
        '3 hr 42 min',
      );
    },
  );
  test('active duration does not add a changing counter to room snapshots', () {
    final room = Room(
      roomNumber: 101,
      roomType: 'Standard',
      normalRent: 1500,
      bookingTime: start,
      status: 'BOOKED',
    );
    final before = room.toJson();
    room.stayDurationLabel(start.add(const Duration(hours: 5)));
    expect(room.toJson(), before);
    expect(before.containsKey('stayDurationMinutes'), isFalse);
  });
  testWidgets('live label advances and becomes fixed when checkout arrives', (
    tester,
  ) async {
    final activeStart = start;
    var clock = start.add(const Duration(hours: 2, minutes: 15));
    Future<void> show(DateTime? checkout) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveStayDuration(
            start: activeStart,
            checkout: checkout,
            now: () => clock,
          ),
        ),
      ),
    );
    await show(null);
    expect(find.text('2 hr 15 min'), findsOneWidget);
    clock = clock.add(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2 hr 16 min'), findsOneWidget);
    await show(activeStart.add(const Duration(hours: 3, minutes: 42)));
    expect(find.text('3 hr 42 min'), findsOneWidget);
    await tester.pump(const Duration(minutes: 10));
    expect(find.text('3 hr 42 min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}

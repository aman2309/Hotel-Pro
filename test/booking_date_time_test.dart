import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/dialogs/booking_dialog.dart';
import 'package:my_first_app/models/room.dart';
import 'package:my_first_app/theme/app_theme.dart';
import 'package:my_first_app/widgets/date_time_field.dart';

void main() {
  testWidgets(
    'booking dates, exact times and stay length update together without losing guest input',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Book'),
                onPressed: () => unawaited(
                  showBookingDialog(
                    context,
                    Room(roomNumber: 101, roomType: 'Deluxe', normalRent: 1500),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();
      final name = find.widgetWithText(TextFormField, 'Guest Name *');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Test Guest');
      final inputRects = find
          .byType(TextFormField)
          .evaluate()
          .take(2)
          .map((e) => tester.getRect(find.byWidget(e.widget)))
          .toList();
      expect(
        inputRects[1].top - inputRects[0].bottom,
        greaterThanOrEqualTo(12),
      );
      Future<void> openField(String label) async {
        final field = find.byWidgetPredicate(
          (w) => w is DateTimeField && w.label == label,
        );
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
      }

      await openField('Check-in time');
      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .onDateTimeChanged(DateTime(2000, 1, 1, 21, 37));
      await tester.tap(find.text('Use time'));
      await tester.pumpAndSettle();
      final checkin = tester.widget<DateTimeField>(
        find.byWidgetPredicate(
          (w) => w is DateTimeField && w.label == 'Check-in time',
        ),
      );
      expect(checkin.value, '9:37 PM');
      await openField('Check-out time');
      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .onDateTimeChanged(DateTime(2000, 1, 1, 11, 45));
      await tester.tap(find.text('Use time'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DateTimeField>(
              find.byWidgetPredicate(
                (w) => w is DateTimeField && w.label == 'Check-out time',
              ),
            )
            .value,
        '11:45 AM',
      );
      await openField('Check-out date');
      final now = DateTime.now(),
          checkout = DateTime(now.year, now.month, now.day + 3);
      tester
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(checkout);
      await tester.tap(find.text('Use date'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Number of Days *'),
            )
            .controller!
            .text,
        '3',
      );
      expect(tester.widget<TextFormField>(name).controller!.text, 'Test Guest');
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

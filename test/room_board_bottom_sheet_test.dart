import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/models/room.dart';
import 'package:my_first_app/screens/hotel_dashboard_view.dart';
import 'package:my_first_app/theme/app_theme.dart';
import 'package:my_first_app/theme/custom_colors.dart';
import 'package:my_first_app/widgets/custom_bottom_sheet.dart';
import 'package:my_first_app/widgets/custom_dialog.dart';
import 'package:my_first_app/widgets/custom_dropdown.dart';
import 'package:my_first_app/widgets/hotel_room_card.dart';

void main() {
  testWidgets(
    'all rooms appear on Home with compact status counts and no floor selection',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rooms = List.generate(
        30,
        (i) => Room(
          roomNumber: 101 + i,
          floorId: 'ground',
          roomType: 'Deluxe',
          normalRent: 1000,
          status: ['EMPTY', 'BOOKED', 'CLEANING', 'CLOSED'][i % 4],
        ),
      );
      Room? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HotelDashboardView(
            hotelName: 'Hotel Pro',
            rooms: rooms,
            onAction: (_) {},
            onOpenRoom: (room) => opened = room,
            onRefresh: () async {},
          ),
        ),
      );
      expect(find.byType(HotelRoomCard), findsWidgets);
      expect(find.text('Create floor'), findsNothing);
      await tester.pumpAndSettle();
      final navTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
      final fullyVisible = find.byType(HotelRoomCard).evaluate().where((e) {
        final rect = tester.getRect(find.byWidget(e.widget));
        return rect.top >= 56 && rect.bottom <= navTop;
      }).length;
      expect(fullyVisible, greaterThanOrEqualTo(12));
      final greenCard = find
          .byWidgetPredicate(
            (w) => w is HotelRoomCard && w.room.status == 'EMPTY',
          )
          .first;
      expect(
        tester
            .widget<Material>(
              find
                  .descendant(of: greenCard, matching: find.byType(Material))
                  .first,
            )
            .color,
        CustomColors.availableTint,
      );
      await tester.tap(greenCard);
      expect(opened?.roomNumber, 101);
      await tester.tap(find.text('Booked').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<HotelRoomCard>(find.byType(HotelRoomCard))
            .every((c) => c.room.status == 'BOOKED'),
        isTrue,
      );
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Hotel tools'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dropdown options use a sheet and retain form validation', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Form(
            key: form,
            child: CustomDropdown<String>(
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'upi', child: Text('UPI')),
              ],
              decoration: const InputDecoration(labelText: 'Payment method'),
              validator: (value) =>
                  value == null ? 'Choose payment method' : null,
              onChanged: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    await tester.tap(find.byType(CustomDropdown<String>));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text('UPI'));
    await tester.pumpAndSettle();
    expect(selected, 'upi');
    expect(form.currentState!.validate(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('date selection fits a short landscape sheet', (tester) async {
    tester.view.physicalSize = const Size(740, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DateTime? picked;
    final date = DateTime(2026, 11, 3);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Date'),
              onPressed: () async {
                picked = await showCustomDateSheet(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2026),
                  lastDate: DateTime(2027),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use date'));
    await tester.pumpAndSettle();
    expect(picked, date);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheets return results and keep actions above keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    bool? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open'),
              onPressed: () async {
                saved = await showCustomBottomSheet<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => CustomDialog(
                    title: const Text('Edit room'),
                    content: const SizedBox(height: 550, child: TextField()),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.getBottomLeft(find.text('Save')).dy, lessThan(380));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });
}

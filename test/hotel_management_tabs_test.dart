import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/models/room.dart';
import 'package:my_first_app/screens/hotel_dashboard_view.dart';
import 'package:my_first_app/stores/hotel_settings_store.dart';
import 'package:my_first_app/theme/app_theme.dart';
import 'package:my_first_app/widgets/custom_button.dart';
import 'package:my_first_app/widgets/hotel_settings_form.dart';

void main() {
  testWidgets(
    'edit/delete target the selected room and immediately update Home',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rooms = [
        Room(roomNumber: 101, roomType: 'Standard', normalRent: 0),
        Room(
          roomNumber: 102,
          roomType: 'Deluxe',
          normalRent: 1500,
          status: 'BOOKED',
        ),
        Room(
          roomNumber: 103,
          roomType: 'Standard',
          normalRent: 1000,
          futureBooking: true,
        ),
      ];
      rooms.addAll([
        Room(
          roomNumber: 104,
          roomType: 'Standard',
          normalRent: 1500,
          status: 'CLEANING',
        ),
        Room(
          roomNumber: 105,
          roomType: 'Standard',
          normalRent: 1500,
          status: 'CLOSED',
        ),
      ]);
      Room? edited, deleted;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StatefulBuilder(
            builder: (context, update) => HotelDashboardView(
              hotelName: 'Hotel Pro',
              rooms: rooms,
              onAction: (_) {},
              onOpenRoom: (_) {},
              onRefresh: () async {},
              onEditRoom: (room) async {
                edited = room;
                update(() {
                  room.roomType = 'Suite';
                  room.normalRent = 2200;
                });
              },
              onDeleteRoom: (room) async {
                deleted = room;
                update(() => rooms.remove(room));
              },
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .destinations
            .length,
        4,
      );
      await tester.tap(find.text('Edit rooms'));
      await tester.pumpAndSettle();
      expect(find.text('ROOM 101'), findsOneWidget);
      expect(find.text('ROOM 102'), findsOneWidget);
      expect(find.text('ROOM 103'), findsOneWidget);
      expect(
        tester
            .widget<CustomButton>(find.byKey(const ValueKey('edit-room-102')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<CustomButton>(find.byKey(const ValueKey('delete-room-103')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('edit-room-101')));
      await tester.pumpAndSettle();
      expect(edited, same(rooms.first));
      expect(
        tester
            .widget<CustomButton>(find.byKey(const ValueKey('edit-room-101')))
            .onPressed,
        isNotNull,
      );
      expect(find.text('Suite · ₹2200 / day'), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('₹2200 / day'), findsOneWidget);
      await tester.tap(find.text('Edit rooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-room-101')));
      await tester.pumpAndSettle();
      expect(deleted?.roomNumber, 101);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('edit-room-105')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<CustomButton>(find.byKey(const ValueKey('edit-room-105')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<CustomButton>(find.byKey(const ValueKey('delete-room-104')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('ROOM 101'), findsNothing);
      expect(find.text('All rooms · 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [const Size(320, 640), const Size(740, 360)]) {
    testWidgets('Settings is embedded and keeps its draft at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HotelDashboardView(
            hotelName: 'Hotel Pro',
            rooms: const [],
            onAction: (_) {},
            onOpenRoom: (_) {},
            onRefresh: () async {},
          ),
        ),
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(HotelSettingsForm), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      final name = find.widgetWithText(TextFormField, 'Hotel Name');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'My new hotel');
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(name).controller!.text,
        'My new hotel',
      );
      await tester.scrollUntilVisible(
        find.text('Save settings'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'settings validates and does not pretend to save without Firebase',
    (tester) async {
      final previous = HotelSettingsStore.hotelName;
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: HotelSettingsForm(onSaved: () => saved = true),
            ),
          ),
        ),
      );
      final name = find.widgetWithText(TextFormField, 'Hotel Name');
      await tester.enterText(name, '');
      await tester.ensureVisible(find.text('Save settings'));
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(find.text('Enter hotel name'), findsOneWidget);
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Updated hotel');
      await tester.ensureVisible(find.text('Save settings'));
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(saved, isFalse);
      expect(HotelSettingsStore.hotelName, previous);
      expect(
        find.text(
          'Hotel is not connected yet. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

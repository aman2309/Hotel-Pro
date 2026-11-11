import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/screens/hotel_dashboard_view.dart';
import 'package:my_first_app/models/room.dart';
import 'package:my_first_app/theme/app_theme.dart';
import 'package:my_first_app/widgets/available_room_actions.dart';
import 'package:my_first_app/widgets/custom_bottom_sheet.dart';
import 'package:my_first_app/widgets/hotel_settings_form.dart';
import 'package:my_first_app/widgets/hotel_ui.dart';
import 'package:my_first_app/dialogs/reports_dialog.dart';
import 'package:my_first_app/dialogs/booking_dialog.dart';
import 'package:my_first_app/dialogs/hotel_settings_dialog.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(740, 360)]) {
    testWidgets(
      'temporary-close and four navigation destinations fit $size at large text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var closed = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => HotelDashboardView(
                hotelName: 'Hotel Pro',
                rooms: [
                  Room(roomNumber: 101, roomType: 'Standard', normalRent: 1500),
                ],
                onAction: (_) {},
                onRefresh: () async {},
                onEditRoom: (_) async {},
                onDeleteRoom: (_) async {},
                onOpenRoom: (_) {
                  unawaited(
                    showCustomBottomSheet<void>(
                      context: context,
                      builder: (context) => CustomDialog(
                        title: const Text('ROOM 101'),
                        content: AvailableRoomActions(
                          onBook: () {},
                          onClose: () async {
                            closed = true;
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    ),
                  );
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
        await tester.tap(find.text('ROOM 101'));
        await tester.pumpAndSettle();
        final button = find.widgetWithText(OutlinedButton, 'Temporarily close');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final bounds = tester.getRect(button),
            label = tester.getRect(find.text('Temporarily close'));
        expect(bounds.height, greaterThanOrEqualTo(46));
        expect(label.top, greaterThanOrEqualTo(bounds.top));
        expect(label.bottom, lessThanOrEqualTo(bounds.bottom));
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(closed, isTrue);
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Reports'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Payments received'), findsOneWidget);
        expect(find.text('Hotel tools'), findsNothing);
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Settings'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Hotel tools'), findsOneWidget);
        expect(find.text('Edit hotel information'), findsOneWidget);
        expect(find.byType(HotelSettingsForm), findsNothing);
        await tester.tap(find.text('Edit rooms'));
        await tester.pumpAndSettle();
        final edit = find.byKey(const ValueKey('edit-room-101'));
        final delete = find.byKey(const ValueKey('delete-room-101'));
        await tester.scrollUntilVisible(
          edit,
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final editRect = tester.getRect(edit),
            deleteRect = tester.getRect(delete);
        if (size.width < 400) {
          expect(deleteRect.top, greaterThan(editRect.bottom));
        }
        final surface = find
            .ancestor(of: edit, matching: find.byType(CustomSurface))
            .first;
        final material = find
            .ancestor(of: edit, matching: find.byType(Material))
            .first;
        expect(
          find
              .descendant(of: surface, matching: find.byType(Material))
              .evaluate()
              .where(
                (e) =>
                    tester.widget<Material>(find.byWidget(e.widget)).type ==
                    MaterialType.transparency,
              ),
          isEmpty,
        );
        expect(tester.getRect(material).contains(editRect.topLeft), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'room actions remain reachable with the keyboard in a short window',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      var closed = false;
      Widget host(BuildContext context) {
        Future<void> open() async {
          await showCustomBottomSheet<void>(
            context: context,
            builder: (sheetContext) {
              return CustomDialog(
                title: const Text('ROOM 101'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Available · Standard room'),
                    const SizedBox(height: 20),
                    AvailableRoomActions(
                      onBook: () {},
                      onClose: () async {
                        closed = true;
                        Navigator.pop(sheetContext);
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Close'),
                  ),
                ],
              );
            },
          );
        }

        return Scaffold(
          body: TextButton(onPressed: open, child: const Text('Open')),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Builder(builder: host),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(OutlinedButton, 'Temporarily close');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final entry in <(String, void Function(BuildContext))>[
    ('settings', (context) => unawaited(showHotelSettingsDialog(context))),
    (
      'booking',
      (context) => unawaited(
        showBookingDialog(
          context,
          Room(roomNumber: 101, roomType: 'Standard', normalRent: 1500),
        ),
      ),
    ),
    ('reports', (context) => unawaited(showReportsDialog(context))),
  ]) {
    testWidgets('${entry.$1} sheet fits a short window with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(740, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => entry.$2(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/screens/hotel_dashboard_view.dart';
import 'package:my_first_app/screens/license_screen.dart';
import 'package:my_first_app/widgets/hotel_auth_form.dart';
import 'package:my_first_app/widgets/otp_code_boxes.dart';
import 'package:my_first_app/dialogs/hotel_settings_dialog.dart';
import 'package:my_first_app/dialogs/booking_dialog.dart';
import 'package:my_first_app/dialogs/expenses_dialog.dart';
import 'package:my_first_app/dialogs/reports_dialog.dart';
import 'package:my_first_app/models/room.dart';
import 'package:my_first_app/models/bill_record.dart';
import 'package:my_first_app/models/customer.dart';
import 'package:my_first_app/dialogs/customer_list_dialog.dart';
import 'package:my_first_app/dialogs/room_control_dialog.dart';
import 'package:my_first_app/dialogs/bill_preview_dialog.dart';
import 'package:my_first_app/dialogs/booking_view_dialog.dart';
import 'package:my_first_app/dialogs/backup_restore_dialog.dart';
import 'package:my_first_app/theme/app_theme.dart';

import 'support/fake_phone_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Poppins');
    for (final name in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      fonts.addFont(rootBundle.load('assets/fonts/Poppins-$name.ttf'));
    }
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  final rooms = [
    Room(
      roomNumber: 101,
      floorId: 'ground',
      roomType: 'Deluxe',
      normalRent: 1500,
    ),
    Room(
      roomNumber: 102,
      floorId: 'ground',
      roomType: 'Suite',
      normalRent: 2500,
      status: 'BOOKED',
      guestName: 'Aarav Sharma',
      bookingTime: DateTime(2026, 11, 2, 10),
      days: 2,
    ),
    Room(
      roomNumber: 103,
      floorId: 'ground',
      roomType: 'Deluxe',
      normalRent: 1500,
      status: 'CLEANING',
    ),
    Room(
      roomNumber: 104,
      floorId: 'first',
      roomType: 'Standard',
      normalRent: 1000,
      status: 'CLOSED',
    ),
  ];
  Widget dashboard({ValueChanged<String>? action}) => HotelDashboardView(
    hotelName: 'The Fern Residency',
    rooms: rooms,
    onAction: action ?? (_) {},
    onOpenRoom: (_) {},
    onEditRoom: (_) async {},
    onDeleteRoom: (_) async {},
    onRefresh: () async {},
  );
  for (final size in [
    const Size(320, 720),
    const Size(800, 1024),
    const Size(1280, 800),
    const Size(740, 360),
  ]) {
    testWidgets('modern dashboard fits $size and retains action routes', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: dashboard(action: (s) => picked = s),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('ROOM 101'), findsOneWidget);
      expect(find.text('Create floor'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Settings'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Guests'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guests'));
      await tester.pump();
      expect(picked, 'customers');
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('ROOM 101'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('phone forms fit the new dialog shell', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final open in <void Function(BuildContext)>[
      (c) {
        unawaited(showHotelSettingsDialog(c));
      },
      (c) {
        unawaited(showBookingDialog(c, rooms.first));
      },
      (c) {
        unawaited(showExpensesDialog(c));
      },
      (c) {
        unawaited(showReportsDialog(c));
      },
      (c) {
        unawaited(showCustomerListDialog(c));
      },
      (c) {
        unawaited(
          showEditCustomerDialog(
            c,
            Customer(
              mobile: '9999999999',
              guestName: 'Aarav Sharma',
              idType: 'Aadhaar',
              idNumber: '1234',
            ),
          ),
        );
      },
      (c) {
        unawaited(showRoomControlDialog(c, rooms[1]));
      },
      (c) {
        unawaited(showBookingViewDialog(c, rooms[1]));
      },
      (c) {
        unawaited(
          showBillPreviewDialog(
            c,
            BillRecord.fromJson({
              'billNumber': 'INV-001',
              'guestName': 'Aarav Sharma',
              'mobile': '9999999999',
              'roomNumber': 102,
              'roomType': 'Suite',
              'totalBill': 5000,
              'balance': 4000,
              'advance': 1000,
            }),
          ),
        );
      },
      (c) {
        unawaited(showBackupRestoreDialog(c, onRestoreCompleted: () async {}));
      },
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => open(c),
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
    }
  });
  testWidgets('OTP and membership fit compact screens', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HotelAuthForm(
          isSignup: false,
          service: FakePhoneAuth(),
          onReady: () {},
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, '9999999999');
    await tester.ensureVisible(find.text('Send OTP'));
    await tester.tap(find.text('Send OTP'));
    await tester.pump();
    expect(find.byType(OtpCodeBoxes), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const LicenseScreen(locked: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('render modern dashboard preview', (tester) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RepaintBoundary(key: key, child: dashboard()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = File('docs/validation/modern-ui/dashboard.png');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'docs/validation/modern-ui/rooms.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    for (final section in ['Edit rooms', 'Reports', 'Settings']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(section),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'docs/validation/modern-ui/${section == 'Settings'
              ? 'settings'
              : section == 'Reports'
              ? 'reports'
              : 'edit-rooms'}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
  });
}

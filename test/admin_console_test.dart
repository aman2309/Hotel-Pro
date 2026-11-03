import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/admin/admin_console.dart';
import 'package:my_first_app/admin/admin_api.dart';
import 'package:my_first_app/theme/app_theme.dart';

class FakeAdminApi extends AdminApi {
  final calls = <String>[];
  final hotel = <String, dynamic>{
    'hotelId': 'hotel-test',
    'hotelName': 'Test Hotel',
    'email': 'owner@example.test',
    'phoneNumber': '+919000000000',
    'ownerName': 'Test Owner',
    'enabled': true,
    'status': 'Trial',
    'rooms': {
      'total': 12,
      'available': 10,
      'booked': 2,
      'future': 1,
      'cleaning': 0,
      'closed': 0,
    },
    'license': {},
    'settings': {},
    'guests': 2,
    'analytics': {
      'billed': 1500,
      'expenses': 200,
      'net': 1300,
      'completedStays': 1,
      'series': [],
    },
  };
  @override
  Future<Map<String, dynamic>> call(
    String name, [
    Map<String, dynamic> data = const {},
  ]) async {
    calls.add(name);
    return switch (name) {
      'adminListHotelsV2' => {
        'items': [hotel],
      },
      'adminHotelDetails' => hotel,
      'adminHotelRecords' => {
        'items': [
          {
            'id': 'room_101',
            'roomNumber': 101,
            'roomType': 'Standard',
            'status': 'EMPTY',
            'normalRent': 1000,
          },
        ],
      },
      'adminIssueLicenseKey' => {
        'key': 'HP-AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-AAAA-BBBB',
        'durationMonths': 1,
        'hotelId': 'hotel-test',
      },
      _ => {'items': []},
    };
  }
}

void main() {
  for (final size in [const Size(360, 800), const Size(1440, 1000)]) {
    testWidgets('admin overview and hotel data fit $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = FakeAdminApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminConsole(
            email: 'admin@example.test',
            onSignOut: () async {},
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A clear view of your hotels'), findsOneWidget);
      final hotel = find.text('Test Hotel');
      await tester.ensureVisible(hotel);
      await tester.tap(hotel);
      await tester.pumpAndSettle();
      expect(find.text('Hotel information'), findsOneWidget);
      expect(api.calls, contains('adminHotelDetails'));
      expect(api.calls, contains('adminHotelRecords'));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('admin issues a one-time copyable key through the server', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeAdminApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AdminConsole(
          email: 'admin@example.test',
          onSignOut: () async {},
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate key'));
    await tester.pumpAndSettle();
    expect(find.text('Generate license key'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('Generate key').last);
    await tester.pumpAndSettle();
    expect(api.calls, contains('adminIssueLicenseKey'));
    expect(find.text('Your license key is ready'), findsOneWidget);
    expect(
      find.text('HP-AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-AAAA-BBBB'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

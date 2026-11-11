import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/admin/admin_app.dart';
import 'package:my_first_app/theme/app_theme.dart';

import 'support/fake_phone_auth.dart';

void main() {
  test('only an explicit superadmin build serves the admin portal', () {
    expect(WebPortal.fromEnvironment(), WebPortal.hotel);
  });

  testWidgets('hotel website is mobile OTP only with no admin login', (
    tester,
  ) async {
    final phone = FakePhoneAuth();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AdminLogin(hotelMode: true, phoneService: phone),
      ),
    );
    expect(find.text('YOUR HOTEL WORKSPACE'), findsOneWidget);
    expect(find.text('+91'), findsOneWidget);
    expect(find.text('Super Admin'), findsNothing);
    expect(find.text('Admin email'), findsNothing);
    expect(find.text('Password'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mobile number'),
      '9876543210',
    );
    await tester.ensureVisible(find.text('Send OTP'));
    await tester.tap(find.text('Send OTP'));
    await tester.pump();
    expect(phone.sent, ['+919876543210']);
    expect(phone.draftsAtSend.single, isNull);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Enter OTP'),
      '123456',
    );
    await tester.ensureVisible(find.text('Verify & log in'));
    await tester.tap(find.text('Verify & log in'));
    await tester.pump();
    expect(phone.verifiedCode, '123456');
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin website is email and password only', (tester) async {
    String? adminEmail;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AdminLogin(signIn: (email, password) async => adminEmail = email),
      ),
    );
    expect(find.text('ADMIN WORKSPACE'), findsOneWidget);
    expect(find.text('Hotel Login'), findsNothing);
    expect(find.text('Mobile number'), findsNothing);
    expect(find.text('New to Hotel Pro? Create account'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Admin email'),
      'cloud@admin.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'secret',
    );
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(adminEmail, 'cloud@admin.com');
    expect(tester.takeException(), isNull);
  });
}

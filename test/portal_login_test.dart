import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/admin/admin_app.dart';
import 'package:my_first_app/theme/app_theme.dart';

import 'support/fake_phone_auth.dart';

void main() {
  testWidgets(
    'hotel web login is mobile OTP only and super admin keeps email login',
    (tester) async {
      final phone = FakePhoneAuth();
      String? adminEmail;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminLogin(
            initialHotelMode: true,
            phoneService: phone,
            signIn: (email, password) async => adminEmail = email,
          ),
        ),
      );
      expect(find.text('YOUR HOTEL WORKSPACE'), findsOneWidget);
      expect(find.text('+91'), findsOneWidget);
      expect(find.text('Login email'), findsNothing);
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
      expect(find.text('OTP sent to +919876543210'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter OTP'),
        '123456',
      );
      await tester.ensureVisible(find.text('Verify & log in'));
      await tester.tap(find.text('Verify & log in'));
      await tester.pump();
      expect(phone.verifiedCode, '123456');

      await tester.ensureVisible(find.text('Super Admin'));
      await tester.tap(find.text('Super Admin'));
      await tester.pumpAndSettle();
      expect(find.text('ADMIN WORKSPACE'), findsOneWidget);
      expect(find.text('Mobile number'), findsNothing);
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
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

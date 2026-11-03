import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/admin/admin_app.dart';
import 'package:my_first_app/theme/app_theme.dart';

void main() {
  testWidgets(
    'hotel login uses existing credentials and mode switch clears password',
    (tester) async {
      String? submittedEmail;
      String? submittedPassword;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminLogin(
            initialHotelMode: true,
            signIn: (email, password) async {
              submittedEmail = email;
              submittedPassword = password;
            },
          ),
        ),
      );
      expect(find.text('YOUR HOTEL WORKSPACE'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Login email'),
        'owner@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'OwnerPassword',
      );
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(submittedEmail, 'owner@example.test');
      expect(submittedPassword, 'OwnerPassword');
      await tester.ensureVisible(find.text('Super Admin'));
      await tester.tap(find.text('Super Admin'));
      await tester.pumpAndSettle();
      expect(find.text('ADMIN WORKSPACE'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Password'),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Admin email'),
            )
            .controller!
            .text,
        'owner@example.test',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

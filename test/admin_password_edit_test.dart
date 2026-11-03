import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/admin/admin_app.dart';
import 'package:my_first_app/theme/app_theme.dart';

void main() {
  testWidgets(
    'a rejected admin password can be cleared and replaced without losing email',
    (tester) async {
      var attempts = 0;
      String? retriedPassword;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminLogin(
            signIn: (email, password) async {
              attempts++;
              if (attempts == 1) {
                throw FirebaseAuthException(code: 'invalid-credential');
              }
              retriedPassword = password;
            },
          ),
        ),
      );
      final email = find.widgetWithText(TextFormField, 'Admin email');
      final password = find.widgetWithText(TextFormField, 'Password');
      await tester.enterText(email, 'admin@example.test');
      await tester.enterText(password, 'WrongPassword');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      final field = tester.widget<TextFormField>(password);
      expect(field.enabled, isTrue);
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 13),
      );
      await tester.tap(find.byTooltip('Clear password'));
      await tester.pumpAndSettle();
      expect(field.controller!.text, isEmpty);
      expect(
        tester.widget<TextFormField>(email).controller!.text,
        'admin@example.test',
      );
      expect(find.text('Email or password is incorrect.'), findsNothing);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: password, matching: find.byType(TextField)),
            )
            .obscureText,
        isFalse,
      );
      expect(field.controller!.text, isEmpty);
      await tester.enterText(password, 'ReplacementPassword');
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(password).controller!.text,
        'ReplacementPassword',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(retriedPassword, 'ReplacementPassword');
      expect(tester.takeException(), isNull);
    },
  );
}

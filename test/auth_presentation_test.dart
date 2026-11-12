import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/screens/cpanel_auth_screen.dart';
import 'package:my_first_app/screens/splash_screen.dart';
import 'package:my_first_app/screens/hotel_signup_screen.dart';
import 'package:my_first_app/theme/app_theme.dart';
import 'package:my_first_app/widgets/hotel_auth_form.dart';

import 'support/fake_phone_auth.dart';

void main() {
  testWidgets('login is mobile OTP only and switches to signup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final phone = FakePhoneAuth();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HotelAuthForm(isSignup: false, service: phone, onReady: () {}),
      ),
    );
    final context = tester.element(find.byType(HotelAuthForm));
    expect(Theme.of(context).textTheme.bodyMedium?.fontFamily, 'Poppins');
    expect(find.text('+91'), findsOneWidget);
    expect(find.text('Login ID (email)'), findsNothing);
    expect(find.text('Password'), findsNothing);
    await tester.ensureVisible(find.text('Send OTP'));
    await tester.tap(find.text('Send OTP'));
    await tester.pump();
    expect(find.text('Please enter Mobile number'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '12345');
    await tester.tap(find.text('Send OTP'));
    await tester.pump();
    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    expect(phone.sent, isEmpty);
    await tester.ensureVisible(find.text('New to Hotel Pro? Create account'));
    await tester.tap(find.text('New to Hotel Pro? Create account'));
    await tester.pumpAndSettle();
    expect(find.byType(HotelSignupScreen), findsOneWidget);
    expect(find.text('Make yourself at home.'), findsOneWidget);
    expect(find.text('Owner name'), findsOneWidget);
    expect(find.text('Hotel name'), findsOneWidget);
    expect(find.text('+91'), findsOneWidget);
    expect(find.text('Confirm password'), findsNothing);
    expect(find.text('Password'), findsNothing);
    expect(find.text('Login ID (email)'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('signup sends OTP with owner details and verifies it', (
    tester,
  ) async {
    final phone = FakePhoneAuth();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HotelSignupScreen(service: phone),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Owner name'),
      'Asha Devi',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Hotel name'),
      'Lake View',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mobile number'),
      '9876543210',
    );
    await tester.ensureVisible(find.text('Send OTP'));
    await tester.tap(find.text('Send OTP'));
    await tester.pump();
    expect(phone.sent, ['+919876543210']);
    expect(phone.draftsAtSend.single, {
      'ownerName': 'Asha Devi',
      'hotelName': 'Lake View',
      'mobile': '9876543210',
    });
    expect(find.text('OTP sent to +919876543210'), findsOneWidget);
    expect(find.text('Resend OTP in 30s'), findsOneWidget);
    await tester.ensureVisible(find.text('Verify & create account'));
    await tester.tap(find.text('Verify & create account'));
    await tester.pump();
    expect(find.text('Please enter the 6-digit OTP.'), findsOneWidget);
    expect(phone.verifiedCode, isNull);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Enter OTP'),
      '654321',
    );
    await tester.tap(find.text('Verify & create account'));
    await tester.pump();
    expect(phone.verifiedCode, '654321');

    await tester.pump(const Duration(seconds: 31));
    await tester.ensureVisible(find.text('Resend OTP'));
    await tester.tap(find.text('Resend OTP'));
    await tester.pump();
    expect(phone.sent.length, 2);
    expect(phone.resendTokens.last, 7);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a number without a hotel shows the sign up hint', (
    tester,
  ) async {
    final phone = FakePhoneAuth()
      ..verifyError = StateError(
        'Bad state: No hotel account found. Choose Sign up to create your hotel.',
      );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HotelAuthForm(isSignup: false, service: phone, onReady: () {}),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, '9876543210');
    await tester.ensureVisible(find.text('Send OTP'));
    await tester.tap(find.text('Send OTP'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Enter OTP'),
      '111111',
    );
    await tester.ensureVisible(find.text('Verify & log in'));
    await tester.tap(find.text('Verify & log in'));
    await tester.pump();
    expect(
      find.text('No hotel account found. Choose Sign up to create your hotel.'),
      findsOneWidget,
    );
    expect(phone.draftsAtSend.single, isNull);
    await tester.ensureVisible(find.text('Change number'));
    await tester.tap(find.text('Change number'));
    await tester.pump();
    expect(find.text('+91'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 640),
    const Size(800, 1024),
    const Size(1280, 800),
    const Size(740, 360),
  ]) {
    testWidgets('auth stays usable at ${size.width} x ${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CpanelAuthScreen(onReady: () {}),
        ),
      );
      await tester.ensureVisible(find.text('New to Hotel Pro? Create account'));
      await tester.tap(find.text('New to Hotel Pro? Create account'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Send OTP'));
      expect(find.text('+91'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // An open keyboard and larger text must keep the submit button reachable.
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: CpanelAuthScreen(onReady: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Send OTP'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('splash opens its destination after the animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const SplashScreen(
          destination: Scaffold(body: Text('Destination')),
        ),
      ),
    );
    expect(find.text('Hotel Pro'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

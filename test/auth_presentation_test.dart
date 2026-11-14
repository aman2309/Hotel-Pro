import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/screens/cpanel_auth_screen.dart';
import 'package:my_first_app/screens/splash_screen.dart';
import 'package:my_first_app/screens/hotel_signup_screen.dart';
import 'package:my_first_app/theme/app_theme.dart';
import 'package:my_first_app/widgets/hotel_auth_form.dart';

import 'package:my_first_app/widgets/otp_code_boxes.dart';
import 'package:my_first_app/widgets/phone_otp_form.dart';
import 'package:my_first_app/services/phone_auth_service.dart';

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
    expect(phone.sent, ['9876543210']);
    expect(phone.draftsAtSend.single, {
      'ownerName': 'Asha Devi',
      'hotelName': 'Lake View',
      'mobile': '9876543210',
    });
    expect(find.text('OTP sent to +919876543210'), findsOneWidget);
    expect(find.text('Resend OTP in 30s'), findsOneWidget);
    expect(find.byType(OtpCodeBoxes), findsOneWidget);
    await tester.ensureVisible(find.text('Verify & create account'));
    await tester.tap(find.text('Verify & create account'));
    await tester.pump();
    expect(find.text('Please enter the 4-digit OTP.'), findsOneWidget);
    expect(phone.verifiedCode, isNull);
    // Typing the 4th digit verifies straight away.
    await tester.enterText(find.byKey(OtpCodeBoxes.inputKey), '6543');
    await tester.pump();
    expect(phone.verifiedCode, '6543');

    await tester.pump(const Duration(seconds: 31));
    await tester.ensureVisible(find.text('Resend OTP'));
    await tester.tap(find.text('Resend OTP'));
    await tester.pump();
    expect(phone.sent, ['9876543210', '9876543210']);
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
    await tester.enterText(find.byKey(OtpCodeBoxes.inputKey), '1111');
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

  testWidgets('OTP boxes take a pasted code, backspace and server limits', (
    tester,
  ) async {
    final phone = FakePhoneAuth()
      ..verifyError = const OtpException('Incorrect OTP. Please try again.');
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
    final input = find.byKey(OtpCodeBoxes.inputKey);
    await tester.ensureVisible(input);
    // A pasted SMS fragment keeps only the 4 digits.
    await tester.enterText(input, '12');
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(phone.verifiedCode, isNull);
    await tester.enterText(input, '1');
    await tester.pump();
    expect(find.text('2'), findsNothing);
    await tester.enterText(input, 'OTP 4821 x');
    await tester.pump();
    expect(phone.verifiedCode, '4821');
    expect(find.text('Incorrect OTP. Please try again.'), findsOneWidget);
    for (final digit in ['4', '8', '2']) {
      expect(find.text(digit), findsNothing);
    }

    phone.sendError = const OtpException(
      'Please wait before requesting another OTP.',
      retryAfter: Duration(seconds: 12),
    );
    await tester.pump(const Duration(seconds: 31));
    await tester.ensureVisible(find.text('Resend OTP'));
    await tester.tap(find.text('Resend OTP'));
    await tester.pump();
    expect(
      find.text('Please wait before requesting another OTP.'),
      findsOneWidget,
    );
    expect(find.text('Resend OTP in 12s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android SMS consent fills the boxes and verifies', (
    tester,
  ) async {
    final phone = FakePhoneAuth();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PhoneOtpForm(
            isSignup: false,
            service: phone,
            smsCodeListener: () async => '7305',
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, '9876543210');
    await tester.tap(find.text('Send OTP'));
    await tester.pump();
    await tester.pump();
    expect(phone.verifiedCode, '7305');
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

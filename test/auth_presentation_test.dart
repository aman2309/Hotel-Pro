import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/screens/cpanel_auth_screen.dart';
import 'package:my_first_app/screens/splash_screen.dart';
import 'package:my_first_app/screens/hotel_signup_screen.dart';
import 'package:my_first_app/theme/app_theme.dart';

void main() {
  testWidgets('login validates empty fields and switches to signup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CpanelAuthScreen(onReady: () {}),
      ),
    );
    final context = tester.element(find.byType(CpanelAuthScreen));
    expect(Theme.of(context).textTheme.bodyMedium?.fontFamily, 'Poppins');
    await tester.ensureVisible(find.text('Log in'));
    await tester.tap(find.text('Log in'));
    await tester.pump();
    expect(find.text('Please enter Login ID (email)'), findsOneWidget);
    await tester.ensureVisible(find.text('New to Hotel Pro? Create account'));
    await tester.tap(find.text('New to Hotel Pro? Create account'));
    await tester.pumpAndSettle();
    expect(find.byType(HotelSignupScreen), findsOneWidget);
    expect(find.text('Sign up'), findsNothing);
    expect(find.text('Make yourself at home.'), findsOneWidget);
    expect(find.text('Owner name'), findsOneWidget);
    expect(find.text('+91'), findsOneWidget);
    expect(find.text('Code'), findsNothing);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signup uses a separate route and fresh state on reopening', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CpanelAuthScreen(onReady: () {}),
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'owner@example.com',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'LoginPassword123',
    );
    await tester.ensureVisible(find.text('New to Hotel Pro? Create account'));
    await tester.tap(find.text('New to Hotel Pro? Create account'));
    await tester.pumpAndSettle();
    expect(find.byType(HotelSignupScreen), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(3))
          .controller!
          .text,
      'owner@example.com',
    );
    await tester.ensureVisible(find.byType(TextFormField).at(0));
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Unfinished owner',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(HotelSignupScreen), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!
          .text,
      'LoginPassword123',
    );
    await tester.ensureVisible(find.text('New to Hotel Pro? Create account'));
    await tester.tap(find.text('New to Hotel Pro? Create account'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(0))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(4))
          .controller!
          .text,
      isEmpty,
    );
    Navigator.of(
      tester.element(find.byType(HotelSignupScreen)),
    ).pop('new-owner@example.com');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(0))
          .controller!
          .text,
      'new-owner@example.com',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      find.text(
        'Account created successfully. Please log in with your email and password.',
      ),
      findsOneWidget,
    );
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
      await tester.ensureVisible(find.text('Create account'));
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
      await tester.ensureVisible(find.text('Create account'));
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

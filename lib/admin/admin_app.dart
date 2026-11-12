import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../theme/custom_colors.dart';
import '../widgets/hotel_ui.dart';
import 'admin_console.dart';
import '../app_navigator.dart';
import '../screens/cloud_gate.dart';
import '../screens/hotel_signup_screen.dart';
import '../services/phone_auth_service.dart';
import '../widgets/phone_otp_form.dart';

/// Each web site serves exactly one portal: hotel owners (mobile OTP) or
/// the super admin console (email + password). Chosen at build time with
/// `--dart-define=WEB_PORTAL=superadmin`; anything else is the hotel site.
enum WebPortal {
  hotel,
  superAdmin;

  static WebPortal fromEnvironment() =>
      const String.fromEnvironment('WEB_PORTAL') == 'superadmin'
      ? WebPortal.superAdmin
      : WebPortal.hotel;
}

class HotelAdminApp extends StatelessWidget {
  const HotelAdminApp({super.key, this.portal = WebPortal.hotel});
  final WebPortal portal;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: portal == WebPortal.superAdmin ? 'Hotel Pro Admin' : 'Hotel Pro',
    navigatorKey: appNavigatorKey,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: _AdminGate(portal: portal),
  );
}

class _AdminGate extends StatelessWidget {
  const _AdminGate({required this.portal});
  final WebPortal portal;
  bool get _hotel => portal == WebPortal.hotel;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: PhoneAuthService.instance.signingIn,
    builder: (context, signingIn, _) => StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) => _route(context, snapshot, signingIn),
    ),
  );

  Widget _route(
    BuildContext context,
    AsyncSnapshot<User?> snapshot,
    bool signingIn,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // While an OTP login maps its hotel the form stays, so a rejected
    // number keeps its message on screen.
    if (snapshot.data == null || (_hotel && signingIn)) {
      return AdminLogin(hotelMode: _hotel);
    }
    return FutureBuilder<IdTokenResult>(
      future: snapshot.data!.getIdTokenResult(true),
      builder: (context, token) {
        if (token.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (token.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Could not verify access. Check your connection and sign in again.',
                  ),
                  TextButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          );
        }
        final isAdmin = token.data?.claims?['admin'] == true;
        if (_hotel && isAdmin) {
          return const _WrongPortal(
            'This is the hotel login. Super admin uses the separate admin website.',
          );
        }
        if (!_hotel && !isAdmin) {
          return const _WrongPortal(
            'This account does not have admin access. Hotel owners log in on the hotel website with their mobile number.',
          );
        }
        if (_hotel) {
          return CloudGate(
            key: ValueKey(snapshot.data!.uid),
            firebaseReady: true,
          );
        }
        return AdminConsole(
          onSignOut: () => FirebaseAuth.instance.signOut(),
          email: snapshot.data!.email ?? 'Admin',
        );
      },
    );
  }
}

class _WrongPortal extends StatelessWidget {
  const _WrongPortal(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    ),
  );
}

class AdminLogin extends StatefulWidget {
  const AdminLogin({
    super.key,
    this.signIn,
    this.hotelMode = false,
    this.phoneService,
  });

  /// true: hotel owner OTP login. false: super admin email + password.
  final bool hotelMode;

  /// Super admin email/password sign-in override (tests).
  final Future<void> Function(String email, String password)? signIn;

  /// Hotel owner OTP service override (tests).
  final PhoneAuthService? phoneService;
  @override
  State<AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin> {
  final _email = TextEditingController(), _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false, _visible = false;
  String? _error;
  bool get _hotelMode => widget.hotelMode;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _openSignup() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HotelSignupScreen(service: widget.phoneService),
      ),
    );
  }

  Future<void> _login() async {
    if (_busy) return;
    if (!_email.text.trim().contains('@') || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.signIn != null) {
        await widget.signIn!(_email.text.trim(), _password.text);
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code == 'too-many-requests'
              ? 'Too many attempts. Try again later.'
              : 'Email or password is incorrect.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not sign in. Check internet and retry.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_error != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _passwordFocus.requestFocus();
            _password.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _password.text.length,
            );
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: AppIcon(size: 48, radius: 12)),
                const SizedBox(height: 20),
                const Text(
                  'Hotel Pro',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
                ),
                Text(
                  _hotelMode ? 'YOUR HOTEL WORKSPACE' : 'ADMIN WORKSPACE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    letterSpacing: 3,
                    fontSize: 11,
                    color: CustomColors.muted,
                  ),
                ),
                const SizedBox(height: 32),
                const SizedBox(height: 20),
                CustomSurface(
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Welcome back',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _hotelMode
                              ? 'Log in with your mobile number and OTP to manage rooms, bookings and reports.'
                              : 'All hotels, analytics and license keys. Admin access only.',
                          style: TextStyle(color: CustomColors.muted),
                        ),
                        const SizedBox(height: 24),
                        if (_hotelMode) ...[
                          PhoneOtpForm(
                            isSignup: false,
                            service: widget.phoneService,
                            onBusyChanged: (busy) =>
                                setState(() => _busy = busy),
                          ),
                          const SizedBox(height: 8),
                          CustomButton.text(
                            onPressed: _busy ? null : _openSignup,
                            child: const Text(
                              'New to Hotel Pro? Create account',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ] else ...[
                          CustomTextField(
                            controller: _email,
                            label: _hotelMode ? 'Login email' : 'Admin email',
                            icon: Icons.alternate_email_rounded,
                            keyboardType: TextInputType.emailAddress,
                            enabled: !_busy,
                            autofillHints: const [AutofillHints.username],
                          ),
                          CustomTextField(
                            controller: _password,
                            focusNode: _passwordFocus,
                            onChanged: (_) {
                              if (_error != null) setState(() => _error = null);
                            },
                            label: 'Password',
                            icon: Icons.lock_outline_rounded,
                            enabled: !_busy,
                            obscureText: !_visible,
                            onToggleVisibility: () =>
                                setState(() => _visible = !_visible),
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _login(),
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: CustomColors.error,
                                ),
                              ),
                            ),
                          CustomButton(
                            onPressed: _busy ? null : _login,
                            child: Text(_busy ? 'Signing in…' : 'Sign in'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _hotelMode
                      ? 'Same account. Same hotel. Live Firebase data.'
                      : 'Private access · Connected to Firebase',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: CustomColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

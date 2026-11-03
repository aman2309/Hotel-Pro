import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../theme/custom_colors.dart';
import '../widgets/hotel_ui.dart';
import 'admin_console.dart';
import '../app_navigator.dart';
import '../screens/cloud_gate.dart';
import '../services/password_auth_service.dart';

class HotelAdminApp extends StatelessWidget {
  const HotelAdminApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Hotel Pro',
    navigatorKey: appNavigatorKey,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const _AdminGate(),
  );
}

class _AdminGate extends StatelessWidget {
  const _AdminGate();
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.data == null) {
        return const AdminLogin(initialHotelMode: true);
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
          if (token.data?.claims?['admin'] != true) {
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
    },
  );
}

class AdminLogin extends StatefulWidget {
  const AdminLogin({super.key, this.signIn, this.initialHotelMode = false});
  final bool initialHotelMode;
  final Future<void> Function(String email, String password)? signIn;
  @override
  State<AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin> {
  final _email = TextEditingController(), _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false, _visible = false;
  String? _error;
  late bool _hotelMode;
  @override
  void initState() {
    super.initState();
    _hotelMode = widget.initialHotelMode;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
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
      } else if (_hotelMode) {
        await PasswordAuthService.instance.login(
          _email.text.trim(),
          _password.text,
        );
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
                const Icon(Icons.apartment_rounded, size: 48),
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
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.hotel_outlined),
                      label: Text('Hotel Login'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.admin_panel_settings_outlined),
                      label: Text('Super Admin'),
                    ),
                  ],
                  selected: {_hotelMode},
                  onSelectionChanged: _busy
                      ? null
                      : (values) => setState(() {
                          _hotelMode = values.single;
                          _error = null;
                          _password.clear();
                        }),
                ),
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
                              ? 'Use your app account to manage rooms, bookings and reports.'
                              : 'All hotels, analytics and license keys. Admin access only.',
                          style: TextStyle(color: CustomColors.muted),
                        ),
                        const SizedBox(height: 24),
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
                              style: const TextStyle(color: CustomColors.error),
                            ),
                          ),
                        CustomButton(
                          onPressed: _busy ? null : _login,
                          child: Text(_busy ? 'Signing in…' : 'Sign in'),
                        ),
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

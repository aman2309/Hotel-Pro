import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../theme/custom_colors.dart';
import '../widgets/hotel_ui.dart';
import 'admin_console.dart';

class HotelAdminApp extends StatelessWidget {
  const HotelAdminApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Hotel Pro Admin',
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
      if (snapshot.data == null) return const AdminLogin();
      return FutureBuilder<IdTokenResult>(
        future: snapshot.data!.getIdTokenResult(true),
        builder: (context, token) {
          if (token.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (token.data?.claims?['admin'] != true) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 48),
                      const SizedBox(height: 16),
                      const Text('Administrator access required.'),
                      const Text(
                        'Hotel owner accounts cannot open this panel.',
                      ),
                      TextButton(
                        onPressed: () => FirebaseAuth.instance.signOut(),
                        child: const Text('Use another account'),
                      ),
                    ],
                  ),
                ),
              ),
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
  const AdminLogin({super.key, this.signIn});
  final Future<void> Function(String email, String password)? signIn;
  @override
  State<AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin> {
  final _email = TextEditingController(), _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false, _visible = false;
  String? _error;
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
      setState(() => _error = 'Enter your admin email and password.');
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
                const Icon(Icons.apartment_rounded, size: 48),
                const SizedBox(height: 20),
                const Text(
                  'Hotel Pro',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
                ),
                const Text(
                  'ADMIN WORKSPACE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    letterSpacing: 3,
                    fontSize: 11,
                    color: CustomColors.muted,
                  ),
                ),
                const SizedBox(height: 32),
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
                        const Text(
                          'Your hotels. One connected workspace.',
                          style: TextStyle(color: CustomColors.muted),
                        ),
                        const SizedBox(height: 24),
                        CustomTextField(
                          controller: _email,
                          label: 'Admin email',
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
                const Text(
                  'Private access · Connected to Firebase',
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

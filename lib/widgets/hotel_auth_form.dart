import 'custom_button.dart';
import '../screens/hotel_signup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/password_auth_service.dart';
import '../theme/custom_colors.dart';
import '../utils/responsive_ui.dart';
import 'custom_text_field.dart';

class HotelAuthForm extends StatefulWidget {
  const HotelAuthForm({
    super.key,
    required this.onReady,
    required this.isSignup,
    this.initialEmail = '',
  });

  final bool isSignup;
  final String initialEmail;

  final VoidCallback onReady;

  @override
  State<HotelAuthForm> createState() => _HotelAuthFormState();
}

class _HotelAuthFormState extends State<HotelAuthForm> {
  bool get _register => widget.isSignup;

  @override
  void initState() {
    super.initState();
    _email.text = widget.initialEmail;
  }

  bool _busy = false;
  final _formKey = GlobalKey<FormState>();
  String? _error;
  final _owner = TextEditingController();
  final _hotel = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _hidePassword = true;
  bool _hideConfirm = true;
  String? _success;

  @override
  void dispose() {
    _owner.dispose();
    _hotel.dispose();
    _mobile.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      if (_register) {
        await PasswordAuthService.instance.signup(
          email: _email.text,
          password: _password.text,
          owner: _owner.text,
          hotel: _hotel.text,
          mobile: _mobile.text.trim(),
        );
        if (!mounted) return;
        Navigator.of(context).pop(_email.text.trim());
      } else {
        await PasswordAuthService.instance.login(_email.text, _password.text);
        if (mounted) widget.onReady();
      }
    } catch (error) {
      if (mounted) setState(() => _error = PasswordAuthService.message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboard,
  }) {
    return CustomTextField(
      controller: controller,
      margin: const EdgeInsets.only(bottom: 16),
      label: label,
      icon: icon,
      enabled: !_busy,
      countryCode: controller == _mobile ? '+91' : null,
      keyboardType: keyboard,
      obscureText: controller == _password
          ? _hidePassword
          : controller == _confirm
          ? _hideConfirm
          : false,
      onToggleVisibility: controller == _password
          ? () => setState(() => _hidePassword = !_hidePassword)
          : controller == _confirm
          ? () => setState(() => _hideConfirm = !_hideConfirm)
          : null,
      autofillHints: controller == _mobile
          ? const [AutofillHints.telephoneNumberNational]
          : controller == _email
          ? const [AutofillHints.username, AutofillHints.email]
          : controller == _password || controller == _confirm
          ? [_register ? AutofillHints.newPassword : AutofillHints.password]
          : null,
      inputFormatters: controller == _mobile
          ? [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ]
          : null,
      validator: (value) {
        if (value == null || value.trim().isEmpty) return 'Please enter $label';
        if (controller == _email &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
          return 'Please enter a valid email address';
        }
        if (controller == _password && _register && value.length < 8) {
          return 'Use at least 8 characters';
        }
        if (controller == _confirm && value != _password.text) {
          return 'Passwords do not match';
        }
        if (controller == _mobile &&
            !RegExp(r'^[6-9][0-9]{9}$').hasMatch(value.trim())) {
          return 'Enter a valid 10-digit mobile number';
        }
        return null;
      },
    );
  }

  Future<void> _openSignup() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _success = null;
    });
    final email = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => HotelSignupScreen(initialEmail: _email.text.trim()),
      ),
    );
    if (!mounted || email == null) return;
    setState(() {
      _formKey.currentState?.reset();
      _email.text = email;
      _password.clear();
      _hidePassword = true;
      _success =
          'Account created successfully. Please log in with your email and password.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: CustomColors.background,
        body: ResponsivePage(
          builder: (context, ui) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (_register)
                    IconButton(
                      tooltip: 'Back to login',
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: CustomColors.primary,
                      ),
                    ),
                  const Icon(
                    Icons.apartment_rounded,
                    color: CustomColors.primary,
                    size: 26,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Hotel Pro',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: CustomColors.text,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: CustomColors.gold,
                    size: 20,
                  ),
                ],
              ),
              SizedBox(height: ui.isShort ? 16 : 28),
              Container(
                height: ui.isShort
                    ? 120
                    : ui.value(phone: 160.0, tablet: 190.0, desktop: 200.0),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [CustomColors.bannerStart, CustomColors.bannerEnd],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -18,
                      top: -36,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: CustomColors.bannerRing,
                            width: 26,
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      right: 22,
                      bottom: -8,
                      child: Icon(
                        Icons.villa_rounded,
                        size: 80,
                        color: CustomColors.bannerAccent,
                      ),
                    ),
                    const Positioned(
                      left: 22,
                      top: 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'A little more ease.',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: CustomColors.bannerText,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'For every stay.',
                            style: TextStyle(
                              fontSize: 14,
                              color: CustomColors.bannerAccent,
                            ),
                          ),
                          SizedBox(height: 22),
                          Icon(
                            Icons.wb_sunny_rounded,
                            color: CustomColors.gold,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                _register ? 'Make yourself at home.' : 'Good to see you again.',
                style: TextStyle(
                  fontSize: ui.isCompact ? 24 : 27,
                  color: CustomColors.text,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _register
                    ? 'Create an account for your hotel.'
                    : 'Your hotel, right where you left it.',
                style: const TextStyle(color: CustomColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_register) ...[
                        _field(
                          _owner,
                          'Owner name',
                          Icons.person_outline_rounded,
                        ),
                        _field(_hotel, 'Hotel name', Icons.apartment_rounded),
                      ],
                      if (_register)
                        _field(
                          _mobile,
                          'Mobile number',
                          Icons.phone_rounded,
                          keyboard: TextInputType.phone,
                        ),
                      _field(
                        _email,
                        'Login ID (email)',
                        Icons.alternate_email_rounded,
                        keyboard: TextInputType.emailAddress,
                      ),
                      _field(_password, 'Password', Icons.lock_outline_rounded),
                      if (_register)
                        _field(
                          _confirm,
                          'Confirm password',
                          Icons.lock_outline_rounded,
                        ),
                      if (_success != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _success!,
                            style: const TextStyle(color: CustomColors.primary),
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: CustomColors.error),
                          ),
                        ),
                      const SizedBox(height: 4),
                      CustomButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: CustomColors.button,
                          foregroundColor: CustomColors.onButton,
                          disabledBackgroundColor:
                              CustomColors.disabledBackground,
                          disabledForegroundColor: CustomColors.muted,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: CustomColors.onButton,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _register ? 'Create account' : 'Log in',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 19,
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              CustomButton.text(
                onPressed: _busy
                    ? null
                    : _register
                    ? () => Navigator.of(context).pop()
                    : _openSignup,
                child: Text(
                  _register
                      ? 'Already a member? Sign in'
                      : 'New to Hotel Pro? Create account',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: CustomColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border_rounded,
                    size: 14,
                    color: CustomColors.muted,
                  ),
                  SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      'Made for your kind of hospitality',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: CustomColors.muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

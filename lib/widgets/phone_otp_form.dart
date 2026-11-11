import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/phone_auth_service.dart';
import '../theme/custom_colors.dart';
import 'custom_button.dart';
import 'custom_text_field.dart';

/// Mobile number (+91 fixed) then OTP. Used by the app login, the app
/// signup page and the hotel web login. Signup also asks owner and hotel
/// name; verifying the OTP creates the hotel and signs the owner in.
class PhoneOtpForm extends StatefulWidget {
  const PhoneOtpForm({
    super.key,
    required this.isSignup,
    this.service,
    this.buttonStyle,
    this.onBusyChanged,
  });

  final bool isSignup;

  /// Defaults to [PhoneAuthService.instance]; tests pass a fake.
  final PhoneAuthService? service;
  final ButtonStyle? buttonStyle;
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<PhoneOtpForm> createState() => PhoneOtpFormState();
}

class PhoneOtpFormState extends State<PhoneOtpForm> {
  static const int resendSeconds = 30;

  final _formKey = GlobalKey<FormState>();
  final _owner = TextEditingController();
  final _hotel = TextEditingController();
  final _mobile = TextEditingController();
  final _otp = TextEditingController();
  final _otpFocus = FocusNode();

  bool _busy = false;
  String? _error;
  String? _verificationId;
  int? _resendToken;
  String? _sentTo;
  int _resendIn = 0;
  Timer? _resendTimer;

  PhoneAuthService get _service => widget.service ?? PhoneAuthService.instance;
  bool get _codeStage => _verificationId != null;

  @override
  void initState() {
    super.initState();
    _service.signingIn.addListener(_onSigningInChanged);
    final previous = _service.lastSignInError;
    if (previous != null) {
      _error = previous;
      _service.lastSignInError = null;
    }
  }

  @override
  void dispose() {
    _service.signingIn.removeListener(_onSigningInChanged);
    _resendTimer?.cancel();
    _owner.dispose();
    _hotel.dispose();
    _mobile.dispose();
    _otp.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  /// Android can verify the SMS by itself; show its result here too.
  void _onSigningInChanged() {
    if (!mounted || _service.signingIn.value) return;
    final error = _service.lastSignInError;
    if (error == null) return;
    _service.lastSignInError = null;
    _setBusy(false);
    setState(() => _error = error);
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    setState(() => _busy = value);
    widget.onBusyChanged?.call(value);
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = resendSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  Future<void> _sendOtp({bool resend = false}) async {
    if (_busy) return;
    if (!resend && !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final mobile = _mobile.text.trim();
    final e164 = PhoneAuthService.indianE164(mobile);
    _service.signupDraft = widget.isSignup
        ? {
            'ownerName': _owner.text.trim(),
            'hotelName': _hotel.text.trim(),
            'mobile': mobile,
          }
        : null;
    setState(() => _error = null);
    _setBusy(true);
    final completer = Completer<void>();
    void done() {
      if (!completer.isCompleted) completer.complete();
    }

    await _service.sendOtp(
      e164Phone: e164,
      forceResendingToken: resend ? _resendToken : null,
      onCodeSent: (sent) {
        if (mounted) {
          setState(() {
            _verificationId = sent.verificationId;
            _resendToken = sent.resendToken ?? _resendToken;
            _sentTo = e164;
            _otp.clear();
          });
          _startResendCountdown();
          _otpFocus.requestFocus();
        }
        done();
      },
      onAutoVerified: (_) => done(),
      onError: (message) {
        if (mounted) setState(() => _error = message);
        done();
      },
    );
    await completer.future;
    if (mounted) _setBusy(false);
  }

  Future<void> _verify() async {
    if (_busy || _verificationId == null) return;
    final code = _otp.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Please enter the 6-digit OTP.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    _setBusy(true);
    try {
      await _service.verifyOtp(verificationId: _verificationId!, smsCode: code);
      // The gate opens the hotel; signup's route is closed by the service.
    } catch (error) {
      _service.lastSignInError = null;
      if (mounted) {
        setState(() {
          _error = PhoneAuthService.signInMessage(error);
          if (FirebaseSessionExpired.matches(error)) _verificationId = null;
        });
      }
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  void _changeNumber() {
    _resendTimer?.cancel();
    setState(() {
      _verificationId = null;
      _resendToken = null;
      _sentTo = null;
      _resendIn = 0;
      _error = null;
      _otp.clear();
    });
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? 'Please enter $label' : null;

  @override
  Widget build(BuildContext context) {
    final verifyLabel = widget.isSignup
        ? 'Verify & create account'
        : 'Verify & log in';
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_codeStage) ...[
              if (widget.isSignup) ...[
                CustomTextField(
                  controller: _owner,
                  margin: const EdgeInsets.only(bottom: 16),
                  label: 'Owner name',
                  icon: Icons.person_outline_rounded,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  validator: (v) => _required(v, 'Owner name'),
                ),
                CustomTextField(
                  controller: _hotel,
                  margin: const EdgeInsets.only(bottom: 16),
                  label: 'Hotel name',
                  icon: Icons.apartment_rounded,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.organizationName],
                  validator: (v) => _required(v, 'Hotel name'),
                ),
              ],
              CustomTextField(
                controller: _mobile,
                margin: const EdgeInsets.only(bottom: 16),
                label: 'Mobile number',
                icon: Icons.phone_rounded,
                countryCode: PhoneAuthService.countryCode,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                onSubmitted: (_) => _sendOtp(),
                validator: (value) {
                  final missing = _required(value, 'Mobile number');
                  if (missing != null) return missing;
                  return PhoneAuthService.isValidIndianMobile(value!)
                      ? null
                      : 'Enter a valid 10-digit mobile number';
                },
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'OTP sent to $_sentTo',
                        style: const TextStyle(
                          color: CustomColors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    CustomButton.text(
                      onPressed: _busy ? null : _changeNumber,
                      child: const Text('Change number'),
                    ),
                  ],
                ),
              ),
              CustomTextField(
                controller: _otp,
                focusNode: _otpFocus,
                margin: const EdgeInsets.only(bottom: 16),
                label: 'Enter OTP',
                icon: Icons.sms_outlined,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onSubmitted: (_) => _verify(),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: CustomColors.error),
                ),
              ),
            CustomButton(
              style: widget.buttonStyle,
              onPressed: _busy ? null : (_codeStage ? _verify : _sendOtp),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _codeStage ? verifyLabel : 'Send OTP',
                      textAlign: TextAlign.center,
                    ),
            ),
            if (_codeStage)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: CustomButton.text(
                  onPressed: _busy || _resendIn > 0
                      ? null
                      : () => _sendOtp(resend: true),
                  child: Text(
                    _resendIn > 0
                        ? 'Resend OTP in ${_resendIn}s'
                        : 'Resend OTP',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// An expired OTP session needs a fresh code, so the form returns to the
/// mobile step.
abstract final class FirebaseSessionExpired {
  static bool matches(Object error) {
    final text = error.toString();
    return text.contains('session-expired') ||
        text.contains('invalid-verification-id');
  }
}

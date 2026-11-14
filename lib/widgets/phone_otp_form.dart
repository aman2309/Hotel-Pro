import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_auth/smart_auth.dart';

import '../services/phone_auth_service.dart';
import '../theme/custom_colors.dart';
import 'custom_button.dart';
import 'custom_text_field.dart';
import 'otp_code_boxes.dart';

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
    this.smsCodeListener,
  });

  final bool isSignup;

  /// Defaults to [PhoneAuthService.instance]; tests pass a fake.
  final PhoneAuthService? service;
  final ButtonStyle? buttonStyle;
  final ValueChanged<bool>? onBusyChanged;

  /// Waits for the OTP SMS and returns its code. Defaults to the Android
  /// SMS User Consent API (no app hash needed); tests pass a fake.
  final Future<String?> Function()? smsCodeListener;

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
  String? _sentTo;
  String? _sentMobile;
  int _resendIn = 0;
  Timer? _resendTimer;
  int _smsListenGeneration = 0;

  PhoneAuthService get _service => widget.service ?? PhoneAuthService.instance;
  bool get _codeStage => _sentMobile != null;

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
    _stopSmsListener();
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

  void _startResendCountdown([int seconds = resendSeconds]) {
    _resendTimer?.cancel();
    setState(() => _resendIn = seconds);
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
    final mobile = resend ? _sentMobile! : _mobile.text.trim();
    _service.signupDraft = widget.isSignup
        ? {
            'ownerName': _owner.text.trim(),
            'hotelName': _hotel.text.trim(),
            'mobile': mobile,
          }
        : null;
    setState(() => _error = null);
    _setBusy(true);
    try {
      final sent = await _service.sendOtp(mobile: mobile);
      if (!mounted) return;
      setState(() {
        _sentMobile = mobile;
        _sentTo = PhoneAuthService.indianE164(mobile);
        _otp.clear();
      });
      _startResendCountdown(sent.resendAfter.inSeconds);
      _otpFocus.requestFocus();
      _listenForSms();
    } on OtpException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
      final wait = error.retryAfter;
      if (wait != null && _codeStage) _startResendCountdown(wait.inSeconds);
    } catch (error) {
      if (mounted) {
        setState(() => _error = PhoneAuthService.signInMessage(error));
      }
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  /// Android: ask once to read the incoming OTP SMS and fill the boxes.
  Future<void> _listenForSms() async {
    final generation = ++_smsListenGeneration;
    final listener =
        widget.smsCodeListener ??
        (kIsWeb || defaultTargetPlatform != TargetPlatform.android
            ? null
            : _userConsentSms);
    if (listener == null) return;
    String? code;
    try {
      code = await listener();
    } catch (_) {
      return;
    }
    if (!mounted || generation != _smsListenGeneration || !_codeStage) return;
    if (code == null || !RegExp(r'^\d{4}$').hasMatch(code)) return;
    if (_otp.text == code) return;
    _otp.text = code;
    await _verify();
  }

  static Future<String?> _userConsentSms() async {
    final result = await SmartAuth.instance.getSmsWithUserConsentApi(
      matcher: r'\b\d{4}\b',
    );
    return result.hasData ? result.requireData.code : null;
  }

  void _stopSmsListener() {
    _smsListenGeneration++;
    if (widget.smsCodeListener == null &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      unawaited(
        SmartAuth.instance.removeUserConsentApiListener().catchError(
          (_) => const SmartAuthResult<void>.success(null),
        ),
      );
    }
  }

  Future<void> _verify() async {
    final mobile = _sentMobile;
    if (_busy || mobile == null) return;
    final code = _otp.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(code)) {
      setState(() => _error = 'Please enter the 4-digit OTP.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    _setBusy(true);
    try {
      await _service.verifyOtp(mobile: mobile, code: code);
      // The gate opens the hotel; signup's route is closed by the service.
    } catch (error) {
      _service.lastSignInError = null;
      if (mounted) {
        setState(() {
          _error = PhoneAuthService.signInMessage(error);
          _otp.clear();
          if (error is OtpException && error.needsNewCode) _resendIn = 0;
        });
        _otpFocus.requestFocus();
      }
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  void _changeNumber() {
    _resendTimer?.cancel();
    _stopSmsListener();
    setState(() {
      _sentMobile = null;
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
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: OtpCodeBoxes(
                  controller: _otp,
                  focusNode: _otpFocus,
                  length: PhoneAuthService.otpLength,
                  enabled: !_busy,
                  onCompleted: (_) => _verify(),
                ),
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

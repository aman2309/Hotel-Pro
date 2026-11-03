import '../theme/custom_colors.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/phone_auth_service.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.e164Phone,
    required this.verificationId,
    this.resendToken,
  });

  final String e164Phone;
  final String verificationId;
  final int? resendToken;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const int _otpLength = 6;
  static const int _resendSeconds = 60;

  late String _verificationId;
  int? _resendToken;
  late final List<TextEditingController> _digits;
  late final List<FocusNode> _focusNodes;

  Timer? _timer;
  int _secondsLeft = _resendSeconds;
  bool _verifying = false;
  bool _resending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _digits = List<TextEditingController>.generate(
      _otpLength,
      (_) => TextEditingController(),
    );
    _focusNodes = List<FocusNode>.generate(_otpLength, (_) => FocusNode());
    _startCountdown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNodes.first.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final TextEditingController controller in _digits) {
      controller.dispose();
    }
    for (final FocusNode node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  String get _code => _digits.map((c) => c.text).join();

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  void _onDigitChanged(int index, String value) {
    final String digit = value.replaceAll(RegExp(r'\D'), '');
    if (digit.length > 1) {
      _pasteCode(digit);
      return;
    }
    _digits[index].value = TextEditingValue(
      text: digit,
      selection: TextSelection.collapsed(offset: digit.length),
    );
    if (digit.isNotEmpty && index < _otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (_code.length == _otpLength) {
      unawaited(_verify());
    }
  }

  void _pasteCode(String raw) {
    final String digits = raw.replaceAll(RegExp(r'\D'), '');
    for (int i = 0; i < _otpLength; i++) {
      _digits[i].text = i < digits.length ? digits[i] : '';
    }
    final int next = digits.length >= _otpLength
        ? _otpLength - 1
        : digits.length;
    _focusNodes[next.clamp(0, _otpLength - 1)].requestFocus();
    if (digits.length >= _otpLength) {
      unawaited(_verify());
    }
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _digits[index].text.isEmpty &&
        index > 0) {
      _digits[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _verify() async {
    if (_verifying) {
      return;
    }
    final String smsCode = _code;
    if (smsCode.length != _otpLength) {
      setState(() => _error = 'Enter the 6-digit OTP.');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      await PhoneAuthService.instance.verifyOtp(
        verificationId: _verificationId,
        smsCode: smsCode,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _verifying = false;
        _error = PhoneAuthService.humanize(error);
      });
    }
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resending || _verifying) {
      return;
    }

    setState(() {
      _resending = true;
      _error = null;
    });

    await PhoneAuthService.instance.sendOtp(
      e164Phone: widget.e164Phone,
      forceResendingToken: _resendToken,
      onCodeSent: (PhoneCodeSent sent) {
        if (!mounted) {
          return;
        }
        setState(() {
          _resending = false;
          _verificationId = sent.verificationId;
          _resendToken = sent.resendToken;
        });
        _startCountdown();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('OTP sent again.')));
      },
      onAutoVerified: (_) {
        if (!mounted) {
          return;
        }
        setState(() => _resending = false);
      },
      onError: (String message) {
        if (!mounted) {
          return;
        }
        setState(() {
          _resending = false;
          _error = message;
        });
      },
      onAutoRetrievalTimeout: (String verificationId) {
        if (!mounted) {
          return;
        }
        setState(() => _verificationId = verificationId);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CustomColors.background,
      appBar: AppBar(
        backgroundColor: CustomColors.background,
        foregroundColor: CustomColors.text,
        elevation: 0,
        title: const Text('Verify OTP'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: CustomColors.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.mark_email_read_outlined,
                        color: CustomColors.button,
                        size: 44,
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Verify your number',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Enter the 6-digit OTP sent to',
                        style: TextStyle(color: CustomColors.text),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.e164Phone,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: List<Widget>.generate(_otpLength, (
                          int index,
                        ) {
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Focus(
                                onKeyEvent: (_, KeyEvent event) =>
                                    _onKey(index, event),
                                child: CustomTextField(
                                  controller: _digits[index],
                                  focusNode: _focusNodes[index],
                                  enabled: !_verifying,
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(1),
                                  ],
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    counterText: '',
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 17,
                                      horizontal: 0,
                                    ),
                                  ),
                                  onChanged: (String value) =>
                                      _onDigitChanged(index, value),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: CustomColors.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: CustomButton(
                          onPressed: _verifying ? null : _verify,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CustomColors.background,
                            foregroundColor: CustomColors.text,
                          ),
                          child: _verifying
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: CustomColors.surface,
                                  ),
                                )
                              : const Text(
                                  'Verify OTP',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_resending)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        )
                      else if (_secondsLeft > 0)
                        Text(
                          'Resend OTP in ${_secondsLeft}s',
                          style: TextStyle(
                            color: CustomColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else
                        CustomButton.text(
                          onPressed: _resend,
                          child: const Text(
                            'Resend OTP',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

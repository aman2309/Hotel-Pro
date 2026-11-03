import '../widgets/custom_bottom_sheet.dart';
import '../theme/custom_colors.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/country_dial_codes.dart';
import '../services/phone_auth_service.dart';
import 'otp_verification_screen.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final TextEditingController _numberController = TextEditingController();
  final FocusNode _numberFocus = FocusNode();

  CountryDialCode _country = kDefaultCountryDial;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _numberController.dispose();
    _numberFocus.dispose();
    super.dispose();
  }

  String get _digitsOnly {
    String digits = _numberController.text.replaceAll(RegExp(r'\D'), '');
    if (_country.dialCode == '+91' && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  String get _e164 => '${_country.dialCode}$_digitsOnly';

  String? _validateNumber() {
    final String digits = _digitsOnly;
    if (digits.isEmpty) {
      return 'Enter mobile number.';
    }
    if (_country.dialCode == '+91' && digits.length != 10) {
      return 'Enter a 10-digit Indian mobile number.';
    }
    if (digits.length < 6 || digits.length > 15) {
      return 'Enter a valid mobile number.';
    }
    return null;
  }

  Future<void> _sendOtp({int? resendToken}) async {
    if (_sending) return;
    final String? invalid = _validateNumber();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    await PhoneAuthService.instance.sendOtp(
      e164Phone: _e164,
      forceResendingToken: resendToken,
      onCodeSent: (PhoneCodeSent sent) {
        if (!mounted) {
          return;
        }
        setState(() => _sending = false);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => OtpVerificationScreen(
              e164Phone: _e164,
              verificationId: sent.verificationId,
              resendToken: sent.resendToken,
            ),
          ),
        );
      },
      onAutoVerified: (PhoneAuthOutcome outcome) {
        if (!mounted) {
          return;
        }
        setState(() => _sending = false);
      },
      onError: (String message) {
        if (!mounted) {
          return;
        }
        setState(() {
          _sending = false;
          _error = message;
        });
      },
    );
  }

  Future<void> _pickCountry() async {
    final CountryDialCode?
    selected = await showCustomBottomSheet<CountryDialCode>(
      context: context,
      backgroundColor: CustomColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Select country code',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: kCountryDialCodes.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final CountryDialCode country = kCountryDialCodes[index];
                    final bool selectedCode =
                        country.dialCode == _country.dialCode &&
                        country.name == _country.name;
                    return ListTile(
                      title: Text(country.name),
                      trailing: Text(
                        country.dialCode,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      selected: selectedCode,
                      onTap: () => Navigator.pop(sheetContext, country),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      setState(() => _country = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CustomColors.primary,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/images/hotel_logo.png',
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.hotel_rounded,
                        size: 72,
                        color: CustomColors.surface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Hotel Pro',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: CustomColors.surface,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Mobile number se OTP login karein.\nEk number se dono phones par wahi hotel khulega.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: CustomColors.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: CustomColors.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Mobile number',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          InkWell(
                            onTap: _sending ? null : _pickCountry,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: CustomColors.border),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    _country.dialCode,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.arrow_drop_down_rounded,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CustomTextField(
                              controller: _numberController,
                              focusNode: _numberFocus,
                              enabled: !_sending,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.done,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(15),
                              ],
                              decoration: const InputDecoration(
                                hintText: '9876543210',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                              ),
                              onSubmitted: (_) => _sendOtp(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Default country code is +91. Tap the code to change it.',
                        style: TextStyle(
                          color: CustomColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: CustomColors.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 48,
                        child: CustomButton(
                          onPressed: _sending ? null : () => _sendOtp(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CustomColors.primary,
                            foregroundColor: CustomColors.surface,
                          ),
                          child: _sending
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: CustomColors.surface,
                                  ),
                                )
                              : const Text(
                                  'Send OTP',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
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

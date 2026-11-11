import 'custom_button.dart';
import '../screens/hotel_signup_screen.dart';
import 'package:flutter/material.dart';

import '../services/phone_auth_service.dart';
import '../theme/custom_colors.dart';
import '../utils/responsive_ui.dart';
import 'phone_otp_form.dart';

/// App login and signup: mobile number (+91) and OTP only.
class HotelAuthForm extends StatefulWidget {
  const HotelAuthForm({
    super.key,
    required this.onReady,
    required this.isSignup,
    this.service,
  });

  final bool isSignup;
  final VoidCallback onReady;
  final PhoneAuthService? service;

  @override
  State<HotelAuthForm> createState() => _HotelAuthFormState();
}

class _HotelAuthFormState extends State<HotelAuthForm> {
  bool get _register => widget.isSignup;
  bool _busy = false;

  Future<void> _openSignup() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HotelSignupScreen(service: widget.service),
      ),
    );
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
              PhoneOtpForm(
                isSignup: _register,
                service: widget.service,
                onBusyChanged: (busy) => setState(() => _busy = busy),
                buttonStyle: FilledButton.styleFrom(
                  backgroundColor: CustomColors.button,
                  foregroundColor: CustomColors.onButton,
                  disabledBackgroundColor: CustomColors.disabledBackground,
                  disabledForegroundColor: CustomColors.muted,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
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

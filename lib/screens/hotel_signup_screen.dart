import 'package:flutter/material.dart';
import '../services/phone_auth_service.dart';
import '../widgets/hotel_auth_form.dart';

/// Signup: owner and hotel details, then mobile OTP. Verifying the OTP
/// creates the hotel and logs the owner straight in.
class HotelSignupScreen extends StatelessWidget {
  const HotelSignupScreen({super.key, this.service});
  final PhoneAuthService? service;

  @override
  Widget build(BuildContext context) =>
      HotelAuthForm(isSignup: true, service: service, onReady: () {});
}

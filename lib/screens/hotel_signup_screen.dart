import 'package:flutter/material.dart';
import '../widgets/hotel_auth_form.dart';

class HotelSignupScreen extends StatelessWidget {
  const HotelSignupScreen({super.key, this.initialEmail = ''});
  final String initialEmail;

  @override
  Widget build(BuildContext context) =>
      HotelAuthForm(isSignup: true, initialEmail: initialEmail, onReady: () {});
}

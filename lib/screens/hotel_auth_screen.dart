import 'package:flutter/material.dart';
import '../widgets/hotel_auth_form.dart';

/// Login has its own route and form state; signup is a separate page.
class HotelAuthScreen extends StatelessWidget {
  const HotelAuthScreen({super.key, required this.onReady});
  final VoidCallback onReady;

  @override
  Widget build(BuildContext context) =>
      HotelAuthForm(isSignup: false, onReady: onReady);
}

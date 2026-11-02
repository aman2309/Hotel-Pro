import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_navigator.dart';
import 'firebase_options.dart';
import 'config/backend_config.dart';
import 'screens/cloud_gate.dart';
import 'screens/cpanel_gate.dart';
import 'services/license_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LicenseService.instance.init();

  if (hotelUsesCpanel) {
    runApp(const HotelApp(firebaseReady: false, cpanel: true));
    return;
  }

  var firebaseReady = false;
  if (Platform.isAndroid) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
      firebaseReady = true;
    } catch (error) {
      debugPrint('Firebase init failed: $error');
    }
  }

  runApp(HotelApp(firebaseReady: firebaseReady));
}

class HotelApp extends StatelessWidget {
  const HotelApp({super.key, required this.firebaseReady, this.cpanel = false});

  final bool firebaseReady;
  final bool cpanel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Hotel Pro 1',
      home: cpanel ? const CpanelGate() : CloudGate(firebaseReady: firebaseReady),
    );
  }
}

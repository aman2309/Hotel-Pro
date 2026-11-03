import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_navigator.dart';
import 'theme/app_theme.dart';
import 'firebase_options.dart';
import 'screens/cloud_gate.dart';
import 'screens/splash_screen.dart';
import 'services/license_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LicenseService.instance.init();

  var firebaseReady = false;
  if (Platform.isAndroid) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );
      try {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: kDebugMode
              ? const AndroidDebugProvider()
              : const AndroidPlayIntegrityProvider(),
        );
      } on FirebaseException catch (error) {
        debugPrint('App Check provider initialization failed: ${error.code}');
      }
      firebaseReady = true;
    } catch (error) {
      debugPrint('Firebase init failed: $error');
    }
  }

  runApp(HotelApp(firebaseReady: firebaseReady));
}

class HotelApp extends StatelessWidget {
  const HotelApp({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Hotel Pro',
      theme: AppTheme.light,
      home: SplashScreen(destination: CloudGate(firebaseReady: firebaseReady)),
    );
  }
}

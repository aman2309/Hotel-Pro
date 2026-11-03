import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin/firebase_admin_options.dart';
import 'admin/admin_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: adminFirebaseOptions);
    await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
    runApp(const HotelAdminApp());
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Could not connect to Firebase. Refresh this page.'),
          ),
        ),
      ),
    );
  }
}

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase is not configured for web.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'Firebase is configured for Android only in this app.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDluaE9ZCxnDcRlW-HwFIuSDJnBUEbQjFU',
    appId: '1:731313332286:android:b27b800afa2dc084d4716f',
    messagingSenderId: '731313332286',
    projectId: 'yankees-hotel-pro',
    storageBucket: 'yankees-hotel-pro.firebasestorage.app',
  );
}

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'hotel_firestore_service.dart';
import 'phone_auth_service.dart';
import '../stores/hotel_settings_store.dart';

/// Passwords belong only to Firebase Authentication, never to Firestore.
class PasswordAuthService {
  static final instance = PasswordAuthService();
  Future<void>? _preparation;

  Future<void> waitForPreparation() async {
    await _preparation;
  }

  Future<void> signup({
    required String email,
    required String password,
    required String owner,
    required String hotel,
    required String mobile,
  }) {
    return _run(() async {
      final auth = FirebaseAuth.instance;
      final credential = await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      try {
        final user = credential.user!;
        await user.updateDisplayName(owner.trim());
        HotelSettingsStore.hotelName = hotel.trim();
        final account = await HotelFirestoreService.instance
            .ensureOwnerBusiness(
              user,
              allowCreate: true,
              contactPhone: '+91$mobile',
            );
        if (account == null) {
          throw StateError(
            'Account created, but hotel setup could not finish. Please log in and retry setup or contact support.',
          );
        }
      } finally {
        // Registration must never open the dashboard automatically.
        await PhoneAuthService.instance.signOutAuthOnly();
      }
    });
  }

  Future<void> login(String email, String password) => _run(() async {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  });

  Future<void> _run(Future<void> Function() action) async {
    if (_preparation != null) {
      throw StateError('Please wait for the current request.');
    }
    final done = Completer<void>();
    _preparation = done.future;
    try {
      await action();
    } finally {
      _preparation = null;
      done.complete();
    }
  }

  static String message(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'user-not-found' => "You don't have an account. Please sign up first.",
        'invalid-credential' ||
        'wrong-password' ||
        'INVALID_LOGIN_CREDENTIALS' =>
          'Login ID or password is incorrect. If you don’t have an account, please sign up first.',
        'email-already-in-use' =>
          'An account already exists with this email. Please log in.',
        'invalid-email' =>
          'Please enter a valid email address as your Login ID.',
        'weak-password' =>
          'Please choose a stronger password with at least 8 characters.',
        'user-disabled' => 'This account is disabled. Please contact support.',
        'too-many-requests' => 'Too many attempts. Please wait and try again.',
        'network-request-failed' =>
          'Please check your internet connection and try again.',
        'operation-not-allowed' =>
          'Email/password login is not enabled yet. Please contact support.',
        _ => 'Unable to sign in. Please try again or contact support.',
      };
    }
    return 'Unable to complete account setup. Please try logging in or contact support.';
  }
}

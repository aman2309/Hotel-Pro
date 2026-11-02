import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import '../app_navigator.dart';
import 'cloud_sync_service.dart';
import 'hotel_firestore_service.dart';
import 'otp_request_gate.dart';

class PhoneAuthSession {
  static String? uid;
  static String? phoneNumber;
  static String? businessId;

  static void capture(User user) {
    uid = user.uid;
    phoneNumber = user.phoneNumber;
  }

  /// Clears only the signed-in user. Keeps [businessId] so the same hotel
  /// cloud identity can be reused after the next OTP.
  static void clearAuthUser() {
    uid = null;
    phoneNumber = null;
  }

  static void clear() {
    clearAuthUser();
    businessId = null;
  }
}

class PhoneAuthOutcome {
  const PhoneAuthOutcome({required this.uid, required this.phoneNumber});

  final String uid;
  final String phoneNumber;
}

class PhoneCodeSent {
  const PhoneCodeSent({required this.verificationId, this.resendToken});

  final String verificationId;
  final int? resendToken;
}

class PhoneAuthService {
  PhoneAuthService._();

  static final PhoneAuthService instance = PhoneAuthService._();

  static const Duration otpTimeout = Duration(seconds: 60);
  final _otpGate = OtpRequestGate();
  Future<PhoneAuthOutcome>? _signInFuture;

  /// Auth emits its user before the first-login mapping transaction finishes.
  /// Bootstrap must wait for that verified new-owner decision, not race it.
  Future<void> waitForLoginPreparation() async {
    await _signInFuture;
  }

  /// Sign out of Firebase Auth only. Hotel SharedPreferences, rooms, bills,
  /// customers, and the cached businessId are left untouched.
  Future<void> signOutAuthOnly() async {
    debugPrint(
      '[PHONE_AUTH] signOut auth-only; hotel prefs and businessId cache kept',
    );
    PhoneAuthSession.clear();
    HotelFirestoreService.instance.clearAccount();
    if (Firebase.apps.isEmpty) {
      return;
    }
    await FirebaseAuth.instance.signOut();
  }

  Future<void> sendOtp({
    required String e164Phone,
    int? forceResendingToken,
    required void Function(PhoneCodeSent sent) onCodeSent,
    required void Function(PhoneAuthOutcome outcome) onAutoVerified,
    required void Function(String message) onError,
    void Function(String verificationId)? onAutoRetrievalTimeout,
    bool forceRecaptcha = false,
  }) async {
    try {
      await _otpGate.begin(e164Phone);
    } catch (error) {
      onError(humanize(error));
      return;
    }
    Timer? watchdog;
    void finish() {
      watchdog?.cancel();
      _otpGate.finish();
    }

    watchdog = Timer(const Duration(minutes: 2), () {
      finish();
      onError('OTP request timed out. Check internet and try again later.');
    });
    await _sendOtp(
      e164Phone: e164Phone,
      forceResendingToken: forceResendingToken,
      forceRecaptcha: forceRecaptcha,
      onCodeSent: (sent) {
        finish();
        onCodeSent(sent);
      },
      onAutoVerified: (outcome) {
        finish();
        onAutoVerified(outcome);
      },
      onError: (message) {
        finish();
        onError(message);
      },
      onAutoRetrievalTimeout: (id) {
        finish();
        onAutoRetrievalTimeout?.call(id);
      },
    );
  }

  Future<void> _sendOtp({
    required String e164Phone,
    int? forceResendingToken,
    required void Function(PhoneCodeSent sent) onCodeSent,
    required void Function(PhoneAuthOutcome outcome) onAutoVerified,
    required void Function(String message) onError,
    void Function(String verificationId)? onAutoRetrievalTimeout,
    bool forceRecaptcha = false,
  }) async {
    try {
      if (Firebase.apps.isEmpty) {
        onError('Firebase is not ready on this device.');
        return;
      }
      // Play Store builds use Google's app-signing SHA-256. If that fingerprint
      // is missing in Firebase, Play Integrity fails; retry via reCAPTCHA.
      await FirebaseAuth.instance.setSettings(
        appVerificationDisabledForTesting: false,
        forceRecaptchaFlow: forceRecaptcha,
      );
      debugPrint(
        '[PHONE_AUTH] appVerification disabled=false '
        'forceRecaptcha=$forceRecaptcha',
      );
      debugPrint('[PHONE_AUTH] sending OTP');
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: e164Phone,
        timeout: otpTimeout,
        forceResendingToken: forceResendingToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('[PHONE_AUTH] auto-verification completed (native SMS)');
          try {
            final PhoneAuthOutcome outcome = await _signIn(credential);
            onAutoVerified(outcome);
          } catch (error) {
            onError(humanize(error));
          }
        },
        verificationFailed: (FirebaseAuthException error) {
          debugPrint(
            '[PHONE_AUTH] verificationFailed code=${error.code} '
            'message=${error.message}',
          );
          if (error.code == 'too-many-requests' ||
              error.code == 'quota-exceeded') {
            unawaited(_otpGate.rateLimited(e164Phone));
          }
          if (!forceRecaptcha && _needsRecaptchaFallback(error)) {
            debugPrint(
              '[PHONE_AUTH] Play Integrity SHA mismatch; retry reCAPTCHA',
            );
            _sendOtp(
              e164Phone: e164Phone,
              forceResendingToken: forceResendingToken,
              onCodeSent: onCodeSent,
              onAutoVerified: onAutoVerified,
              onError: onError,
              onAutoRetrievalTimeout: onAutoRetrievalTimeout,
              forceRecaptcha: true,
            );
            return;
          }
          onError(humanize(error));
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint(
            '[PHONE_AUTH] codeSent (SMS requested) '
            'resendToken=${resendToken != null}',
          );
          onCodeSent(
            PhoneCodeSent(
              verificationId: verificationId,
              resendToken: resendToken,
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('[PHONE_AUTH] auto-retrieval timeout');
          onAutoRetrievalTimeout?.call(verificationId);
        },
      );
    } catch (error) {
      debugPrint('[PHONE_AUTH] send OTP threw $error');
      onError(humanize(error));
    }
  }

  Future<PhoneAuthOutcome> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    final PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _signIn(credential);
  }

  Future<PhoneAuthOutcome> _signIn(PhoneAuthCredential credential) async {
    final active = _signInFuture;
    if (active != null) return active;
    final future = _finishSignIn(credential);
    _signInFuture = future;
    try {
      return await future;
    } finally {
      _signInFuture = null;
    }
  }

  Future<PhoneAuthOutcome> _finishSignIn(PhoneAuthCredential credential) async {
    final UserCredential userCredential = await FirebaseAuth.instance
        .signInWithCredential(credential);
    final User? user = userCredential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Sign-in succeeded but no user was returned.',
      );
    }
    PhoneAuthSession.capture(user);
    debugPrint('[PHONE_AUTH] signed in');
    final account = await HotelFirestoreService.instance.ensureOwnerBusiness(
      user,
      allowCreate: userCredential.additionalUserInfo?.isNewUser == true,
    );
    PhoneAuthSession.businessId = account?.businessId;
    await CloudSyncService.bindLoginPhoneStore(user.phoneNumber ?? '');

    debugPrint(
      '[PHONE_AUTH] businessId=${account?.businessId ?? ''} '
      'uid=${user.uid}',
    );
    if (account == null) {
      debugPrint(
        'HotelFirestore owner/business bootstrap did not complete. '
        'Local hotel data remains the primary fallback.',
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appNavigatorKey.currentState?.popUntil(
        (Route<dynamic> route) => route.isFirst,
      );
    });
    return PhoneAuthOutcome(uid: user.uid, phoneNumber: user.phoneNumber ?? '');
  }

  static String humanize(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-phone-number':
          return 'Invalid mobile number. Check country code and number.';
        case 'too-many-requests':
          return 'Firebase ने OTP requests रोक दी हैं। अभी दोनों फोन पर कोशिश बंद करें; unblock का समय निश्चित नहीं है।';
        case 'quota-exceeded':
          return 'SMS quota exceeded. Try again later.';
        case 'session-expired':
          return 'OTP expired. Please resend OTP.';
        case 'invalid-verification-code':
          return 'Incorrect OTP. Please try again.';
        case 'invalid-verification-id':
          return 'OTP session expired. Please resend OTP.';
        case 'missing-client-identifier':
        case 'app-not-authorized':
          return _playSigningHelp;
        case 'network-request-failed':
          return 'No internet connection. Check network and retry.';
        case 'user-disabled':
          return 'This account is disabled.';
        case 'captcha-check-failed':
          return 'Phone verification check failed. Try again.';
        default:
          if (_needsRecaptchaFallback(error)) {
            return _playSigningHelp;
          }
          final String? message = error.message;
          if (message != null && message.trim().isNotEmpty) {
            return message;
          }
          return 'Could not verify phone (${error.code}).';
      }
    }
    return error.toString();
  }

  static const String _playSigningHelp =
      'Phone verification needs the Play signing SHA-256 in Firebase. Check internet and tap Send OTP again.';

  static bool _needsRecaptchaFallback(FirebaseAuthException error) {
    final String blob = '${error.code} ${error.message ?? ''}'.toLowerCase();
    return blob.contains('play_integrity') ||
        blob.contains('sha-256') ||
        blob.contains('sha256') ||
        blob.contains('not authorized to use firebase authentication') ||
        blob.contains('app-not-authorized') ||
        error.code == 'missing-client-identifier';
  }
}

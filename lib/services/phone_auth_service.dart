import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import '../app_navigator.dart';
import '../stores/hotel_settings_store.dart';
import 'hotel_data_buffer.dart';
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
  PhoneAuthService({
    FirebaseAuth? auth,
    OtpRequestGate? otpGate,
    this.firebaseReady,
  }) : _authOverride = auth,
       _otpGate = otpGate ?? OtpRequestGate();

  static final PhoneAuthService instance = PhoneAuthService();

  static const Duration otpTimeout = Duration(seconds: 60);
  final FirebaseAuth? _authOverride;
  final OtpRequestGate _otpGate;
  final bool Function()? firebaseReady;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  bool get _isFirebaseReady =>
      firebaseReady?.call() ?? Firebase.apps.isNotEmpty;
  int _otpRequestGeneration = 0;
  Future<PhoneAuthOutcome>? _signInFuture;
  Map<String, String>? signupDraft;

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
    _otpRequestGeneration++;
    _otpGate.finish();
    PhoneAuthSession.clear();
    signupDraft = null;
    if (HotelDataBuffer.cloudOnly) HotelDataBuffer.clearSession();
    HotelFirestoreService.instance.clearAccount();
    if (!_isFirebaseReady) {
      return;
    }
    await _auth.signOut();
  }

  Future<void> sendOtp({
    required String e164Phone,
    int? forceResendingToken,
    required void Function(PhoneCodeSent sent) onCodeSent,
    required void Function(PhoneAuthOutcome outcome) onAutoVerified,
    required void Function(String message) onError,
    void Function(String verificationId)? onAutoRetrievalTimeout,
  }) async {
    if (_signInFuture != null) {
      onError('Phone verification is completing. Please wait.');
      return;
    }
    try {
      await _otpGate.begin(e164Phone);
    } catch (error) {
      onError(humanize(error));
      return;
    }
    final generation = ++_otpRequestGeneration;
    var terminal = false;
    var codeIssued = false;
    Timer? watchdog;
    bool isCurrent() => generation == _otpRequestGeneration && !terminal;
    void finish() {
      watchdog?.cancel();
      if (generation == _otpRequestGeneration) _otpGate.finish();
    }

    void fail(String message) {
      if (!isCurrent() || codeIssued) return;
      terminal = true;
      finish();
      onError(message);
    }

    watchdog = Timer(const Duration(minutes: 2), () {
      fail(
        'Verification timed out. Close any verification window before trying again.',
      );
    });
    await _sendOtp(
      e164Phone: e164Phone,
      forceResendingToken: forceResendingToken,
      isCurrent: isCurrent,
      onCodeSent: (sent) {
        if (!isCurrent() || codeIssued) return;
        codeIssued = true;
        finish();
        onCodeSent(sent);
      },
      onAutoVerified: (outcome) {
        if (!isCurrent()) return;
        terminal = true;
        finish();
        onAutoVerified(outcome);
      },
      onError: fail,
      onAutoRetrievalTimeout: (id) {
        if (!isCurrent()) return;
        if (!codeIssued) {
          fail('SMS verification timed out. Please try again.');
        } else {
          onAutoRetrievalTimeout?.call(id);
        }
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
    required bool Function() isCurrent,
  }) async {
    try {
      if (!_isFirebaseReady) {
        onError('Firebase is not ready on this device.');
        return;
      }
      // Let Firebase choose native Play Integrity/reCAPTCHA. Starting another
      // request from verificationFailed races the SDK's existing browser flow.
      await _auth.setSettings(
        appVerificationDisabledForTesting: false,
        forceRecaptchaFlow: false,
      );
      debugPrint('[PHONE_AUTH] native app verification enabled');
      debugPrint('[PHONE_AUTH] sending OTP');
      await _auth.verifyPhoneNumber(
        phoneNumber: e164Phone,
        timeout: otpTimeout,
        forceResendingToken: forceResendingToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          if (!isCurrent()) return;
          debugPrint('[PHONE_AUTH] auto-verification completed (native SMS)');
          try {
            final PhoneAuthOutcome outcome = await _signIn(credential);
            onAutoVerified(outcome);
          } catch (error) {
            onError(humanize(error));
          }
        },
        verificationFailed: (FirebaseAuthException error) async {
          if (!isCurrent()) return;
          debugPrint(
            '[PHONE_AUTH] verificationFailed code=${error.code} '
            'native app verification failed',
          );
          if (error.code == 'too-many-requests' ||
              error.code == 'quota-exceeded') {
            try {
              await _otpGate.rateLimited(e164Phone);
            } catch (_) {
              debugPrint('[PHONE_AUTH] could not persist OTP cooldown');
            }
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
    if (signupDraft != null) {
      HotelSettingsStore.hotelName = signupDraft!['hotelName']!;
      await user.updateDisplayName(signupDraft!['ownerName']);
    }
    debugPrint('[PHONE_AUTH] signed in');
    final account = await HotelFirestoreService.instance.ensureOwnerBusiness(
      user,
      allowCreate: signupDraft != null,
    );
    PhoneAuthSession.businessId = account?.businessId;
    if (account == null || HotelFirestoreService.instance.lastError != null) {
      final message =
          HotelFirestoreService.instance.lastError ??
          'Create your account using Sign up first.';
      await signOutAuthOnly();
      throw StateError(message);
    }
    signupDraft = null;

    debugPrint(
      '[PHONE_AUTH] businessId=${account.businessId} '
      'uid=${user.uid}',
    );
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
        case 'invalid-app-credential':
        case 'missing-client-identifier':
        case 'app-not-authorized':
          return _appVerificationSetupHelp;
        case 'network-request-failed':
          return 'No internet connection. Check network and retry.';
        case 'user-disabled':
          return 'This account is disabled.';
        case 'web-context-already-presented':
          return 'A verification window is already open. Complete or close it before trying again.';
        case 'web-context-cancelled':
          return 'Phone verification was cancelled. Please try again.';
        case 'captcha-check-failed':
          return 'Phone verification check failed. Try again.';
        default:
          if (_isAppVerificationConfigurationError(error)) {
            return _appVerificationSetupHelp;
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

  static const String _appVerificationSetupHelp =
      'Phone verification setup is incomplete for this app. Please contact support before retrying.';

  static bool _isAppVerificationConfigurationError(
    FirebaseAuthException error,
  ) {
    final String blob = '${error.code} ${error.message ?? ''}'.toLowerCase();
    return blob.contains('play_integrity') ||
        blob.contains('sha-256') ||
        blob.contains('sha256') ||
        blob.contains('not authorized to use firebase authentication') ||
        blob.contains('app-not-authorized') ||
        error.code == 'missing-client-identifier';
  }
}

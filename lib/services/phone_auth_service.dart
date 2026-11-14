import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import '../app_navigator.dart';
import '../stores/hotel_settings_store.dart';
import 'hotel_data_buffer.dart';
import 'hotel_firestore_service.dart';

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

/// The SMS was sent; a new OTP can be requested after [resendAfter].
class OtpSent {
  const OtpSent({this.resendAfter = const Duration(seconds: 30)});
  final Duration resendAfter;
}

/// A send or verify request the owner can act on (wrong code, wait, ...).
class OtpException implements Exception {
  const OtpException(
    this.message, {
    this.retryAfter,
    this.needsNewCode = false,
  });
  final String message;

  /// Set when the server asks to wait before the next send.
  final Duration? retryAfter;

  /// The current code can no longer be used (expired or locked).
  final bool needsNewCode;

  @override
  String toString() => message;
}

/// Hotel owner login by SMS OTP. The `sendLoginOtp` Cloud Function generates
/// the code and sends it through the DLT SMS gateway; `verifyLoginOtp`
/// checks it and returns a custom token for the owner's +91 Firebase user,
/// so existing owners keep the same uid and hotel.
class PhoneAuthService {
  PhoneAuthService({FirebaseAuth? auth, this.firebaseReady})
    : _authOverride = auth;

  static final PhoneAuthService instance = PhoneAuthService();

  final FirebaseAuth? _authOverride;
  final bool Function()? firebaseReady;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  bool get _isFirebaseReady =>
      firebaseReady?.call() ?? Firebase.apps.isNotEmpty;
  Future<PhoneAuthOutcome>? _signInFuture;

  HttpsCallable _callable(String name) =>
      FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable(name);

  /// Owner/hotel details from the signup form. When set, the next OTP
  /// sign-in may create a new hotel; login always clears it.
  Map<String, String>? signupDraft;

  /// True while an OTP is being exchanged and the hotel mapped.
  /// Gates keep the login form on screen until this finishes.
  final ValueNotifier<bool> signingIn = ValueNotifier<bool>(false);

  /// Why the last OTP sign-in was rejected after Firebase Auth succeeded
  /// (for example: no hotel for this number). The login form shows it once.
  String? lastSignInError;

  static const String countryCode = '+91';
  static const int otpLength = 4;

  /// `9876543210` -> `+919876543210`.
  static String indianE164(String tenDigits) =>
      '$countryCode${tenDigits.replaceAll(RegExp(r'\D'), '')}';

  static bool isValidIndianMobile(String value) =>
      RegExp(r'^[6-9][0-9]{9}$').hasMatch(value.trim());

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
    signupDraft = null;
    if (HotelDataBuffer.cloudOnly) HotelDataBuffer.clearSession();
    HotelFirestoreService.instance.clearAccount();
    if (!_isFirebaseReady) {
      return;
    }
    await _auth.signOut();
  }

  /// Sends a new OTP to the 10-digit [mobile]. Also used for resend: the
  /// previous code stops working.
  Future<OtpSent> sendOtp({required String mobile}) async {
    if (_signInFuture != null) {
      throw const OtpException('Login is completing. Please wait.');
    }
    if (!_isFirebaseReady) {
      throw const OtpException('Firebase is not ready on this device.');
    }
    try {
      final result = await _callable(
        'sendLoginOtp',
      ).call(<String, dynamic>{'mobile': mobile.trim()});
      debugPrint('[OTP_SEND] success data=${result.data}');
      final data = result.data;
      final seconds = data is Map ? data['resendAfter'] : null;
      debugPrint('[PHONE_AUTH] OTP SMS requested');
      return OtpSent(
        resendAfter: Duration(seconds: seconds is num ? seconds.toInt() : 30),
      );
    } catch (error) {
      _debugOtpError('OTP_SEND', error);
      throw _otpException(error);
    }
  }

  /// Prints the full server error (code, message, details) to the console.
  static void _debugOtpError(String tag, Object error) {
    if (error is FirebaseFunctionsException) {
      debugPrint(
        '[$tag] FAILED code=${error.code} message=${error.message} '
        'details=${error.details}',
      );
    } else {
      debugPrint('[$tag] FAILED ${error.runtimeType}: $error');
    }
  }

  Future<PhoneAuthOutcome> verifyOtp({
    required String mobile,
    required String code,
  }) async {
    final active = _signInFuture;
    if (active != null) return active;
    lastSignInError = null;
    final future = _verifyAndSignIn(mobile.trim(), code.trim());
    _signInFuture = future;
    signingIn.value = true;
    try {
      return await future;
    } catch (error) {
      lastSignInError = signInMessage(error);
      rethrow;
    } finally {
      _signInFuture = null;
      signingIn.value = false;
    }
  }

  Future<PhoneAuthOutcome> _verifyAndSignIn(String mobile, String code) async {
    final Map<dynamic, dynamic> data;
    try {
      final result = await _callable(
        'verifyLoginOtp',
      ).call(<String, dynamic>{'mobile': mobile, 'code': code});
      data = result.data as Map;
    } catch (error) {
      _debugOtpError('OTP_VERIFY', error);
      throw _otpException(error);
    }
    final token = data['token'];
    if (token is! String || token.isEmpty) {
      throw const OtpException('Could not complete login. Please try again.');
    }
    final userCredential = await _auth.signInWithCustomToken(token);
    return _finishSignIn(userCredential, isNewUser: data['isNewUser'] == true);
  }

  /// Hotels registered with the old email login belong to an email UID.
  /// The server moves such a hotel to this verified mobile when the hotel's
  /// saved mobile matches exactly. Missing function or no match: false.
  Future<bool> _claimLegacyHotel() async {
    try {
      final result = await _callable('claimHotelByPhone').call();
      final data = result.data;
      final claimed = data is Map && data['claimed'] == true;
      debugPrint('[PHONE_AUTH] legacy hotel claim claimed=$claimed');
      return claimed;
    } catch (error) {
      debugPrint('[PHONE_AUTH] legacy hotel claim skipped: $error');
      return false;
    }
  }

  Future<PhoneAuthOutcome> _finishSignIn(
    UserCredential userCredential, {
    required bool isNewUser,
  }) async {
    final User? user = userCredential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Sign-in succeeded but no user was returned.',
      );
    }
    PhoneAuthSession.capture(user);
    final draft = signupDraft;
    final bool isSignup = draft != null;
    debugPrint('[PHONE_AUTH] signed in signup=$isSignup');
    var claimed = false;
    if (isNewUser) {
      claimed = await _claimLegacyHotel();
    }
    if (isSignup && !claimed) {
      final owner = (draft['ownerName'] ?? '').trim();
      final hotel = (draft['hotelName'] ?? '').trim();
      if (hotel.isNotEmpty) HotelSettingsStore.hotelName = hotel;
      if (owner.isNotEmpty && user.displayName != owner) {
        await user.updateDisplayName(owner);
        await user.reload();
      }
    }
    final firestore = HotelFirestoreService.instance;
    final User signedIn = _auth.currentUser ?? user;
    var account = await firestore.ensureOwnerBusiness(
      signedIn,
      allowCreate: isSignup,
      contactPhone: user.phoneNumber,
    );
    if ((account == null || firestore.lastError != null) &&
        !isSignup &&
        !claimed &&
        await _claimLegacyHotel()) {
      account = await firestore.ensureOwnerBusiness(signedIn);
    }
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

  static OtpException _otpException(Object error) {
    if (error is OtpException) return error;
    if (error is FirebaseFunctionsException) {
      final details = error.details;
      final map = details is Map ? details : const {};
      final reason = map['reason'];
      final retry = map['retryAfter'];
      final message = switch (error.code) {
        'unavailable' || 'internal' || 'deadline-exceeded'
            when reason == null =>
          'Could not reach the server. Check internet and retry.',
        _ => error.message ?? 'Could not complete OTP login. Please retry.',
      };
      return OtpException(
        message,
        retryAfter: retry is num ? Duration(seconds: retry.toInt()) : null,
        needsNewCode: reason == 'expired' || reason == 'too-many-attempts',
      );
    }
    return OtpException(humanize(error));
  }

  /// Message for the login/signup form, for any error from [verifyOtp].
  static String signInMessage(Object error) {
    if (error is OtpException) return error.message;
    if (error is StateError) {
      return error.message.replaceFirst(RegExp(r'^(Bad state: )+'), '');
    }
    return humanize(error);
  }

  static String humanize(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'network-request-failed':
          return 'No internet connection. Check network and retry.';
        case 'user-disabled':
          return 'This account is disabled.';
        case 'invalid-custom-token':
        case 'custom-token-mismatch':
          return 'Login could not be completed. Please resend OTP.';
        default:
          final String? message = error.message;
          if (message != null && message.trim().isNotEmpty) {
            return message;
          }
          return 'Could not log in (${error.code}).';
      }
    }
    return error.toString();
  }
}

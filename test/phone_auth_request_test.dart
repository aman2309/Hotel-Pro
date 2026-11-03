import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_first_app/services/phone_auth_service.dart' as hotel;

class _Auth implements FirebaseAuth {
  int requests = 0;
  bool? verificationDisabled;
  bool? forcedCaptcha;
  PhoneVerificationFailed? fail;
  PhoneCodeSent? sent;
  void Function()? respond;
  @override
  Future<void> setSettings({
    bool appVerificationDisabledForTesting = false,
    String? userAccessGroup,
    bool migrateCurrentUser = false,
    String? phoneNumber,
    String? smsCode,
    bool? forceRecaptchaFlow,
  }) async {
    verificationDisabled = appVerificationDisabledForTesting;
    forcedCaptcha = forceRecaptchaFlow;
  }

  @override
  Future<void> verifyPhoneNumber({
    String? phoneNumber,
    PhoneMultiFactorInfo? multiFactorInfo,
    required PhoneVerificationCompleted verificationCompleted,
    required PhoneVerificationFailed verificationFailed,
    required PhoneCodeSent codeSent,
    required PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
    String? autoRetrievedSmsCodeForTesting,
    Duration timeout = const Duration(seconds: 30),
    int? forceResendingToken,
    MultiFactorSession? multiFactorSession,
  }) async {
    requests++;
    fail = verificationFailed;
    sent = codeSent;
    respond?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'an app authorization error never launches a recursive reCAPTCHA request',
    () async {
      final auth = _Auth();
      auth.respond = () => auth.fail!(
        FirebaseAuthException(
          code: 'app-not-authorized',
          message: 'Invalid app info in play_integrity_token',
        ),
      );
      final service = hotel.PhoneAuthService(
        auth: auth,
        firebaseReady: () => true,
      );
      final errors = <String>[];
      await service.sendOtp(
        e164Phone: '+919999999991',
        onCodeSent: (_) {},
        onAutoVerified: (_) {},
        onError: errors.add,
      );
      expect(auth.requests, 1);
      expect(auth.forcedCaptcha, isFalse);
      expect(auth.verificationDisabled, isFalse);
      expect(errors.single, contains('setup is incomplete'));
    },
  );
  test('duplicate failure callbacks are delivered only once', () async {
    final auth = _Auth();
    auth.respond = () {
      final error = FirebaseAuthException(code: 'missing-client-identifier');
      auth.fail!(error);
      auth.fail!(error);
    };
    final service = hotel.PhoneAuthService(
      auth: auth,
      firebaseReady: () => true,
    );
    final errors = <String>[];
    await service.sendOtp(
      e164Phone: '+919999999992',
      onCodeSent: (_) {},
      onAutoVerified: (_) {},
      onError: errors.add,
    );
    expect(errors, hasLength(1));
    expect(auth.requests, 1);
  });
  test(
    'code-sent and late native errors do not open duplicate screens',
    () async {
      final auth = _Auth();
      auth.respond = () {
        auth.sent!('verification-id', 1);
        auth.sent!('verification-id', 1);
        auth.fail!(
          FirebaseAuthException(code: 'web-context-already-presented'),
        );
      };
      final service = hotel.PhoneAuthService(
        auth: auth,
        firebaseReady: () => true,
      );
      var screens = 0;
      final errors = <String>[];
      await service.sendOtp(
        e164Phone: '+919999999993',
        onCodeSent: (_) => screens++,
        onAutoVerified: (_) {},
        onError: errors.add,
      );
      expect(screens, 1);
      expect(errors, isEmpty);
    },
  );
  test(
    'rapid repeated taps never start a second native verification',
    () async {
      final auth = _Auth();
      auth.respond = () => auth.sent!('verification-id', 1);
      final service = hotel.PhoneAuthService(
        auth: auth,
        firebaseReady: () => true,
      );
      final errors = <String>[];
      await Future.wait([
        service.sendOtp(
          e164Phone: '+919999999994',
          onCodeSent: (_) {},
          onAutoVerified: (_) {},
          onError: errors.add,
        ),
        service.sendOtp(
          e164Phone: '+919999999994',
          onCodeSent: (_) {},
          onAutoVerified: (_) {},
          onError: errors.add,
        ),
      ]);
      expect(auth.requests, 1);
      expect(errors, hasLength(1));
    },
  );
  test(
    'callbacks from an older request cannot alter a new OTP attempt',
    () async {
      final auth = _Auth();
      auth.respond = () => auth.sent!('first-id', 1);
      final service = hotel.PhoneAuthService(
        auth: auth,
        firebaseReady: () => true,
      );
      var screens = 0;
      final errors = <String>[];
      await service.sendOtp(
        e164Phone: '+919999999995',
        onCodeSent: (_) => screens++,
        onAutoVerified: (_) {},
        onError: errors.add,
      );
      final oldFail = auth.fail!;
      final oldSent = auth.sent!;
      auth.respond = () => auth.sent!('second-id', 2);
      await service.sendOtp(
        e164Phone: '+919999999996',
        onCodeSent: (_) => screens++,
        onAutoVerified: (_) {},
        onError: errors.add,
      );
      oldFail(FirebaseAuthException(code: 'app-not-authorized'));
      oldSent('stale-id', 1);
      expect(screens, 2);
      expect(errors, isEmpty);
      expect(auth.requests, 2);
    },
  );
}

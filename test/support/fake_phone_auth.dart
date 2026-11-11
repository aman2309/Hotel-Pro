import 'package:my_first_app/services/phone_auth_service.dart';

/// Records OTP requests without Firebase.
class FakePhoneAuth extends PhoneAuthService {
  FakePhoneAuth() : super(firebaseReady: () => false);

  final List<String> sent = [];
  final List<int?> resendTokens = [];
  final List<Map<String, String>?> draftsAtSend = [];
  String? verifiedCode;
  Object? verifyError;

  @override
  Future<void> sendOtp({
    required String e164Phone,
    int? forceResendingToken,
    required void Function(PhoneCodeSent sent) onCodeSent,
    required void Function(PhoneAuthOutcome outcome) onAutoVerified,
    required void Function(String message) onError,
    void Function(String verificationId)? onAutoRetrievalTimeout,
  }) async {
    sent.add(e164Phone);
    resendTokens.add(forceResendingToken);
    draftsAtSend.add(signupDraft == null ? null : {...signupDraft!});
    onCodeSent(const PhoneCodeSent(verificationId: 'vid', resendToken: 7));
  }

  @override
  Future<PhoneAuthOutcome> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    verifiedCode = smsCode;
    final error = verifyError;
    if (error != null) throw error;
    return PhoneAuthOutcome(uid: 'owner-uid', phoneNumber: sent.last);
  }
}

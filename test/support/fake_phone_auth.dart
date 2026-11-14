import 'package:my_first_app/services/phone_auth_service.dart';

/// Records OTP requests without Firebase or SMS.
class FakePhoneAuth extends PhoneAuthService {
  FakePhoneAuth() : super(firebaseReady: () => false);

  final List<String> sent = [];
  final List<Map<String, String>?> draftsAtSend = [];
  String? verifiedCode;
  Object? verifyError;
  Object? sendError;

  @override
  Future<OtpSent> sendOtp({required String mobile}) async {
    final error = sendError;
    if (error != null) throw error;
    sent.add(mobile);
    draftsAtSend.add(signupDraft == null ? null : {...signupDraft!});
    return const OtpSent(resendAfter: Duration(seconds: 30));
  }

  @override
  Future<PhoneAuthOutcome> verifyOtp({
    required String mobile,
    required String code,
  }) async {
    verifiedCode = code;
    final error = verifyError;
    if (error != null) throw error;
    return PhoneAuthOutcome(uid: 'owner-uid', phoneNumber: '+91$mobile');
  }
}

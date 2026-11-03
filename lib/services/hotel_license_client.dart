import 'package:cloud_functions/cloud_functions.dart';

/// License keys are redeemed only by the Firebase server; never logged or stored.
class HotelLicenseClient {
  HotelLicenseClient._();
  static final instance = HotelLicenseClient._();
  Future<Map<String, dynamic>> Function(String key)? debugRedeem;
  Future<Map<String, dynamic>> redeem(String key) async {
    if (debugRedeem != null) return debugRedeem!(key);
    final result = await FirebaseFunctions.instanceFor(
      region: 'asia-south1',
    ).httpsCallable('redeemHotelLicenseKey').call({'key': key});
    return Map<String, dynamic>.from(result.data as Map);
  }
}

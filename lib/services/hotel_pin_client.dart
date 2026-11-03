import 'package:cloud_functions/cloud_functions.dart';

/// Calls the license backend. The PIN is sent once and never logged.
class HotelPinClient {
  HotelPinClient._();
  static final HotelPinClient instance = HotelPinClient._();

  Future<Map<String, dynamic>> Function(String pin)? debugRedeem;

  Future<Map<String, dynamic>> redeem(String pin) async {
    final Future<Map<String, dynamic>> Function(String pin)? override =
        debugRedeem;
    if (override != null) return override(pin);
    final HttpsCallable callable = FirebaseFunctions.instanceFor(
      region: 'asia-south1',
    ).httpsCallable('redeemHotelPin');
    final HttpsCallableResult<dynamic> result = await callable.call(
      <String, dynamic>{'pin': pin},
    );
    final data = result.data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }
}

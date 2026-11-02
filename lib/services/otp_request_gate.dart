import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local protection supplements Firebase throttling; it cannot lift its limits.
class OtpRequestGate {
  OtpRequestGate({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  bool _busy = false;
  String _key(String phone) => 'otp_next_${sha256.convert(utf8.encode(phone))}';

  Future<void> begin(String phone) async {
    if (_busy) throw StateError('OTP request चल रही है। कृपया प्रतीक्षा करें।');
    _busy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = _now().millisecondsSinceEpoch;
      final next = prefs.getInt(_key(phone)) ?? 0;
      if (next > current) {
        throw StateError(
          '${((next - current) / 1000).ceil()} सेकंड बाद फिर कोशिश करें।',
        );
      }
      await prefs.setInt(_key(phone), current + 60000);
    } catch (_) {
      _busy = false;
      rethrow;
    }
  }

  void finish() => _busy = false;

  Future<void> rateLimited(String phone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _key(phone),
        _now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      );
    } finally {
      finish();
    }
  }
}

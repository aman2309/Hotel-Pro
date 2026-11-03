import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';

class AdminApi {
  Future<Map<String, dynamic>> call(
    String name, [
    Map<String, dynamic> data = const {},
  ]) async {
    final result = await FirebaseFunctions.instanceFor(region: 'asia-south1')
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
        )
        .call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  String requestId() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

List<Map<String, dynamic>> adminItems(Map<String, dynamic> data) =>
    (data['items'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
Map<String, dynamic> adminMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
num adminNumber(dynamic value) =>
    value is num ? value : num.tryParse('$value') ?? 0;
String adminDate(dynamic value) {
  final d = value is num
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
      : DateTime.tryParse('$value');
  if (d == null) return '—';
  final local = d.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String adminMoney(dynamic value) {
  final n = adminNumber(value).round();
  return '₹${n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
}

String adminFailure(Object error) {
  if (error is FirebaseFunctionsException) {
    if (error.code == 'permission-denied') {
      return error.message ?? 'Administrator access required.';
    }
    const messages = {
      'INVALID_DURATION': 'Enter 1–1,200 months or 1–100 years.',
      'KEY_NOT_UNUSED': 'Only unused keys can be revoked.',
      'HOTEL_NOT_FOUND': 'Hotel no longer exists.',
      'REQUEST_REUSED':
          'This request was already used with different settings. Reopen the form.',
    };
    return messages[error.message] ??
        error.message ??
        'Could not load Firebase data. Retry.';
  }
  return 'Could not complete this request. Check internet and retry.';
}

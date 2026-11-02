import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// IDs are assigned once and persisted before a network attempt.
class HotelRecordIds {
  static String create(String prefix) {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return '${prefix}_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  static String guest(String normalizedPhone) =>
      'guest_${sha256.convert(utf8.encode(normalizedPhone))}';
  static String stay(
    String mobile,
    DateTime? bookingTime,
    DateTime? bookingDate,
  ) =>
      'stay_${sha256.convert(utf8.encode('$mobile|${bookingTime?.toIso8601String() ?? bookingDate?.toIso8601String() ?? ''}'))}';
}

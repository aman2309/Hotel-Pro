import 'package:flutter/foundation.dart';

import 'hotel_photo_ref.dart';

/// Temporary runtime probe for one booking photo-upload. Never logs Base64.
class HotelPhotoUploadDebug {
  static const String tag = 'PHOTO_UPLOAD_DEBUG';

  static void stage(
    String numberAndName, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    if (!kDebugMode) return;
    final String extra = details.entries
        .map((MapEntry<String, Object?> e) => '${e.key}=${e.value}')
        .join(' | ');
    debugPrint(
      extra.isEmpty
          ? '[$tag] $numberAndName'
          : '[$tag] $numberAndName | $extra',
    );
  }

  static Map<String, Object?> photoPresence(String raw) {
    final String trimmed = raw.trim();
    return <String, Object?>{
      'present': trimmed.isNotEmpty,
      'looksLikeBase64': HotelPhotoRef.looksLikePhotoBytes(trimmed),
      'base64Length': trimmed.length,
    };
  }
}

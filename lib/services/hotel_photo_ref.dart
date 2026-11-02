/// Local ID-photo metadata for Firestore. Bytes stay on-device / Storage.
class HotelPhotoRef {
  const HotelPhotoRef({
    required this.hasPhoto,
    this.kind,
    this.byteLength,
    this.fileName,
    this.storagePath,
    this.contentType,
    this.sha256,
    this.photoUpdatedAtMs,
  });

  static const bool storageEnabled = true;
  static const String jpegContentType = 'image/jpeg';
  static const int maxBytes = 5 * 1024 * 1024;

  final bool hasPhoto;
  final String? kind;
  final int? byteLength;
  final String? fileName;
  final String? storagePath;
  final String? contentType;
  final String? sha256;
  final int? photoUpdatedAtMs;

  static const Set<String> localPhotoKeys = <String>{
    'idFrontPhoto',
    'idBackPhoto',
    'idFrontPhotoPath',
    'idBackPhotoPath',
    'frontPhoto',
    'backPhoto',
    'idPhotoPath',
    'photoData',
    'photo',
  };

  static bool looksLikePhotoBytes(String value) {
    final String trimmed = value.trim();
    if (trimmed.length < 80) {
      return false;
    }
    if (trimmed.startsWith('file:') || trimmed.startsWith('content:')) {
      return false;
    }
    // JPEG Base64 starts with /9j/ (FF D8 FF). Do not treat that as a file path.
    if (trimmed.startsWith('/') && !trimmed.startsWith('/9j/')) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(trimmed);
  }

  factory HotelPhotoRef.fromLocalValue(dynamic value) {
    if (value == null) {
      return const HotelPhotoRef(hasPhoto: false);
    }
    if (value is Map) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(value);
      return HotelPhotoRef(
        hasPhoto: map['hasPhoto'] == true,
        kind: map['kind']?.toString(),
        byteLength: map['byteLength'] is num
            ? (map['byteLength'] as num).toInt()
            : null,
        fileName: map['fileName']?.toString(),
        storagePath: _nonEmpty(map['storagePath'] ?? map['idFrontStoragePath']),
        contentType: map['contentType']?.toString(),
        sha256: map['sha256']?.toString(),
        photoUpdatedAtMs: map['photoUpdatedAt'] is num
            ? (map['photoUpdatedAt'] as num).toInt()
            : null,
      );
    }
    final String raw = value.toString();
    if (raw.isEmpty) {
      return const HotelPhotoRef(hasPhoto: false);
    }
    if (looksLikePhotoBytes(raw)) {
      return HotelPhotoRef(
        hasPhoto: true,
        kind: 'localBase64',
        byteLength: raw.length,
      );
    }
    final String name = raw.split('/').last.split('\\').last;
    return HotelPhotoRef(
      hasPhoto: true,
      kind: 'localPath',
      fileName: name.isEmpty ? null : name,
    );
  }

  HotelPhotoRef withStorage({
    required String path,
    String? contentType,
    int? byteLength,
    String? sha256,
    int? photoUpdatedAtMs,
  }) {
    return HotelPhotoRef(
      hasPhoto: true,
      kind: kind ?? 'localBase64',
      byteLength: byteLength ?? this.byteLength,
      fileName: fileName,
      storagePath: path,
      contentType: contentType ?? this.contentType ?? jpegContentType,
      sha256: sha256 ?? this.sha256,
      photoUpdatedAtMs: photoUpdatedAtMs ?? this.photoUpdatedAtMs,
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'hasPhoto': hasPhoto,
      'kind': kind,
      'byteLength': byteLength,
      'fileName': fileName,
      'storagePath': storagePath,
      'contentType': contentType,
      'sha256': sha256,
      'photoUpdatedAt': photoUpdatedAtMs,
      'storageEnabled': storageEnabled,
    };
  }

  /// Local string fields stay empty until Storage restore fills Base64.
  String toLocalString() => '';

  static String? _nonEmpty(dynamic value) {
    final String text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }
}

class HotelPhotoPaths {
  HotelPhotoPaths._();

  static String front(String businessId, String guestId) =>
      'businesses/$businessId/guests/$guestId/id_front.jpg';

  static String back(String businessId, String guestId) =>
      'businesses/$businessId/guests/$guestId/id_back.jpg';

  static String additionalFront(
    String businessId,
    String guestId,
    String additionalGuestId,
  ) =>
      'businesses/$businessId/guests/$guestId/additional/$additionalGuestId/id_front.jpg';

  static String additionalBack(
    String businessId,
    String guestId,
    String additionalGuestId,
  ) =>
      'businesses/$businessId/guests/$guestId/additional/$additionalGuestId/id_back.jpg';

  static String additionalGuestId({
    required String mobile,
    required String idNumber,
    String? customerId,
  }) {
    final String existing = (customerId ?? '').trim();
    if (existing.isNotEmpty) {
      return existing;
    }
    final String digits = mobile.replaceAll(RegExp(r'\D'), '');
    final String id = idNumber.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final String token = '${digits}_$id';
    return token.isEmpty ? 'ag_unknown' : 'ag_$token';
  }

  static String metaKey({
    required String guestId,
    required String side,
    String? additionalGuestId,
  }) {
    if (additionalGuestId == null || additionalGuestId.isEmpty) {
      return '$guestId:$side';
    }
    return '$guestId:additional:$additionalGuestId:$side';
  }

  /// Content-addressed versions preserve both copies of concurrent ID edits.
  static String versioned(String path, String sha) {
    final parts = path.split('/');
    final file = parts.removeLast();
    return '${parts.join('/')}/versions/$sha/$file';
  }

  static String? metaKeyFromStoragePath(String path) {
    final List<String> parts = path.split('/');
    if (parts.length < 5 || parts[0] != 'businesses' || parts[2] != 'guests') {
      return null;
    }
    final String guestId = parts[3];
    if (parts.length >= 7 && parts[4] == 'additional') {
      final String file = parts.last;
      return metaKey(
        guestId: guestId,
        additionalGuestId: parts[5],
        side: file.contains('back') ? 'back' : 'front',
      );
    }
    if (parts.length >= 5) {
      final String file = parts.last;
      return metaKey(
        guestId: guestId,
        side: file.contains('back') ? 'back' : 'front',
      );
    }
    return null;
  }
}

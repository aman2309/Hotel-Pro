import 'hotel_photo_ref.dart';

const syncPhotoFields = <String>{
  'idFrontPhoto',
  'idBackPhoto',
  'idFrontPhotoPath',
  'idBackPhotoPath',
  'idFrontBase64',
  'idBackBase64',
  'frontPhoto',
  'backPhoto',
  'idPhotoPath',
  'photoData',
  'photo',
};

/// Removes ID-photo bytes from a sync payload. Local prefs keep the photos.
Map<String, dynamic> syncPayloadForServer(Map<String, dynamic> payload) {
  final copy = Map<String, dynamic>.from(payload);
  for (final field in syncPhotoFields) {
    final value = copy[field];
    if (value is String && _isPhotoBody(value)) {
      copy.remove(field);
    }
  }
  for (final listField in const ['extraGuests', 'futureExtraGuests']) {
    final list = copy[listField];
    if (list is! List) continue;
    copy[listField] = list.map((item) {
      if (item is! Map) return item;
      return syncPayloadForServer(Map<String, dynamic>.from(item));
    }).toList();
  }
  return copy;
}

bool _isPhotoBody(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  return HotelPhotoRef.looksLikePhotoBytes(trimmed) || trimmed.length > 80;
}

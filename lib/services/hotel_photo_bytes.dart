import 'dart:convert';
import 'hotel_photo_file_stub.dart'
    if (dart.library.io) 'hotel_photo_file_io.dart';
import 'dart:typed_data';

import 'hotel_photo_ref.dart';

/// Reads an ID photo stored either as JPEG bytes or as a local file path.
Uint8List? hotelPhotoBytes(String photoData) {
  final String trimmed = photoData.trim();
  if (trimmed.isEmpty) return null;
  if (!HotelPhotoRef.looksLikePhotoBytes(trimmed)) {
    return _readFile(trimmed);
  }
  try {
    return base64Decode(trimmed);
  } catch (_) {
    return _readFile(trimmed);
  }
}

Uint8List? _readFile(String path) => readHotelPhotoFile(path);

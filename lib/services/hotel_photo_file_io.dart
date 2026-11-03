import 'dart:io';
import 'dart:typed_data';

Uint8List? readHotelPhotoFile(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final bytes = file.readAsBytesSync();
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}

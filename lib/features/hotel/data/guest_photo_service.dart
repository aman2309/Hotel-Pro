import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../models/customer.dart';
import '../../../models/room.dart';
import '../../../services/hotel_photo_bytes.dart';
import '../../../services/hotel_photo_ref.dart';
import '../../../services/hotel_photo_storage_service.dart'
    show compressHotelIdPhoto;

/// Transfers photo bytes to/from Storage; never stores them in Firestore or disk.
class GuestPhotoService {
  GuestPhotoService._();
  static final GuestPhotoService instance = GuestPhotoService._();
  final Map<String, String> _downloaded = {};

  Future<Map<String, String>> uploadCustomerPhotos(
    String businessId,
    Customer guest,
  ) async {
    final paths = <String, String>{};
    if (guest.customerId.isEmpty) {
      throw ArgumentError('Guest identity is required.');
    }
    for (final front in [true, false]) {
      final raw = front ? guest.idFrontPhotoPath : guest.idBackPhotoPath;
      if (raw.trim().isEmpty) continue;
      final side = front ? 'front' : 'back';
      final key = HotelPhotoPaths.metaKey(
        guestId: guest.customerId,
        side: side,
      );
      if (raw.startsWith('businesses/$businessId/')) {
        paths[key] = raw;
        continue;
      }
      final original = hotelPhotoBytes(raw);
      if (original == null) {
        throw FormatException('Guest $side photo could not be read.');
      }
      final bytes = compressHotelIdPhoto(original);
      if (bytes.length > HotelPhotoRef.maxBytes) {
        throw StateError('ID photo exceeds 5 MB.');
      }
      final base = front
          ? HotelPhotoPaths.front(businessId, guest.customerId)
          : HotelPhotoPaths.back(businessId, guest.customerId);
      final path = HotelPhotoPaths.versioned(
        base,
        sha256.convert(bytes).toString(),
      );
      await FirebaseStorage.instance
          .ref(path)
          .putData(
            bytes,
            SettableMetadata(contentType: HotelPhotoRef.jpegContentType),
          );
      paths[key] = path;
      _downloaded[path] = base64Encode(bytes);
    }
    return paths;
  }

  Future<void> hydrateGuests({
    required String businessId,
    required List<Customer> guests,
    required Map<String, Map<String, dynamic>> guestDocs,
  }) async {
    for (final guest in guests) {
      final doc = guestDocs[guest.customerId];
      if (doc == null || doc['deleted'] == true) continue;
      for (final front in [true, false]) {
        final field = front ? 'idFrontPhotoPath' : 'idBackPhotoPath';
        final metadata = HotelPhotoRef.fromLocalValue(doc[field]);
        final path =
            (doc[front ? 'idFrontStoragePath' : 'idBackStoragePath'] ??
                    metadata.storagePath)
                ?.toString();
        if (path == null || path.isEmpty) continue;
        if (!path.startsWith('businesses/$businessId/guests/')) {
          throw StateError('Photo belongs to a different hotel.');
        }
        var bytes = _downloaded[path];
        if (bytes == null) {
          final data = await FirebaseStorage.instance
              .ref(path)
              .getData(HotelPhotoRef.maxBytes);
          if (data == null) {
            throw StateError('Photo download returned no data.');
          }
          bytes = base64Encode(data);
          _downloaded[path] = bytes;
        }
        if (front) {
          guest.idFrontPhotoPath = bytes;
        } else {
          guest.idBackPhotoPath = bytes;
        }
      }
    }
  }

  void hydrateRoomExtras({
    required List<Room> rooms,
    required List<Customer> guests,
  }) {
    String phone(String value) => value
        .replaceAll(RegExp(r'\D'), '')
        .replaceFirst(RegExp(r'^91(?=\d{10}$)'), '');
    for (final room in rooms) {
      for (final extra in [...room.extraGuests, ...room.futureExtraGuests]) {
        final mobile = phone('${extra['mobile'] ?? ''}');
        if (mobile.isEmpty) continue;
        for (final guest in guests) {
          if (phone(guest.mobile) != mobile) continue;
          if (guest.idFrontPhotoPath.isNotEmpty) {
            extra['idFrontPhoto'] = guest.idFrontPhotoPath;
          }
          if (guest.idBackPhotoPath.isNotEmpty) {
            extra['idBackPhoto'] = guest.idBackPhotoPath;
          }
          break;
        }
      }
    }
  }
}

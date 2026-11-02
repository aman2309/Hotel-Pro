import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A conflict never authorizes replacing another device's record.
class HotelSyncConflict implements Exception {
  HotelSyncConflict(this.paths);
  final List<String> paths;
  @override
  String toString() =>
      'Another device changed ${paths.join(', ')}. '
      'Local changes are saved; review the conflict before continuing.';
}

/// Compare business fields, not wall clocks or independently uploaded photos.
String hotelRecordFingerprint(Map<String, dynamic>? record) {
  if (record == null) return 'missing';
  if (record['deleted'] == true) return 'deleted';
  record = {'deleted': false, ...record};
  dynamic canonical(dynamic value) {
    if (value is Map) {
      final keys =
          value.keys
              .map((key) => key.toString())
              .where(
                (key) => !const {
                  'updatedAt',
                  'createdAt',
                  'updatedAtMs',
                  'deviceId',
                  'schemaVersion',
                  'photoUpdatedAt',
                  'idFrontPhotoPath',
                  'idBackPhotoPath',
                  'idFrontPhoto',
                  'idBackPhoto',
                  'frontPhoto',
                  'backPhoto',
                  'additionalPhotos',
                  'hasFrontPhoto',
                  'hasBackPhoto',
                  'idFrontStoragePath',
                  'idBackStoragePath',
                  'idFrontSha256',
                  'idBackSha256',
                  'idFrontByteLength',
                  'idBackByteLength',
                  'idFrontContentType',
                  'idBackContentType',
                }.contains(key),
              )
              .toList()
            ..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList();
    if (value is num && value == value.roundToDouble()) return value.toInt();
    return value;
  }

  return sha256.convert(utf8.encode(jsonEncode(canonical(record)))).toString();
}

class HotelSyncChange {
  const HotelSyncChange(this.path, this.expected, this.data);
  final String path;
  final String expected;
  final Map<String, dynamic> data;
  Map<String, dynamic> toJson() => {
    'path': path,
    'expected': expected,
    'data': data,
  };
  factory HotelSyncChange.fromJson(Map<String, dynamic> json) =>
      HotelSyncChange(
        json['path'] as String,
        json['expected'] as String,
        Map<String, dynamic>.from(json['data'] as Map),
      );
}

/// Only edits relative to a persisted local baseline become writes. Absence
/// never deletes unknown remote records. Financial/history records are retained.
List<HotelSyncChange> planHotelChanges({
  required Map<String, Map<String, dynamic>> local,
  required Map<String, String> baseline,
  required Map<String, String> remoteBaseline,
}) {
  final changes = <HotelSyncChange>[];
  for (final entry in local.entries) {
    final fingerprint = hotelRecordFingerprint(entry.value);
    if (baseline[entry.key] == fingerprint) continue;
    changes.add(
      HotelSyncChange(
        entry.key,
        remoteBaseline[entry.key] ?? 'missing',
        entry.value,
      ),
    );
  }
  for (final path in baseline.keys) {
    if (local.containsKey(path)) continue;
    final collection = path.split('/').first;
    if (!const {
      'rooms',
      'bookings',
      'futureBookings',
      'closedRooms',
    }.contains(collection)) {
      continue;
    }
    // Completed bookings are an audit trail, never inferred deletions.
    if (collection == 'bookings' && !path.startsWith('bookings/bkg_room_')) {
      continue;
    }
    changes.add(
      HotelSyncChange(path, remoteBaseline[path] ?? 'missing', {
        'deleted': true,
      }),
    );
  }
  return changes;
}

/// Transaction retries after an uncertain acknowledgement are idempotent.
bool hotelChangeCanCommit(
  HotelSyncChange change,
  Map<String, dynamic>? current,
) {
  if (hotelRecordFingerprint(current) == change.expected) return true;
  if (current == null) return false;
  // A merge retains legacy unknown fields. A retry compares authored fields,
  // while arrays (room payments/bookings) still compare in their entirety.
  final authored = {for (final key in change.data.keys) key: current[key]};
  authored['deleted'] = current['deleted'] ?? false;
  return hotelRecordFingerprint(authored) ==
      hotelRecordFingerprint(change.data);
}

/// Reject ambiguous or foreign mappings; UID mapping is authoritative.
String? resolveHotelMapping({
  required String uid,
  String? userBusinessId,
  String? phoneBusinessId,
  String? phoneOwnerUid,
  List<String> legacyOwnedBusinesses = const [],
}) {
  if (userBusinessId != null && userBusinessId.isNotEmpty) {
    if (phoneBusinessId != null && phoneBusinessId != userBusinessId) {
      throw StateError('UID and phone index map to different hotels.');
    }
    return userBusinessId;
  }
  if (phoneBusinessId != null) {
    if (phoneOwnerUid != uid) {
      throw StateError(
        'Phone index belongs to another owner; support review required.',
      );
    }
    return phoneBusinessId;
  }
  if (legacyOwnedBusinesses.length > 1) {
    throw StateError('Multiple legacy hotels found; mapping review required.');
  }
  return legacyOwnedBusinesses.isEmpty ? null : legacyOwnedBusinesses.single;
}

/// Production rules reject listing businesses. That denial is not an existing
/// hotel when this number has no user document and no phone index.
bool firstHotelForSignedInNumber({
  required bool userDocumentExists,
  required bool phoneIndexExists,
}) {
  return !userDocumentExists && !phoneIndexExists;
}

String? legacyHotelAfterList({
  required String uid,
  required bool listPermissionDenied,
  List<String> legacyOwnedBusinesses = const [],
}) {
  if (listPermissionDenied) return null;
  return resolveHotelMapping(
    uid: uid,
    legacyOwnedBusinesses: legacyOwnedBusinesses,
  );
}

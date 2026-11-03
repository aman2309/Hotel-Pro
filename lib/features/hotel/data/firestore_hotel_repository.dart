import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../models/bill_record.dart';
import '../../../models/customer.dart';
import '../../../models/room.dart';
import '../../../services/hotel_cloud_codec.dart';
import '../../../services/hotel_firestore_service.dart';
import '../../../services/hotel_sync_plan.dart';
import '../domain/entities/hotel_data.dart';
import '../domain/entities/hotel_settings.dart';
import '../domain/repositories/hotel_repository.dart';
import 'guest_photo_service.dart';

/// Firestore implementation of [HotelRepository].
///
/// Every read is a live snapshot and every write is an atomic batch that also
/// tombstones records which no longer apply (for example a room booking that
/// was checked out). Nothing is persisted to the device: a fresh install
/// rebuilds the whole hotel from Firestore on first snapshot.
class FirestoreHotelRepository implements HotelRepository {
  FirestoreHotelRepository({HotelFirestoreService? firestore})
    : _firestore = firestore ?? HotelFirestoreService.instance;

  final HotelFirestoreService _firestore;
  final HotelCloudCodec _codec = HotelCloudCodec(deviceId: 'hotel-pro-app');
  final Map<String, _BusinessCache> _cache = <String, _BusinessCache>{};

  static const List<String> _watchCollections = <String>[
    'rooms',
    'bookings',
    'futureBookings',
    'closedRooms',
    'bills',
    'guests',
    'expenses',
    'settings',
    'payments',
    'extraCharges',
  ];

  @override
  Stream<HotelData> watch(String businessId) {
    return Stream<HotelData>.multi((MultiStreamController<HotelData> multi) {
      final _BusinessCache cache = _cache.putIfAbsent(
        businessId,
        () => _BusinessCache(),
      );
      final Set<String> ready = <String>{};
      final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> subs =
          <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
      bool disposed = false;
      HotelData? last;

      void emit() {
        if (disposed || multi.isClosed) return;
        final HotelData data = _decode(businessId, cache);
        last = data;
        multi.add(data);
        _hydratePhotos(businessId, cache, data, () {
          if (disposed || multi.isClosed) return;
          multi.add(last ?? data);
        });
      }

      for (final String name in _watchCollections) {
        subs.add(
          _firestore
              .col(businessId, name)
              .snapshots(includeMetadataChanges: true)
              .listen(
                (QuerySnapshot<Map<String, dynamic>> snapshot) {
                  if (snapshot.metadata.isFromCache ||
                      snapshot.metadata.hasPendingWrites) {
                    return;
                  }
                  cache.replace(name, snapshot);
                  ready.add(name);
                  if (ready.length == _watchCollections.length) {
                    emit();
                  }
                },
                onError: (Object error, StackTrace stack) {
                  if (!disposed && !multi.isClosed) {
                    multi.addError(error, stack);
                  }
                },
              ),
        );
      }

      multi.onCancel = () async {
        disposed = true;
        for (final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> sub
            in subs) {
          await sub.cancel();
        }
      };
    });
  }

  HotelData _decode(String businessId, _BusinessCache cache) {
    final List<Map<String, dynamic>> roomDocs = cache.docs('rooms');
    final List<Room> rooms = _codec.roomsFromCloud(roomDocs);
    _codec.mergeRelatedIntoRooms(
      rooms: rooms,
      bookings: cache.docs('bookings'),
      futureBookings: cache.docs('futureBookings'),
      closedRooms: cache.docs('closedRooms'),
    );
    final HotelSettingsData settings = HotelSettingsData.fromMap(
      Map<String, dynamic>.from(
        _codec.toLocalValue(
              Map<String, dynamic>.from(
                cache.collections['settings']?['hotel'] ?? <String, dynamic>{},
              ),
            )
            as Map,
      ),
    );
    return HotelData(
      rooms: rooms,
      bills: _codec.billsFromCloud(cache.docs('bills')),
      customers: _codec.guestsFromCloud(cache.docs('guests')),
      expenses: _codec.expensesFromCloud(cache.docs('expenses')),
      settings: settings,
    );
  }

  void _hydratePhotos(
    String businessId,
    _BusinessCache cache,
    HotelData data,
    void Function() onReady,
  ) {
    final String signature = cache
        .docs('guests')
        .map(
          (Map<String, dynamic> doc) =>
              '${doc['customerId']}:${doc['idFrontStoragePath']}:'
              '${doc['idBackStoragePath']}:${doc['photoUpdatedAt']}',
        )
        .join('|');
    if (signature.isEmpty || cache.lastPhotoSignature == signature) {
      return;
    }
    cache.lastPhotoSignature = signature;
    unawaited(() async {
      try {
        await GuestPhotoService.instance.hydrateGuests(
          businessId: businessId,
          guests: data.customers,
          guestDocs: <String, Map<String, dynamic>>{
            for (final Map<String, dynamic> doc in cache.docs('guests'))
              if ((doc['customerId'] ?? '').toString().isNotEmpty)
                doc['customerId'].toString(): doc,
          },
        );
        GuestPhotoService.instance.hydrateRoomExtras(
          rooms: data.rooms,
          guests: data.customers,
        );
        onReady();
      } catch (error) {
        cache.lastPhotoSignature = null;
        debugPrint('[HotelRepository] photo hydrate skipped: $error');
      }
    }());
  }

  @override
  Future<void> saveRoom(String businessId, Room room) async {
    final cache = _requireCache(businessId);
    final snapshot = _codec.build(
      rooms: [room],
      bills: const [],
      guests: const [],
      expenses: const [],
      settings: _settingsMap(cache),
    );
    final docs = snapshot.docs
        .where(
          (doc) => const {
            'rooms',
            'bookings',
            'futureBookings',
            'closedRooms',
            'payments',
            'extraCharges',
          }.contains(doc.collection),
        )
        .toList();
    final newIds = _ids(docs);
    final projections = {
      'bookings': HotelCloudCodec.currentBookingId(room.roomNumber),
      'futureBookings': HotelCloudCodec.futureBookingId(room.roomNumber),
      'closedRooms': HotelCloudCodec.closedRoomId(room.roomNumber),
    };
    final tombstones = <HotelCloudDoc>[
      for (final entry in projections.entries)
        if (cache.doc(entry.key, entry.value) != null &&
            !newIds.contains('${entry.key}/${entry.value}'))
          _tombstone(entry.key, entry.value),
    ];
    await _commit(businessId, cache, docs, tombstones);
  }

  /// Replaces the complete room set. Stale rooms and their booking, payment,
  /// charge and closed-room projections are tombstoned in the same batch.
  @override
  Future<void> saveRooms(String businessId, List<Room> rooms) async {
    final _BusinessCache? cache = _cache[businessId];
    final HotelCloudSnapshot snapshot = _codec.build(
      rooms: rooms,
      bills: const <BillRecord>[],
      guests: const <Customer>[],
      expenses: const <Map<String, dynamic>>[],
      settings: _settingsMap(cache),
    );
    final List<HotelCloudDoc> docs = snapshot.docs
        .where(
          (HotelCloudDoc doc) => const {
            'rooms',
            'bookings',
            'futureBookings',
            'closedRooms',
            'payments',
            'extraCharges',
          }.contains(doc.collection),
        )
        .toList();
    final Set<String> newIds = _ids(docs);
    final List<HotelCloudDoc> tombstones = <HotelCloudDoc>[];
    if (cache != null) {
      for (final collection in [
        'rooms',
        'bookings',
        'futureBookings',
        'closedRooms',
      ]) {
        for (final id in cache.ids(collection)) {
          if (collection == 'bookings' && !id.startsWith('bkg_room_')) continue;
          if (!newIds.contains('$collection/$id')) {
            tombstones.add(_tombstone(collection, id));
          }
        }
      }
    }
    await _commit(businessId, cache, docs, tombstones);
  }

  @override
  Future<void> deleteRoom(String businessId, int roomNumber) async {
    final _BusinessCache? cache = _cache[businessId];
    final List<HotelCloudDoc> tombstones = <HotelCloudDoc>[];
    if (cache != null) {
      for (final String id in cache.ids('rooms')) {
        final Map<String, dynamic>? doc = cache.doc('rooms', id);
        if (doc != null && doc['roomNumber'] == roomNumber) {
          tombstones.add(_tombstone('rooms', id));
        }
      }
    }
    tombstones.add(_tombstone('rooms', HotelCloudCodec.roomId(roomNumber)));
    await _commit(businessId, cache, const <HotelCloudDoc>[], tombstones);
  }

  @override
  Future<void> saveCustomer(String businessId, Customer customer) async {
    final String guestId = customer.customerId.trim();
    if (guestId.isEmpty) return;
    final _BusinessCache? cache = _cache[businessId];
    final Map<String, String> paths = await GuestPhotoService.instance
        .uploadCustomerPhotos(businessId, customer);
    final HotelCloudSnapshot snapshot = _codec.build(
      rooms: const <Room>[],
      bills: const <BillRecord>[],
      guests: <Customer>[customer],
      expenses: const <Map<String, dynamic>>[],
      settings: _settingsMap(cache),
      photoStoragePaths: paths,
    );
    final List<HotelCloudDoc> docs = snapshot.docs
        .where((HotelCloudDoc doc) => doc.collection == 'guests')
        .map((HotelCloudDoc doc) {
          final Map<String, dynamic>? cloud = cache?.doc('guests', doc.id);
          return HotelCloudDoc(
            collection: doc.collection,
            id: doc.id,
            data: HotelCloudCodec.mergeGuestPhotoMetadata(
              local: doc.data,
              cloud: cloud,
            ),
          );
        })
        .toList();
    await _commit(businessId, cache, docs, const <HotelCloudDoc>[]);
  }

  @override
  Future<void> saveBill(String businessId, BillRecord bill) async {
    final _BusinessCache? cache = _cache[businessId];
    final HotelCloudSnapshot snapshot = _codec.build(
      rooms: const <Room>[],
      bills: <BillRecord>[bill],
      guests: const <Customer>[],
      expenses: const <Map<String, dynamic>>[],
      settings: _settingsMap(cache),
    );
    final docs = snapshot.docs
        .where(
          (doc) => const {
            'bills',
            'bookings',
            'payments',
            'extraCharges',
          }.contains(doc.collection),
        )
        .toList();
    await _commit(businessId, cache, docs, const []);
  }

  @override
  Future<void> saveExpenses(
    String businessId,
    List<Map<String, dynamic>> expenses,
  ) async {
    final _BusinessCache? cache = _cache[businessId];
    final HotelCloudSnapshot snapshot = _codec.build(
      rooms: const <Room>[],
      bills: const <BillRecord>[],
      guests: const <Customer>[],
      expenses: expenses,
      settings: _settingsMap(cache),
    );
    final List<HotelCloudDoc> docs = snapshot.docs
        .where((HotelCloudDoc doc) => doc.collection == 'expenses')
        .toList();
    final Set<String> newIds = _ids(docs);
    final List<HotelCloudDoc> tombstones = <HotelCloudDoc>[];
    if (cache != null) {
      for (final String id in cache.ids('expenses')) {
        if (!newIds.contains('expenses/$id')) {
          tombstones.add(_tombstone('expenses', id));
        }
      }
    }
    await _commit(businessId, cache, docs, tombstones);
  }

  @override
  Future<void> saveSettings(
    String businessId,
    HotelSettingsData settings,
  ) async {
    final _BusinessCache? cache = _cache[businessId];
    final HotelCloudSnapshot snapshot = _codec.build(
      rooms: const <Room>[],
      bills: const <BillRecord>[],
      guests: const <Customer>[],
      expenses: const <Map<String, dynamic>>[],
      settings: settings.toMap(),
    );
    final List<HotelCloudDoc> docs = snapshot.docs
        .where((HotelCloudDoc doc) => doc.collection == 'settings')
        .toList();
    await _commit(businessId, cache, docs, const <HotelCloudDoc>[]);
  }

  @override
  Future<void> replaceAll(String businessId, HotelData data) async {
    final _BusinessCache? cache = _cache[businessId];
    final Map<String, String> photoPaths = <String, String>{};
    for (final Customer guest in data.customers) {
      photoPaths.addAll(
        await GuestPhotoService.instance.uploadCustomerPhotos(
          businessId,
          guest,
        ),
      );
    }
    final HotelCloudSnapshot snapshot = _codec.build(
      rooms: data.rooms,
      bills: data.bills,
      guests: data.customers,
      expenses: data.expenses,
      settings: data.settings.toMap(),
      photoStoragePaths: photoPaths,
    );
    final List<HotelCloudDoc> docs = snapshot.docs
        .where(
          (HotelCloudDoc doc) =>
              doc.collection != 'settings' || doc.id == 'hotel',
        )
        .toList();
    final Set<String> newIds = _ids(docs);
    final List<HotelCloudDoc> tombstones = <HotelCloudDoc>[];
    if (cache != null) {
      for (final String collection in HotelFirestorePaths.businessCollections) {
        for (final String id in cache.ids(collection)) {
          if (collection == 'settings' &&
              (id == 'license' || id == 'sync' || id == 'onboarding')) {
            continue;
          }
          if (!newIds.contains('$collection/$id')) {
            tombstones.add(_tombstone(collection, id));
          }
        }
      }
    }
    await _commit(businessId, cache, docs, tombstones);
  }

  _BusinessCache _requireCache(String businessId) {
    final cache = _cache[businessId];
    if (cache == null ||
        !_watchCollections.every(cache.collections.containsKey)) {
      throw StateError('Load the complete hotel from Firebase before saving.');
    }
    return cache;
  }

  Future<void> _commit(
    String businessId,
    _BusinessCache? unusedCache,
    List<HotelCloudDoc> docs,
    List<HotelCloudDoc> tombstones,
  ) async {
    final cache = _requireCache(businessId);
    final desired = <String, HotelCloudDoc>{
      for (final doc in [...docs, ...tombstones])
        '${doc.collection}/${doc.id}': doc,
    };
    final expected = <String, Map<String, dynamic>?>{
      for (final entry in desired.entries)
        entry.key: cache.doc(entry.value.collection, entry.value.id),
    };
    final changes = desired.entries
        .where(
          (entry) =>
              hotelRecordFingerprint(entry.value.data) !=
                  hotelRecordFingerprint(expected[entry.key]) ||
              (entry.value.collection == 'guests' &&
                  _photoPaths(entry.value.data) !=
                      _photoPaths(expected[entry.key])),
        )
        .toList();
    if (changes.isEmpty) return;
    if (changes.length > 400) {
      throw StateError('Too many related changes for one atomic save.');
    }
    final db = _firestore.businessDoc(businessId).firestore;
    final committed = await db.runTransaction((tx) async {
      final owner = await tx.get(_firestore.businessDoc(businessId));
      if (owner.data()?['ownerUid'] != _firestore.account?.ownerUid ||
          _firestore.businessId != businessId) {
        throw StateError('Hotel account changed. Sign in again.');
      }
      final syncRef = _firestore.col(businessId, 'settings').doc('sync');
      final sync = await tx.get(syncRef);
      if (sync.data()?['migrationInProgress'] == true) {
        throw StateError('Hotel migration in progress. Retry later.');
      }
      final current = <String, Map<String, dynamic>?>{};
      for (final entry in changes) {
        final doc = entry.value;
        current[entry.key] = (await tx.get(
          _firestore.col(businessId, doc.collection).doc(doc.id),
        )).data();
      }
      final payloads = <String, Map<String, dynamic>>{};
      for (final entry in changes) {
        final doc = entry.value;
        final operation = HotelSyncChange(
          entry.key,
          hotelRecordFingerprint(expected[entry.key]),
          doc.data,
        );
        if (!hotelChangeCanCommit(operation, current[entry.key])) {
          throw HotelSyncConflict([entry.key]);
        }
        payloads[entry.key] = doc.collection == 'guests'
            ? mergeRepositoryGuestPhotos(
                doc.data,
                expected[entry.key],
                current[entry.key],
              )
            : doc.data;
      }
      for (final entry in changes) {
        final doc = entry.value;
        tx.set(
          _firestore.col(businessId, doc.collection).doc(doc.id),
          {
            ...payloads[entry.key]!,
            'schemaVersion': 3,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      tx.set(syncRef, {
        'schemaVersion': 3,
        'lastSyncAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return payloads;
    });
    for (final entry in changes) {
      final doc = entry.value;
      final now = hotelRecordFingerprint(cache.doc(doc.collection, doc.id));
      if (now == hotelRecordFingerprint(expected[entry.key]) ||
          now == hotelRecordFingerprint(committed[entry.key])) {
        cache.put(doc.collection, doc.id, {
          ...?cache.doc(doc.collection, doc.id),
          ...committed[entry.key]!,
        });
      }
    }
  }

  String _photoPaths(Map<String, dynamic>? data) =>
      '${data?['idFrontStoragePath']}|${data?['idBackStoragePath']}';

  @override
  Future<void> dispose() async {
    _cache.clear();
  }

  HotelCloudDoc _tombstone(String collection, String id) =>
      HotelCloudDoc(collection: collection, id: id, data: _codec.tombstone());

  Set<String> _ids(List<HotelCloudDoc> docs) => <String>{
    for (final HotelCloudDoc doc in docs) '${doc.collection}/${doc.id}',
  };

  Map<String, dynamic> _settingsMap(_BusinessCache? cache) {
    return Map<String, dynamic>.from(
      _codec.toLocalValue(
            Map<String, dynamic>.from(
              cache?.collections['settings']?['hotel'] ?? <String, dynamic>{},
            ),
          )
          as Map,
    );
  }
}

class _BusinessCache {
  final Map<String, Map<String, Map<String, dynamic>>> collections =
      <String, Map<String, Map<String, dynamic>>>{};
  String? lastPhotoSignature;

  void replace(String name, QuerySnapshot<Map<String, dynamic>> snapshot) {
    collections[name] = <String, Map<String, dynamic>>{
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        doc.id: _record(name, doc.id, doc.data()),
    };
  }

  Map<String, dynamic> _record(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) {
    if (collection == 'guests' &&
        (data['customerId'] ?? '').toString().trim().isEmpty) {
      return <String, dynamic>{...data, 'customerId': id};
    }
    return data;
  }

  void put(String collection, String id, Map<String, dynamic> data) {
    collections.putIfAbsent(
      collection,
      () => <String, Map<String, dynamic>>{},
    )[id] = data;
  }

  Map<String, dynamic>? doc(String collection, String id) =>
      collections[collection]?[id];

  Iterable<String> ids(String collection) =>
      collections[collection]?.keys ?? const <String>[];

  List<Map<String, dynamic>> docs(String collection) =>
      collections[collection]?.values.toList() ?? <Map<String, dynamic>>[];
}

/// Merge independent photo edits without overwriting another device's upload.
Map<String, dynamic> mergeRepositoryGuestPhotos(
  Map<String, dynamic> local,
  Map<String, dynamic>? expected,
  Map<String, dynamic>? current,
) {
  final out = HotelCloudCodec.mergeGuestPhotoMetadata(
    local: local,
    cloud: current,
  );
  for (final side in ['Front', 'Back']) {
    final key = 'id${side}StoragePath';
    final next = local[key];
    final before = expected?[key];
    final remote = current?[key];
    final changed = next != null && next != before;
    if (changed && remote != before && remote != next) {
      throw HotelSyncConflict(['guests/photo/$side']);
    }
    if (!changed && current != null) {
      for (final field in [
        'has${side}Photo',
        key,
        'id${side}PhotoPath',
        'id${side}Sha256',
        'id${side}ByteLength',
        'id${side}ContentType',
      ]) {
        if (current.containsKey(field)) out[field] = current[field];
      }
    }
  }
  return out;
}

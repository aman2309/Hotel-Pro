import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'hotel_data_buffer.dart';
import 'firebase_owner_identity.dart';

import '../models/hotel_cloud_account.dart';
import 'hotel_sync_plan.dart';
import 'phone_auth_service.dart';
import '../stores/hotel_settings_store.dart';

/// Firestore paths for Hotel Pro cloud backup.
///
/// users/{uid}
/// businesses/{businessId}
/// businesses/{businessId}/rooms/{roomId}
/// businesses/{businessId}/bookings/{bookingId}
/// businesses/{businessId}/guests/{guestId}
/// businesses/{businessId}/bills/{billId}
/// businesses/{businessId}/payments/{paymentId}
/// businesses/{businessId}/futureBookings/{bookingId}
/// businesses/{businessId}/expenses/{expenseId}
/// businesses/{businessId}/settings/{settingId}
/// businesses/{businessId}/closedRooms/{recordId}
/// businesses/{businessId}/extraCharges/{chargeId}
class HotelFirestorePaths {
  HotelFirestorePaths._();

  static const String users = 'users';
  static const String businesses = 'businesses';
  static const String rooms = 'rooms';
  static const String bookings = 'bookings';
  static const String guests = 'guests';
  static const String bills = 'bills';
  static const String payments = 'payments';
  static const String futureBookings = 'futureBookings';
  static const String expenses = 'expenses';
  static const String settings = 'settings';
  static const String closedRooms = 'closedRooms';
  static const String extraCharges = 'extraCharges';
  static const String phoneIndex = 'phoneIndex';

  static const List<String> businessCollections = <String>[
    rooms,
    bookings,
    guests,
    bills,
    payments,
    futureBookings,
    expenses,
    settings,
    closedRooms,
    extraCharges,
  ];
}

/// Owns all Cloud Firestore access for Hotel Pro.
///
/// Phase 2 uploads/restores hotel documents through [HotelCloudSyncService].
/// This class keeps collection paths and batched writes in one place.
class HotelFirestoreService {
  HotelFirestoreService._();

  static final HotelFirestoreService instance = HotelFirestoreService._();

  static const String _logTag = 'HotelFirestore';
  static const String _prefBusinessId = 'hotel_firestore_business_id';
  static const String _prefOwnerUid = 'hotel_firestore_owner_uid';
  static const String ownerRole = 'owner';

  HotelCloudAccount? _account;
  String? _createdBusinessThisSession;
  String? lastError;

  HotelCloudAccount? get account => _account;
  String? get businessId => _account?.businessId;
  bool wasBusinessCreatedThisSession(String businessId) =>
      _createdBusinessThisSession == businessId;

  bool get isAvailable => Firebase.apps.isNotEmpty;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get usersCol =>
      _db.collection(HotelFirestorePaths.users);

  CollectionReference<Map<String, dynamic>> get businessesCol =>
      _db.collection(HotelFirestorePaths.businesses);

  DocumentReference<Map<String, dynamic>> userDoc(String uid) =>
      usersCol.doc(uid);

  DocumentReference<Map<String, dynamic>> businessDoc(String businessId) =>
      businessesCol.doc(businessId);

  CollectionReference<Map<String, dynamic>> roomsCol(String businessId) =>
      businessDoc(businessId).collection(HotelFirestorePaths.rooms);

  CollectionReference<Map<String, dynamic>> bookingsCol(String businessId) =>
      businessDoc(businessId).collection(HotelFirestorePaths.bookings);

  CollectionReference<Map<String, dynamic>> billsCol(String businessId) =>
      businessDoc(businessId).collection(HotelFirestorePaths.bills);

  CollectionReference<Map<String, dynamic>> paymentsCol(String businessId) =>
      businessDoc(businessId).collection(HotelFirestorePaths.payments);

  CollectionReference<Map<String, dynamic>> futureBookingsCol(
    String businessId,
  ) => businessDoc(businessId).collection(HotelFirestorePaths.futureBookings);

  CollectionReference<Map<String, dynamic>> guestsCol(String businessId) =>
      businessDoc(businessId).collection(HotelFirestorePaths.guests);

  CollectionReference<Map<String, dynamic>> expensesCol(String businessId) =>
      businessDoc(businessId).collection(HotelFirestorePaths.expenses);

  CollectionReference<Map<String, dynamic>> closedRoomsCol(String businessId) =>
      businessDoc(businessId).collection(HotelFirestorePaths.closedRooms);

  CollectionReference<Map<String, dynamic>> extraChargesCol(
    String businessId,
  ) => businessDoc(businessId).collection(HotelFirestorePaths.extraCharges);

  CollectionReference<Map<String, dynamic>> col(
    String businessId,
    String collection,
  ) => businessDoc(businessId).collection(collection);

  Map<String, dynamic>? _cloudRecord(
    String collection,
    String id,
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    // Older photo-only writes could omit customerId. The existing document ID
    // is the stable guest identity and must retain its original Storage paths.
    if (collection == 'guests' &&
        (data['customerId'] ?? '').toString().trim().isEmpty) {
      return {...data, 'customerId': id};
    }
    return data;
  }

  Future<Map<String, Map<String, Map<String, dynamic>>>> fetchBusinessData(
    String businessId,
  ) async {
    // A revision barrier avoids combining pre-checkout rooms with post-checkout
    // bills when another transaction commits between collection reads.
    final sync = col(businessId, 'settings').doc('sync');
    for (var attempt = 0; attempt < 3; attempt++) {
      final before = (await sync.get(
        const GetOptions(source: Source.server),
      )).data()?['lastSyncAt'];
      final out = <String, Map<String, Map<String, dynamic>>>{};
      for (final name in HotelFirestorePaths.businessCollections) {
        final snap = await col(
          businessId,
          name,
        ).get(const GetOptions(source: Source.server));
        out[name] = {
          for (final doc in snap.docs)
            doc.id: _cloudRecord(name, doc.id, doc.data())!,
        };
      }
      final after = (await sync.get(
        const GetOptions(source: Source.server),
      )).data()?['lastSyncAt'];
      if (before == after) return out;
    }
    throw StateError(
      'Hotel changed during restore. Retry to load a consistent copy.',
    );
  }

  Future<Map<String, dynamic>?> fetchDoc(
    String businessId,
    String collection,
    String id,
  ) async {
    final DocumentSnapshot<Map<String, dynamic>> snap = await col(
      businessId,
      collection,
    ).doc(id).get();
    if (!snap.exists) {
      return null;
    }
    return snap.data();
  }

  void clearAccount() {
    _account = null;
    _createdBusinessThisSession = null;
  }

  /// Atomic compare-and-set: room, booking, bill and payment projections either
  /// all commit or all remain pending. No client wall clock decides the winner.
  Future<Map<String, String>> commitChanges(
    String businessId,
    List<HotelSyncChange> changes, {
    bool migrating = false,
  }) async {
    if (changes.isEmpty) return {};
    if (changes.length > 400) {
      throw StateError(
        'More than 400 related edits require a reviewed migration.',
      );
    }
    final uid = PhoneAuthSession.uid;
    if (uid == null ||
        _account?.ownerUid != uid ||
        _account?.businessId != businessId) {
      throw StateError(
        'Owner session changed. Pending changes remain isolated.',
      );
    }
    return _db.runTransaction((transaction) async {
      final owner = await transaction.get(businessDoc(businessId));
      if (owner.data()?['ownerUid'] != uid) {
        throw StateError('Hotel owner mismatch.');
      }
      final syncRef = col(businessId, 'settings').doc('sync');
      final sync = await transaction.get(syncRef);
      if (!migrating && sync.data()?['migrationInProgress'] == true) {
        throw StateError('Hotel migration in progress. Retry later.');
      }
      final current = <String, Map<String, dynamic>?>{};
      for (final change in changes) {
        final parts = change.path.split('/');
        final snap = await transaction.get(
          col(businessId, parts[0]).doc(parts[1]),
        );
        current[change.path] = _cloudRecord(parts[0], parts[1], snap.data());
      }
      final conflicts = changes
          .where(
            (change) => !hotelChangeCanCommit(change, current[change.path]),
          )
          .map((change) => change.path)
          .toList();
      if (conflicts.isNotEmpty) throw HotelSyncConflict(conflicts);
      final committed = <String, String>{};
      for (final change in changes) {
        final parts = change.path.split('/');
        // Leave an identical, already committed retry untouched.
        if (hotelRecordFingerprint(current[change.path]) ==
            hotelRecordFingerprint(change.data)) {
          committed[change.path] = hotelRecordFingerprint(current[change.path]);
          continue;
        }
        final payload = Map<String, dynamic>.from(change.data);
        if (parts[0] == 'guests') {
          // Photo metadata has its own durable upload queue.
          for (final key in current[change.path]?.keys ?? <String>[]) {
            if (key.startsWith('idFront') ||
                key.startsWith('idBack') ||
                key == 'additionalPhotos' ||
                key == 'photoUpdatedAt' ||
                key == 'hasFrontPhoto' ||
                key == 'hasBackPhoto') {
              payload[key] = current[change.path]![key];
            }
          }
        }
        committed[change.path] = hotelRecordFingerprint({
          ...?current[change.path],
          ...payload,
        });
        transaction.set(col(businessId, parts[0]).doc(parts[1]), {
          ...payload,
          'schemaVersion': 3,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      transaction.set(col(businessId, 'settings').doc('sync'), {
        'schemaVersion': 3,
        'migrationCompleted': !migrating,
        'migrationInProgress': migrating,
        'lastSyncAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return committed;
    });
  }

  /// Initial/legacy imports may exceed one transaction. A durable migration
  /// marker keeps other devices from loading a partly imported hotel.
  Future<void> commitMigration(
    String businessId,
    List<HotelSyncChange> changes,
    String deviceId,
  ) async {
    final ref = col(businessId, 'settings').doc('sync');
    await _db.runTransaction((tx) async {
      final sync = await tx.get(ref);
      if (sync.data()?['migrationInProgress'] == true &&
          sync.data()?['migrationDeviceId'] != deviceId) {
        throw StateError(
          'Another device is migrating this hotel. Retry later.',
        );
      }
      tx.set(ref, {
        'migrationInProgress': true,
        'migrationDeviceId': deviceId,
        'migrationCompleted': false,
        'lastSyncAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    for (var offset = 0; offset < changes.length; offset += 400) {
      final end = (offset + 400).clamp(0, changes.length);
      await commitChanges(
        businessId,
        changes.sublist(offset, end),
        migrating: true,
      );
    }
    await ref.set({
      'migrationInProgress': false,
      'migrationCompleted': true,
      'schemaVersion': 3,
      'lastSyncAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String humanize(FirebaseException error) => _humanizeFirebase(error);

  /// After Firebase phone login, bind [user.uid] as owner and ensure a
  /// permanent [businessId]. Existing local hotel data is never read or
  /// uploaded here.
  Future<HotelCloudAccount?> ensureOwnerBusiness(
    User user, {
    bool allowCreate = false,
    String? contactPhone,
  }) async {
    if (!isAvailable) {
      _log('Firestore skipped: Firebase is not initialized on this platform.');
      return _account;
    }

    final String uid = user.uid.trim();
    if (uid.isEmpty) {
      lastError = 'Authenticated Firebase user has an empty UID.';
      _logError(lastError!);
      return null;
    }

    if (_account?.ownerUid != uid) clearAccount();
    lastError = null;
    try {
      if (allowCreate) {
        await (await HotelDataBuffer.getInstance()).setBool(
          'hotel_new_owner_$uid',
          true,
        );
      }
      final HotelCloudAccount account = await _ensureOwnerBusinessLocked(
        user,
        contactPhone: contactPhone,
      ).timeout(const Duration(seconds: 20));
      _account = account;
      await _cacheAccount(account);
      _log(
        'Owner ready uid=${account.ownerUid} businessId=${account.businessId} '
        'role=${account.role}',
      );
      return account;
    } on TimeoutException catch (error, stack) {
      lastError = 'Cloud backup timed out. Local hotel data is unchanged.';
      _logError('ensureOwnerBusiness timed out: $error', stack);
      return null;
    } on FirebaseException catch (error, stack) {
      lastError = _humanizeFirebase(error);
      _logError(
        'ensureOwnerBusiness failed code=${error.code} '
        'message=${error.message}',
        stack,
      );
      return null;
    } catch (error, stack) {
      lastError = error.toString();
      _logError('ensureOwnerBusiness failed: $error', stack);
      return null;
    }
  }

  Future<HotelCloudAccount> _ensureOwnerBusinessLocked(
    User user, {
    String? contactPhone,
  }) async {
    final String uid = user.uid;
    final verifiedPhone = (user.phoneNumber ?? '').trim();
    final String phoneNumber = verifiedPhone.isEmpty
        ? (contactPhone ?? '').trim()
        : verifiedPhone;
    final String businessName = _safeBusinessName();
    final String? knownBusinessId = await _resolveExistingBusinessId(
      uid,
      phoneNumber: verifiedPhone,
    );
    final canCreate =
        (await HotelDataBuffer.getInstance()).getBool('hotel_new_owner_$uid') ==
        true;
    final DocumentReference<Map<String, dynamic>> userRef = userDoc(uid);

    final _TransactionResult result = await _db.runTransaction((
      Transaction transaction,
    ) async {
      final DocumentSnapshot<Map<String, dynamic>> userSnap = await transaction
          .get(userRef);

      final digits = verifiedPhoneIndexKey(verifiedPhone);
      final phoneRef = digits == null
          ? null
          : _db.collection(HotelFirestorePaths.phoneIndex).doc(digits);
      final phoneSnap = phoneRef == null
          ? null
          : await transaction.get(phoneRef);
      String? existingBusinessId = resolveHotelMapping(
        uid: uid,
        userBusinessId: _readBusinessId(userSnap.data()) ?? knownBusinessId,
        phoneBusinessId: _readBusinessId(phoneSnap?.data()),
        phoneOwnerUid: phoneSnap?.data()?['ownerUid'] as String?,
      );
      if (existingBusinessId == null || existingBusinessId.isEmpty) {
        if (userSnap.exists) {
          existingBusinessId = _readBusinessId(userSnap.data());
        }
      }

      final bool reusedExistingBusiness =
          existingBusinessId != null && existingBusinessId.isNotEmpty;
      final bool firstHotel = firstHotelForSignedInNumber(
        userDocumentExists: userSnap.exists,
        phoneIndexExists: phoneSnap?.exists ?? false,
      );
      if (!reusedExistingBusiness &&
          !canCreate &&
          (HotelDataBuffer.cloudOnly || !firstHotel)) {
        throw StateError(
          'No hotel account found. Choose Sign up to create your hotel.',
        );
      }
      final String businessId = reusedExistingBusiness
          ? existingBusinessId
          : _newBusinessId(phoneNumber: phoneNumber);

      if (!reusedExistingBusiness &&
          _looksLikePhoneNumber(businessId, phoneNumber)) {
        throw StateError('Refusing to use a phone number as businessId.');
      }

      final DocumentReference<Map<String, dynamic>> bizRef = businessDoc(
        businessId,
      );
      final DocumentSnapshot<Map<String, dynamic>> bizSnap = await transaction
          .get(bizRef);

      if (bizSnap.exists && bizSnap.data()?['ownerUid'] != uid) {
        throw StateError(
          'Existing hotel belongs to another owner. Mapping was not changed.',
        );
      }
      final resolvedPhone = phoneNumber.isNotEmpty
          ? phoneNumber
          : (userSnap.data()?['phoneNumber'] ??
                    bizSnap.data()?['phoneNumber'] ??
                    '')
                .toString();
      final FieldValue now = FieldValue.serverTimestamp();
      if (phoneRef != null && phoneSnap?.exists != true) {
        transaction.set(phoneRef, {
          'ownerUid': uid,
          'businessId': businessId,
          'phoneNumber': phoneNumber,
        });
      }
      final Map<String, dynamic> userPayload = <String, dynamic>{
        'phoneNumber': phoneNumber.isEmpty
            ? (userSnap.data()?['phoneNumber'] ?? '')
            : phoneNumber,
        if (user.email != null) 'email': user.email,
        'businessId': businessId,
        'role': ownerRole,
        'ownerName': user.displayName ?? '',
        'updatedAt': now,
      };
      if (!userSnap.exists) {
        userPayload['createdAt'] = now;
      }

      transaction.set(userRef, userPayload, SetOptions(merge: true));

      if (!bizSnap.exists) {
        transaction.set(bizRef, <String, dynamic>{
          'ownerUid': uid,
          'businessName': businessName,
          'phoneNumber': phoneNumber,
          'createdAt': now,
          'updatedAt': now,
          'onboardingStatus': 'pending',
          'newOwnerSetup': true,
        });
      } else {
        transaction.set(bizRef, <String, dynamic>{
          'ownerUid': uid,
          'phoneNumber': phoneNumber.isEmpty
              ? (bizSnap.data()?['phoneNumber'] ?? '')
              : phoneNumber,
          'updatedAt': now,
        }, SetOptions(merge: true));
      }

      final String resolvedName = !bizSnap.exists
          ? businessName
          : ((bizSnap.data()?['businessName'] as String?)?.trim().isNotEmpty ==
                    true
                ? (bizSnap.data()?['businessName'] as String).trim()
                : businessName);

      return _TransactionResult(
        account: HotelCloudAccount(
          ownerUid: uid,
          phoneNumber: resolvedPhone,
          businessId: businessId,
          businessName: resolvedName,
          role: ownerRole,
        ),
        reusedExistingBusiness: reusedExistingBusiness,
      );
    });

    if (result.reusedExistingBusiness) {
      debugPrint(
        '[PHONE_AUTH] reused businessId=${result.account.businessId} '
        'uid=${result.account.ownerUid}',
      );
      _log('Returning owner reused businessId=${result.account.businessId}');
    } else {
      _createdBusinessThisSession = result.account.businessId;
      debugPrint(
        '[PHONE_AUTH] created businessId=${result.account.businessId} '
        'uid=$uid',
      );
      _log('Created new businessId=${result.account.businessId} for uid=$uid');
    }

    await _writePhoneIndex(
      phoneNumber: verifiedPhone,
      businessId: result.account.businessId,
      ownerUid: uid,
    );

    return result.account;
  }

  String _newBusinessId({required String phoneNumber}) {
    String candidate = 'biz_${businessesCol.doc().id}';
    if (_looksLikePhoneNumber(candidate, phoneNumber)) {
      candidate = 'biz_${businessesCol.doc().id}';
    }
    return candidate;
  }

  String? _readBusinessId(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final String id = (data['businessId'] as String? ?? '').trim();
    return id.isEmpty ? null : id;
  }

  Future<String?> _resolveExistingBusinessId(
    String uid, {
    String phoneNumber = '',
  }) async {
    // Lookup failures must propagate: permission/network errors are not proof
    // that a returning owner is new. Only confirmed server absence permits create.
    final user = await userDoc(
      uid,
    ).get(const GetOptions(source: Source.server));
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    Map<String, dynamic>? phone;
    if (digits.isNotEmpty) {
      phone =
          (await _db
                  .collection(HotelFirestorePaths.phoneIndex)
                  .doc(digits)
                  .get(const GetOptions(source: Source.server)))
              .data();
    }
    final userId = _readBusinessId(user.data());
    final phoneId = _readBusinessId(phone);
    if (userId != null || phoneId != null) {
      return resolveHotelMapping(
        uid: uid,
        userBusinessId: userId,
        phoneBusinessId: phoneId,
        phoneOwnerUid: phone?['ownerUid'] as String?,
      );
    }
    final prefs = await HotelDataBuffer.getInstance();
    if (prefs.getString(_prefOwnerUid) == uid &&
        (prefs.getString(_prefBusinessId) ?? '').isNotEmpty) {
      return prefs.getString(_prefBusinessId);
    }
    try {
      final owned = await businessesCol
          .where('ownerUid', isEqualTo: uid)
          .limit(2)
          .get(const GetOptions(source: Source.server));
      return legacyHotelAfterList(
        uid: uid,
        listPermissionDenied: false,
        legacyOwnedBusinesses: owned.docs.map((doc) => doc.id).toList(),
      );
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
      // Deployed rules use `allow list: if false`. A new number has no
      // business list to read; its own hotel is created below.
      return legacyHotelAfterList(uid: uid, listPermissionDenied: true);
    }
  }

  Future<void> _writePhoneIndex({
    required String phoneNumber,
    required String businessId,
    required String ownerUid,
  }) async {
    final String digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty || businessId.isEmpty) {
      return;
    }
    try {
      final DocumentReference<Map<String, dynamic>> ref = _db
          .collection(HotelFirestorePaths.phoneIndex)
          .doc(digits);
      final DocumentSnapshot<Map<String, dynamic>> snap = await ref.get();
      if (snap.exists) {
        return;
      }
      await ref.set(<String, dynamic>{
        'businessId': businessId,
        'ownerUid': ownerUid,
        'phoneNumber': phoneNumber.startsWith('+') ? phoneNumber : '+$digits',
      });
      debugPrint('[PHONE_AUTH] wrote phoneIndex/$digits -> $businessId');
    } catch (error) {
      _log('phoneIndex write skipped: $error');
    }
  }

  bool _looksLikePhoneNumber(String value, String phoneNumber) {
    final String digits = value.replaceAll(RegExp(r'\D'), '');
    final String phoneDigits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.isNotEmpty && digits == phoneDigits) {
      return true;
    }
    return false;
  }

  String _safeBusinessName() {
    final String name = HotelSettingsStore.hotelName.trim();
    return name.isEmpty ? 'Hotel' : name;
  }

  Future<void> _cacheAccount(HotelCloudAccount account) async {
    final HotelDataBuffer prefs = await HotelDataBuffer.getInstance();
    // Preserve pre-upgrade local ownership before replacing the account cache.
    if (prefs.getString('hotel_local_owner_uid') == null &&
        (prefs.getString(_prefOwnerUid) ?? '').isNotEmpty) {
      await prefs.setString(
        'hotel_local_owner_uid',
        prefs.getString(_prefOwnerUid)!,
      );
      if (prefs.getString(_prefBusinessId) != null) {
        await prefs.setString(
          'hotel_local_business_id',
          prefs.getString(_prefBusinessId)!,
        );
      }
    }
    await prefs.setString(_prefOwnerUid, account.ownerUid);
    await prefs.setString(_prefBusinessId, account.businessId);
  }

  String _humanizeFirebase(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'Cloud backup permission denied. Check Firestore rules.';
      case 'unavailable':
        return 'Cloud backup is offline. Local hotel data is unchanged.';
      case 'unauthenticated':
        return 'Cloud backup needs a signed-in owner.';
      case 'deadline-exceeded':
        return 'Cloud backup timed out. Local hotel data is unchanged.';
      default:
        final String? message = error.message;
        if (message != null && message.trim().isNotEmpty) {
          return message;
        }
        return 'Cloud backup failed (${error.code}).';
    }
  }

  void _log(String message) {
    debugPrint('[$_logTag] $message');
  }

  void _logError(String message, [StackTrace? stack]) {
    debugPrint('[$_logTag] ERROR $message');
    if (stack != null) {
      debugPrint('[$_logTag] $stack');
    }
  }
}

class _TransactionResult {
  const _TransactionResult({
    required this.account,
    required this.reusedExistingBusiness,
  });

  final HotelCloudAccount account;
  final bool reusedExistingBusiness;
}

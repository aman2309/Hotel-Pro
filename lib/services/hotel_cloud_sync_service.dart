import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'hotel_data_buffer.dart';
import 'retryable_task.dart';

import '../models/bill_record.dart';
import '../models/customer.dart';
import '../models/room.dart';
import '../stores/bill_store.dart';
import '../stores/customer_store.dart';
import '../stores/expense_store.dart';
import '../stores/hotel_settings_store.dart';
import 'cloud_sync_service.dart';
import 'hotel_cloud_codec.dart';
import 'hotel_firestore_service.dart';
import 'hotel_photo_storage_service.dart';
import 'hotel_sync_plan.dart';
import 'phone_auth_service.dart';
import 'license_service.dart';

enum HotelCloudStatus { synced, syncing, offline, error, restoring, migrating }

/// Firebase-only business records with owner-scoped, atomic server writes.
/// The memory buffer is UI state, never an offline persistence backend.
class HotelCloudSyncService extends ChangeNotifier {
  HotelCloudSyncService._();
  static final HotelCloudSyncService instance = HotelCloudSyncService._();
  static const _logTag = 'HotelCloudSync';
  static const _prefDeviceId = 'hotel_firestore_device_id';
  static const _timeout = Duration(seconds: 25);
  HotelCloudStatus status = HotelCloudStatus.offline;
  String? lastError;
  bool allowPush = false;
  bool applyingRemote = false;
  bool restoredThisSession = false;
  bool _bootstrapped = false;
  final _bootstrapTask = RetryableTask<void>();
  Future<void>? _flushFuture;
  Future<void>? _captureFuture;
  Future<void>? _pullFuture;
  final _subscriptions =
      <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  Future<void> _journalTail = Future<void>.value();
  Future<T> _journal<T>(Future<T> Function() work) {
    final previous = _journalTail;
    final done = Completer<void>();
    _journalTail = done.future;
    return () async {
      await previous;
      try {
        return await work();
      } finally {
        done.complete();
      }
    }();
  }

  int _actionDepth = 0;
  bool _checkpointing = false;
  bool get hasActiveEdit =>
      _actionDepth > 0 ||
      _captureFuture != null ||
      _flushFuture != null ||
      _checkpointing;
  Map<String, Object>? _actionCheckpoint;
  Map<String, Object>? _confirmedBuffer;
  int remoteRevision = 0;
  DateTime? lastSyncAt;
  bool get bootstrapped => _bootstrapped;
  bool get isReady =>
      HotelFirestoreService.instance.isAvailable &&
      HotelFirestoreService.instance.account?.ownerUid ==
          PhoneAuthSession.uid &&
      (HotelFirestoreService.instance.businessId ?? '').isNotEmpty;
  String get _stateKey =>
      'hotel_sync_v3_${PhoneAuthSession.uid}_${HotelFirestoreService.instance.businessId}';
  Future<bool> get hasPendingChanges async =>
      (await _readState())['desired'] != null;

  Future<Map<String, dynamic>> _readState() async {
    final prefs = await HotelDataBuffer.getInstance();
    final raw = prefs.getString(_stateKey);
    return raw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> _writeState(Map<String, dynamic> state) async {
    await (await HotelDataBuffer.getInstance()).setString(
      _stateKey,
      jsonEncode(state),
    );
  }

  Map<String, String> _strings(dynamic value) =>
      value == null ? {} : Map<String, String>.from(value as Map);
  Map<String, Map<String, dynamic>> _docs(dynamic value) => value == null
      ? {}
      : (value as Map).map(
          (key, data) =>
              MapEntry(key.toString(), Map<String, dynamic>.from(data as Map)),
        );
  Map<String, String> _fingerprints(Map<String, Map<String, dynamic>> docs) =>
      docs.map((path, data) => MapEntry(path, hotelRecordFingerprint(data)));
  Map<String, Map<String, dynamic>> _flatten(
    Map<String, Map<String, Map<String, dynamic>>> cloud,
  ) => {
    for (final collection in cloud.entries)
      for (final doc in collection.value.entries)
        if (collection.key != 'settings' || doc.key == 'hotel')
          '${collection.key}/${doc.key}': HotelCloudCodec().sanitizeForCloud(
            doc.value,
          )..remove('updatedAt'),
  };
  Future<Map<String, Map<String, dynamic>>> _snapshot() async {
    final local = await _localInventory();
    final snapshot = HotelCloudCodec(deviceId: await _deviceId()).build(
      rooms: local.rooms,
      bills: local.bills,
      guests: local.guests,
      expenses: local.expenses,
      settings: local.settings,
      photoStoragePaths: await HotelPhotoStorageService.instance
          .photoStoragePaths(),
    );
    final aliases = _strings((await _readState())['paymentAliases']);
    final result = <String, Map<String, dynamic>>{};
    for (final doc in snapshot.docs) {
      final generated = '${doc.collection}/${doc.id}';
      final path = aliases[generated] ?? generated;
      if (result.containsKey(path) &&
          hotelRecordFingerprint(result[path]) !=
              hotelRecordFingerprint(doc.data)) {
        throw StateError(
          'Duplicate stable ID $path; records retained for review.',
        );
      }
      result[path] = doc.data;
    }
    for (final path in List<String>.from(
      (await _readState())['explicitDeletes'] as List? ?? [],
    )) {
      result[path] = {'deleted': true};
    }
    return result;
  }

  /// Compatibility hook for photo conflict handling; business archives are not
  /// persisted on the device. Confirmed state is always read from Firestore.
  Future<String> archiveLocal(String reason) async => 'session-only';

  Future<void> bootstrap() {
    return _bootstrapTask.run(_bootstrap);
  }

  Future<void> retry() async {
    _bootstrapTask.reset();
    if (!_bootstrapped) {
      await bootstrap();
    } else {
      await flushOutbox();
      await pullFromCloud();
      final photos = HotelPhotoStorageService.instance;
      await photos.syncPending(reason: 'refresh');
      if (photos.hasPendingUploadFailure) {
        lastError =
            'Photo upload is pending. Check internet and refresh again.';
        status = HotelCloudStatus.error;
        notifyListeners();
      }
    }
  }

  Future<void> retainDataForNextLogin() async {
    await HotelPhotoStorageService.instance.stopForSignOut();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    // Do not permit a new login while a previous owner's worker is active.
    await _captureFuture;
    await _flushFuture;
    await _pullFuture;
    _bootstrapped = false;
    _bootstrapTask.reset();
    _confirmedBuffer = null;
    _actionCheckpoint = null;
    allowPush = false;
    restoredThisSession = false;
    notifyListeners();
  }

  Future<void> _bootstrapServerOnly() async {
    allowPush = false;
    status = HotelCloudStatus.restoring;
    notifyListeners();
    try {
      if (!isReady) throw StateError('Sign in again to load your hotel.');
      // Always start from Firestore. Never import device/PHP records.
      await _writeState({});
      await restoreFromCloud();
      allowPush = true;
      restoredThisSession = true;
      _bootstrapped = true;
      status = HotelCloudStatus.synced;
      lastError = null;
      _startListeners(HotelFirestoreService.instance.businessId!);
      HotelPhotoStorageService.instance.startRetryTimer();
    } catch (error) {
      _bootstrapped = false;
      lastError = error.toString();
      status = HotelCloudStatus.error;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// Reject failed edits instead of keeping an offline business-data outbox.
  Future<void> _requireConfirmedSave() async {
    await flushOutbox();
    if (!await hasPendingChanges) {
      _confirmedBuffer = HotelDataBuffer.checkpoint();
      // A save also waits for Storage uploads. Photo failures stay visible.
      final photos = HotelPhotoStorageService.instance;
      await photos.syncPending(reason: 'confirmed-save');
      if (photos.hasPendingUploadFailure) {
        lastError =
            'Hotel records are saved in Firebase. Photo upload is pending; keep the app open and refresh to retry.';
        status = HotelCloudStatus.error;
        notifyListeners();
      }
      return;
    }
    final message =
        lastError ?? 'Could not save to Firebase. Check internet and retry.';
    final state = await _readState();
    final failure = state['conflicts'] != null
        ? 'Another device changed this record. Please refresh and try again.'
        : message;
    final confirmed = _confirmedBuffer ?? _actionCheckpoint;
    if (confirmed != null) HotelDataBuffer.restoreCheckpoint(confirmed);
    final cleanState = await _readState();
    cleanState.remove('desired');
    cleanState.remove('conflicts');
    cleanState.remove('explicitDeletes');
    cleanState.remove('photoVersion');
    await _writeState(cleanState);
    await HotelSettingsStore.loadSettings();
    await CustomerStore.loadCustomers();
    await BillStore.loadBills();
    await ExpenseStore.loadExpenses();
    try {
      await restoreFromCloud();
    } catch (_) {}
    throw StateError(failure);
  }

  Future<void> cancelLocalAction() async {
    if (!HotelDataBuffer.cloudOnly) return;
    _actionDepth = 0;
    final checkpoint = _confirmedBuffer ?? _actionCheckpoint;
    _actionCheckpoint = null;
    if (checkpoint != null) HotelDataBuffer.restoreCheckpoint(checkpoint);
    await HotelSettingsStore.loadSettings();
    await CustomerStore.loadCustomers();
    await BillStore.loadBills();
    await ExpenseStore.loadExpenses();
    remoteRevision++;
    notifyListeners();
  }

  Future<void> _bootstrap() => _bootstrapServerOnly();

  void _startListeners(String businessId) {
    for (final collection in HotelFirestorePaths.businessCollections) {
      _subscriptions.add(
        HotelFirestoreService.instance
            .col(businessId, collection)
            .snapshots(includeMetadataChanges: true)
            .listen(
              (snapshot) {
                if (!snapshot.metadata.isFromCache &&
                    !snapshot.metadata.hasPendingWrites) {
                  unawaited(pullFromCloud());
                }
              },
              onError: (Object error) {
                lastError = error.toString();
                status = HotelCloudStatus.error;
                notifyListeners();
              },
            ),
      );
    }
  }

  Future<void> registerExpenseDeletion(String expenseId) async {
    if (!_bootstrapped || !isReady) return;
    await archiveLocal('before-expense-removal');
    await _journal(() async {
      final state = await _readState();
      final paths = List<String>.from(state['explicitDeletes'] as List? ?? []);
      final path = 'expenses/$expenseId';
      if (!paths.contains(path)) paths.add(path);
      state['explicitDeletes'] = paths;
      await _writeState(state);
    });
  }

  Future<void> beginLocalAction() async {
    // Reserve before yielding so a new listener pull cannot start between
    // waiting for an old pull and opening a room dialog.
    if (HotelDataBuffer.cloudOnly && _actionDepth == 0) {
      if (!_bootstrapped || !isReady) {
        throw StateError('Hotel is not connected to Firebase.');
      }
      await HotelFirestoreService.instance
          .businessDoc(HotelFirestoreService.instance.businessId!)
          .get(const GetOptions(source: Source.server));
      _actionCheckpoint = HotelDataBuffer.checkpoint();
    }
    _actionDepth++;
    try {
      await _pullFuture;
      await HotelPhotoStorageService.instance.waitForUploads();
      final state = await _readState();
      if (state['conflicts'] != null) {
        throw HotelSyncConflict(List<String>.from(state['conflicts'] as List));
      }
    } catch (_) {
      _actionDepth--;
      rethrow;
    }
  }

  Future<void> commitActionCheckpoint({bool requirePhotos = false}) async {
    if (_actionDepth != 1 || _checkpointing) {
      throw StateError(
        'Finish the current hotel action before saving this booking.',
      );
    }
    _checkpointing = true;
    _actionDepth = 0;
    try {
      await notifyLocalChanged();
      await _requireConfirmedSave();
      if (requirePhotos) {
        final photos = HotelPhotoStorageService.instance;
        // syncPending is normally suppressed while this checkpoint is reserved.
        await photos.flushQueue(reason: 'booking-checkpoint');
        if (photos.hasPendingUploadFailure) {
          throw StateError(
            'ID photos could not finish uploading. ${photos.lastUploadError ?? 'Check your connection.'} Keep this form open and retry.',
          );
        }
      }
      _actionCheckpoint = HotelDataBuffer.checkpoint();
      _confirmedBuffer = HotelDataBuffer.checkpoint();
      lastError = null;
      status = HotelCloudStatus.synced;
      notifyListeners();
    } finally {
      _actionDepth = 1;
      _checkpointing = false;
    }
  }

  Future<void> endLocalAction() async {
    _actionDepth--;
    if (_actionDepth == 0) {
      try {
        await notifyLocalChanged();
        if (HotelDataBuffer.cloudOnly) {
          await _requireConfirmedSave();
        } else {
          await flushOutbox();
        }
        await pullFromCloud();
        _actionCheckpoint = null;
      } catch (_) {
        if (HotelDataBuffer.cloudOnly) await cancelLocalAction();
        rethrow;
      }
    }
  }

  Future<void> notifyLocalChanged() {
    if ((!HotelDataBuffer.cloudOnly && !LicenseService.instance.canEditHotel) ||
        applyingRemote ||
        !_bootstrapped ||
        !allowPush ||
        _actionDepth > 0) {
      return Future<void>.value();
    }
    final previous = _captureFuture;
    late final Future<void> next;
    next = () async {
      await previous;
      await _journal(() async {
        await HotelPhotoStorageService.instance.capturePendingPhotos();
        final state = await _readState();
        final local = await _snapshot();
        final changes = planHotelChanges(
          local: local,
          baseline: _strings(state['baseline']),
          remoteBaseline: _strings(state['remoteBaseline']),
        );
        if (changes.isEmpty && state['desired'] == null) return;
        state['desired'] = local;
        state['generation'] = ((state['generation'] as num?)?.toInt() ?? 0) + 1;
        await _writeState(state);
      });
    }();
    _captureFuture = next;
    final captured = next.whenComplete(() {
      if (identical(_captureFuture, next)) _captureFuture = null;
      if (!HotelDataBuffer.cloudOnly) unawaited(flushOutbox());
    });
    return HotelDataBuffer.cloudOnly
        ? captured.then((_) => _requireConfirmedSave())
        : captured;
  }

  Future<void> flushOutbox() async {
    final active = _flushFuture;
    if (active != null) {
      await active;
      return;
    }
    final done = Completer<void>();
    _flushFuture = done.future;
    try {
      if (!isReady || !allowPush || _actionDepth > 0) return;
      await _captureFuture;
      while (true) {
        final state = await _readState();
        if (state['desired'] == null || state['conflicts'] != null) return;
        final desired = _docs(state['desired']);
        final generation = state['generation'];
        final changes = planHotelChanges(
          local: desired,
          baseline: _strings(state['baseline']),
          remoteBaseline: _strings(state['remoteBaseline']),
        );
        status = HotelCloudStatus.syncing;
        notifyListeners();
        final committed = await HotelFirestoreService.instance.commitChanges(
          HotelFirestoreService.instance.businessId!,
          changes,
        );
        // Capture can't interleave this read/write section.
        await _captureFuture;
        final latest = await _journal(() async {
          final latest = await _readState();
          latest['baseline'] = _fingerprints(desired);
          final remote = _strings(latest['remoteBaseline']);
          for (final change in changes) {
            remote[change.path] = committed[change.path]!;
          }
          latest['remoteBaseline'] = remote;
          final deletes = List<String>.from(
            latest['explicitDeletes'] as List? ?? [],
          );
          deletes.removeWhere((path) => committed[path] == 'deleted');
          latest['explicitDeletes'] = deletes;
          if (latest['generation'] == generation) latest.remove('desired');
          await _writeState(latest);
          return latest;
        });
        lastSyncAt = DateTime.now();
        lastError = null;
        status = HotelCloudStatus.synced;
        if (latest['desired'] == null) break;
      }
      unawaited(
        HotelPhotoStorageService.instance.syncPending(reason: 'committed'),
      );
    } on HotelSyncConflict catch (error) {
      await _journal(() async {
        final state = await _readState();
        state['conflicts'] = error.paths;
        state['conflictArchive'] = await archiveLocal('concurrent-conflict');
        await _writeState(state);
      });
      lastError = error.toString();
      status = HotelCloudStatus.error;
    } catch (error) {
      lastError = error.toString();
      status = error is FirebaseException
          ? _statusForFirebase(error)
          : HotelCloudStatus.offline;
    } finally {
      done.complete();
      _flushFuture = null;
      notifyListeners();
    }
  }

  /// Explicit user resolution. Pending records stay in an exportable archive.
  Future<void> useCloudAfterReview() async {
    final cloud = await HotelFirestoreService.instance.fetchBusinessData(
      HotelFirestoreService.instance.businessId!,
    );
    if (_flatten(cloud).values.every((doc) => doc['deleted'] == true)) {
      throw StateError(
        'Cloud is empty. Review the preserved PHP/local export with support before migrating.',
      );
    }
    await archiveLocal('reviewed-conflict');
    final state = await _readState();
    state.remove('desired');
    state.remove('conflicts');
    state.remove('explicitDeletes');
    await _writeState(state);
    // Baseline marks this as a reviewed returning owner, not legacy migration.
    state['baseline'] = _fingerprints(await _snapshot());
    state['remoteBaseline'] = _fingerprints(_flatten(cloud));
    state.remove('photoVersion');
    await _writeState(state);
    allowPush = true;
    if (!_bootstrapped) {
      await retry();
    } else {
      await pullFromCloud();
    }
  }

  Future<bool> pullFromCloud() async {
    if (_pullFuture != null ||
        !_bootstrapped ||
        !isReady ||
        applyingRemote ||
        _checkpointing ||
        _actionDepth > 0 ||
        _captureFuture != null ||
        _flushFuture != null) {
      return false;
    }
    final completer = Completer<void>();
    _pullFuture = completer.future;
    try {
      if (await hasPendingChanges) return false;
      final changed = await restoreFromCloud();
      if (changed) {
        await LicenseService.instance.readCloudLicense(
          HotelFirestoreService.instance.businessId!,
        );
        status = HotelCloudStatus.synced;
        lastError = null;
      }
      return changed;
    } catch (error) {
      lastError = error.toString();
      status = HotelCloudStatus.offline;
      return false;
    } finally {
      completer.complete();
      _pullFuture = null;
      notifyListeners();
    }
  }

  Future<bool> restoreFromCloud() async {
    if (!isReady) {
      debugPrint(
        '[CLOUD_RESTORE] skipped: Firebase owner business is not ready',
      );
      debugPrint('[CLOUD_RESTORE] complete');
      return false;
    }
    final String businessId = HotelFirestoreService.instance.businessId!;
    debugPrint('[CLOUD_RESTORE] businessId=$businessId');

    if (_actionDepth > 0 ||
        _checkpointing ||
        await hasPendingChanges ||
        _captureFuture != null) {
      return false;
    }
    applyingRemote = true;
    try {
      await HotelPhotoStorageService.instance.waitForPhotoCapture();
      final Map<String, Map<String, Map<String, dynamic>>> cloud =
          await HotelFirestoreService.instance
              .fetchBusinessData(businessId)
              .timeout(_timeout);
      if (cloud['settings']?['sync']?['migrationInProgress'] == true) {
        throw StateError(
          'Cloud migration is incomplete. Local records are unchanged.',
        );
      }
      final stateBefore = await _readState();
      final remoteFingerprints = _fingerprints(_flatten(cloud));
      final prefsBefore = await HotelDataBuffer.getInstance();
      final photoVersion = (cloud['guests'] ?? {}).values
          .map(
            (doc) =>
                '${doc['photoUpdatedAt']}:${doc['idFrontSha256']}:${doc['idBackSha256']}',
          )
          .join('|');
      if (stateBefore['baseline'] != null &&
          mapEquals(
            remoteFingerprints,
            _strings(stateBefore['remoteBaseline']),
          ) &&
          stateBefore['photoVersion'] == photoVersion &&
          !HotelPhotoStorageService.instance.hasRestoreFailures &&
          prefsBefore.getString(CloudSyncService.roomKey) != null) {
        return true;
      }
      await archiveLocal('before-restore');
      final HotelCloudCodec codec = HotelCloudCodec(
        deviceId: await _deviceId(),
      );

      final List<Room> rooms = codec.mergeRelatedIntoRooms(
        rooms: codec.roomsFromCloud(
          (cloud['rooms'] ?? <String, Map<String, dynamic>>{}).values,
        ),
        bookings:
            (cloud['bookings'] ?? <String, Map<String, dynamic>>{}).values,
        futureBookings:
            (cloud['futureBookings'] ?? <String, Map<String, dynamic>>{})
                .values,
        closedRooms:
            (cloud['closedRooms'] ?? <String, Map<String, dynamic>>{}).values,
      );
      if (!HotelDataBuffer.cloudOnly &&
          _flatten(cloud).values.every((doc) => doc['deleted'] == true)) {
        debugPrint('[CLOUD_RESTORE] skipped: cloud hotel data is empty');
        debugPrint('[CLOUD_RESTORE] complete');
        return false;
      }

      final List<BillRecord> bills = codec.billsFromCloud(
        (cloud['bills'] ?? <String, Map<String, dynamic>>{}).values,
      );
      final List<Customer> guests = codec.guestsFromCloud(
        (cloud['guests'] ?? <String, Map<String, dynamic>>{}).values,
      );
      final List<Map<String, dynamic>> expenses = codec.expensesFromCloud(
        (cloud['expenses'] ?? <String, Map<String, dynamic>>{}).values,
      );
      // Preserve already downloaded local photos when their cloud hash matches.
      final previousGuests = _decodeGuests(
        (await HotelDataBuffer.getInstance()).getString(
          CloudSyncService.customerKey,
        ),
      );
      for (final guest in guests) {
        for (final previous in previousGuests) {
          if (previous.customerId != guest.customerId) continue;
          final doc = cloud['guests']?[guest.customerId];
          if ((doc?['idFrontSha256'] == null &&
                  previous.mobile == guest.mobile) ||
              HotelPhotoStorageService.sha256OfBase64(
                    previous.idFrontPhotoPath,
                  ) ==
                  doc?['idFrontSha256']) {
            guest.idFrontPhotoPath = previous.idFrontPhotoPath;
          }
          if ((doc?['idBackSha256'] == null &&
                  previous.mobile == guest.mobile) ||
              HotelPhotoStorageService.sha256OfBase64(
                    previous.idBackPhotoPath,
                  ) ==
                  doc?['idBackSha256']) {
            guest.idBackPhotoPath = previous.idBackPhotoPath;
          }
        }
      }
      final int futureCount = rooms
          .where((Room room) => room.futureBooking)
          .length;
      final int paymentCount =
          cloud['payments']?.values
              .where((payment) => payment['deleted'] != true)
              .length ??
          0;
      final int bookingCount = rooms
          .where((Room room) => room.status == 'BOOKED')
          .length;

      final HotelDataBuffer prefs = await HotelDataBuffer.getInstance();
      {
        await prefs.setString(
          CloudSyncService.roomKey,
          jsonEncode(rooms.map((Room room) => room.toJson()).toList()),
        );
      }
      await prefs.setString(
        CloudSyncService.billKey,
        jsonEncode(bills.map((BillRecord bill) => bill.toJson()).toList()),
      );
      await prefs.setString(
        CloudSyncService.customerKey,
        jsonEncode(
          guests
              .map(
                (Customer guest) => <String, dynamic>{
                  'customerId': guest.customerId,
                  'mobile': guest.mobile,
                  'guestName': guest.guestName,
                  'address': guest.address,
                  'idType': guest.idType,
                  'idNumber': guest.idNumber,
                  'idFrontPhotoPath': guest.idFrontPhotoPath,
                  'idBackPhotoPath': guest.idBackPhotoPath,
                  'stayHistory': guest.stayHistory,
                },
              )
              .toList(),
        ),
      );
      await prefs.setString(CloudSyncService.expenseKey, jsonEncode(expenses));

      final Map<String, dynamic>? settings =
          cloud['settings']?['hotel'] ??
          (HotelDataBuffer.cloudOnly
              ? {
                  'hotel_name':
                      HotelFirestoreService.instance.account?.businessName ??
                      'Hotel',
                  'hotel_mobile':
                      HotelFirestoreService.instance.account?.phoneNumber ?? '',
                }
              : null);
      if (settings != null && settings['deleted'] != true) {
        final Map<String, dynamic> localSettings = Map<String, dynamic>.from(
          codec.toLocalValue(settings) as Map,
        );
        await prefs.setString(
          'hotel_name',
          localSettings['hotel_name']?.toString() ?? 'Hotel',
        );
        await prefs.setString(
          'hotel_address',
          localSettings['hotel_address']?.toString() ?? '',
        );
        await prefs.setString(
          'hotel_mobile',
          localSettings['hotel_mobile']?.toString() ?? '',
        );
        await prefs.setString(
          'hotel_registration_number',
          localSettings['hotel_registration_number']?.toString() ?? '',
        );
        await prefs.setString(
          'hotel_gst_number',
          localSettings['hotel_gst_number']?.toString() ?? '',
        );
        final double gst =
            double.tryParse(
              localSettings['hotel_gst_tax_rate']?.toString() ?? '',
            ) ??
            5;
        await prefs.setDouble('hotel_gst_tax_rate', gst);
        await prefs.setString(
          'hotel_admin_password',
          localSettings['hotel_admin_password']?.toString() ?? 'HOTEL2026',
        );
      }

      debugPrint('[CLOUD_RESTORE] customers restored count=${guests.length}');
      _log(
        'Restored rooms=${rooms.length} booked=$bookingCount '
        'bills=${bills.length} payments=$paymentCount '
        'guests=${guests.length} expenses=${expenses.length} '
        'futureBookings=$futureCount',
      );

      try {
        await HotelPhotoStorageService.instance
            .restorePhotos(
              businessId: businessId,
              guestDocs: cloud['guests'] ?? <String, Map<String, dynamic>>{},
            )
            .timeout(const Duration(seconds: 90));
      } catch (error, stack) {
        debugPrint('[PHOTO_RESTORE] download failure reason=$error');
        _logError('Photo restore skipped; hotel data is intact: $error', stack);
      }
      final localDocs = await _snapshot();
      final remoteDocs = _flatten(cloud);
      final state = await _readState();
      state['baseline'] = _fingerprints(localDocs);
      await prefs.setString(
        'hotel_firestore_last_sync_at',
        DateTime.now().toIso8601String(),
      );
      state['remoteBaseline'] = _fingerprints(remoteDocs);
      state['photoVersion'] = photoVersion;
      await _writeState(state);
      await HotelSettingsStore.loadSettings();
      await CustomerStore.loadCustomers();
      await BillStore.loadBills();
      await ExpenseStore.loadExpenses();
      if (HotelDataBuffer.cloudOnly) {
        _confirmedBuffer = HotelDataBuffer.checkpoint();
      }
      remoteRevision++;
      lastSyncAt = DateTime.now();
      notifyListeners();
      return true;
    } catch (error, stack) {
      debugPrint('[CLOUD_RESTORE] failed reason=$error');
      _logError('Cloud restore failed: $error', stack);
      debugPrint('[CLOUD_RESTORE] complete');
      rethrow;
    } finally {
      applyingRemote = false;
    }
  }

  Future<_LocalInventory> _localInventory() async {
    final HotelDataBuffer prefs = await HotelDataBuffer.getInstance();
    final String? roomsRaw = prefs.getString(CloudSyncService.roomKey);
    final bool missing =
        roomsRaw == null || roomsRaw.isEmpty || roomsRaw == '[]';
    return _LocalInventory(
      rooms: _decodeRooms(roomsRaw),
      bills: _decodeBills(prefs.getString(CloudSyncService.billKey)),
      guests: _decodeGuests(prefs.getString(CloudSyncService.customerKey)),
      expenses: _decodeMaps(prefs.getString(CloudSyncService.expenseKey)),
      roomsMissingOrEmpty: missing,
      settings: <String, dynamic>{
        'hotel_name': prefs.getString('hotel_name') ?? 'Hotel',
        'hotel_address': prefs.getString('hotel_address') ?? '',
        'hotel_mobile': prefs.getString('hotel_mobile') ?? '',
        'hotel_registration_number':
            prefs.getString('hotel_registration_number') ?? '',
        'hotel_gst_number': prefs.getString('hotel_gst_number') ?? '',
        'hotel_gst_tax_rate':
            prefs.getDouble('hotel_gst_tax_rate') ??
            double.tryParse(prefs.getString('hotel_gst_tax_rate') ?? '') ??
            5,
        'hotel_admin_password':
            prefs.getString('hotel_admin_password') ?? 'HOTEL2026',
      },
    );
  }

  List<Room> _decodeRooms(String? raw) {
    if (raw == null || raw.isEmpty || raw == '[]') {
      return <Room>[];
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return HotelCloudCodec.decodeRoomList(
        decoded,
        onError: (Object error, int index) {
          throw FormatException('Local room $index unreadable: $error');
        },
      );
    } catch (error) {
      throw FormatException('Local rooms unreadable: $error');
    }
  }

  List<BillRecord> _decodeBills(String? raw) {
    if (raw == null || raw.isEmpty || raw == '[]') {
      return <BillRecord>[];
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (dynamic item) =>
                BillRecord.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
    } catch (error) {
      throw FormatException('Local bills unreadable: $error');
    }
  }

  List<Customer> _decodeGuests(String? raw) {
    if (raw == null || raw.isEmpty || raw == '[]') {
      return <Customer>[];
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((dynamic item) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          item as Map,
        );
        return Customer(
          customerId: data['customerId']?.toString() ?? '',
          mobile: data['mobile']?.toString() ?? '',
          guestName: data['guestName']?.toString() ?? '',
          address: data['address']?.toString() ?? '',
          idType: data['idType']?.toString() ?? '',
          idNumber: data['idNumber']?.toString() ?? '',
          idFrontPhotoPath:
              data['idFrontPhotoPath']?.toString() ??
              data['idPhotoPath']?.toString() ??
              '',
          idBackPhotoPath: data['idBackPhotoPath']?.toString() ?? '',
          stayHistory: (data['stayHistory'] as List<dynamic>? ?? [])
              .map(
                (dynamic history) => Map<String, dynamic>.from(history as Map),
              )
              .toList(),
        );
      }).toList();
    } catch (error) {
      throw FormatException('Local guests unreadable: $error');
    }
  }

  List<Map<String, dynamic>> _decodeMaps(String? raw) {
    if (raw == null || raw.isEmpty || raw == '[]') {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((dynamic item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (error) {
      throw FormatException('Local list unreadable: $error');
    }
  }

  Future<String> _deviceId() async {
    final HotelDataBuffer prefs = await HotelDataBuffer.getInstance();
    var id = prefs.getString(_prefDeviceId);
    if (id == null || id.isEmpty) {
      id = 'dev_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(_prefDeviceId, id);
    }
    return id;
  }

  HotelCloudStatus _statusForFirebase(FirebaseException error) {
    if (error.code == 'unavailable' || error.code == 'network-request-failed') {
      return HotelCloudStatus.offline;
    }
    return HotelCloudStatus.error;
  }

  void _log(String message) => debugPrint('[$_logTag] $message');

  void _logError(String message, [StackTrace? stack]) {
    debugPrint('[$_logTag] ERROR $message');
    if (stack != null) {
      debugPrint('[$_logTag] $stack');
    }
  }
}

class _LocalInventory {
  const _LocalInventory({
    required this.rooms,
    required this.bills,
    required this.guests,
    required this.expenses,
    required this.roomsMissingOrEmpty,
    required this.settings,
  });

  final List<Room> rooms;
  final List<BillRecord> bills;
  final List<Customer> guests;
  final List<Map<String, dynamic>> expenses;
  final bool roomsMissingOrEmpty;
  final Map<String, dynamic> settings;
}

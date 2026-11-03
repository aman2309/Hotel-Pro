import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'hotel_data_buffer.dart';
import 'serial_work_queue.dart';

import '../models/customer.dart';
import '../models/room.dart';
import 'cloud_sync_service.dart';
import 'hotel_cloud_codec.dart';
import 'hotel_cloud_policy.dart';
import 'hotel_firestore_service.dart';
import 'hotel_photo_ref.dart';
import 'hotel_photo_upload_debug.dart';
import 'phone_auth_service.dart';
import 'hotel_sync_plan.dart';
import 'hotel_cloud_sync_service.dart';

Uint8List compressHotelIdPhoto(Uint8List bytes) {
  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return bytes;
  }
  img.Image frame = decoded;
  const int maxEdge = 1600;
  if (frame.width > maxEdge || frame.height > maxEdge) {
    if (frame.width >= frame.height) {
      frame = img.copyResize(frame, width: maxEdge);
    } else {
      frame = img.copyResize(frame, height: maxEdge);
    }
  }
  int quality = 82;
  Uint8List out = Uint8List.fromList(img.encodeJpg(frame, quality: quality));
  while (out.length > HotelPhotoRef.maxBytes && quality > 45) {
    quality -= 12;
    out = Uint8List.fromList(img.encodeJpg(frame, quality: quality));
  }
  return out.length <= HotelPhotoRef.maxBytes ? out : bytes;
}

/// Firebase Storage for ID photos; selected bytes and retry jobs live in RAM only.
class HotelPhotoStorageService extends ChangeNotifier {
  HotelPhotoStorageService._();

  static final HotelPhotoStorageService instance = HotelPhotoStorageService._();

  static const String _logTag = 'HotelPhotoStorage';
  static const String _queueKey = 'hotel_storage_photo_outbox_v3';
  static const String _indexKey = 'hotel_storage_photo_index_v3';
  static const Duration _timeout = Duration(seconds: 40);

  final _queueWork = SerialWorkQueue();
  Future<void>? _flushFuture;
  Timer? _retryTimer;
  bool restoring = false;
  bool hasRestoreFailures = false;
  int pendingUploadCount = 0;
  String? lastPhotoError;
  // Download failures for an older guest must not reject a new booking.
  String? lastUploadError;
  bool get hasPendingUploadFailure =>
      pendingUploadCount > 0 || lastUploadError != null;
  Future<void>? _syncFuture;
  Future<void>? _enqueueFuture;
  Map<String, String> _photoHeads = <String, String>{};

  Future<void> stopForSignOut() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await _syncFuture;
    await _flushFuture;
  }

  /// The UI archives pending bytes before an explicit cloud-photo resolution.
  Future<void> keepCloudPhotosAfterReview() async {
    await waitForUploads();
    await HotelCloudSyncService.instance.archiveLocal(
      'reviewed-photo-conflict',
    );
    final businessId = await _businessId();
    final queue = await _readQueue();
    queue.removeWhere(
      (job) =>
          job['storagePath'].toString().startsWith('businesses/$businessId/'),
    );
    await (await HotelDataBuffer.getInstance()).setString(
      _queueKey,
      jsonEncode(queue),
    );
    pendingUploadCount = 0;
    lastPhotoError = null;
    hasRestoreFailures = true;
    notifyListeners();
  }

  Future<void> waitForUploads() async {
    await _syncFuture;
    await _flushFuture;
  }

  /// Upload jobs already carry their own bytes. Room restores only need to
  /// wait for that durable capture, not for slow Storage network retries.
  Future<void> waitForPhotoCapture() async {
    await _enqueueFuture;
  }

  Map<String, String> _pathIndex = <String, String>{};
  bool _indexLoaded = false;

  bool get isAvailable =>
      Firebase.apps.isNotEmpty && HotelFirestoreService.instance.isAvailable;

  void startRetryTimer() {
    _retryTimer ??= Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(syncPending(reason: 'timer'));
    });
  }

  Future<Map<String, String>> photoStoragePaths() async {
    await _loadIndex();
    final businessId = await _businessId();
    final Map<String, String> keyed = <String, String>{};
    _pathIndex.forEach((String path, String _) {
      if (!path.startsWith("businesses/$businessId/")) return;
      final String? key = HotelPhotoPaths.metaKeyFromStoragePath(path);
      if (key != null) {
        keyed[key] = path;
      }
    });
    return keyed;
  }

  Future<void> syncPending({String reason = 'sync'}) async {
    final active = _syncFuture;
    if (active != null) {
      await active;
      return;
    }
    final done = Completer<void>();
    _syncFuture = done.future;
    try {
      if (!HotelCloudSyncService.instance.bootstrapped ||
          HotelCloudSyncService.instance.hasActiveEdit ||
          await HotelCloudSyncService.instance.hasPendingChanges) {
        return;
      }
      await _syncPendingLocked(reason: reason);
    } catch (error) {
      lastPhotoError = error.toString();
    } finally {
      done.complete();
      _syncFuture = null;
      notifyListeners();
    }
  }

  Future<void> _syncPendingLocked({required String reason}) async {
    HotelPhotoUploadDebug.stage(
      '7 HotelPhotoStorageService upload method called',
      <String, Object?>{
        'method': 'syncPending',
        'reason': reason,
        'restoring': restoring,
        'isAvailable': isAvailable,
        'firebaseApps': Firebase.apps.length,
      },
    );
    _logAuthAndBucket();
    if (restoring) {
      HotelPhotoUploadDebug.stage(
        '7 HotelPhotoStorageService skipped',
        <String, Object?>{'reason': 'restoring=true'},
      );
      return;
    }
    await capturePendingPhotos();
    await flushQueue(reason: reason);
  }

  /// Capture bytes before committing records or allowing a remote restore.
  /// Enqueue and flush share the lock, so a running upload cannot drop new jobs.
  Future<void> capturePendingPhotos() {
    final capture = _queueWork.run(_enqueueFromLocal);
    _enqueueFuture = capture;
    return capture.whenComplete(() {
      if (identical(_enqueueFuture, capture)) _enqueueFuture = null;
    });
  }

  void _logAuthAndBucket() {
    final User? user = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser;
    HotelPhotoUploadDebug.stage('4 Firebase currentUser', <String, Object?>{
      'signedIn': user != null,
      'uid': user?.uid ?? '',
      'sessionUid': PhoneAuthSession.uid ?? '',
    });
    HotelPhotoUploadDebug.stage('5 Resolved businessId', <String, Object?>{
      'serviceBusinessId': HotelFirestoreService.instance.businessId ?? '',
      'sessionBusinessId': PhoneAuthSession.businessId ?? '',
    });
    HotelPhotoUploadDebug.stage(
      '10 Firebase Storage bucket being used',
      <String, Object?>{
        'optionsBucket': Firebase.apps.isEmpty
            ? ''
            : (Firebase.app().options.storageBucket ?? ''),
        'storageInstanceBucket': Firebase.apps.isEmpty
            ? ''
            : FirebaseStorage.instance.bucket,
        'expected': 'yankees-hotel-pro.firebasestorage.app',
      },
    );
  }

  Future<void> flushQueue({String reason = 'flush'}) {
    return _flushFuture ??= () async {
      try {
        await _queueWork.run(() => _flushLocked(reason: reason));
      } finally {
        _flushFuture = null;
      }
    }();
  }

  Future<void> _enqueueFromLocal() async {
    final String? businessId = await _businessId();
    HotelPhotoUploadDebug.stage('5 Resolved businessId', <String, Object?>{
      'businessId': businessId ?? '',
      'source': '_enqueueFromLocal',
    });
    if (businessId == null) {
      HotelPhotoUploadDebug.stage(
        '7 HotelPhotoStorageService skipped',
        <String, Object?>{'reason': 'no businessId'},
      );
      _log('Photo enqueue skipped: no businessId');
      return;
    }
    await _loadIndex();
    final HotelDataBuffer prefs = await HotelDataBuffer.getInstance();
    final List<Map<String, dynamic>> queue = await _readQueue();

    void offer(Map<String, dynamic> job) {
      final String path = job['storagePath'] as String;
      final String op = (job['op'] ?? 'upload').toString();
      final String sha = (job['sha256'] ?? '').toString();
      if (_photoHeads['$businessId:${HotelPhotoPaths.metaKeyFromStoragePath(path)}'] ==
          sha) {
        return;
      }
      if (op != 'delete' && sha.isNotEmpty && _pathIndex[path] == sha) {
        HotelPhotoUploadDebug.stage(
          '7 HotelPhotoStorageService skipped unchanged photo',
          <String, Object?>{
            'storagePath': path,
            'reason': 'index match at enqueue',
          },
        );
        return;
      }
      if (op == 'delete' && !_pathIndex.containsKey(path)) {
        return;
      }
      final existing = queue
          .where((item) => item['storagePath'] == path)
          .toList();
      if (existing.isNotEmpty) {
        return; // Keep the original expected version on retry.
      }
      job['expectedSha'] =
          _photoHeads['$businessId:${HotelPhotoPaths.metaKeyFromStoragePath(path)}'];
      queue.add(job);
    }

    final List<Customer> guests = _decodeGuests(
      prefs.getString(CloudSyncService.customerKey),
    );
    for (final Customer guest in guests) {
      final String guestId = guest.customerId.trim();
      if (guestId.isEmpty) {
        continue;
      }
      _offerCustomerSide(
        offer: offer,
        businessId: businessId,
        guest: guest,
        side: 'front',
        raw: guest.idFrontPhotoPath,
      );
      _offerCustomerSide(
        offer: offer,
        businessId: businessId,
        guest: guest,
        side: 'back',
        raw: guest.idBackPhotoPath,
      );
      HotelPhotoUploadDebug.stage(
        '6 Resolved guestId/customerId',
        <String, Object?>{
          'guestId': guestId,
          'front': HotelPhotoUploadDebug.photoPresence(guest.idFrontPhotoPath),
          'back': HotelPhotoUploadDebug.photoPresence(guest.idBackPhotoPath),
        },
      );
    }

    final List<Room> rooms = HotelCloudCodec.decodeRoomList(
      _decodeList(prefs.getString(CloudSyncService.roomKey)),
    );
    for (final job in queue) {
      if ((job['base64'] ?? '').toString().isNotEmpty) continue;
      if (!job['storagePath'].toString().startsWith(
        'businesses/$businessId/',
      )) {
        continue;
      }
      final raw = _localBase64ForJob(job, guests: guests, rooms: rooms);
      if (raw != null && sha256OfBase64(raw) == job['sha256']) {
        job['base64'] = raw;
      }
    }
    for (final Room room in rooms) {
      final String primaryId = _primaryGuestId(guests, room);
      _offerExtraList(
        offer: offer,
        businessId: businessId,
        primaryGuestId: primaryId,
        extras: room.extraGuests,
        guests: guests,
      );
      _offerExtraList(
        offer: offer,
        businessId: businessId,
        primaryGuestId: primaryId,
        extras: room.futureExtraGuests,
        guests: guests,
      );
    }

    await prefs.setString(_queueKey, jsonEncode(queue));
    pendingUploadCount = queue
        .where(
          (job) => job['storagePath'].toString().startsWith(
            'businesses/$businessId/',
          ),
        )
        .length;
    HotelPhotoUploadDebug.stage(
      '15 Pending/retry queue state',
      <String, Object?>{
        'phase': 'afterEnqueue',
        'queueSize': queue.length,
        'paths': queue
            .map(
              (Map<String, dynamic> job) =>
                  '${job['op']}:${job['storagePath']}',
            )
            .toList()
            .join(','),
      },
    );
    _log('Photo queue size=${queue.length} reason=enqueue');
  }

  void _offerCustomerSide({
    required void Function(Map<String, dynamic> job) offer,
    required String businessId,
    required Customer guest,
    required String side,
    required String raw,
  }) {
    final String? sha = sha256OfBase64(raw);
    final String path = side == 'front'
        ? HotelPhotoPaths.front(businessId, guest.customerId)
        : HotelPhotoPaths.back(businessId, guest.customerId);
    if (sha == null) {
      // Missing local bytes must never delete a cloud photo.
      return;
    }
    offer(<String, dynamic>{
      'op': 'upload',
      'storagePath': HotelPhotoPaths.versioned(path, sha),
      'sha256': sha,
      'guestId': guest.customerId,
      'side': side,
      'source': 'customer',
      'base64': raw,
      'retries': 0,
    });
  }

  void _offerExtraList({
    required void Function(Map<String, dynamic> job) offer,
    required String businessId,
    required String primaryGuestId,
    required List<Map<String, dynamic>> extras,
    required List<Customer> guests,
  }) {
    if (primaryGuestId.isEmpty) {
      return;
    }
    for (final Map<String, dynamic> extra in extras) {
      final String mobile = (extra['mobile'] ?? '').toString();
      final String idNumber = (extra['idNumber'] ?? '').toString();
      final Customer? linked = _byMobile(guests, mobile);
      final String additionalId = HotelPhotoPaths.additionalGuestId(
        mobile: mobile,
        idNumber: idNumber,
        customerId: linked?.customerId,
      );
      final String frontRaw =
          (extra['idFrontPhoto'] ?? extra['frontPhoto'] ?? '').toString();
      final String backRaw = (extra['idBackPhoto'] ?? extra['backPhoto'] ?? '')
          .toString();
      final String? frontSha = sha256OfBase64(frontRaw);
      final String? backSha = sha256OfBase64(backRaw);
      final String frontPath = HotelPhotoPaths.additionalFront(
        businessId,
        primaryGuestId,
        additionalId,
      );
      final String backPath = HotelPhotoPaths.additionalBack(
        businessId,
        primaryGuestId,
        additionalId,
      );
      _offerSideBytes(
        offer: offer,
        path: frontPath,
        sha: frontSha,
        raw: frontRaw,
        guestId: primaryGuestId,
        additionalGuestId: additionalId,
        side: 'front',
      );
      _offerSideBytes(
        offer: offer,
        path: backPath,
        sha: backSha,
        raw: backRaw,
        guestId: primaryGuestId,
        additionalGuestId: additionalId,
        side: 'back',
      );
    }
  }

  void _offerSideBytes({
    required void Function(Map<String, dynamic> job) offer,
    required String path,
    required String? sha,
    required String raw,
    required String guestId,
    required String side,
    String additionalGuestId = '',
  }) {
    if (sha == null) {
      // Missing local bytes must never delete a cloud photo.
      return;
    }
    offer(<String, dynamic>{
      'op': 'upload',
      'storagePath': HotelPhotoPaths.versioned(path, sha),
      'sha256': sha,
      'guestId': guestId,
      'additionalGuestId': additionalGuestId,
      'side': side,
      'source': additionalGuestId.isEmpty ? 'customer' : 'extra',
      'base64': raw,
      'retries': 0,
    });
  }

  Future<void> _flushLocked({required String reason}) async {
    lastUploadError = null;
    HotelPhotoUploadDebug.stage(
      '7 HotelPhotoStorageService upload method called',
      <String, Object?>{
        'method': 'flushQueue',
        'reason': reason,
        'isAvailable': isAvailable,
      },
    );
    if (!isAvailable) {
      HotelPhotoUploadDebug.stage(
        '7 HotelPhotoStorageService skipped',
        <String, Object?>{'reason': 'Storage not available'},
      );
      _log('Photo flush skipped ($reason): Storage not available');
      return;
    }
    final String? businessId = await _businessId();
    if (businessId == null) {
      HotelPhotoUploadDebug.stage(
        '7 HotelPhotoStorageService skipped',
        <String, Object?>{'reason': 'flush no businessId'},
      );
      return;
    }
    await _loadIndex();
    final HotelDataBuffer prefs = await HotelDataBuffer.getInstance();
    final List<Map<String, dynamic>> queue = await _readQueue();
    if (queue.isEmpty) {
      HotelPhotoUploadDebug.stage(
        '15 Pending/retry queue state',
        <String, Object?>{
          'phase': 'flush',
          'queueSize': 0,
          'reason': 'empty queue, nothing to upload',
        },
      );
      return;
    }
    HotelPhotoUploadDebug.stage(
      '15 Pending/retry queue state',
      <String, Object?>{
        'phase': 'flushStart',
        'queueSize': queue.length,
        'paths': queue
            .map(
              (Map<String, dynamic> job) =>
                  '${job['op']}:${job['storagePath']}',
            )
            .toList()
            .join(','),
      },
    );
    final List<Customer> guests = _decodeGuests(
      prefs.getString(CloudSyncService.customerKey),
    );
    final List<Room> rooms = HotelCloudCodec.decodeRoomList(
      _decodeList(prefs.getString(CloudSyncService.roomKey)),
    );
    final List<Map<String, dynamic>> remaining = <Map<String, dynamic>>[];

    for (final Map<String, dynamic> job in queue) {
      final String path = (job['storagePath'] ?? '').toString();
      final String op = (job['op'] ?? 'upload').toString();
      final String expectedSha = (job['sha256'] ?? '').toString();
      if (path.isEmpty) {
        continue;
      }
      if (!path.startsWith('businesses/$businessId/')) {
        remaining.add(job);
        continue;
      }
      if (op == 'delete') {
        _log(
          'Skipping queued Storage delete for $path; '
          'photos stay unless the guest is removed',
        );
        continue;
      }
      if (expectedSha.isEmpty) {
        continue;
      }
      if (_pathIndex[path] == expectedSha) {
        HotelPhotoUploadDebug.stage(
          '7 HotelPhotoStorageService skipped unchanged photo',
          <String, Object?>{
            'storagePath': path,
            'reason': 'sha256 already uploaded',
          },
        );
        continue;
      }
      final String? raw =
          job['base64'] as String? ??
          _localBase64ForJob(job, guests: guests, rooms: rooms);
      final String? actualSha = sha256OfBase64(raw ?? '');
      if (actualSha == null) {
        HotelPhotoUploadDebug.stage('8 Base64 decode', <String, Object?>{
          'result': 'failure',
          'reason': 'local bytes missing or not decodable',
          'storagePath': path,
          'rawPresent': (raw ?? '').isNotEmpty,
          'rawLength': (raw ?? '').length,
        });
        remaining.add(job);
        continue;
      }
      if (actualSha != expectedSha) {
        job['sha256'] = actualSha;
      }
      try {
        HotelPhotoUploadDebug.stage(
          '7 HotelPhotoStorageService upload method called',
          <String, Object?>{
            'method': 'putData',
            'guestId': job['guestId'],
            'side': job['side'],
          },
        );
        final Uint8List? decoded = decodeBase64Photo(raw!);
        if (decoded == null || decoded.isEmpty) {
          HotelPhotoUploadDebug.stage('8 Base64 decode', <String, Object?>{
            'result': 'failure',
            'decodedByteLength': 0,
            'storagePath': path,
          });
          throw StateError('Could not decode ID photo for $path');
        }
        HotelPhotoUploadDebug.stage('8 Base64 decode', <String, Object?>{
          'result': 'success',
          'decodedByteLength': decoded.length,
        });
        final Uint8List compressed = await compute(
          compressHotelIdPhoto,
          decoded,
        );
        HotelPhotoUploadDebug.stage('9 Exact Storage path', <String, Object?>{
          'storagePath': path,
          'compressedByteLength': compressed.length,
          'contentType': HotelPhotoRef.jpegContentType,
        });
        _logAuthAndBucket();
        if (compressed.length > HotelPhotoRef.maxBytes) {
          throw StateError('ID photo exceeds 5 MB after compress ($path)');
        }
        final Reference storageRef = FirebaseStorage.instance.ref(path);
        final PhotoUploadChoice choice = await _choiceForExistingPhoto(
          storageRef,
          compressed,
          path,
        );
        if (choice == PhotoUploadChoice.retryRead) {
          remaining.add(job);
          continue;
        }
        if (choice == PhotoUploadChoice.keepOriginal) {
          continue;
        }
        HotelPhotoUploadDebug.stage(
          '11 putData()/upload started',
          <String, Object?>{
            'storagePath': path,
            'byteLength': compressed.length,
          },
        );
        await FirebaseStorage.instance
            .ref(path)
            .putData(
              compressed,
              SettableMetadata(contentType: HotelPhotoRef.jpegContentType),
            )
            .timeout(_timeout);
        HotelPhotoUploadDebug.stage(
          '12 Upload completion result',
          <String, Object?>{
            'result': 'success',
            'storagePath': path,
            'byteLength': compressed.length,
          },
        );
        final storageSha = sha256.convert(compressed).toString();
        await _patchGuestMetadata(
          businessId: businessId,
          job: job,
          path: path,
          sha256: storageSha,
          byteLength: compressed.length,
        );
        _pathIndex[path] = actualSha;
        _photoHeads['$businessId:${HotelPhotoPaths.metaKeyFromStoragePath(path)}'] =
            storageSha;
        await _writeIndex();
        lastPhotoError = null;
        _log('Uploaded $path (${compressed.length} bytes)');
      } on FirebaseException catch (error, stack) {
        final int retries = ((job['retries'] as num?)?.toInt() ?? 0) + 1;
        job['retries'] = retries;
        HotelPhotoUploadDebug.stage(
          '13 Full FirebaseException',
          <String, Object?>{
            'code': error.code,
            'message': error.message,
            'plugin': error.plugin,
            'storagePath': path,
            'retries': retries,
          },
        );
        debugPrint('[${HotelPhotoUploadDebug.tag}] stack: $stack');
        HotelPhotoUploadDebug.stage(
          '12 Upload completion result',
          <String, Object?>{'result': 'firebaseException', 'storagePath': path},
        );
        _logError('Upload failed $path try=$retries: $error', stack);
        lastPhotoError = error.toString();
        lastUploadError = error.toString();
        remaining.add(job);
      } catch (error, stack) {
        final int retries = ((job['retries'] as num?)?.toInt() ?? 0) + 1;
        job['retries'] = retries;
        HotelPhotoUploadDebug.stage(
          '13 Full FirebaseException',
          <String, Object?>{
            'code': error is FirebaseException
                ? error.code
                : error.runtimeType.toString(),
            'message': error.toString(),
            'plugin': error is FirebaseException ? error.plugin : 'unknown',
            'storagePath': path,
            'retries': retries,
          },
        );
        debugPrint('[${HotelPhotoUploadDebug.tag}] stack: $stack');
        HotelPhotoUploadDebug.stage(
          '12 Upload completion result',
          <String, Object?>{'result': 'error', 'storagePath': path},
        );
        _logError('Upload failed $path try=$retries: $error', stack);
        lastPhotoError = error.toString();
        lastUploadError = error.toString();
        remaining.add(job);
      }
    }

    await prefs.setString(_queueKey, jsonEncode(remaining));
    pendingUploadCount = remaining
        .where(
          (job) => job['storagePath'].toString().startsWith(
            'businesses/$businessId/',
          ),
        )
        .length;
    notifyListeners();
    HotelPhotoUploadDebug.stage('15 Pending/retry queue state', <
      String,
      Object?
    >{
      'phase': 'flushEnd',
      'remaining': remaining.length,
      'paths': remaining
          .map(
            (Map<String, dynamic> job) =>
                '${job['op']}:${job['storagePath']}:retries=${job['retries']}',
          )
          .toList()
          .join(','),
    });
  }

  String? _localBase64ForJob(
    Map<String, dynamic> job, {
    required List<Customer> guests,
    required List<Room> rooms,
  }) {
    final String source = (job['source'] ?? 'customer').toString();
    final String side = (job['side'] ?? 'front').toString();
    if (source == 'customer') {
      final String guestId = (job['guestId'] ?? '').toString();
      for (final Customer guest in guests) {
        if (guest.customerId == guestId) {
          return side == 'back'
              ? guest.idBackPhotoPath
              : guest.idFrontPhotoPath;
        }
      }
      return null;
    }
    final String additionalId = (job['additionalGuestId'] ?? '').toString();
    final String primaryId = (job['guestId'] ?? '').toString();
    for (final Room room in rooms) {
      final String roomPrimary = _primaryGuestId(guests, room);
      if (roomPrimary != primaryId) {
        continue;
      }
      for (final List<Map<String, dynamic>> extras
          in <List<Map<String, dynamic>>>[
            room.extraGuests,
            room.futureExtraGuests,
          ]) {
        for (final Map<String, dynamic> extra in extras) {
          final Customer? linked = _byMobile(
            guests,
            (extra['mobile'] ?? '').toString(),
          );
          final String id = HotelPhotoPaths.additionalGuestId(
            mobile: (extra['mobile'] ?? '').toString(),
            idNumber: (extra['idNumber'] ?? '').toString(),
            customerId: linked?.customerId,
          );
          if (id != additionalId) {
            continue;
          }
          final String raw = side == 'back'
              ? (extra['idBackPhoto'] ?? extra['backPhoto'] ?? '').toString()
              : (extra['idFrontPhoto'] ?? extra['frontPhoto'] ?? '').toString();
          return raw;
        }
      }
    }
    return null;
  }

  Future<void> _patchGuestMetadata({
    required String businessId,
    required Map<String, dynamic> job,
    required String path,
    required String sha256,
    required int byteLength,
    bool deleted = false,
  }) async {
    final String guestId = (job['guestId'] ?? '').toString();
    final String side = (job['side'] ?? 'front').toString();
    final String additional = (job['additionalGuestId'] ?? '').toString();
    if (guestId.isEmpty) {
      HotelPhotoUploadDebug.stage(
        '14 Firestore photo metadata update result',
        <String, Object?>{'result': 'skipped', 'reason': 'empty guestId'},
      );
      return;
    }
    final bool front = side != 'back';
    final bool hasPhoto = !deleted && path.isNotEmpty;
    final Map<String, dynamic> photoMeta = <String, dynamic>{
      'hasPhoto': hasPhoto,
      'kind': hasPhoto ? 'storage' : 'none',
      'storagePath': hasPhoto ? path : null,
      'byteLength': hasPhoto ? byteLength : 0,
      'contentType': hasPhoto ? HotelPhotoRef.jpegContentType : null,
      'sha256': hasPhoto ? sha256 : null,
      'storageEnabled': true,
    };
    final ref = HotelFirestoreService.instance
        .guestsCol(businessId)
        .doc(guestId);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final current = snap.data();
      if (current == null || current['deleted'] == true) {
        throw StateError('Guest is not yet committed; photo remains pending.');
      }
      final sideSha = front ? 'idFrontSha256' : 'idBackSha256';
      final existing = additional.isEmpty
          ? current[sideSha]
          : (current['additionalPhotos'] as Map?)?[additional]?[sideSha];
      if (existing != null &&
          existing != job['expectedSha'] &&
          existing != sha256) {
        throw HotelSyncConflict(['guests/$guestId/$side/photo']);
      }
      final sideData = <String, dynamic>{
        front ? 'idFrontStoragePath' : 'idBackStoragePath': path,
        front ? 'hasFrontPhoto' : 'hasBackPhoto': hasPhoto,
        front ? 'idFrontByteLength' : 'idBackByteLength': byteLength,
        front ? 'idFrontContentType' : 'idBackContentType':
            HotelPhotoRef.jpegContentType,
        sideSha: sha256,
        front ? 'idFrontPhotoPath' : 'idBackPhotoPath': photoMeta,
      };
      transaction.set(ref, {
        'schemaVersion': 3,
        'photoUpdatedAt': DateTime.now().millisecondsSinceEpoch,
        if (additional.isEmpty) ...sideData,
        if (additional.isNotEmpty) 'additionalPhotos': {additional: sideData},
      }, SetOptions(merge: true));
    });
  }

  Future<Uint8List?> readGuestPhoto(
    Customer guest, {
    required bool front,
  }) async {
    final raw = front ? guest.idFrontPhotoPath : guest.idBackPhotoPath;
    final local = decodeBase64Photo(raw);
    if (local != null) return local;
    if (!isAvailable || guest.customerId.isEmpty) return null;
    final businessId = await _businessId();
    if (businessId == null) return null;
    final snap = await HotelFirestoreService.instance
        .col(businessId, 'guests')
        .doc(guest.customerId)
        .get(const GetOptions(source: Source.server));
    final data = snap.data();
    if (data == null || data['deleted'] == true) return null;
    final path = _pathFromDoc(data, front: front);
    if (path == null) return null;
    final value = await _downloadBase64(path);
    if (value == null) {
      throw StateError(lastPhotoError ?? 'ID photo could not be downloaded.');
    }
    if (front) {
      guest.idFrontPhotoPath = value;
    } else {
      guest.idBackPhotoPath = value;
    }
    return decodeBase64Photo(value);
  }

  /// Download photos after Firestore guest restore. Never throws to caller.
  Future<void> restorePhotos({
    required String businessId,
    required Map<String, Map<String, dynamic>> guestDocs,
  }) async {
    restoring = true;
    hasRestoreFailures = false;
    try {
      await _loadIndex();
      final HotelDataBuffer prefs = await HotelDataBuffer.getInstance();
      final List<Customer> guests = _decodeGuests(
        prefs.getString(CloudSyncService.customerKey),
      );
      bool guestsChanged = false;
      for (final Customer guest in guests) {
        final Map<String, dynamic>? doc = guestDocs[guest.customerId];
        for (final side in ['front', 'back']) {
          final head = doc?[side == 'front' ? 'idFrontSha256' : 'idBackSha256'];
          if (head is String) {
            _photoHeads['$businessId:${HotelPhotoPaths.metaKey(guestId: guest.customerId, side: side)}'] =
                head;
          }
        }
        if (doc != null && doc['deleted'] == true) {
          continue;
        }
        if (!HotelPhotoRef.looksLikePhotoBytes(guest.idFrontPhotoPath) &&
            (doc?['hasFrontPhoto'] == true ||
                _pathFromDoc(doc ?? {}, front: true) != null)) {
          final String frontPath =
              (doc == null ? null : _pathFromDoc(doc, front: true)) ??
              HotelPhotoPaths.front(businessId, guest.customerId);
          final String? front = await _downloadBase64(frontPath);
          if (front != null) {
            guest.idFrontPhotoPath = front;
            guestsChanged = true;
          }
        }
        if (!HotelPhotoRef.looksLikePhotoBytes(guest.idBackPhotoPath) &&
            (doc?['hasBackPhoto'] == true ||
                _pathFromDoc(doc ?? {}, front: false) != null)) {
          final String backPath =
              (doc == null ? null : _pathFromDoc(doc, front: false)) ??
              HotelPhotoPaths.back(businessId, guest.customerId);
          final String? back = await _downloadBase64(backPath);
          if (back != null) {
            guest.idBackPhotoPath = back;
            guestsChanged = true;
          }
        }
      }
      if (guestsChanged) {
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
      }

      final List<Room> rooms = HotelCloudCodec.decodeRoomList(
        _decodeList(prefs.getString(CloudSyncService.roomKey)),
      );
      bool roomsChanged = false;
      for (final Room room in rooms) {
        final String primaryId = _primaryGuestId(guests, room);
        if (primaryId.isEmpty) {
          continue;
        }
        final Map<String, dynamic>? primaryDoc = guestDocs[primaryId];
        if (await _restoreExtraPhotos(
          extras: room.extraGuests,
          guests: guests,
          businessId: businessId,
          primaryGuestId: primaryId,
          primaryDoc: primaryDoc,
        )) {
          roomsChanged = true;
        }
        if (await _restoreExtraPhotos(
          extras: room.futureExtraGuests,
          guests: guests,
          businessId: businessId,
          primaryGuestId: primaryId,
          primaryDoc: primaryDoc,
        )) {
          roomsChanged = true;
        }
      }
      if (roomsChanged) {
        await prefs.setString(
          CloudSyncService.roomKey,
          jsonEncode(rooms.map((Room room) => room.toJson()).toList()),
        );
      }
      if (guestsChanged || roomsChanged) {
        _log(
          'Restored ID photos guestsChanged=$guestsChanged '
          'roomsChanged=$roomsChanged',
        );
      }
    } catch (error, stack) {
      _logError('Photo restore failed; hotel data is intact: $error', stack);
    } finally {
      restoring = false;
      notifyListeners();
    }
  }

  Future<bool> _restoreExtraPhotos({
    required List<Map<String, dynamic>> extras,
    required List<Customer> guests,
    required String businessId,
    required String primaryGuestId,
    required Map<String, dynamic>? primaryDoc,
  }) async {
    bool changed = false;
    for (final Map<String, dynamic> extra in extras) {
      final String mobile = (extra['mobile'] ?? '').toString();
      final String idNumber = (extra['idNumber'] ?? '').toString();
      final Customer? linked = _byMobile(guests, mobile);
      final String additionalId = HotelPhotoPaths.additionalGuestId(
        mobile: mobile,
        idNumber: idNumber,
        customerId: linked?.customerId,
      );
      if (await _fillExtraSide(
        extra: extra,
        key: 'idFrontPhoto',
        altKey: 'frontPhoto',
        fromCustomer: linked?.idFrontPhotoPath ?? '',
        storagePath: HotelPhotoPaths.additionalFront(
          businessId,
          primaryGuestId,
          additionalId,
        ),
        wantsDownload: _additionalWantsPhoto(
          primaryDoc,
          additionalId,
          front: true,
        ),
      )) {
        changed = true;
      }
      if (await _fillExtraSide(
        extra: extra,
        key: 'idBackPhoto',
        altKey: 'backPhoto',
        fromCustomer: linked?.idBackPhotoPath ?? '',
        storagePath: HotelPhotoPaths.additionalBack(
          businessId,
          primaryGuestId,
          additionalId,
        ),
        wantsDownload: _additionalWantsPhoto(
          primaryDoc,
          additionalId,
          front: false,
        ),
      )) {
        changed = true;
      }
    }
    return changed;
  }

  Future<bool> _fillExtraSide({
    required Map<String, dynamic> extra,
    required String key,
    required String altKey,
    required String fromCustomer,
    required String storagePath,
    required bool wantsDownload,
  }) async {
    final String current = (extra[key] ?? extra[altKey] ?? '').toString();
    if (HotelPhotoRef.looksLikePhotoBytes(current)) {
      extra[key] = current;
      return false;
    }
    if (HotelPhotoRef.looksLikePhotoBytes(fromCustomer)) {
      extra[key] = fromCustomer;
      extra[altKey] = fromCustomer;
      return true;
    }
    if (!wantsDownload) {
      return false;
    }
    final String? downloaded = await _downloadBase64(storagePath);
    if (downloaded == null) {
      return false;
    }
    extra[key] = downloaded;
    extra[altKey] = downloaded;
    return true;
  }

  bool _additionalWantsPhoto(
    Map<String, dynamic>? doc,
    String additionalId, {
    required bool front,
  }) {
    if (doc == null) {
      return true;
    }
    final dynamic nested = doc['additionalPhotos'];
    if (nested is Map) {
      final dynamic item = nested[additionalId];
      if (item is Map) {
        final bool flagged =
            item[front ? 'hasFrontPhoto' : 'hasBackPhoto'] == true;
        final String path =
            (item[front ? 'idFrontStoragePath' : 'idBackStoragePath'] ?? '')
                .toString();
        return flagged || path.isNotEmpty;
      }
    }
    return true;
  }

  Future<void> deleteGuestPhotos({
    required String businessId,
    required String guestId,
  }) async {
    if (!isAvailable || guestId.trim().isEmpty) {
      return;
    }
    try {
      final List<String> paths = <String>[
        HotelPhotoPaths.front(businessId, guestId),
        HotelPhotoPaths.back(businessId, guestId),
      ];
      for (final String path in paths) {
        try {
          await FirebaseStorage.instance.ref(path).delete();
        } catch (_) {}
        _pathIndex.remove(path);
      }
      try {
        final ListResult listed = await FirebaseStorage.instance
            .ref('businesses/$businessId/guests/$guestId/additional')
            .listAll();
        for (final Reference ref in listed.items) {
          try {
            await ref.delete();
          } catch (_) {}
          _pathIndex.remove(ref.fullPath);
        }
        for (final Reference prefix in listed.prefixes) {
          final ListResult nested = await prefix.listAll();
          for (final Reference ref in nested.items) {
            try {
              await ref.delete();
            } catch (_) {}
            _pathIndex.remove(ref.fullPath);
          }
        }
      } catch (_) {}
      await _writeIndex();
      _log('Deleted Storage photos for guest $guestId');
    } catch (error, stack) {
      _logError('Delete guest photos failed $guestId: $error', stack);
    }
  }

  String? _pathFromDoc(Map<String, dynamic> doc, {required bool front}) {
    final String key = front ? 'idFrontStoragePath' : 'idBackStoragePath';
    final String top = (doc[key] ?? '').toString().trim();
    if (top.isNotEmpty) {
      return top;
    }
    final dynamic nested = doc[front ? 'idFrontPhotoPath' : 'idBackPhotoPath'];
    if (nested is Map) {
      final String path = (nested['storagePath'] ?? '').toString().trim();
      if (path.isNotEmpty) {
        return path;
      }
    }
    return null;
  }

  Future<String?> _downloadBase64(String? path) async {
    if (path == null || path.isEmpty || !isAvailable) {
      if ((path ?? '').isNotEmpty && !isAvailable) {
        debugPrint(
          '[PHOTO_RESTORE] download failure path=$path reason=storage unavailable',
        );
      }
      return null;
    }
    final businessId = await _businessId();
    if (!path.startsWith('businesses/$businessId/guests/')) {
      hasRestoreFailures = true;
      throw StateError('Photo belongs to another hotel.');
    }
    debugPrint('[PHOTO_RESTORE] storage path=$path');
    try {
      final Uint8List bytes =
          await FirebaseStorage.instance
              .ref(path)
              .getData(HotelPhotoRef.maxBytes)
              .timeout(_timeout) ??
          Uint8List(0);
      if (bytes.isEmpty) {
        debugPrint('[PHOTO_RESTORE] download failure path=$path reason=empty');
        return null;
      }
      _pathIndex[path] = sha256.convert(bytes).toString();
      await _writeIndex();
      debugPrint(
        '[PHOTO_RESTORE] download success path=$path bytes=${bytes.length}',
      );
      return base64Encode(bytes);
    } catch (error) {
      hasRestoreFailures = true;
      lastPhotoError = error.toString();
      debugPrint('[PHOTO_RESTORE] download failure path=$path reason=$error');
      _log('Download skipped $path: $error');
      return null;
    }
  }

  static String? sha256OfBase64(String raw) {
    final Uint8List? bytes = decodeBase64Photo(raw);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    return sha256.convert(bytes).toString();
  }

  static Uint8List? decodeBase64Photo(String raw) {
    final String trimmed = raw.trim();
    if (!HotelPhotoRef.looksLikePhotoBytes(trimmed)) {
      return null;
    }
    try {
      return base64Decode(trimmed.replaceAll(RegExp(r'\s'), ''));
    } catch (_) {
      try {
        var padded = trimmed.replaceAll(RegExp(r'\s'), '');
        while (padded.length % 4 != 0) {
          padded = '$padded=';
        }
        return base64Decode(padded);
      } catch (_) {
        return null;
      }
    }
  }

  Future<String?> _businessId() async {
    final account = HotelFirestoreService.instance.account;
    if (account == null || account.ownerUid != PhoneAuthSession.uid) {
      return null;
    }
    return account.businessId;
  }

  Future<void> _loadIndex() async {
    if (_indexLoaded) {
      return;
    }
    final HotelDataBuffer prefs = await HotelDataBuffer.getInstance();
    _photoHeads = Map<String, String>.from(
      jsonDecode(prefs.getString('hotel_storage_heads_v4') ?? '{}') as Map,
    );
    final String raw = prefs.getString(_indexKey) ?? '{}';
    try {
      _pathIndex = Map<String, String>.from(
        (jsonDecode(raw) as Map).map(
          (dynamic key, dynamic value) =>
              MapEntry(key.toString(), value.toString()),
        ),
      );
    } catch (_) {
      _pathIndex = <String, String>{};
    }
    _indexLoaded = true;
  }

  Future<void> _writeIndex() async {
    final HotelDataBuffer prefs = await HotelDataBuffer.getInstance();
    await prefs.setString(_indexKey, jsonEncode(_pathIndex));
    await prefs.setString('hotel_storage_heads_v4', jsonEncode(_photoHeads));
  }

  static const String _mismatchKey = 'hotel_photo_mismatch_log';
  final List<Map<String, Object?>> mismatchNotes = <Map<String, Object?>>[];

  Future<void> retainOnlyBusiness(String businessId) async {
    final List<Map<String, dynamic>> queue = await _readQueue();
    final List<Map<String, dynamic>> kept = queue
        .where(
          (Map<String, dynamic> job) => (job['storagePath'] ?? '')
              .toString()
              .startsWith('businesses/$businessId/'),
        )
        .toList();
    final HotelDataBuffer prefs = await HotelDataBuffer.getInstance();
    await prefs.setString(_queueKey, jsonEncode(kept));
    pendingUploadCount = kept.length;
    notifyListeners();
  }

  Future<void> notePhotoMismatch({
    required String path,
    required int remoteBytes,
    required int localBytes,
  }) async {
    final Map<String, Object?> note = <String, Object?>{
      'path': path,
      'remoteBytes': remoteBytes,
      'localBytes': localBytes,
      'keptOriginal': true,
      'at': DateTime.now().toIso8601String(),
    };
    mismatchNotes.add(note);
    final HotelDataBuffer prefs = await HotelDataBuffer.getInstance();
    final List<dynamic> existing =
        jsonDecode(prefs.getString(_mismatchKey) ?? '[]') as List<dynamic>;
    existing.add(note);
    await prefs.setString(_mismatchKey, jsonEncode(existing));
    lastPhotoError =
        'Photo metadata mismatch recorded. Original cloud photo was kept.';
    notifyListeners();
  }

  Future<PhotoUploadChoice> _choiceForExistingPhoto(
    Reference ref,
    Uint8List compressed,
    String path,
  ) async {
    try {
      final Uint8List? remote = await ref.getData(HotelPhotoRef.maxBytes);
      if (remote == null || remote.isEmpty) {
        return choosePhotoUpload(
          readFailed: false,
          missing: true,
          remoteSha: null,
          localSha: sha256.convert(compressed).toString(),
        );
      }
      final String remoteSha = sha256.convert(remote).toString();
      final String localSha = sha256.convert(compressed).toString();
      final PhotoUploadChoice choice = choosePhotoUpload(
        readFailed: false,
        missing: false,
        remoteSha: remoteSha,
        localSha: localSha,
      );
      if (photoMetadataMismatched(
        missing: false,
        readFailed: false,
        remoteSha: remoteSha,
        localSha: localSha,
      )) {
        await notePhotoMismatch(
          path: path,
          remoteBytes: remote.length,
          localBytes: compressed.length,
        );
      }
      return choice;
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') {
        return PhotoUploadChoice.uploadNew;
      }
      lastPhotoError = 'Photo read failed. Original was not replaced.';
      lastUploadError = error.toString();
      notifyListeners();
      return PhotoUploadChoice.retryRead;
    }
  }

  Future<List<Map<String, dynamic>>> _readQueue() async {
    final HotelDataBuffer prefs = await HotelDataBuffer.getInstance();
    final String raw = prefs.getString(_queueKey) ?? '[]';
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((dynamic item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  List<dynamic> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty || raw == '[]') {
      return <dynamic>[];
    }
    try {
      return jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return <dynamic>[];
    }
  }

  List<Customer> _decodeGuests(String? raw) {
    final List<Customer> guests = <Customer>[];
    for (final dynamic item in _decodeList(raw)) {
      try {
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          item as Map,
        );
        guests.add(
          Customer(
            customerId: data['customerId']?.toString() ?? '',
            mobile: data['mobile']?.toString() ?? '',
            guestName: data['guestName']?.toString() ?? '',
            address: data['address']?.toString() ?? '',
            idType: data['idType']?.toString() ?? '',
            idNumber: data['idNumber']?.toString() ?? '',
            idFrontPhotoPath: data['idFrontPhotoPath']?.toString() ?? '',
            idBackPhotoPath: data['idBackPhotoPath']?.toString() ?? '',
            stayHistory: (data['stayHistory'] as List<dynamic>? ?? [])
                .map((dynamic h) => Map<String, dynamic>.from(h as Map))
                .toList(),
          ),
        );
      } catch (_) {}
    }
    return guests;
  }

  String _primaryGuestId(List<Customer> guests, Room room) {
    final Customer? found = _byMobile(guests, room.mobile);
    if (found != null && found.customerId.trim().isNotEmpty) {
      return found.customerId.trim();
    }
    if (room.mobile.trim().isNotEmpty) {
      return 'room_${room.roomNumber}_${room.mobile.replaceAll(RegExp(r'\D'), '')}';
    }
    return '';
  }

  Customer? _byMobile(List<Customer> guests, String mobile) {
    final String digits = mobile.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return null;
    }
    for (final Customer guest in guests) {
      final String other = guest.mobile.replaceAll(RegExp(r'\D'), '');
      if (other == digits ||
          (other.length >= 10 &&
              digits.length >= 10 &&
              other.substring(other.length - 10) ==
                  digits.substring(digits.length - 10))) {
        return guest;
      }
    }
    return null;
  }

  void _log(String message) => debugPrint('[$_logTag] $message');

  void _logError(String message, [StackTrace? stack]) {
    debugPrint('[$_logTag] ERROR $message');
    if (stack != null) {
      debugPrint('[$_logTag] $stack');
    }
  }
}

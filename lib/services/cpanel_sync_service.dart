import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/backend_config.dart';
import 'cloud_sync_service.dart';
import 'cpanel_api.dart';
import 'cpanel_session.dart';
import 'cpanel_sync_payload.dart';
import 'hotel_photo_ref.dart';
import 'hotel_cloud_sync_service.dart';
import 'hotel_license_policy.dart';
import 'license_service.dart';

class CpanelSyncService extends ChangeNotifier {
  CpanelSyncService._();
  static final CpanelSyncService instance = CpanelSyncService._();

  final CpanelApi api = CpanelApi();
  final CpanelSession session = CpanelSession();
  String? lastError;
  int? lastHttpStatus;
  bool syncing = false;
  List<Map<String, dynamic>> pendingConflicts = [];
  Future<void>? _queue;

  Future<T> _serial<T>(Future<T> Function() work) {
    final previous = _queue ?? Future<void>.value();
    final result = previous.then((_) => work());
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> bootstrap() async {
    await session.restore();
    if (session.accessToken == null || session.userId == null) {
      throw StateError('Login required');
    }
    await pull();
    if (lastError != null && lastHttpStatus == 403) {
      _publishSyncStatus();
      return;
    }
    await captureAndPush();
    _publishSyncStatus();
  }

  Future<bool> redeem(String pin) async {
    try {
      final result = await api.send(
        'POST',
        '/v1/license/redeem',
        body: {'pin': pin},
        accessToken: session.accessToken,
      );
      applyLicense(Map<String, dynamic>.from(result['license'] as Map));
      return result['activated'] == true;
    } on CpanelApiException catch (error) {
      LicenseService.instance.lastError = error.message;
      LicenseService.instance.notifyListeners();
      return false;
    }
  }

  Future<void> keepThisPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final revisions = _decodeIntMap(prefs.getString('hp_revisions'));
    for (final conflict in pendingConflicts) {
      final key = '${conflict['entity']}/${conflict['recordId']}';
      revisions[key] = (conflict['serverRevision'] as num?)?.toInt() ?? 0;
    }
    await prefs.setString('hp_revisions', jsonEncode(revisions));
    pendingConflicts = [];
    await captureAndPush();
  }

  Future<void> useServerCopy() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('hp_cursor', 0);
    pendingConflicts = [];
    await CpanelSession.rememberOutbox([]);
    await pull();
  }

  Future<void> captureAndPush({bool photos = true}) {
    return _serial(() => _pushOnce(photos: photos));
  }

  Future<void> _pushOnce({bool photos = true}) async {
    if (!hotelUsesCpanel || session.accessToken == null) return;
    final changes = _changesForServer(await _diff());
    if (changes.isEmpty) {
      await CpanelSession.rememberOutbox([]);
      if (photos && await _uploadGuestPhotos()) {
        await _pushOnce(photos: false);
        return;
      }
      lastError = null;
      lastHttpStatus = null;
      _publishSyncStatus();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(changes);
    final previous = prefs.getString('hp_outbox');
    final key = previous == encoded
        ? (prefs.getString('hp_outbox_key') ?? _idempotencyKey(encoded))
        : _idempotencyKey(encoded);
    await prefs.setString('hp_outbox_key', key);
    await CpanelSession.rememberOutbox(changes);
    if (!_membershipCanWrite()) {
      _fail(
        'This account cannot change this hotel.',
        status: HotelCloudStatus.error,
      );
      return;
    }
    if (!LicenseService.instance.canEditHotel) {
      _fail(
        LicenseService.instance.statusMessage.isEmpty
            ? 'License required for new changes. Existing data remains.'
            : LicenseService.instance.statusMessage,
        status: HotelCloudStatus.error,
      );
      return;
    }
    HotelCloudSyncService.instance.status = HotelCloudStatus.syncing;
    HotelCloudSyncService.instance.notifyListeners();
    var delay = const Duration(seconds: 1);
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final result = await _sendAuthorized(
          'POST',
          '/v1/sync',
          body: {
            'idempotencyKey': key,
            if (session.businessId != null) 'businessId': session.businessId,
            'changes': changes,
          },
        );
        await _storeRevisions(List<Map<String, dynamic>>.from(
          (result['applied'] as List).map((item) => Map<String, dynamic>.from(item as Map)),
        ));
        await CpanelSession.rememberOutbox([]);
        await prefs.remove('hp_outbox_key');
        pendingConflicts = [];
        lastError = null;
        lastHttpStatus = 200;
        if (photos && await _uploadGuestPhotos()) {
          await _pushOnce(photos: false);
          return;
        }
        _publishSyncStatus();
        return;
      } on CpanelApiException catch (error) {
        pendingConflicts = (error.details['conflicts'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _fail(
          'Changes were not saved (HTTP ${error.status}). ${error.message}',
          httpStatus: error.status,
          status: HotelCloudStatus.error,
        );
        if (error.status == 409 || error.status == 403 || error.status == 413) return;
      } catch (_) {
        _fail(
          'Changes are saved on this phone and will sync when the server is reachable.',
          status: HotelCloudStatus.offline,
        );
      }
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }

  Future<void> pull() => _serial(_pullOnce);

  Future<void> retry() {
    return _serial(() async {
      await _pushOnce();
      await _pullOnce();
    });
  }

  Future<void> _pullOnce() async {
    final prefs = await SharedPreferences.getInstance();
    final cursor = prefs.getInt('hp_cursor') ?? 0;
    final result = await _sendAuthorized('GET', '/v1/sync?cursor=$cursor');
    final remoteBusiness = result['businessId']?.toString();
    if (remoteBusiness != null &&
        remoteBusiness.isNotEmpty &&
        session.businessId != null &&
        remoteBusiness != session.businessId) {
      _fail(
        'This account is not a member of the opened hotel.',
        httpStatus: 403,
        status: HotelCloudStatus.error,
      );
      return;
    }
    final remoteUser = result['userId']?.toString();
    if (remoteUser != null &&
        remoteUser.isNotEmpty &&
        session.userId != null &&
        remoteUser != session.userId) {
      _fail(
        'This login does not match the hotel account on this phone.',
        httpStatus: 403,
        status: HotelCloudStatus.error,
      );
      return;
    }
    final role = result['role']?.toString();
    if (role != null && role.isNotEmpty) session.role = role;
    final changes = (result['changes'] as List? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    await _merge(changes, protected: await _pendingKeys());
    final next = _asInt(result['cursor']);
    await prefs.setInt('hp_cursor', next == 0 ? cursor : next);
    if (result['license'] is Map) {
      applyLicense(Map<String, dynamic>.from(result['license'] as Map));
    }
    var applied = changes.isNotEmpty;
    if (!applied) {
      applied = await _downloadMissingGuestPhotos();
    }
    if (applied) {
      final sync = HotelCloudSyncService.instance;
      sync.remoteRevision++;
      sync.notifyListeners();
    }
    if (changes.length >= 100 && next > cursor) {
      await _pullOnce();
    }
  }

  Future<bool> _downloadMissingGuestPhotos() async {
    final prefs = await SharedPreferences.getInstance();
    final guests = _list(prefs, CloudSyncService.customerKey);
    final changed = await _fetchMissingPhotos(guests);
    if (changed) {
      await prefs.setString(CloudSyncService.customerKey, jsonEncode(guests));
    }
    return changed;
  }

  Future<List<Map<String, dynamic>>> _diff() async {
    final prefs = await SharedPreferences.getInstance();
    final acked = _decodeMap(prefs.getString('hp_acked'));
    final revisions = _decodeIntMap(prefs.getString('hp_revisions'));
    final current = await _localRecords();
    final changes = <Map<String, dynamic>>[];
    for (final entry in current.entries) {
      final encoded = jsonEncode(entry.value);
      if (acked[entry.key] == encoded) continue;
      final parts = entry.key.split('/');
      changes.add({
        'entity': parts[0],
        'recordId': parts[1],
        'baseRevision': revisions[entry.key] ?? 0,
        'deleted': entry.value['deleted'] == true,
        'payload': entry.value,
      });
    }
    for (final key in acked.keys) {
      if (current.containsKey(key)) continue;
      final parts = key.split('/');
      changes.add({
        'entity': parts[0],
        'recordId': parts[1],
        'baseRevision': revisions[key] ?? 0,
        'deleted': true,
        'payload': {'deleted': true},
      });
    }
    return changes;
  }

  Future<Map<String, Map<String, dynamic>>> _localRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final records = <String, Map<String, dynamic>>{};
    void add(String entity, String key, String idField) {
      final list = jsonDecode(prefs.getString(key) ?? '[]') as List;
      for (final item in list) {
        final map = Map<String, dynamic>.from(item as Map);
        final id = entity == 'rooms'
            ? 'room_${map['roomNumber']}'
            : map[idField]?.toString() ?? '';
        if (id.isEmpty || id.endsWith('_')) continue;
        records['$entity/$id'] = map;
      }
    }
    add('rooms', CloudSyncService.roomKey, 'roomNumber');
    add('bills', CloudSyncService.billKey, 'billNumber');
    add('guests', CloudSyncService.customerKey, 'customerId');
    add('expenses', CloudSyncService.expenseKey, 'expenseId');
    records['settings/hotel'] = {
      'hotel_name': prefs.getString('hotel_name') ?? 'Hotel',
      'hotel_address': prefs.getString('hotel_address') ?? '',
      'hotel_mobile': prefs.getString('hotel_mobile') ?? '',
      'hotel_registration_number': prefs.getString('hotel_registration_number') ?? '',
      'hotel_gst_number': prefs.getString('hotel_gst_number') ?? '',
      'hotel_gst_tax_rate': prefs.getDouble('hotel_gst_tax_rate') ?? 5,
      if (prefs.getString('hotel_admin_password') != null)
        'hotel_admin_password': prefs.getString('hotel_admin_password'),
    };
    return records;
  }

  Future<void> _merge(
    List<Map<String, dynamic>> changes, {
    Set<String> protected = const {},
  }) async {
    if (changes.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final grouped = <String, List<Map<String, dynamic>>>{
      'rooms': _list(prefs, CloudSyncService.roomKey),
      'bills': _list(prefs, CloudSyncService.billKey),
      'guests': _list(prefs, CloudSyncService.customerKey),
      'expenses': _list(prefs, CloudSyncService.expenseKey),
    };
    final revisions = _decodeIntMap(prefs.getString('hp_revisions'));
    final acked = _decodeMap(prefs.getString('hp_acked'));
    for (final change in changes) {
      final entity = change['entity']?.toString() ?? '';
      final id = change['recordId']?.toString() ?? '';
      final payload = Map<String, dynamic>.from(change['payload'] as Map? ?? {});
      final key = '$entity/$id';
      if (protected.contains(key)) {
        final serverRevision = _asInt(change['revision']);
        if (serverRevision != (revisions[key] ?? 0)) {
          pendingConflicts.add({
            'entity': entity,
            'recordId': id,
            'serverRevision': serverRevision,
            'financial': entity == 'bills' || entity == 'payments',
          });
        }
        continue;
      }
      if (entity == 'settings') {
        await _applySettings(prefs, payload);
        revisions['$entity/$id'] = _asInt(change['revision']);
        acked['$entity/$id'] = jsonEncode(payload);
        continue;
      }
      final list = grouped[entity];
      if (list == null) continue;
      final index = list.indexWhere((item) => _idOf(entity, item) == id);
      Map<String, dynamic> stored = payload;
      if (change['deleted'] == true) {
        if (index >= 0) list.removeAt(index);
      } else if (index >= 0) {
        stored = _keepLocalPhotos(list[index], payload);
        list[index] = stored;
      } else {
        list.add(payload);
      }
      revisions['$entity/$id'] = _asInt(change['revision']);
      acked['$entity/$id'] = jsonEncode(stored);
    }
    await prefs.setString(CloudSyncService.roomKey, jsonEncode(grouped['rooms']));
    await prefs.setString(CloudSyncService.billKey, jsonEncode(grouped['bills']));
    await prefs.setString(CloudSyncService.customerKey, jsonEncode(grouped['guests']));
    await prefs.setString(CloudSyncService.expenseKey, jsonEncode(grouped['expenses']));
    await prefs.setString('hp_revisions', jsonEncode(revisions));
    await prefs.setString('hp_acked', jsonEncode(acked));
    if (await _fetchMissingPhotos(grouped['guests'] ?? [])) {
      await prefs.setString(CloudSyncService.customerKey, jsonEncode(grouped['guests']));
    }
    if (session.userId != null) {
      await CpanelSession.snapshotActiveCache(session.userId!);
    }
  }

  Future<void> _applySettings(SharedPreferences prefs, Map<String, dynamic> payload) async {
    await prefs.setString('hotel_name', payload['hotel_name']?.toString() ?? 'Hotel');
    await prefs.setString('hotel_address', payload['hotel_address']?.toString() ?? '');
    await prefs.setString('hotel_mobile', payload['hotel_mobile']?.toString() ?? '');
    await prefs.setString('hotel_registration_number', payload['hotel_registration_number']?.toString() ?? '');
    await prefs.setString('hotel_gst_number', payload['hotel_gst_number']?.toString() ?? '');
    final rate = payload['hotel_gst_tax_rate'];
    await prefs.setDouble('hotel_gst_tax_rate', rate is num ? rate.toDouble() : 5);
    final admin = payload['hotel_admin_password']?.toString();
    if (admin != null && admin.isNotEmpty) {
      await prefs.setString('hotel_admin_password', admin);
    }
  }

  Future<bool> _uploadGuestPhotos() async {
    final prefs = await SharedPreferences.getInstance();
    final guests = _list(prefs, CloudSyncService.customerKey);
    var changed = false;
    for (final guest in guests) {
      final guestId = guest['customerId']?.toString() ?? '';
      if (guestId.isEmpty || session.accessToken == null) continue;
      changed = await _uploadSlot(guest, guestId, 'front', 'idFrontPhotoPath', 'idFrontPhotoId') || changed;
      changed = await _uploadSlot(guest, guestId, 'back', 'idBackPhotoPath', 'idBackPhotoId') || changed;
    }
    if (changed) {
      await prefs.setString(CloudSyncService.customerKey, jsonEncode(guests));
    }
    return changed;
  }

  Future<bool> _uploadSlot(
    Map<String, dynamic> guest,
    String guestId,
    String slot,
    String pathField,
    String idField,
  ) async {
    final path = guest[pathField]?.toString() ?? '';
    if (path.isEmpty || guest[idField] != null) return false;
    final file = await _photoFile(path);
    if (file == null) return false;
    try {
      final result = await _uploadPhoto(file, guestId, slot);
      guest[idField] = result['photoId'];
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _uploadPhoto(
    File file,
    String guestId,
    String slot,
  ) async {
    try {
      return await api.uploadPhoto(
        accessToken: session.accessToken!,
        guestId: guestId,
        slot: slot,
        file: file,
      );
    } on CpanelApiException catch (error) {
      if (error.status != 401 || !await _refreshSession()) rethrow;
      return api.uploadPhoto(
        accessToken: session.accessToken!,
        guestId: guestId,
        slot: slot,
        file: file,
      );
    }
  }

  Future<void> _downloadPhoto(String photoId, File destination) async {
    try {
      await api.downloadPhoto(
        accessToken: session.accessToken!,
        photoId: photoId,
        destination: destination,
      );
    } on CpanelApiException catch (error) {
      if (error.status != 401 || !await _refreshSession()) rethrow;
      await api.downloadPhoto(
        accessToken: session.accessToken!,
        photoId: photoId,
        destination: destination,
      );
    }
  }

  Future<bool> _refreshSession() async {
    if (session.refreshToken == null) return false;
    try {
      final refreshed = await api.send(
        'POST',
        '/v1/auth/refresh',
        body: {'refreshToken': session.refreshToken},
      );
      await session.updateTokens(refreshed);
      return session.accessToken != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _fetchMissingPhotos(List<Map<String, dynamic>> guests) async {
    if (session.accessToken == null) return false;
    final directory = await getApplicationDocumentsDirectory();
    var changed = false;
    for (final guest in guests) {
      final guestId = guest['customerId']?.toString() ?? '';
      if (guestId.isEmpty) continue;
      changed = await _fetchSlot(guest, guestId, 'front', 'idFrontPhotoPath', 'idFrontPhotoId', directory) || changed;
      changed = await _fetchSlot(guest, guestId, 'back', 'idBackPhotoPath', 'idBackPhotoId', directory) || changed;
    }
    return changed;
  }

  Future<bool> _fetchSlot(
    Map<String, dynamic> guest,
    String guestId,
    String slot,
    String pathField,
    String idField,
    Directory directory,
  ) async {
    final photoId = guest[idField]?.toString() ?? '';
    final current = guest[pathField]?.toString() ?? '';
    if (photoId.isEmpty || (current.isNotEmpty && File(current).existsSync())) return false;
    final destination = File('${directory.path}/hotelpro_photos/$guestId-$slot.jpg');
    try {
      await _downloadPhoto(photoId, destination);
      guest[pathField] = destination.path;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _storeRevisions(List<Map<String, dynamic>> applied) async {
    final prefs = await SharedPreferences.getInstance();
    final revisions = _decodeIntMap(prefs.getString('hp_revisions'));
    final acked = _decodeMap(prefs.getString('hp_acked'));
    final current = await _localRecords();
    for (final item in applied) {
      final key = '${item['entity']}/${item['recordId']}';
      revisions[key] = _asInt(item['revision']);
      if (current[key] != null) acked[key] = jsonEncode(current[key]);
    }
    await prefs.setString('hp_revisions', jsonEncode(revisions));
    await prefs.setString('hp_acked', jsonEncode(acked));
  }

  void applyLicense(Map<String, dynamic> license) {
    final now = DateTime.now().toUtc();
    final trialStart = DateTime.tryParse(license['trialStartedAt']?.toString() ?? '');
    final trialEnd = DateTime.tryParse(license['trialEndsAt']?.toString() ?? '');
    final expires = DateTime.tryParse(license['expiresAt']?.toString() ?? '');
    final assessment = assessHotelLicense(
      readFailed: false,
      documentExists: true,
      trialStart: trialStart,
      activated: license['activated'] == true,
      now: now,
      trialEndsAt: trialEnd,
      expiresAt: expires,
    );
    final service = LicenseService.instance;
    service.trialStart = trialStart;
    service.trialEndsAt = trialEnd;
    service.expiresAt = expires;
    if (license.containsKey('canWrite')) {
      final canWrite = license['canWrite'] == true;
      service.cloudView = canWrite
          ? (expires != null && now.isBefore(expires)
              ? HotelLicenseView.activated
              : HotelLicenseView.trial)
          : HotelLicenseView.expired;
      service.statusMessage = canWrite &&
              (assessment.view == HotelLicenseView.missing ||
                  assessment.view == HotelLicenseView.unreadable)
          ? 'Trial is active.'
          : assessment.message;
    } else {
      service.cloudView = assessment.view;
      service.statusMessage = assessment.message;
    }
    service.activated = service.cloudView == HotelLicenseView.activated;
    service.lastError = service.canEditHotel ? null : service.statusMessage;
    service.notifyListeners();
  }

  List<Map<String, dynamic>> _list(SharedPreferences prefs, String key) {
    final raw = jsonDecode(prefs.getString(key) ?? '[]') as List;
    return raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  String _idOf(String entity, Map<String, dynamic> item) {
    if (entity == 'rooms') return 'room_${item['roomNumber']}';
    if (entity == 'bills') return item['billNumber']?.toString() ?? '';
    if (entity == 'guests') return item['customerId']?.toString() ?? '';
    return item['expenseId']?.toString() ?? '';
  }

  Map<String, String> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map;
    return decoded.map((key, value) => MapEntry(key.toString(), value.toString()));
  }

  Map<String, int> _decodeIntMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map;
    return decoded.map((key, value) => MapEntry(key.toString(), _asInt(value)));
  }

  Map<String, dynamic> _keepLocalPhotos(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final merged = Map<String, dynamic>.from(remote);
    for (final field in syncPhotoFields) {
      final localValue = local[field];
      final remoteValue = merged[field];
      if (localValue is String &&
          localValue.isNotEmpty &&
          (remoteValue == null || remoteValue == '')) {
        merged[field] = localValue;
      }
    }
    for (final field in const ['idFrontPhotoId', 'idBackPhotoId']) {
      if ((merged[field] == null || merged[field] == '') && local[field] != null) {
        merged[field] = local[field];
      }
    }
    return merged;
  }

  int _asInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _membershipCanWrite() {
    final role = session.role;
    if (role == null || role.isEmpty) return true;
    return role == 'owner';
  }

  List<Map<String, dynamic>> _changesForServer(List<Map<String, dynamic>> changes) {
    return changes.map((change) {
      final copy = Map<String, dynamic>.from(change);
      final payload = copy['payload'];
      if (payload is Map) {
        copy['payload'] = syncPayloadForServer(Map<String, dynamic>.from(payload));
      }
      return copy;
    }).toList();
  }

  String _idempotencyKey(String encoded) => sha256.convert(utf8.encode(encoded)).toString();

  Future<Set<String>> _pendingKeys() async {
    final raw = (await SharedPreferences.getInstance()).getString('hp_outbox');
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List;
      return list.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return '${map['entity']}/${map['recordId']}';
      }).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> _sendAuthorized(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      return await api.send(method, path, body: body, accessToken: session.accessToken);
    } on CpanelApiException catch (error) {
      if (error.status != 401 || session.refreshToken == null) rethrow;
      final refreshed = await api.send(
        'POST',
        '/v1/auth/refresh',
        body: {'refreshToken': session.refreshToken},
      );
      await session.updateTokens(refreshed);
      return await api.send(method, path, body: body, accessToken: session.accessToken);
    }
  }

  Future<File?> _photoFile(String raw) async {
    if (!HotelPhotoRef.looksLikePhotoBytes(raw)) {
      final file = File(raw);
      return file.existsSync() ? file : null;
    }
    try {
      final bytes = base64Decode(raw);
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/hp_${sha256.convert(bytes)}.jpg');
      if (!file.existsSync()) {
        await file.writeAsBytes(bytes, flush: true);
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  void _fail(
    String message, {
    int? httpStatus,
    required HotelCloudStatus status,
  }) {
    lastError = message;
    lastHttpStatus = httpStatus;
    final sync = HotelCloudSyncService.instance;
    sync.lastError = message;
    sync.status = status;
    sync.notifyListeners();
    notifyListeners();
  }

  void _publishSyncStatus() {
    final sync = HotelCloudSyncService.instance;
    sync.lastError = lastError;
    if (lastError == null) {
      sync.status = HotelCloudStatus.synced;
    }
    sync.notifyListeners();
    notifyListeners();
  }
}

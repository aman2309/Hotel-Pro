// Historical compatibility code; excluded from the production app import graph.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_sync_service.dart';

const _activeUserKey = 'hp_cpanel_active_user';
const _cacheKeys = <String>[
  CloudSyncService.roomKey,
  CloudSyncService.billKey,
  CloudSyncService.customerKey,
  CloudSyncService.expenseKey,
  'hotel_name',
  'hotel_address',
  'hotel_mobile',
  'hotel_registration_number',
  'hotel_gst_number',
  'hotel_admin_password',
];
const _gstRateKey = 'hotel_gst_tax_rate';

class CpanelSession {
  CpanelSession({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  String? userId;
  String? businessId;
  String? role;
  String? accessToken;
  String? refreshToken;
  String? hotelName;

  Future<void> restore() async {
    userId = await _storage.read(key: 'hp_user');
    businessId = await _storage.read(key: 'hp_business');
    role = await _storage.read(key: 'hp_role');
    accessToken = await _storage.read(key: 'hp_access');
    refreshToken = await _storage.read(key: 'hp_refresh');
    hotelName = await _storage.read(key: 'hp_hotel');
  }

  Future<void> saveFromLogin(Map<String, dynamic> body) async {
    final nextUser = body['userId']?.toString() ?? '';
    await parkActiveCache(nextUser);
    userId = nextUser;
    businessId = body['businessId']?.toString();
    role = body['role']?.toString();
    accessToken = body['accessToken']?.toString();
    refreshToken = body['refreshToken']?.toString();
    hotelName = body['hotelName']?.toString();
    await _storage.write(key: 'hp_user', value: userId);
    await _storage.write(key: 'hp_business', value: businessId);
    await _storage.write(key: 'hp_role', value: role);
    await _storage.write(key: 'hp_access', value: accessToken);
    await _storage.write(key: 'hp_refresh', value: refreshToken);
    await _storage.write(key: 'hp_hotel', value: hotelName);
    await restoreCache(nextUser);
  }

  Future<void> updateTokens(Map<String, dynamic> body) async {
    accessToken = body['accessToken']?.toString();
    refreshToken = body['refreshToken']?.toString() ?? refreshToken;
    await _storage.write(key: 'hp_access', value: accessToken);
    await _storage.write(key: 'hp_refresh', value: refreshToken);
  }

  /// Keeps the previous account's cache and outbox. Does not upload it.
  Future<void> logout() async {
    if (userId != null) await parkActiveCache('');
    userId = null;
    businessId = null;
    role = null;
    accessToken = null;
    refreshToken = null;
    await _storage.deleteAll();
  }

  static String cachePrefix(String userId) => 'hp_cache_$userId';

  static Future<void> parkActiveCache(String nextUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getString(_activeUserKey);
    if (active != null && active.isNotEmpty && active != nextUserId) {
      for (final key in _cacheKeys) {
        final value = prefs.getString(key);
        if (value != null) {
          await prefs.setString('${cachePrefix(active)}_$key', value);
        }
        await prefs.remove(key);
      }
      final outbox = prefs.getString('hp_outbox');
      if (outbox != null) {
        await prefs.setString('${cachePrefix(active)}_outbox', outbox);
        await prefs.remove('hp_outbox');
      }
      final rate = prefs.getDouble(_gstRateKey);
      if (rate != null) {
        await prefs.setDouble('${cachePrefix(active)}_$_gstRateKey', rate);
      }
      await prefs.remove(_gstRateKey);
    }
    if (nextUserId.isEmpty) {
      await prefs.remove(_activeUserKey);
      for (final key in _cacheKeys) {
        await prefs.remove(key);
      }
    }
  }

  static Future<void> snapshotActiveCache(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _cacheKeys) {
      final value = prefs.getString(key);
      if (value != null) {
        await prefs.setString('${cachePrefix(userId)}_$key', value);
      }
    }
    final rate = prefs.getDouble(_gstRateKey);
    if (rate != null) {
      await prefs.setDouble('${cachePrefix(userId)}_$_gstRateKey', rate);
    }
    await prefs.setString(_activeUserKey, userId);
  }

  static Future<void> restoreCache(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _cacheKeys) {
      final saved = prefs.getString('${cachePrefix(userId)}_$key');
      if (saved != null) {
        await prefs.setString(key, saved);
      }
    }
    final outbox = prefs.getString('${cachePrefix(userId)}_outbox');
    if (outbox != null) await prefs.setString('hp_outbox', outbox);
    final rate = prefs.getDouble('${cachePrefix(userId)}_$_gstRateKey');
    if (rate != null) await prefs.setDouble(_gstRateKey, rate);
    await prefs.setString(_activeUserKey, userId);
  }

  static Future<void> rememberOutbox(List<Map<String, dynamic>> changes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hp_outbox', jsonEncode(changes));
    final user = prefs.getString(_activeUserKey);
    if (user != null) {
      await prefs.setString('${cachePrefix(user)}_outbox', jsonEncode(changes));
    }
  }
}

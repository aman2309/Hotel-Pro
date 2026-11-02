import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'phone_auth_service.dart';

/// Compatibility with existing local keys and read-only PHP migration.
/// Firestore is the sole live writer. This service never sends PHP PUTs.
class CloudSyncService {
  static const roomKey = 'hotelpro1_rooms';
  static const billKey = 'hotelpro1_bills';
  static const customerKey = 'hotelpro1_customers';
  static const expenseKey = 'hotelpro1_expenses';
  static const defaultUrl = 'https://2ndhealing.com/api/hotelpro1_store.php';
  static const defaultApiKey =
      '80a2d3cdf38216577c3bf7734c05331ab8906cbd7dcfe5ba';

  static bool autoSyncPaused = false;
  static Future<void> ensureDefaults() async {}
  static Future<void> markDirty() async {}
  static Future<void> clearDirty() async {}
  static Future<bool> isEnabled() async => false;
  static Future<int> localRevision() async => 0;
  static Future<String?> lastSyncAt() async =>
      (await SharedPreferences.getInstance()).getString(
        'hotel_firestore_last_sync_at',
      );
  static Future<void> restoreFromCloudIfLocalEmpty() async {}
  static Future<String?> syncIfEnabled({
    bool force = false,
    bool pullOnly = false,
  }) async => null;
  static Future<String> syncNow({
    bool forcePush = false,
    bool forcePull = false,
    bool pullOnly = false,
    int conflictRetries = 1,
  }) async => 'Firestore handles hotel sync';
  static Future<bool> isLocalBusinessDataEmpty() async {
    final prefs = await SharedPreferences.getInstance();
    return [
      roomKey,
      billKey,
      customerKey,
      expenseKey,
    ].every((key) => (prefs.getString(key) ?? '[]') == '[]');
  }

  static String loginStoreId(String phoneNumber) {
    var digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10) digits = digits.substring(digits.length - 10);
    if (digits.length < 10) {
      throw StateError('Verified login phone is required.');
    }
    return sha256.convert(utf8.encode('hp1_login_$digits')).toString();
  }

  static Future<void> bindLoginPhoneStore(String phoneNumber) async {
    await (await SharedPreferences.getInstance()).setString(
      'hp1_store_id',
      loginStoreId(phoneNumber),
    );
  }

  /// The old API authenticates only a shared app key, so use only the key
  /// derived internally from the verified phone. PIN stores require an admin
  /// mapping review; a shared license PIN is not proof of hotel ownership.
  static Future<void> importLegacyForVerifiedOwner() async {
    final phone = PhoneAuthSession.phoneNumber;
    if (PhoneAuthSession.uid == null || phone == null) {
      throw StateError('Verified owner required.');
    }
    final prefs = await SharedPreferences.getInstance();
    // The old PHP store uses a truncated phone hash and a shared API key.
    // It is not owner-authenticated. Import only after an administrator has
    // reviewed its full-phone/UID/business mapping; never infer ownership from PIN.
    if (payloadHasHotelData({
      for (final key in [roomKey, billKey, customerKey, expenseKey])
        key: prefs.getString(key) ?? '[]',
    })) {
      return;
    }
    if (prefs.getBool('hotel_new_owner_${PhoneAuthSession.uid}') == true) {
      return;
    }
    const reviewedLegacyImport = bool.fromEnvironment(
      'REVIEWED_LEGACY_PHP_IMPORT',
      defaultValue: false,
    );
    if (!reviewedLegacyImport) {
      throw StateError(
        'Legacy PHP hotel requires an approved owner mapping/import. No empty hotel data was uploaded.',
      );
    }
    final marker = 'hotel_php_import_${PhoneAuthSession.uid}';
    if (prefs.getBool(marker) == true) return;
    final response = await http
        .get(
          Uri.parse(defaultUrl),
          headers: {
            'X-Api-Key': defaultApiKey,
            'X-Store-Id': loginStoreId(phone),
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw StateError(
        'Legacy hotel lookup failed (${response.statusCode}). Retry; no data was uploaded.',
      );
    }
    final decoded = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (decoded['ok'] != true) throw StateError('Legacy lookup failed.');
    final payload = Map<String, dynamic>.from(decoded['data'] as Map);
    // Keep the original payload before any conversion/migration.
    await prefs.setString(
      'hotel_archive_${DateTime.now().microsecondsSinceEpoch}_php',
      jsonEncode({'ownerUid': PhoneAuthSession.uid, 'data': payload}),
    );
    if (payloadHasHotelData(payload)) {
      final local = {
        for (final key in [roomKey, billKey, customerKey, expenseKey])
          key: prefs.getString(key) ?? '[]',
      };
      if (payloadHasHotelData(local) &&
          [
            roomKey,
            billKey,
            customerKey,
            expenseKey,
          ].any((key) => local[key] != (payload[key] ?? '[]').toString())) {
        throw StateError(
          'Legacy PHP and local records differ. Both copies are preserved; reviewed migration required.',
        );
      }
      for (final key in [roomKey, billKey, customerKey, expenseKey]) {
        final raw = payload[key];
        if (raw == null) continue;
        final value = raw is String ? raw : jsonEncode(raw);
        if (jsonDecode(value) is! List) {
          throw FormatException('Legacy $key is not a list.');
        }
        await prefs.setString(key, value);
      }
      final settings = payload['settings'];
      if (settings is Map) {
        for (final entry in settings.entries) {
          if (!entry.key.toString().startsWith('hotel_')) continue;
          if (entry.key == 'hotel_gst_tax_rate') {
            await prefs.setDouble(
              entry.key.toString(),
              double.parse(entry.value.toString()),
            );
          } else {
            await prefs.setString(entry.key.toString(), entry.value.toString());
          }
        }
      }
    }
    await prefs.setBool(marker, true);
  }

  static bool payloadHasHotelData(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return false;
    }
    final String bills = (data[billKey] ?? '[]').toString();
    final String guests = (data[customerKey] ?? '[]').toString();
    final String expenses = (data[expenseKey] ?? '[]').toString();
    if (bills != '[]' && bills.isNotEmpty && bills != 'null') {
      return true;
    }
    if (guests != '[]' && guests.isNotEmpty && guests != 'null') {
      return true;
    }
    if (expenses != '[]' && expenses.isNotEmpty && expenses != 'null') {
      return true;
    }
    try {
      final Object? decoded = jsonDecode((data[roomKey] ?? '[]').toString());
      if (decoded is! List || decoded.isEmpty) {
        return false;
      }
      for (final Object? item in decoded) {
        if (item is! Map) {
          continue;
        }
        final String status = (item['status'] ?? '').toString();
        final String guest = (item['guestName'] ?? '').toString().trim();
        final bool future = item['futureBooking'] == true;
        if (status == 'BOOKED' ||
            status == 'CLOSED' ||
            status == 'CLEANING' ||
            future ||
            guest.isNotEmpty) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }
}

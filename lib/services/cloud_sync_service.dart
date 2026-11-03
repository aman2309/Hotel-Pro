import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'hotel_data_buffer.dart';

/// Compatibility with existing local keys and read-only PHP migration.
/// Firestore is the sole live writer. This service never sends PHP PUTs.
class CloudSyncService {
  static const roomKey = 'hotelpro1_rooms';
  static const billKey = 'hotelpro1_bills';
  static const customerKey = 'hotelpro1_customers';
  static const expenseKey = 'hotelpro1_expenses';
  static bool autoSyncPaused = false;
  static Future<void> ensureDefaults() async {}
  static Future<void> markDirty() async {}
  static Future<void> clearDirty() async {}
  static Future<bool> isEnabled() async => false;
  static Future<int> localRevision() async => 0;
  static Future<String?> lastSyncAt() async =>
      (await HotelDataBuffer.getInstance()).getString(
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
    final prefs = await HotelDataBuffer.getInstance();
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
    await (await HotelDataBuffer.getInstance()).setString(
      'hp1_store_id',
      loginStoreId(phoneNumber),
    );
  }

  /// Historical callers must not revive the retired cPanel backend.
  static Future<void> importLegacyForVerifiedOwner() async {
    throw StateError(
      'The app uses Firebase only. Legacy imports require a separate server migration.',
    );
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

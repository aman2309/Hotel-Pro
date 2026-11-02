import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bill_record.dart';
import '../services/hotel_record_ids.dart';
import '../services/cloud_sync_service.dart';
import '../services/hotel_cloud_sync_service.dart';

class BillStore {
  static const String _storageKey = CloudSyncService.billKey;

  static final List<BillRecord> bills = [];

  static Future<void> loadBills() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final String? savedData = prefs.getString(_storageKey);

    if (savedData == null || savedData.isEmpty) {
      return;
    }

    final List<dynamic> decoded = jsonDecode(savedData) as List<dynamic>;

    bills
      ..clear()
      ..addAll(
        decoded.map(
          (item) => BillRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        ),
      );
  }

  static Future<void> saveBill(BillRecord bill) async {
    final bool alreadyExists = bills.any(
      (existingBill) => existingBill.billNumber == bill.billNumber,
    );

    if (alreadyExists &&
        bills
                .firstWhere(
                  (existing) => existing.billNumber == bill.billNumber,
                )
                .toJson()
                .toString() !=
            bill.toJson().toString()) {
      throw StateError('Bill ID already exists with different details.');
    }
    if (!alreadyExists) {
      bills.add(bill);
    }

    await _saveBillsToDisk();
  }

  // Offline devices cannot safely allocate the same sequential bill number.
  // Existing bill numbers stay intact; new receipts have globally unique IDs.
  static String nextBillNumber() => HotelRecordIds.create('BILL');

  static Future<void> _saveBillsToDisk() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final List<Map<String, dynamic>> data = bills
        .map((bill) => bill.toJson())
        .toList();

    await prefs.setString(_storageKey, jsonEncode(data));
    await CloudSyncService.markDirty();
    unawaited(CloudSyncService.syncIfEnabled(force: true));
    await HotelCloudSyncService.instance.notifyLocalChanged();
  }
}

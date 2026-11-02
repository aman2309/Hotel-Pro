import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/cloud_sync_service.dart';
import '../services/hotel_record_ids.dart';
import '../services/hotel_cloud_codec.dart';
import '../services/hotel_cloud_sync_service.dart';

class ExpenseStore {
  static const String _storageKey = CloudSyncService.expenseKey;

  static final List<Map<String, dynamic>> expenses = [];

  static Future<void> loadExpenses() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final String? savedData = prefs.getString(_storageKey);

    expenses.clear();

    if (savedData == null || savedData.isEmpty) {
      return;
    }

    final List<dynamic> decoded = jsonDecode(savedData);

    expenses.addAll(
      decoded.map((item) => Map<String, dynamic>.from(item as Map)),
    );
  }

  static Future<void> saveExpenses() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await prefs.setString(_storageKey, jsonEncode(expenses));
    await CloudSyncService.markDirty();
    unawaited(CloudSyncService.syncIfEnabled(force: true));
    await HotelCloudSyncService.instance.notifyLocalChanged();
  }

  static Future<void> addExpense(Map<String, dynamic> expense) async {
    expense['expenseId'] ??= HotelRecordIds.create('exp');
    if (expenses.any(
      (existing) => existing['expenseId'] == expense['expenseId'],
    )) {
      return;
    }
    expenses.add(expense);

    await saveExpenses();
  }

  static Future<void> deleteExpense(Map<String, dynamic> expense) async {
    await HotelCloudSyncService.instance.registerExpenseDeletion(
      HotelCloudCodec.expenseId(expense),
    );
    expenses.remove(expense);

    await saveExpenses();
  }
}

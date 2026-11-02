import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer.dart';
import '../services/hotel_record_ids.dart';
import '../services/cloud_sync_service.dart';
import '../services/hotel_cloud_sync_service.dart';
import '../services/hotel_photo_upload_debug.dart';

class CustomerStore {
  static final List<Customer> customers = [];

  static const String _customerKey = CloudSyncService.customerKey;

  static Future<void> loadCustomers() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final String? savedData = prefs.getString(_customerKey);

    customers.clear();

    if (savedData == null || savedData.isEmpty) {
      return;
    }

    final List<dynamic> customerList = jsonDecode(savedData);

    for (final dynamic item in customerList) {
      final Map<String, dynamic> data = Map<String, dynamic>.from(item);

      customers.add(
        Customer(
          customerId: data["customerId"] ?? "",
          mobile: data["mobile"] ?? "",
          guestName: data["guestName"] ?? "",
          address: data["address"] ?? "",
          idType: data["idType"] ?? "",
          idNumber: data["idNumber"] ?? "",
          idFrontPhotoPath:
              data["idFrontPhotoPath"] ?? data["idPhotoPath"] ?? "",
          idBackPhotoPath: data["idBackPhotoPath"] ?? "",
          stayHistory: (data["stayHistory"] as List<dynamic>? ?? [])
              .map((history) => Map<String, dynamic>.from(history as Map))
              .toList(),
        ),
      );
    }

    bool customerIdAdded = false;

    for (final Customer customer in customers) {
      if (customer.customerId.isEmpty) {
        customer.customerId = HotelRecordIds.guest(
          normalizedMobile(customer.mobile),
        );
        customerIdAdded = true;
      }
    }

    if (customerIdAdded) {
      await _saveCustomersToDisk();
    }
  }

  static String normalizedMobile(String mobile) {
    final String digits = mobile.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  static Customer? findByMobile(String mobile) {
    final String cleanMobile = normalizedMobile(mobile);

    if (cleanMobile.isEmpty) {
      return null;
    }

    for (final Customer customer in customers) {
      if (normalizedMobile(customer.mobile) == cleanMobile) {
        return customer;
      }
    }

    return null;
  }

  static Future<void> saveCustomer(Customer customer) async {
    Customer? oldCustomer = findByMobile(customer.mobile);

    if (oldCustomer == null) {
      if (customer.customerId.isEmpty) {
        customer.customerId = HotelRecordIds.guest(
          normalizedMobile(customer.mobile),
        );
      }

      customers.add(customer);
    } else {
      oldCustomer.guestName = customer.guestName;
      oldCustomer.idType = customer.idType;
      oldCustomer.idNumber = customer.idNumber;
      if (customer.address.trim().isNotEmpty) {
        oldCustomer.address = customer.address.trim();
      }

      if (customer.idFrontPhotoPath.isNotEmpty) {
        oldCustomer.idFrontPhotoPath = customer.idFrontPhotoPath;
      }

      if (customer.idBackPhotoPath.isNotEmpty) {
        oldCustomer.idBackPhotoPath = customer.idBackPhotoPath;
      }
    }

    await _saveCustomersToDisk();
    final Customer saved = oldCustomer ?? customer;
    HotelPhotoUploadDebug.stage(
      '1 Booking/customer save persisted',
      <String, Object?>{
        'guestId': saved.customerId,
        'frontPresent': saved.idFrontPhotoPath.trim().isNotEmpty,
        'frontBase64Length': saved.idFrontPhotoPath.length,
        'backPresent': saved.idBackPhotoPath.trim().isNotEmpty,
        'backBase64Length': saved.idBackPhotoPath.length,
      },
    );
  }

  static Future<bool> updateCustomer(
    Customer customer, {
    required String mobile,
    required String guestName,
    required String address,
    required String idType,
    required String idNumber,
    required String idFrontPhotoPath,
    required String idBackPhotoPath,
  }) async {
    final String cleanMobile = mobile.trim();

    for (final Customer otherCustomer in customers) {
      if (otherCustomer != customer && otherCustomer.mobile == cleanMobile) {
        return false;
      }
    }

    customer.mobile = cleanMobile;
    customer.guestName = guestName.trim();
    customer.address = address.trim();
    customer.idType = idType.trim();
    customer.idNumber = idNumber.trim();
    customer.idFrontPhotoPath = idFrontPhotoPath;
    customer.idBackPhotoPath = idBackPhotoPath;

    await _saveCustomersToDisk();

    return true;
  }

  static Future<void> addStayHistory(
    String mobile,
    Map<String, dynamic> history,
  ) async {
    final Customer? customer = findByMobile(mobile);

    if (customer == null) {
      return;
    }

    final bill = history['billNumber'];
    if (bill != null &&
        customer.stayHistory.any((stay) => stay['billNumber'] == bill)) {
      return;
    }
    customer.stayHistory.add(Map<String, dynamic>.from(history));

    await _saveCustomersToDisk();
  }

  static Future<void> _saveCustomersToDisk() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final List<Map<String, dynamic>> customerList = customers.map((
      Customer customer,
    ) {
      return {
        "customerId": customer.customerId,
        "mobile": customer.mobile,
        "guestName": customer.guestName,
        "address": customer.address,
        "idType": customer.idType,
        "idNumber": customer.idNumber,
        "idFrontPhotoPath": customer.idFrontPhotoPath,
        "idBackPhotoPath": customer.idBackPhotoPath,
        "stayHistory": customer.stayHistory,
      };
    }).toList();

    await prefs.setString(_customerKey, jsonEncode(customerList));
    await CloudSyncService.markDirty();
    unawaited(CloudSyncService.syncIfEnabled(force: true));
    await HotelCloudSyncService.instance.notifyLocalChanged();
  }
}

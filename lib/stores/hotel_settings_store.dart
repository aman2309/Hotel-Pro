import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/hotel_cloud_sync_service.dart';

class HotelSettingsStore {
  static const String _hotelNameKey = "hotel_name";
  static const String _hotelAddressKey = "hotel_address";
  static const String _hotelMobileKey = "hotel_mobile";
  static const String _registrationNumberKey = "hotel_registration_number";
  static const String _gstNumberKey = "hotel_gst_number";
  static const String _gstTaxRateKey = "hotel_gst_tax_rate";
  static const String _adminPasswordKey = "hotel_admin_password";

  static String hotelName = "Hotel";
  static String hotelAddress = "";
  static String hotelMobile = "";
  static String registrationNumber = "";
  static String gstNumber = "";
  static double gstTaxRate = 5;
  static String adminPassword = "HOTEL2026";

  static Future<void> resetToDefaults() async {
    await saveSettings(
      hotelNameValue: "Hotel",
      hotelAddressValue: "",
      hotelMobileValue: "",
      registrationNumberValue: "",
      gstNumberValue: "",
      gstTaxRateValue: 5,
      adminPasswordValue: "HOTEL2026",
    );
  }

  static String displayPhoneFromLogin(String raw) {
    final String digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return digits.substring(1);
    }
    if (digits.length == 10) {
      return digits;
    }
    final String trimmed = raw.trim();
    return trimmed.isEmpty ? digits : trimmed;
  }

  /// Settings hotel mobile follows the number used to log in.
  static Future<void> applyLoginPhone(String? loginPhone) async {
    final String formatted = displayPhoneFromLogin(loginPhone ?? '');
    if (formatted.isEmpty) {
      return;
    }
    final String currentDigits = hotelMobile.replaceAll(RegExp(r'\D'), '');
    final String nextDigits = formatted.replaceAll(RegExp(r'\D'), '');
    if (currentDigits.isNotEmpty && currentDigits == nextDigits) {
      return;
    }
    await saveSettings(
      hotelNameValue: hotelName,
      hotelAddressValue: hotelAddress,
      hotelMobileValue: formatted,
      registrationNumberValue: registrationNumber,
      gstNumberValue: gstNumber,
      gstTaxRateValue: gstTaxRate,
      adminPasswordValue: adminPassword,
    );
  }

  static Future<void> loadSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    hotelName = prefs.getString(_hotelNameKey) ?? "Hotel";

    hotelAddress = prefs.getString(_hotelAddressKey) ?? "";

    hotelMobile = prefs.getString(_hotelMobileKey) ?? "";

    registrationNumber = prefs.getString(_registrationNumberKey) ?? "";

    gstNumber = prefs.getString(_gstNumberKey) ?? "";

    gstTaxRate =
        prefs.getDouble(_gstTaxRateKey) ??
        double.tryParse(prefs.getString(_gstTaxRateKey) ?? '') ??
        5;

    adminPassword = prefs.getString(_adminPasswordKey) ?? "HOTEL2026";
  }

  static Future<void> saveSettings({
    required String hotelNameValue,
    required String hotelAddressValue,
    required String hotelMobileValue,
    required String registrationNumberValue,
    required String gstNumberValue,
    double? gstTaxRateValue,
    required String adminPasswordValue,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    hotelName = hotelNameValue.trim();
    hotelAddress = hotelAddressValue.trim();
    hotelMobile = hotelMobileValue.trim();
    registrationNumber = registrationNumberValue.trim();
    gstNumber = gstNumberValue.trim().toUpperCase();
    if (gstTaxRateValue != null) {
      gstTaxRate = gstTaxRateValue.clamp(0, 100).toDouble();
    }
    adminPassword = adminPasswordValue;

    await prefs.setString(_hotelNameKey, hotelName);

    await prefs.setString(_hotelAddressKey, hotelAddress);

    await prefs.setString(_hotelMobileKey, hotelMobile);

    await prefs.setString(_registrationNumberKey, registrationNumber);

    await prefs.setString(_gstNumberKey, gstNumber);

    await prefs.setDouble(_gstTaxRateKey, gstTaxRate);

    await prefs.setString(_adminPasswordKey, adminPassword);
    await HotelCloudSyncService.instance.notifyLocalChanged();
  }

  static bool checkAdminPassword(String password) {
    return password == adminPassword;
  }

  static String gstRateLabel() {
    return gstTaxRate.toString().replaceFirst(RegExp(r'\.0$'), '');
  }

  static int taxOn(int amount) {
    if (amount <= 0 || gstTaxRate <= 0) {
      return 0;
    }
    return (amount * gstTaxRate / 100).round();
  }
}

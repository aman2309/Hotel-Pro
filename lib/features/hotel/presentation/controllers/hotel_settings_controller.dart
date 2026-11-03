import 'package:get/get.dart';

import '../../domain/entities/hotel_settings.dart';
import 'hotel_controller.dart';

class HotelSettingsController extends GetxController {
  static HotelSettingsController get instance {
    if (Get.isRegistered<HotelSettingsController>()) {
      return Get.find<HotelSettingsController>();
    }
    return Get.put(HotelSettingsController(), permanent: true);
  }

  final RxString hotelName = 'Hotel'.obs;
  final RxString hotelAddress = ''.obs;
  final RxString hotelMobile = ''.obs;
  final RxString registrationNumber = ''.obs;
  final RxString gstNumber = ''.obs;
  final RxDouble gstTaxRate = 5.0.obs;
  final RxString adminPassword = 'HOTEL2026'.obs;

  HotelSettingsData get value => HotelSettingsData(
    hotelName: hotelName.value,
    address: hotelAddress.value,
    mobile: hotelMobile.value,
    registrationNumber: registrationNumber.value,
    gstNumber: gstNumber.value,
    gstTaxRate: gstTaxRate.value,
    adminPassword: adminPassword.value,
  );

  void apply(HotelSettingsData settings) {
    hotelName.value = settings.hotelName;
    hotelAddress.value = settings.address;
    hotelMobile.value = settings.mobile;
    registrationNumber.value = settings.registrationNumber;
    gstNumber.value = settings.gstNumber;
    gstTaxRate.value = settings.gstTaxRate;
    adminPassword.value = settings.adminPassword;
  }

  Future<void> saveSettings({
    required String hotelNameValue,
    required String hotelAddressValue,
    required String hotelMobileValue,
    required String registrationNumberValue,
    required String gstNumberValue,
    double? gstTaxRateValue,
    required String adminPasswordValue,
  }) async {
    final HotelSettingsData next = HotelSettingsData(
      hotelName: hotelNameValue.trim().isEmpty
          ? 'Hotel'
          : hotelNameValue.trim(),
      address: hotelAddressValue.trim(),
      mobile: hotelMobileValue.trim(),
      registrationNumber: registrationNumberValue.trim(),
      gstNumber: gstNumberValue.trim().toUpperCase(),
      gstTaxRate: (gstTaxRateValue ?? gstTaxRate.value)
          .clamp(0, 100)
          .toDouble(),
      adminPassword: adminPasswordValue,
    );
    apply(next);
    await HotelController.instance.saveSettings(next);
  }

  Future<void> resetToDefaults() => saveSettings(
    hotelNameValue: 'Hotel',
    hotelAddressValue: '',
    hotelMobileValue: '',
    registrationNumberValue: '',
    gstNumberValue: '',
    gstTaxRateValue: 5,
    adminPasswordValue: 'HOTEL2026',
  );

  String displayPhoneFromLogin(String raw) {
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

  Future<void> applyLoginPhone(String? loginPhone) async {
    final String formatted = displayPhoneFromLogin(loginPhone ?? '');
    if (formatted.isEmpty) return;
    final String currentDigits = hotelMobile.value.replaceAll(
      RegExp(r'\D'),
      '',
    );
    final String nextDigits = formatted.replaceAll(RegExp(r'\D'), '');
    if (currentDigits.isNotEmpty && currentDigits == nextDigits) {
      return;
    }
    await saveSettings(
      hotelNameValue: hotelName.value,
      hotelAddressValue: hotelAddress.value,
      hotelMobileValue: formatted,
      registrationNumberValue: registrationNumber.value,
      gstNumberValue: gstNumber.value,
      gstTaxRateValue: gstTaxRate.value,
      adminPasswordValue: adminPassword.value,
    );
  }

  bool checkAdminPassword(String password) => password == adminPassword.value;

  String gstRateLabel() =>
      gstTaxRate.value.toString().replaceFirst(RegExp(r'\.0$'), '');

  int taxOn(int amount) {
    if (amount <= 0 || gstTaxRate.value <= 0) return 0;
    return (amount * gstTaxRate.value / 100).round();
  }
}

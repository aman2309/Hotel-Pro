/// Immutable hotel profile stored in Firestore at
/// `businesses/{businessId}/settings/hotel`.
class HotelSettingsData {
  const HotelSettingsData({
    this.hotelName = 'Hotel',
    this.address = '',
    this.mobile = '',
    this.registrationNumber = '',
    this.gstNumber = '',
    this.gstTaxRate = 5,
    this.adminPassword = 'HOTEL2026',
  });

  final String hotelName;
  final String address;
  final String mobile;
  final String registrationNumber;
  final String gstNumber;
  final double gstTaxRate;
  final String adminPassword;

  HotelSettingsData copyWith({
    String? hotelName,
    String? address,
    String? mobile,
    String? registrationNumber,
    String? gstNumber,
    double? gstTaxRate,
    String? adminPassword,
  }) {
    return HotelSettingsData(
      hotelName: hotelName ?? this.hotelName,
      address: address ?? this.address,
      mobile: mobile ?? this.mobile,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      gstNumber: gstNumber ?? this.gstNumber,
      gstTaxRate: gstTaxRate ?? this.gstTaxRate,
      adminPassword: adminPassword ?? this.adminPassword,
    );
  }

  factory HotelSettingsData.fromMap(Map<String, dynamic> map) {
    final dynamic rawRate = map['hotel_gst_tax_rate'];
    final double rate = rawRate is num
        ? rawRate.toDouble()
        : double.tryParse('${rawRate ?? ''}') ?? 5;
    return HotelSettingsData(
      hotelName: _text(map['hotel_name'], fallback: 'Hotel'),
      address: _text(map['hotel_address']),
      mobile: _text(map['hotel_mobile']),
      registrationNumber: _text(map['hotel_registration_number']),
      gstNumber: _text(map['hotel_gst_number']).toUpperCase(),
      gstTaxRate: rate.clamp(0, 100).toDouble(),
      adminPassword: _text(map['hotel_admin_password'], fallback: 'HOTEL2026'),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'hotel_name': hotelName.trim(),
      'hotel_address': address.trim(),
      'hotel_mobile': mobile.trim(),
      'hotel_registration_number': registrationNumber.trim(),
      'hotel_gst_number': gstNumber.trim().toUpperCase(),
      'hotel_gst_tax_rate': gstTaxRate,
      'hotel_admin_password': adminPassword,
    };
  }

  static String _text(dynamic value, {String fallback = ''}) {
    final String text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }
}

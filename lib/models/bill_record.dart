class BillRecord {
  String billNumber;
  String customerId;
  String guestName;
  String mobile;

  int roomNumber;
  String roomType;

  DateTime? bookingDate;
  DateTime? bookingTime;
  DateTime? checkoutTime;

  int roomRate;
  int bookedDays;
  int roomBill;

  List<Map<String, dynamic>> charges;
  List<Map<String, dynamic>> partPayments;
  int extraCharges;

  int totalBill;
  int discount;
  int advance;
  String advancePaymentMode;
  int balance;

  String paymentMode;
  bool applyGst;

  BillRecord({
    required this.billNumber,
    required this.customerId,
    required this.guestName,
    required this.mobile,
    required this.roomNumber,
    required this.roomType,
    required this.bookingDate,
    required this.bookingTime,
    required this.checkoutTime,
    required this.roomRate,
    required this.bookedDays,
    required this.roomBill,
    required this.charges,
    required this.partPayments,
    required this.extraCharges,
    required this.totalBill,
    required this.discount,
    required this.advance,
    required this.advancePaymentMode,
    required this.balance,
    required this.paymentMode,
    this.applyGst = false,
  });

  Map<String, dynamic> toJson() {
    return {
      "billNumber": billNumber,
      "customerId": customerId,
      "guestName": guestName,
      "mobile": mobile,
      "roomNumber": roomNumber,
      "roomType": roomType,
      "bookingDate": bookingDate?.toIso8601String(),
      "bookingTime": bookingTime?.toIso8601String(),
      "checkoutTime": checkoutTime?.toIso8601String(),
      "roomRate": roomRate,
      "bookedDays": bookedDays,
      "roomBill": roomBill,
      "charges": charges,
      "partPayments": partPayments,
      "extraCharges": extraCharges,
      "totalBill": totalBill,
      "discount": discount,
      "advance": advance,
      "advancePaymentMode": advancePaymentMode,
      "balance": balance,
      "paymentMode": paymentMode,
      "applyGst": applyGst,
    };
  }

  factory BillRecord.fromJson(Map<String, dynamic> json) {
    return BillRecord(
      billNumber: json["billNumber"]?.toString() ?? "",
      customerId: json["customerId"]?.toString() ?? "",
      guestName: json["guestName"]?.toString() ?? "",
      mobile: json["mobile"]?.toString() ?? "",
      roomNumber: json["roomNumber"] as int? ?? 0,
      roomType: json["roomType"]?.toString() ?? "",
      bookingDate: json["bookingDate"] == null
          ? null
          : DateTime.parse(json["bookingDate"] as String),
      bookingTime: json["bookingTime"] == null
          ? null
          : DateTime.parse(json["bookingTime"] as String),
      checkoutTime: json["checkoutTime"] == null ||
              json["checkoutTime"].toString().isEmpty
          ? null
          : DateTime.parse(json["checkoutTime"] as String),
      roomRate: json["roomRate"] as int? ?? 0,
      bookedDays: json["bookedDays"] as int? ?? 0,
      roomBill: json["roomBill"] as int? ?? 0,
      charges: (json["charges"] as List<dynamic>? ?? [])
          .map((charge) => Map<String, dynamic>.from(charge as Map))
          .toList(),
      partPayments: (json["partPayments"] as List<dynamic>? ?? [])
          .map((payment) => Map<String, dynamic>.from(payment as Map))
          .toList(),
      extraCharges: json["extraCharges"] as int? ?? 0,
      totalBill: json["totalBill"] as int? ?? 0,
      discount: json["discount"] as int? ?? 0,
      advance: json["advance"] as int? ?? 0,
      advancePaymentMode: json["advancePaymentMode"]?.toString() ?? "",
      balance: json["balance"] as int? ?? 0,
      paymentMode: json["paymentMode"]?.toString() ?? "",
      applyGst: json["applyGst"] as bool? ?? false,
    );
  }
}

class Room {
  int roomNumber;
  String? roomName;
  String roomType;
  int normalRent;
  String status;
  String faultReason;

  String mobile;
  String guestName;
  String idNumber;
  String guestAddress;

  int bookingRate;
  DateTime? bookingDate;
  DateTime? bookingTime;
  DateTime? bookingEndTime;
  DateTime? checkoutTime;
  int days;
  int advance;
  String paymentMode;
  String billNumber;
  bool applyGst;

  bool futureBooking;

  String futureMobile;
  String futureGuestName;
  String futureIdNumber;
  String futureGuestAddress;

  int futureBookingRate;
  DateTime? futureBookingDate;
  DateTime? futureBookingEnd;
  int futureDays;
  int futureAdvance;
  String futurePaymentMode;

  List<Map<String, dynamic>> charges;
  List<Map<String, dynamic>> partPayments;
  List<Map<String, dynamic>> extraGuests;
  List<Map<String, dynamic>> futureExtraGuests;

  Room({
    required this.roomNumber,
    this.roomName = "",
    required this.roomType,
    required this.normalRent,
    this.status = "EMPTY",
    this.faultReason = "",
    this.mobile = "",
    this.guestName = "",
    this.idNumber = "",
    this.guestAddress = "",
    int? bookingRate,
    this.bookingDate,
    this.bookingTime,
    this.bookingEndTime,
    this.checkoutTime,
    this.days = 0,
    this.advance = 0,
    this.paymentMode = "",
    this.billNumber = "",
    this.applyGst = false,
    this.futureBooking = false,
    this.futureMobile = "",
    this.futureGuestName = "",
    this.futureIdNumber = "",
    this.futureGuestAddress = "",
    int? futureBookingRate,
    this.futureBookingDate,
    this.futureBookingEnd,
    this.futureDays = 0,
    this.futureAdvance = 0,
    this.futurePaymentMode = "",
    List<Map<String, dynamic>>? charges,
    List<Map<String, dynamic>>? partPayments,
    List<Map<String, dynamic>>? extraGuests,
    List<Map<String, dynamic>>? futureExtraGuests,
  }) : bookingRate = bookingRate ?? normalRent,
       futureBookingRate = futureBookingRate ?? normalRent,
       charges = charges ?? [],
       partPayments = partPayments ?? [],
       extraGuests = extraGuests ?? [],
       futureExtraGuests = futureExtraGuests ?? [];

  /// Keep the same Room instance (dialogs hold this object) while refreshing
  /// fields from disk/cloud.
  void copyFrom(Room other) {
    roomNumber = other.roomNumber;
    roomName = other.safeRoomName;
    roomType = other.roomType;
    normalRent = other.normalRent;
    status = other.status;
    faultReason = other.faultReason;
    mobile = other.mobile;
    guestName = other.guestName;
    idNumber = other.idNumber;
    guestAddress = other.guestAddress;
    bookingRate = other.bookingRate;
    bookingDate = other.bookingDate;
    bookingTime = other.bookingTime;
    bookingEndTime = other.bookingEndTime;
    checkoutTime = other.checkoutTime;
    days = other.days;
    advance = other.advance;
    paymentMode = other.paymentMode;
    billNumber = other.billNumber;
    applyGst = other.applyGst;
    futureBooking = other.futureBooking;
    futureMobile = other.futureMobile;
    futureGuestName = other.futureGuestName;
    futureIdNumber = other.futureIdNumber;
    futureGuestAddress = other.futureGuestAddress;
    futureBookingRate = other.futureBookingRate;
    futureBookingDate = other.futureBookingDate;
    futureBookingEnd = other.futureBookingEnd;
    futureDays = other.futureDays;
    futureAdvance = other.futureAdvance;
    futurePaymentMode = other.futurePaymentMode;
    charges = other.charges;
    partPayments = other.partPayments;
    extraGuests = other.extraGuests;
    futureExtraGuests = other.futureExtraGuests;
  }

  /// Clear the current guest stay. Future booking is kept unless asked.
  void clearCurrentStay({bool alsoClearFuture = false}) {
    mobile = "";
    guestName = "";
    idNumber = "";
    guestAddress = "";
    bookingRate = normalRent;
    bookingDate = null;
    bookingTime = null;
    bookingEndTime = null;
    checkoutTime = null;
    days = 0;
    advance = 0;
    paymentMode = "";
    billNumber = "";
    applyGst = false;
    charges = [];
    partPayments = [];
    extraGuests = [];

    if (alsoClearFuture) {
      clearFutureBooking();
    }
  }

  void clearFutureBooking() {
    futureBooking = false;
    futureMobile = "";
    futureGuestName = "";
    futureIdNumber = "";
    futureGuestAddress = "";
    futureBookingRate = normalRent;
    futureBookingDate = null;
    futureBookingEnd = null;
    futureDays = 0;
    futureAdvance = 0;
    futurePaymentMode = "";
    futureExtraGuests = [];
  }

  Map<String, dynamic> toJson() {
    return {
      "roomNumber": roomNumber,
      "roomName": safeRoomName,
      "roomType": roomType,
      "normalRent": normalRent,
      "status": status,
      "faultReason": faultReason,
      "mobile": mobile,
      "guestName": guestName,
      "idNumber": idNumber,
      "guestAddress": guestAddress,
      "bookingRate": bookingRate,
      "bookingDate": bookingDate?.toIso8601String(),
      "bookingTime": bookingTime?.toIso8601String(),
      "bookingEndTime": bookingEndTime?.toIso8601String(),
      "checkoutTime": checkoutTime?.toIso8601String(),
      "days": days,
      "advance": advance,
      "paymentMode": paymentMode,
      "billNumber": billNumber,
      "applyGst": applyGst,
      "futureBooking": futureBooking,
      "futureMobile": futureMobile,
      "futureGuestName": futureGuestName,
      "futureIdNumber": futureIdNumber,
      "futureGuestAddress": futureGuestAddress,
      "futureBookingRate": futureBookingRate,
      "futureBookingDate": futureBookingDate?.toIso8601String(),
      "futureBookingEnd": futureBookingEnd?.toIso8601String(),
      "futureDays": futureDays,
      "futureAdvance": futureAdvance,
      "futurePaymentMode": futurePaymentMode,
      "charges": charges,
      "partPayments": partPayments,
      "extraGuests": extraGuests,
      "futureExtraGuests": futureExtraGuests,
    };
  }

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      roomNumber: json["roomNumber"] as int,
      roomName: json["roomName"]?.toString() ?? "",
      roomType: json["roomType"] as String,
      normalRent: json["normalRent"] as int,
      status: json["status"] as String? ?? "EMPTY",
      faultReason: json["faultReason"] as String? ?? "",
      mobile: json["mobile"] as String? ?? "",
      guestName: json["guestName"] as String? ?? "",
      idNumber: json["idNumber"] as String? ?? "",
      guestAddress: json["guestAddress"] as String? ?? "",
      bookingRate: json["bookingRate"] as int?,
      bookingDate: json["bookingDate"] == null
          ? null
          : DateTime.parse(json["bookingDate"] as String),
      bookingTime: json["bookingTime"] == null
          ? null
          : DateTime.parse(json["bookingTime"] as String),
      bookingEndTime: json["bookingEndTime"] == null
          ? null
          : DateTime.parse(json["bookingEndTime"] as String),
      checkoutTime: json["checkoutTime"] == null
          ? null
          : DateTime.parse(json["checkoutTime"] as String),
      days: json["days"] as int? ?? 0,
      advance: json["advance"] as int? ?? 0,
      paymentMode: json["paymentMode"] as String? ?? "",
      billNumber: json["billNumber"] as String? ?? "",
      applyGst: json["applyGst"] as bool? ?? false,
      futureBooking: json["futureBooking"] as bool? ?? false,
      futureMobile: json["futureMobile"] as String? ?? "",
      futureGuestName: json["futureGuestName"] as String? ?? "",
      futureIdNumber: json["futureIdNumber"] as String? ?? "",
      futureGuestAddress: json["futureGuestAddress"] as String? ?? "",
      futureBookingRate: json["futureBookingRate"] as int?,
      futureBookingDate: json["futureBookingDate"] == null
          ? null
          : DateTime.parse(json["futureBookingDate"] as String),
      futureBookingEnd: json["futureBookingEnd"] == null
          ? null
          : DateTime.parse(json["futureBookingEnd"] as String),
      futureDays: json["futureDays"] as int? ?? 0,
      futureAdvance: json["futureAdvance"] as int? ?? 0,
      futurePaymentMode: json["futurePaymentMode"] as String? ?? "",
      charges: (json["charges"] as List<dynamic>? ?? [])
          .map((charge) => Map<String, dynamic>.from(charge as Map))
          .toList(),
      partPayments: (json["partPayments"] as List<dynamic>? ?? [])
          .map((payment) => Map<String, dynamic>.from(payment as Map))
          .toList(),
      extraGuests: (json["extraGuests"] as List<dynamic>? ?? [])
          .map((guest) => Map<String, dynamic>.from(guest as Map))
          .toList(),
      futureExtraGuests: (json["futureExtraGuests"] as List<dynamic>? ?? [])
          .map((guest) => Map<String, dynamic>.from(guest as Map))
          .toList(),
    );
  }

  String get safeRoomName => roomName ?? "";

  String get label {
    final String name = safeRoomName.trim();
    if (name.isNotEmpty) {
      return name;
    }
    return roomNumber.toString();
  }

  String get cardTitle {
    final String name = safeRoomName.trim();
    if (name.isNotEmpty) {
      return name.toUpperCase();
    }
    return "ROOM $roomNumber";
  }

  /// Elapsed stay as days, hours, and minutes, for example `36 D 4 H 27 M`.
  String stayDurationLabel([DateTime? now]) {
    final DateTime? start = bookingTime;
    if (start == null) return "-";
    final Duration diff = (now ?? DateTime.now()).difference(start);
    if (diff.isNegative) return "0 D 0 H 0 M";
    final int days = diff.inDays;
    final int hours = diff.inHours % 24;
    final int minutes = diff.inMinutes % 60;
    return "$days D $hours H $minutes M";
  }

  static String extraChargeTitle(Map<String, dynamic> charge) {
    final String name = charge["name"]?.toString() ?? "-";
    final int rate = extraChargeInt(charge["rate"]);
    final int quantity = extraChargeInt(charge["quantity"]);
    if (rate > 0 && quantity > 0) {
      return "$name  (₹$rate × $quantity)";
    }
    return name;
  }

  static int extraChargeInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? "") ?? 0;
  }
}

class Customer {
  String customerId;
  String mobile;
  String guestName;
  String address;
  String idType;
  String idNumber;

  String idFrontPhotoPath;
  String idBackPhotoPath;

  List<Map<String, dynamic>> stayHistory;

  Customer({
    this.customerId = "",
    required this.mobile,
    required this.guestName,
    this.address = "",
    required this.idType,
    required this.idNumber,
    this.idFrontPhotoPath = "",
    this.idBackPhotoPath = "",
    List<Map<String, dynamic>>? stayHistory,
  }) : stayHistory = stayHistory ?? [];
}

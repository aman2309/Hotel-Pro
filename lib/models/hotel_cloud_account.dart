/// Authenticated Hotel Pro owner and their permanent business identity.
///
/// Phase 1 stores only this relationship in Firestore. Rooms, bookings,
/// bills, payments, future bookings, and settings stay local.
class HotelCloudAccount {
  const HotelCloudAccount({
    required this.ownerUid,
    required this.phoneNumber,
    required this.businessId,
    required this.businessName,
    this.role = 'owner',
  });

  final String ownerUid;
  final String phoneNumber;
  final String businessId;
  final String businessName;
  final String role;

  Map<String, dynamic> toUserMap({
    required Object createdAt,
    required Object updatedAt,
  }) {
    return <String, dynamic>{
      'phoneNumber': phoneNumber,
      'businessId': businessId,
      'role': role,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  Map<String, dynamic> toBusinessMap({
    required Object createdAt,
    required Object updatedAt,
  }) {
    return <String, dynamic>{
      'ownerUid': ownerUid,
      'businessName': businessName,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

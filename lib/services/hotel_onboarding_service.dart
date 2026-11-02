import 'package:cloud_functions/cloud_functions.dart';

import 'hotel_firestore_service.dart';

/// One-time server setup. A missing function must not empty an existing hotel.
class HotelOnboardingService {
  HotelOnboardingService._();
  static final HotelOnboardingService instance = HotelOnboardingService._();

  Future<void> provisionAfterLogin(String businessId) async {
    final bool createdHere =
        HotelFirestoreService.instance.wasBusinessCreatedThisSession(businessId);
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('provisionHotel')
          .call();
    } on FirebaseFunctionsException catch (error) {
      final bool unavailable =
          error.code == 'not-found' || error.code == 'unavailable' || error.code == 'unimplemented';
      if (createdHere || !unavailable) {
        throw StateError('New hotel setup needs review. Retry login.');
      }
    }
  }
}

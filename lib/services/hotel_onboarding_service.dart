import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'hotel_firestore_service.dart';

/// One-time server setup. A missing function must not empty an existing hotel.
class HotelOnboardingService {
  HotelOnboardingService._();
  static final HotelOnboardingService instance = HotelOnboardingService._();

  Future<void> provisionAfterLogin(String businessId) async {
    // The owner document read during login already told us onboarding is done.
    if (HotelFirestoreService.instance.onboardingCompleted(businessId)) return;
    // Completed owners do not need a callable/network setup step on every restart.
    final marker = await HotelFirestoreService.instance
        .col(businessId, 'settings')
        .doc('onboarding')
        .get(const GetOptions(source: Source.server));
    if (marker.data()?['status'] == 'complete') return;
    final bool createdHere = HotelFirestoreService.instance
        .wasBusinessCreatedThisSession(businessId);
    try {
      await FirebaseFunctions.instanceFor(
        region: 'asia-south1',
      ).httpsCallable('initializeEmptyHotel').call();
    } on FirebaseFunctionsException catch (error) {
      final bool unavailable =
          error.code == 'not-found' ||
          error.code == 'unavailable' ||
          error.code == 'unimplemented';
      if (createdHere || !unavailable) {
        throw StateError('New hotel setup needs review. Retry login.');
      }
    }
  }
}

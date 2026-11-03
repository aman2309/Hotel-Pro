// Historical cPanel compatibility configuration. The production app does not
// import this file; main.dart connects directly to Firebase.
enum HotelBackend { firebase, cpanel }

const HotelBackend kHotelBackend = HotelBackend.firebase;

const String kApiBaseUrl = String.fromEnvironment(
  'HOTEL_API_BASE',
  defaultValue: 'https://api.2ndhealing.com',
);

bool get hotelUsesCpanel => kHotelBackend == HotelBackend.cpanel;

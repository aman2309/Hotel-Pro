/// Switch the running backend without deleting the Firebase project.
/// Override with `--dart-define=HOTEL_API_BASE=https://api.2ndhealing.com`.
enum HotelBackend { firebase, cpanel }

const HotelBackend kHotelBackend = HotelBackend.cpanel;

const String kApiBaseUrl = String.fromEnvironment(
  'HOTEL_API_BASE',
  defaultValue: 'https://api.2ndhealing.com',
);

bool get hotelUsesCpanel => kHotelBackend == HotelBackend.cpanel;

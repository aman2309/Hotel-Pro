import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/services/cpanel_sync_payload.dart';

void main() {
  test('sync payload keeps the booking and drops ID photo bytes', () {
    final payload = syncPayloadForServer({
      'roomNumber': 102,
      'status': 'BOOKED',
      'guestName': 'Kept',
      'idFrontPhotoPath': 'A' * 240,
      'extraGuests': [
        {'name': 'Extra', 'idFrontPhoto': 'B' * 120, 'mobile': '9000000000'},
      ],
    });

    expect(payload['status'], 'BOOKED');
    expect(payload['guestName'], 'Kept');
    expect(payload.containsKey('idFrontPhotoPath'), isFalse);
    final extras = payload['extraGuests'] as List;
    expect((extras.first as Map).containsKey('idFrontPhoto'), isFalse);
    expect((extras.first as Map)['mobile'], '9000000000');
  });

  test('a short local path is not treated as a photo body', () {
    final payload = syncPayloadForServer({'idFrontPhotoPath': '/tmp/a.jpg'});
    expect(payload['idFrontPhotoPath'], '/tmp/a.jpg');
  });
}

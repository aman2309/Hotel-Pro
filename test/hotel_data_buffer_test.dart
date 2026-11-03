import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_first_app/services/hotel_data_buffer.dart';
import 'package:my_first_app/services/hotel_floor_service.dart';
import 'package:my_first_app/models/room.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    HotelDataBuffer.clearSession();
  });
  test(
    'cloud-only session ignores old device data and never persists edits',
    () async {
      SharedPreferences.setMockInitialValues({
        'hotel_name': 'Old device hotel',
      });
      final buffer = await HotelDataBuffer.getInstance();
      expect(buffer.getString('hotel_name'), isNull);
      await buffer.setString('hotel_name', 'Firebase hotel');
      expect(
        (await SharedPreferences.getInstance()).getString('hotel_name'),
        'Old device hotel',
      );
      HotelDataBuffer.clearSession();
      expect(buffer.getString('hotel_name'), isNull);
    },
  );
  test(
    'failed transaction can restore the last confirmed session state',
    () async {
      final buffer = await HotelDataBuffer.getInstance();
      await buffer.setString('rooms', 'confirmed');
      final checkpoint = HotelDataBuffer.checkpoint();
      await buffer.setString('rooms', 'unconfirmed');
      HotelDataBuffer.restoreCheckpoint(checkpoint);
      expect(buffer.getString('rooms'), 'confirmed');
    },
  );
  test('floor IDs are stable across devices and safely normalize names', () {
    expect(
      HotelFloorService.idForName(' Ground floor '),
      HotelFloorService.idForName('ground floor'),
    );
    expect(HotelFloorService.idForName('A/B'), isNot(contains('/')));
  });
  test('room floor survives cloud serialization and live refresh', () {
    final room = Room(
      roomNumber: 101,
      floorId: 'ground',
      roomType: 'Deluxe',
      normalRent: 1000,
    );
    final restored = Room.fromJson(room.toJson());
    expect(restored.floorId, 'ground');
    final current = Room(roomNumber: 101, roomType: 'Deluxe', normalRent: 1000);
    current.copyFrom(restored);
    expect(current.floorId, 'ground');
  });
}

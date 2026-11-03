import 'package:get/get.dart';

import '../../../../models/room.dart';
import 'hotel_controller.dart';

/// Live room list. Object identity is preserved by room number so open dialogs
/// keep pointing at the newest cloud values.
class RoomsController extends GetxController {
  static RoomsController get instance {
    if (Get.isRegistered<RoomsController>()) {
      return Get.find<RoomsController>();
    }
    return Get.put(RoomsController(), permanent: true);
  }

  final RxList<Room> rooms = <Room>[].obs;

  List<Room> get value => rooms;

  void apply(List<Room> incoming) {
    final Map<int, Room> existing = <int, Room>{
      for (final Room room in rooms) room.roomNumber: room,
    };
    final List<Room> next = <Room>[];
    for (final Room room in incoming) {
      final Room? current = existing[room.roomNumber];
      if (current == null) {
        next.add(room);
      } else {
        current.copyFrom(room);
        next.add(current);
      }
    }
    rooms.assignAll(next);
  }

  Room? byNumber(int roomNumber) {
    for (final Room room in rooms) {
      if (room.roomNumber == roomNumber) return room;
    }
    return null;
  }

  Future<void> saveAll(List<Room> value) =>
      HotelController.instance.saveRooms(value);

  Future<void> save(Room room) => HotelController.instance.saveRoom(room);

  Future<void> remove(int roomNumber) =>
      HotelController.instance.deleteRoom(roomNumber);
}

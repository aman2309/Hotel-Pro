import 'package:my_first_app/models/room.dart';
import 'package:my_first_app/models/customer.dart';
import 'package:my_first_app/models/bill_record.dart';
import '../entities/hotel_data.dart';
import '../entities/hotel_settings.dart';

/// Firestore is the single source of truth. There is deliberately no local
/// database in this contract: every write goes to the cloud and every screen
/// observes the live cloud snapshot.
abstract class HotelRepository {
  Stream<HotelData> watch(String businessId);

  Future<void> saveRoom(String businessId, Room room);

  Future<void> saveRooms(String businessId, List<Room> rooms);

  Future<void> deleteRoom(String businessId, int roomNumber);

  Future<void> saveCustomer(String businessId, Customer customer);

  Future<void> saveBill(String businessId, BillRecord bill);

  Future<void> saveExpenses(
    String businessId,
    List<Map<String, dynamic>> expenses,
  );

  Future<void> saveSettings(String businessId, HotelSettingsData settings);

  /// Used by file restore and other reviewed bulk imports.
  Future<void> replaceAll(String businessId, HotelData data);

  Future<void> dispose();
}

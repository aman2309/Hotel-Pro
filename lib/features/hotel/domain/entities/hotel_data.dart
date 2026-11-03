import 'package:my_first_app/models/bill_record.dart';
import 'package:my_first_app/models/customer.dart';
import 'package:my_first_app/models/room.dart';
import '../entities/hotel_settings.dart';

/// One consistent snapshot of a hotel, decoded from Firestore.
class HotelData {
  const HotelData({
    required this.rooms,
    required this.bills,
    required this.customers,
    required this.expenses,
    required this.settings,
  });

  final List<Room> rooms;
  final List<BillRecord> bills;
  final List<Customer> customers;
  final List<Map<String, dynamic>> expenses;
  final HotelSettingsData settings;

  static const HotelData empty = HotelData(
    rooms: <Room>[],
    bills: <BillRecord>[],
    customers: <Customer>[],
    expenses: <Map<String, dynamic>>[],
    settings: HotelSettingsData(),
  );

  bool get isEmpty =>
      rooms.isEmpty && bills.isEmpty && customers.isEmpty && expenses.isEmpty;
}

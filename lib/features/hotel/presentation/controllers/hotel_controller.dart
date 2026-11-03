import 'dart:async';
import 'package:get/get.dart';

import '../../../../models/bill_record.dart';
import '../../../../models/customer.dart';
import '../../../../models/room.dart';
import '../../data/firestore_hotel_repository.dart';
import '../../domain/entities/hotel_data.dart';
import '../../domain/entities/hotel_settings.dart';
import '../../domain/repositories/hotel_repository.dart';
import 'bills_controller.dart';
import 'customers_controller.dart';
import 'expenses_controller.dart';
import 'hotel_settings_controller.dart';
import 'rooms_controller.dart';

/// Owns the live Firestore snapshot for the signed-in hotel and fans it out to
/// the focused GetX controllers.
class HotelController extends GetxController {
  HotelController({HotelRepository? repository})
    : repository = repository ?? FirestoreHotelRepository();

  static final HotelController instance = HotelController();

  final HotelRepository repository;

  final Rx<HotelData> data = HotelData.empty.obs;
  final RxString businessId = ''.obs;
  final RxBool ready = false.obs;
  final RxBool loading = false.obs;
  final RxnString error = RxnString();

  StreamSubscription<HotelData>? _subscription;
  String? _activeBusinessId;

  bool get hasData => ready.value;

  RoomsController get rooms => RoomsController.instance;
  CustomersController get customers => CustomersController.instance;
  BillsController get bills => BillsController.instance;
  ExpensesController get expenses => ExpensesController.instance;
  HotelSettingsController get settings => HotelSettingsController.instance;

  Future<void> start(String id) async {
    final String next = id.trim();
    if (next.isEmpty) {
      error.value = 'Hotel identity is missing.';
      return;
    }
    if (_activeBusinessId == next && _subscription != null) {
      return;
    }
    await _stopStream();
    _activeBusinessId = next;
    businessId.value = next;
    ready.value = false;
    loading.value = true;
    error.value = null;

    _subscription = repository
        .watch(next)
        .listen(
          _onSnapshot,
          onError: (Object failure, StackTrace stack) {
            loading.value = false;
            error.value = _humanize(failure);
          },
        );
  }

  Future<void> stop() async {
    await _stopStream();
    _activeBusinessId = null;
    businessId.value = '';
    ready.value = false;
    data.value = HotelData.empty;
    await repository.dispose();
    loading.value = false;
    error.value = null;
    rooms.apply(const []);
    customers.apply(const []);
    bills.apply(const []);
    expenses.apply(const []);
    settings.apply(const HotelSettingsData());
  }

  Future<void> _stopStream() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _onSnapshot(HotelData snapshot) {
    data.value = snapshot;
    loading.value = false;
    error.value = null;

    rooms.apply(snapshot.rooms);
    customers.apply(snapshot.customers);
    bills.apply(snapshot.bills);
    expenses.apply(snapshot.expenses);
    settings.apply(snapshot.settings);
    if (!ready.value) ready.value = true;
  }

  Future<void> saveRooms(List<Room> rooms) async {
    await _guard(() => repository.saveRooms(businessId.value, rooms));
  }

  Future<void> saveRoom(Room room) async {
    await _guard(() => repository.saveRoom(businessId.value, room));
  }

  Future<void> deleteRoom(int roomNumber) async {
    await _guard(() => repository.deleteRoom(businessId.value, roomNumber));
  }

  Future<void> saveBill(BillRecord bill) async {
    await _guard(() => repository.saveBill(businessId.value, bill));
  }

  Future<void> saveCustomer(Customer customer) async {
    await _guard(() => repository.saveCustomer(businessId.value, customer));
  }

  Future<void> saveExpenses(List<Map<String, dynamic>> expenses) async {
    await _guard(() => repository.saveExpenses(businessId.value, expenses));
  }

  Future<void> saveSettings(HotelSettingsData value) async {
    await _guard(() => repository.saveSettings(businessId.value, value));
  }

  Future<void> replaceAll(HotelData snapshot) async {
    await _guard(() => repository.replaceAll(businessId.value, snapshot));
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (businessId.value.isEmpty) {
      error.value = 'Hotel identity is missing. Please sign in again.';
      throw StateError(error.value!);
    }
    try {
      await action();
      error.value = null;
    } catch (failure) {
      error.value = _humanize(failure);
      rethrow;
    }
  }

  String _humanize(Object failure) {
    final String text = failure.toString();
    if (text.contains('permission-denied')) {
      return 'Firestore permission denied. Check the hotel license.';
    }
    if (text.contains('unavailable') || text.contains('network')) {
      return 'Could not save to Firebase. Check your connection and try again.';
    }
    if (text.contains('unauthenticated')) {
      return 'Please sign in again to reach hotel cloud data.';
    }
    return text.replaceFirst('Exception: ', '');
  }

  @override
  void onClose() {
    unawaited(_stopStream());
    super.onClose();
  }
}

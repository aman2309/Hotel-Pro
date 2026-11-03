import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:my_first_app/features/hotel/data/firestore_hotel_repository.dart';
import 'package:my_first_app/features/hotel/domain/entities/hotel_data.dart';
import 'package:my_first_app/features/hotel/domain/entities/hotel_settings.dart';
import 'package:my_first_app/features/hotel/domain/repositories/hotel_repository.dart';
import 'package:my_first_app/features/hotel/presentation/controllers/hotel_controller.dart';
import 'package:my_first_app/models/room.dart';
import 'package:my_first_app/models/customer.dart';
import 'package:my_first_app/models/bill_record.dart';
import 'package:my_first_app/services/hotel_sync_plan.dart';

class _HotelRepository implements HotelRepository {
  final snapshots = StreamController<HotelData>.broadcast();
  int saves = 0;
  bool disposed = false;
  @override
  Stream<HotelData> watch(String id) => snapshots.stream;
  @override
  Future<void> saveRoom(String id, Room room) async {
    saves++;
  }

  @override
  Future<void> saveRooms(String id, List<Room> rooms) async {
    saves++;
  }

  @override
  Future<void> deleteRoom(String id, int room) async {
    saves++;
  }

  @override
  Future<void> saveCustomer(String id, Customer guest) async {
    saves++;
  }

  @override
  Future<void> saveBill(String id, BillRecord bill) async {
    saves++;
  }

  @override
  Future<void> saveExpenses(
    String id,
    List<Map<String, dynamic>> expenses,
  ) async {
    saves++;
  }

  @override
  Future<void> saveSettings(String id, HotelSettingsData settings) async {
    saves++;
  }

  @override
  Future<void> replaceAll(String id, HotelData data) async {
    saves++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.testMode = true;
  });
  tearDown(() async {
    Get.reset();
  });
  test(
    'client never seeds rooms locally; Firebase server owns initial room creation',
    () async {
      final repository = _HotelRepository();
      final controller = HotelController(repository: repository);
      await controller.start('hotel-a');
      repository.snapshots.add(HotelData.empty);
      await Future<void>.delayed(Duration.zero);
      expect(controller.ready.value, isTrue);
      expect(controller.rooms.value, isEmpty);
      expect(repository.saves, 0);
      await controller.stop();
      expect(repository.disposed, isTrue);
      expect(controller.businessId.value, isEmpty);
      await repository.snapshots.close();
    },
  );
  test(
    'an identity edit preserves a newer photo uploaded by another device',
    () {
      final merged = mergeRepositoryGuestPhotos(
        {
          'guestName': 'Updated',
          'idFrontStoragePath': 'old',
          'hasFrontPhoto': true,
        },
        {'guestName': 'Before', 'idFrontStoragePath': 'old'},
        {
          'guestName': 'Before',
          'idFrontStoragePath': 'newer',
          'hasFrontPhoto': true,
        },
      );
      expect(merged['guestName'], 'Updated');
      expect(merged['idFrontStoragePath'], 'newer');
    },
  );
  test('two independent photo replacements surface a conflict', () {
    expect(
      () => mergeRepositoryGuestPhotos(
        {'idFrontStoragePath': 'ours'},
        {'idFrontStoragePath': 'before'},
        {'idFrontStoragePath': 'theirs'},
      ),
      throwsA(isA<HotelSyncConflict>()),
    );
  });
  test('retrying the same photo replacement remains idempotent', () {
    final merged = mergeRepositoryGuestPhotos(
      {'idFrontStoragePath': 'ours'},
      {'idFrontStoragePath': 'before'},
      {'idFrontStoragePath': 'ours'},
    );
    expect(merged['idFrontStoragePath'], 'ours');
  });
}

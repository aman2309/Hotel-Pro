import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_first_app/services/hotel_sync_plan.dart';
import 'package:my_first_app/services/hotel_data_buffer.dart';
import 'package:my_first_app/services/hotel_record_ids.dart';
import 'package:my_first_app/services/hotel_photo_ref.dart';
import 'package:my_first_app/services/cloud_sync_service.dart';
import 'package:my_first_app/stores/bill_store.dart';
import 'package:my_first_app/stores/customer_store.dart';
import 'package:my_first_app/models/customer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    HotelDataBuffer.clearSession();
    SharedPreferences.setMockInitialValues({});
    CustomerStore.customers.clear();
    BillStore.bills.clear();
  });
  test('returning UID reuses legacy business id', () {
    expect(
      resolveHotelMapping(
        uid: 'A',
        userBusinessId: 'old-random-id',
        phoneBusinessId: 'old-random-id',
        phoneOwnerUid: 'A',
      ),
      'old-random-id',
    );
    expect(
      resolveHotelMapping(uid: 'A', legacyOwnedBusinesses: ['old-id']),
      'old-id',
    );
  });
  test(
    'a denied business list still opens the first hotel for a new number',
    () {
      expect(
        firstHotelForSignedInNumber(
          userDocumentExists: false,
          phoneIndexExists: false,
        ),
        isTrue,
      );
      expect(
        firstHotelForSignedInNumber(
          userDocumentExists: true,
          phoneIndexExists: false,
        ),
        isFalse,
      );
      expect(
        legacyHotelAfterList(uid: 'new-user', listPermissionDenied: true),
        isNull,
      );
      expect(
        legacyHotelAfterList(
          uid: 'A',
          listPermissionDenied: false,
          legacyOwnedBusinesses: ['old-id'],
        ),
        'old-id',
      );
    },
  );
  test('foreign, contradictory, multiple mappings require review', () {
    expect(
      () => resolveHotelMapping(
        uid: 'B',
        phoneBusinessId: 'hotel-A',
        phoneOwnerUid: 'A',
      ),
      throwsStateError,
    );
    expect(
      () => resolveHotelMapping(
        uid: 'A',
        userBusinessId: 'x',
        phoneBusinessId: 'y',
        phoneOwnerUid: 'A',
      ),
      throwsStateError,
    );
    expect(
      () => resolveHotelMapping(uid: 'A', legacyOwnedBusinesses: ['x', 'y']),
      throwsStateError,
    );
  });
  test('empty first local state never tombstones unknown cloud records', () {
    final plan = planHotelChanges(
      local: {},
      baseline: {},
      remoteBaseline: {'rooms/room_101': 'cloud'},
    );
    expect(plan, isEmpty);
  });
  test('stale unchanged room is not uploaded when another room changes', () {
    final room = {'status': 'EMPTY', 'deleted': false};
    final baseline = {
      'rooms/room_101': hotelRecordFingerprint(room),
      'rooms/room_102': hotelRecordFingerprint(room),
    };
    final plan = planHotelChanges(
      local: {
        'rooms/room_101': room,
        'rooms/room_102': {'status': 'BOOKED', 'deleted': false},
      },
      baseline: baseline,
      remoteBaseline: baseline,
    );
    expect(plan.map((c) => c.path), ['rooms/room_102']);
    expect(hotelChangeCanCommit(plan.single, room), isTrue);
  });
  test(
    'concurrent booking/payment refuses different winner but accepts uncertain acknowledgement retry',
    () {
      final before = {'status': 'EMPTY'};
      final change = HotelSyncChange(
        'rooms/room_101',
        hotelRecordFingerprint(before),
        {'status': 'BOOKED', 'guestName': 'A'},
      );
      expect(
        hotelChangeCanCommit(change, {'status': 'BOOKED', 'guestName': 'B'}),
        isFalse,
      );
      expect(hotelChangeCanCommit(change, change.data), isTrue);
      expect(hotelChangeCanCommit(change, before), isTrue);
    },
  );
  test(
    'retry preserves unrecognized legacy fields after an acknowledged merge',
    () {
      final change = HotelSyncChange('rooms/room_101', 'before', {
        'status': 'BOOKED',
        'guestName': 'A',
      });
      expect(
        hotelChangeCanCommit(change, {
          'status': 'BOOKED',
          'guestName': 'A',
          'legacyNote': 'Keep me',
        }),
        isTrue,
      );
      expect(
        hotelChangeCanCommit(change, {
          'status': 'BOOKED',
          'guestName': 'B',
          'legacyNote': 'Keep me',
        }),
        isFalse,
      );
    },
  );
  test('financial history is never erased by missing local records', () {
    final plan = planHotelChanges(
      local: {},
      baseline: {
        'bills/old': 'x',
        'payments/old': 'x',
        'guests/old': 'x',
        'expenses/old': 'x',
      },
      remoteBaseline: {},
    );
    expect(plan, isEmpty);
  });
  test('explicit room removal produces retry-safe soft delete', () {
    final plan = planHotelChanges(
      local: {},
      baseline: {'rooms/room_101': 'old'},
      remoteBaseline: {'rooms/room_101': 'old'},
    );
    expect(plan.single.data, {'deleted': true});
    expect(
      hotelChangeCanCommit(plan.single, {'status': 'EMPTY', 'deleted': true}),
      isTrue,
    );
  });
  test(
    'offline operation survives disk roundtrip with original expected version',
    () async {
      final operation = HotelSyncChange('rooms/room_101', 'original-version', {
        'status': 'BOOKED',
        'guestName': 'A',
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'hotel_sync_v3_A_hotelA',
        jsonEncode(operation.toJson()),
      );
      final restored = HotelSyncChange.fromJson(
        jsonDecode(
          (await SharedPreferences.getInstance()).getString(
            'hotel_sync_v3_A_hotelA',
          )!,
        ),
      );
      expect(restored.expected, 'original-version');
      expect(
        (await SharedPreferences.getInstance()).getString(
          'hotel_sync_v3_B_hotelB',
        ),
        isNull,
      );
      expect(
        hotelChangeCanCommit(restored, {
          'status': 'BOOKED',
          'guestName': 'other',
        }),
        isFalse,
      );
    },
  );
  test(
    'photo uploads and clock skew do not change business conflict version',
    () {
      expect(
        hotelRecordFingerprint({
          'guestName': 'A',
          'updatedAtMs': 100,
          'idFrontStoragePath': 'one',
        }),
        hotelRecordFingerprint({
          'guestName': 'A',
          'updatedAtMs': 999,
          'idFrontStoragePath': 'two',
        }),
      );
    },
  );
  test('new bill numbers are unique across two offline devices', () {
    final ids = List.generate(500, (_) => BillStore.nextBillNumber());
    expect(ids.toSet().length, 500);
  });
  test(
    'new guest gets same stable ID on independent devices, legacy IDs remain intact',
    () async {
      Customer make() => Customer(
        mobile: '9999999999',
        guestName: 'A',
        idType: 'ID',
        idNumber: '123',
      );
      final a = make();
      await CustomerStore.saveCustomer(a);
      CustomerStore.customers.clear();
      final b = make();
      await CustomerStore.saveCustomer(b);
      expect(a.customerId, b.customerId);
      CustomerStore.customers.clear();
      final legacy = make()..customerId = 'CUST-0012';
      await CustomerStore.saveCustomer(legacy);
      await CustomerStore.saveCustomer(make());
      expect(CustomerStore.customers.single.customerId, 'CUST-0012');
    },
  );
  test(
    'content-versioned photo paths preserve guest and additional metadata keys',
    () {
      final path = HotelPhotoPaths.versioned(
        HotelPhotoPaths.front('biz', 'guest'),
        'a' * 64,
      );
      expect(HotelPhotoPaths.metaKeyFromStoragePath(path), 'guest:front');
      final extra = HotelPhotoPaths.versioned(
        HotelPhotoPaths.additionalBack('biz', 'guest', 'other'),
        'b' * 64,
      );
      expect(
        HotelPhotoPaths.metaKeyFromStoragePath(extra),
        'guest:additional:other:back',
      );
      expect(
        path,
        isNot(
          HotelPhotoPaths.versioned(
            HotelPhotoPaths.front('biz', 'guest'),
            'c' * 64,
          ),
        ),
      );
    },
  );
  test(
    'legacy PHP live writer is disabled even if old preferences enable it',
    () async {
      SharedPreferences.setMockInitialValues({
        'cloud_sync_enabled': true,
        'hp1_store_id': 'a' * 64,
      });
      expect(await CloudSyncService.isEnabled(), isFalse);
      expect(await CloudSyncService.syncIfEnabled(force: true), isNull);
    },
  );
  test('stay identity survives room change and checkout', () {
    final time = DateTime(2026, 10, 1, 10);
    expect(
      HotelRecordIds.stay('9999999999', time, time),
      HotelRecordIds.stay('9999999999', time, time),
    );
    expect(
      HotelRecordIds.stay('9999999999', time, time),
      isNot(
        HotelRecordIds.stay(
          '9999999999',
          time.add(const Duration(days: 1)),
          time,
        ),
      ),
    );
  });
}

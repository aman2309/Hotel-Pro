import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/models/bill_record.dart';
import 'package:my_first_app/models/customer.dart';
import 'package:my_first_app/models/room.dart';
import 'package:my_first_app/services/hotel_cloud_codec.dart';
import 'package:my_first_app/services/hotel_cloud_policy.dart';
import 'package:my_first_app/services/hotel_photo_ref.dart';
import 'package:my_first_app/services/phone_auth_service.dart';
import 'package:my_first_app/stores/hotel_settings_store.dart';

void main() {
  const HotelCloudPolicy policy = HotelCloudPolicy();

  test('A existing local data with empty cloud migrates', () {
    expect(
      policy.decide(
        localHasData: true,
        cloudHasData: false,
        localMigrationCompleted: false,
      ),
      HotelCloudBootstrapAction.migrate,
    );
  });

  test('B same phone reopen does not migrate again', () {
    expect(
      policy.decide(
        localHasData: true,
        cloudHasData: true,
        localMigrationCompleted: true,
      ),
      HotelCloudBootstrapAction.incrementalSync,
    );
  });

  test('C fresh phone with cloud data restores', () {
    expect(
      policy.decide(
        localHasData: false,
        cloudHasData: true,
        localMigrationCompleted: false,
      ),
      HotelCloudBootstrapAction.restore,
    );
  });

  test('fresh default empty rooms are not hotel data', () {
    expect(
      policy.localHasHotelData(
        roomsMissingOrEmpty: false,
        roomCount: 12,
        billCount: 0,
        guestCount: 0,
        expenseCount: 0,
        anyOccupiedOrClosedRoom: false,
        looksLikeFreshDefault: true,
      ),
      isFalse,
    );
    expect(
      policy.decide(
        localHasData: false,
        cloudHasData: true,
        localMigrationCompleted: false,
      ),
      HotelCloudBootstrapAction.restore,
    );
    expect(
      policy.allowPushToCloud(
        cloudHasData: true,
        localHasData: false,
        restoreFailed: false,
      ),
      isFalse,
    );
  });

  test('occupied rooms remain local hotel data', () {
    expect(
      policy.localHasHotelData(
        roomsMissingOrEmpty: false,
        roomCount: 12,
        billCount: 0,
        guestCount: 1,
        expenseCount: 0,
        anyOccupiedOrClosedRoom: true,
        looksLikeFreshDefault: false,
      ),
      isTrue,
    );
  });

  test('J empty local never overwrites populated cloud', () {
    expect(
      policy.allowPushToCloud(
        cloudHasData: true,
        localHasData: false,
        restoreFailed: true,
      ),
      isFalse,
    );
  });

  test('conflict keeps newer cloud record', () {
    expect(
      policy.localWinsConflict(
        localUpdatedAtMs: 100,
        cloudUpdatedAtMs: 200,
      ),
      isFalse,
    );
    expect(
      policy.localWinsConflict(
        localUpdatedAtMs: 300,
        cloudUpdatedAtMs: 200,
      ),
      isTrue,
    );
  });

  test('D room uses stable id and survives rebuild', () {
    final Room room = Room(
      roomNumber: 201,
      roomType: 'Deluxe',
      normalRent: 1500,
      status: 'EMPTY',
    );
    final HotelCloudCodec codec = HotelCloudCodec(deviceId: 'devA', updatedAtMs: 1);
    final HotelCloudSnapshot first = codec.build(
      rooms: <Room>[room],
      bills: const <BillRecord>[],
      guests: const <Customer>[],
      expenses: const <Map<String, dynamic>>[],
      settings: <String, dynamic>{'hotel_name': 'Park'},
    );
    final HotelCloudSnapshot second = codec.build(
      rooms: <Room>[room],
      bills: const <BillRecord>[],
      guests: const <Customer>[],
      expenses: const <Map<String, dynamic>>[],
      settings: <String, dynamic>{'hotel_name': 'Park'},
    );
    expect(HotelCloudCodec.roomId(201), 'room_201');
    expect(first.idsByCollection['rooms'], second.idsByCollection['rooms']);
  });

  test('E booking billing part payment checkout keep related ids', () {
    final Room booked = Room(
      roomNumber: 101,
      roomType: 'Deluxe',
      normalRent: 1500,
      status: 'BOOKED',
      guestName: 'Rahul',
      mobile: '9999999999',
      days: 2,
      bookingRate: 1500,
      advance: 500,
      paymentMode: 'UPI',
      partPayments: <Map<String, dynamic>>[
        <String, dynamic>{
          'amount': 200,
          'paymentMode': 'Cash',
          'dateTime': '2026-09-17T10:00:00.000',
        },
      ],
    );
    final BillRecord bill = BillRecord(
      billNumber: 'BILL-000001',
      customerId: 'CUST-0001',
      guestName: 'Rahul',
      mobile: '9999999999',
      roomNumber: 101,
      roomType: 'Deluxe',
      bookingDate: DateTime(2026, 9, 17),
      bookingTime: DateTime(2026, 9, 17, 10),
      checkoutTime: DateTime(2026, 9, 18, 10),
      roomRate: 1500,
      bookedDays: 2,
      roomBill: 3000,
      charges: const <Map<String, dynamic>>[],
      partPayments: <Map<String, dynamic>>[
        <String, dynamic>{
          'amount': 200,
          'paymentMode': 'Cash',
          'dateTime': '2026-09-17T10:00:00.000',
        },
      ],
      extraCharges: 0,
      totalBill: 3000,
      discount: 0,
      advance: 500,
      advancePaymentMode: 'UPI',
      balance: 2300,
      paymentMode: 'UPI',
    );
    final HotelCloudSnapshot snap = HotelCloudCodec(deviceId: 'devA', updatedAtMs: 5)
        .build(
      rooms: <Room>[booked],
      bills: <BillRecord>[bill],
      guests: <Customer>[
        Customer(
          customerId: 'CUST-0001',
          mobile: '9999999999',
          guestName: 'Rahul',
          idType: 'Aadhaar',
          idNumber: '1234',
        ),
      ],
      expenses: const <Map<String, dynamic>>[],
      settings: <String, dynamic>{'hotel_name': 'Park'},
    );
    expect(snap.idsByCollection['bookings'], contains('bkg_room_101'));
    expect(snap.idsByCollection['bookings'], contains('bkg_BILL-000001'));
    expect(snap.idsByCollection['bills'], contains('BILL-000001'));
    expect(snap.idsByCollection['guests'], contains('CUST-0001'));
    expect(snap.idsByCollection['payments']!.isNotEmpty, isTrue);
  });

  test('F G H closed cleaning future booking survive snapshot', () {
    final Room closed = Room(
      roomNumber: 102,
      roomType: 'Luxury',
      normalRent: 2000,
      status: 'CLOSED',
      faultReason: 'AC',
    );
    final Room cleaning = Room(
      roomNumber: 103,
      roomType: 'Deluxe',
      normalRent: 1500,
      status: 'CLEANING',
    );
    final Room future = Room(
      roomNumber: 104,
      roomType: 'Luxury',
      normalRent: 2000,
      futureBooking: true,
      futureGuestName: 'Amit',
      futureMobile: '8888888888',
      futureDays: 1,
      futureBookingDate: DateTime(2026, 10, 1),
    );
    final HotelCloudSnapshot snap = HotelCloudCodec(deviceId: 'devA', updatedAtMs: 9)
        .build(
      rooms: <Room>[closed, cleaning, future],
      bills: const <BillRecord>[],
      guests: const <Customer>[],
      expenses: const <Map<String, dynamic>>[],
      settings: <String, dynamic>{'hotel_name': 'Park'},
    );
    expect(snap.idsByCollection['closedRooms'], contains('closed_102'));
    expect(
      snap.docs.firstWhere((HotelCloudDoc doc) => doc.id == 'room_103').data['status'],
      'CLEANING',
    );
    expect(snap.idsByCollection['futureBookings'], contains('fb_room_104'));
  });

  test('I later local updatedAt wins after offline edit', () {
    expect(
      policy.localWinsConflict(localUpdatedAtMs: 50, cloudUpdatedAtMs: 10),
      isTrue,
    );
  });

  test('ID photos are metadata only never base64 in cloud docs', () {
    const String fakePhoto =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==AAAAEXTRA';
    expect(HotelPhotoRef.looksLikePhotoBytes(fakePhoto), isTrue);
    final Customer guest = Customer(
      customerId: 'CUST-0002',
      mobile: '7777777777',
      guestName: 'Neha',
      idType: 'Aadhaar',
      idNumber: '9999',
      idFrontPhotoPath: fakePhoto,
      idBackPhotoPath: fakePhoto,
    );
    final HotelCloudCodec codec = HotelCloudCodec(deviceId: 'devA', updatedAtMs: 11);
    final HotelCloudSnapshot snap = codec.build(
      rooms: const <Room>[],
      bills: const <BillRecord>[],
      guests: <Customer>[guest],
      expenses: const <Map<String, dynamic>>[],
      settings: <String, dynamic>{'hotel_name': 'Park'},
    );
    final HotelCloudDoc guestDoc = snap.docs.firstWhere(
      (HotelCloudDoc doc) => doc.collection == 'guests',
    );
    expect(codec.mapContainsPhotoBytes(guestDoc.data), isFalse);
    expect(guestDoc.data['idFrontPhotoPath'], isA<Map>());
    expect(guestDoc.data['idFrontPhotoPath']['hasPhoto'], isTrue);
  });

  test('expenses use stable ids from existing fields', () {
    final Map<String, dynamic> expense = <String, dynamic>{
      'dateTime': '2026-09-17T09:00:00.000',
      'category': 'Cleaning',
      'description': 'Soap',
      'amount': 80,
      'paymentMode': 'Cash',
    };
    expect(HotelCloudCodec.expenseId(expense), contains('exp_'));
    expect(
      HotelCloudCodec.expenseId(expense),
      HotelCloudCodec.expenseId(expense),
    );
  });

  test('room json num fields still produce a valid room_{id} document', () {
    final List<Room> rooms = HotelCloudCodec.decodeRoomList(
      <dynamic>[
        <String, dynamic>{
          'roomNumber': 205.0,
          'roomName': 'Oak',
          'roomType': 'Deluxe',
          'normalRent': 1800.0,
          'status': 'EMPTY',
        },
        <String, dynamic>{'bad': true},
      ],
    );
    expect(rooms.length, 1);
    expect(HotelCloudCodec.roomId(rooms.first.roomNumber), 'room_205');
    final HotelCloudSnapshot snap = HotelCloudCodec(deviceId: 'devA', updatedAtMs: 1)
        .build(
      rooms: rooms,
      bills: const <BillRecord>[],
      guests: const <Customer>[],
      expenses: const <Map<String, dynamic>>[],
      settings: <String, dynamic>{'hotel_name': 'Park'},
    );
    expect(snap.idsByCollection['rooms'], contains('room_205'));
    final Map<String, dynamic> safe = HotelCloudCodec.firestoreSafeMap(
      snap.docs.firstWhere((HotelCloudDoc doc) => doc.id == 'room_205').data,
    );
    expect(safe['roomNumber'], 205);
    expect(safe['deleted'], isFalse);
  });

  test('cloud restore guests keep empty photo strings for Storage fill', () {
    final HotelCloudCodec codec = HotelCloudCodec(deviceId: 'devA', updatedAtMs: 1);
    final List<Customer> guests = codec.guestsFromCloud(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'customerId': 'CUST-0001',
          'mobile': '9999999999',
          'guestName': 'Rahul',
          'idType': 'Aadhaar',
          'idNumber': '1234',
          'hasFrontPhoto': true,
          'idFrontStoragePath':
              'businesses/biz_x/guests/CUST-0001/id_front.jpg',
          'idFrontPhotoPath': <String, dynamic>{
            'hasPhoto': true,
            'storageEnabled': true,
            'storagePath': 'businesses/biz_x/guests/CUST-0001/id_front.jpg',
          },
          'idBackPhotoPath': <String, dynamic>{
            'hasPhoto': true,
            'storageEnabled': true,
          },
        },
      ],
    );
    expect(guests, hasLength(1));
    expect(guests.first.idFrontPhotoPath, isEmpty);
    expect(guests.first.idBackPhotoPath, isEmpty);
    expect(HotelCloudCodec.localPhotoString('not-a-path'), isEmpty);
  });

  test('cloud restore merges live booking and future booking onto rooms', () {
    final HotelCloudCodec codec = HotelCloudCodec(deviceId: 'devA', updatedAtMs: 1);
    final List<Room> rooms = codec.roomsFromCloud(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'roomNumber': 101,
          'roomType': 'Deluxe',
          'normalRent': 1500,
          'status': 'EMPTY',
        },
        <String, dynamic>{
          'roomNumber': 104,
          'roomType': 'Luxury',
          'normalRent': 2000,
          'status': 'EMPTY',
        },
      ],
    );
    codec.mergeRelatedIntoRooms(
      rooms: rooms,
      bookings: <Map<String, dynamic>>[
        <String, dynamic>{
          'bookingId': 'bkg_room_101',
          'roomNumber': 101,
          'guestName': 'Rahul',
          'mobile': '9999999999',
          'status': 'BOOKED',
          'days': 2,
          'roomRate': 1500,
          'advance': 500,
          'partPayments': <Map<String, dynamic>>[
            <String, dynamic>{'amount': 200, 'paymentMode': 'Cash'},
          ],
          'extraGuests': <Map<String, dynamic>>[
            <String, dynamic>{
              'guestName': 'Neha',
              'mobile': '8888888888',
              'idFrontPhoto': <String, dynamic>{
                'hasPhoto': true,
                'storageEnabled': true,
              },
            },
          ],
        },
        <String, dynamic>{
          'bookingId': 'bkg_BILL-000001',
          'roomNumber': 104,
          'guestName': 'Old',
          'status': 'CHECKED_OUT',
        },
      ],
      futureBookings: <Map<String, dynamic>>[
        <String, dynamic>{
          'bookingId': 'fb_room_104',
          'roomNumber': 104,
          'guestName': 'Amit',
          'mobile': '8888888888',
          'futureBooking': true,
          'days': 1,
          'roomRate': 2000,
        },
      ],
      closedRooms: const <Map<String, dynamic>>[],
    );
    final Room booked = rooms.firstWhere((Room room) => room.roomNumber == 101);
    final Room future = rooms.firstWhere((Room room) => room.roomNumber == 104);
    expect(booked.status, 'BOOKED');
    expect(booked.guestName, 'Rahul');
    expect(booked.partPayments, isNotEmpty);
    expect(booked.extraGuests, isNotEmpty);
    expect(booked.extraGuests.first['idFrontPhoto'], isEmpty);
    expect(future.status, 'EMPTY');
    expect(future.futureBooking, isTrue);
    expect(future.futureGuestName, 'Amit');
  });

  test('empty local photos do not clobber existing cloud photo metadata', () {
    final Map<String, dynamic> merged = HotelCloudCodec.mergeGuestPhotoMetadata(
      local: <String, dynamic>{
        'customerId': 'CUST-0001',
        'hasFrontPhoto': false,
        'hasBackPhoto': false,
        'idFrontStoragePath': null,
        'idBackStoragePath': null,
      },
      cloud: <String, dynamic>{
        'hasFrontPhoto': true,
        'hasBackPhoto': true,
        'idFrontStoragePath':
            'businesses/biz_x/guests/CUST-0001/id_front.jpg',
        'idBackStoragePath': 'businesses/biz_x/guests/CUST-0001/id_back.jpg',
        'idFrontSha256': 'abc',
        'idBackSha256': 'def',
      },
    );
    expect(merged['hasFrontPhoto'], isTrue);
    expect(merged['hasBackPhoto'], isTrue);
    expect(
      merged['idFrontStoragePath'],
      'businesses/biz_x/guests/CUST-0001/id_front.jpg',
    );
  });

  test('login phone fills settings as a 10-digit Indian mobile', () {
    expect(
      HotelSettingsStore.displayPhoneFromLogin('+919876543210'),
      '9876543210',
    );
    expect(
      HotelSettingsStore.displayPhoneFromLogin('09876543210'),
      '9876543210',
    );
  });

  test('second phone joining an existing hotel restores shared cloud', () {
    expect(
      policy.decide(
        localHasData: true,
        cloudHasData: true,
        localMigrationCompleted: false,
      ),
      HotelCloudBootstrapAction.restore,
    );
  });

  test('auth sign-out keeps cached businessId', () {
    PhoneAuthSession.businessId = 'biz_xehC63jAFQWvlgKRwabV';
    PhoneAuthSession.uid = 'temp';
    PhoneAuthSession.clearAuthUser();
    expect(PhoneAuthSession.uid, isNull);
    expect(PhoneAuthSession.businessId, 'biz_xehC63jAFQWvlgKRwabV');
  });

  test('missing SHA client identifier is explained without disabling verification', () {
    expect(
      PhoneAuthService.humanize(
        FirebaseAuthException(
          code: 'missing-client-identifier',
          message: 'App identifier missing',
        ),
      ),
      contains('SHA-256'),
    );
    expect(
      PhoneAuthService.humanize(
        FirebaseAuthException(
          code: 'unknown',
          message:
              'A play_integrity_token was passed, but no matching SHA-256 was registered',
        ),
      ),
      contains('Send OTP again'),
    );
    expect(
      PhoneAuthService.humanize(
        FirebaseAuthException(
          code: 'captcha-check-failed',
          message: 'captcha',
        ),
      ),
      contains('Phone verification check failed'),
    );
  });
}

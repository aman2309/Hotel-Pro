import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/bill_record.dart';
import '../models/customer.dart';
import '../models/room.dart';
import '../utils/stay_duration.dart';
import 'hotel_cloud_policy.dart';
import 'hotel_record_ids.dart';
import 'hotel_photo_ref.dart';

class HotelCloudDoc {
  const HotelCloudDoc({
    required this.collection,
    required this.id,
    required this.data,
  });

  final String collection;
  final String id;
  final Map<String, dynamic> data;
}

class HotelCloudSnapshot {
  const HotelCloudSnapshot({required this.docs, required this.idsByCollection});

  final List<HotelCloudDoc> docs;
  final Map<String, Set<String>> idsByCollection;
}

/// Maps existing Hotel Pro models to Firestore documents with stable IDs.
class HotelCloudCodec {
  HotelCloudCodec({this.deviceId = 'device', this.updatedAtMs});

  final String deviceId;
  final int? updatedAtMs;

  static const int schemaVersion = HotelCloudPolicy.schemaVersion;

  static String roomId(int roomNumber) => 'room_$roomNumber';

  static const List<String> _frontPhotoKeys = <String>[
    'hasFrontPhoto',
    'idFrontStoragePath',
    'idFrontPhotoPath',
    'idFrontSha256',
    'idFrontByteLength',
    'idFrontContentType',
  ];

  static const List<String> _backPhotoKeys = <String>[
    'hasBackPhoto',
    'idBackStoragePath',
    'idBackPhotoPath',
    'idBackSha256',
    'idBackByteLength',
    'idBackContentType',
  ];

  /// Keep existing cloud ID-photo metadata when the local guest has no bytes.
  static Map<String, dynamic> mergeGuestPhotoMetadata({
    required Map<String, dynamic> local,
    Map<String, dynamic>? cloud,
  }) {
    if (cloud == null) {
      return local;
    }
    final Map<String, dynamic> out = Map<String, dynamic>.from(local);
    if (local['hasFrontPhoto'] != true && _cloudHasPhoto(cloud, front: true)) {
      for (final String key in _frontPhotoKeys) {
        if (cloud.containsKey(key)) {
          out[key] = cloud[key];
        }
      }
    }
    if (local['hasBackPhoto'] != true && _cloudHasPhoto(cloud, front: false)) {
      for (final String key in _backPhotoKeys) {
        if (cloud.containsKey(key)) {
          out[key] = cloud[key];
        }
      }
    }
    if ((local['additionalPhotos'] == null ||
            (local['additionalPhotos'] is Map &&
                (local['additionalPhotos'] as Map).isEmpty)) &&
        cloud['additionalPhotos'] is Map &&
        (cloud['additionalPhotos'] as Map).isNotEmpty) {
      out['additionalPhotos'] = cloud['additionalPhotos'];
    }
    return out;
  }

  static bool _cloudHasPhoto(
    Map<String, dynamic> cloud, {
    required bool front,
  }) {
    if (cloud[front ? 'hasFrontPhoto' : 'hasBackPhoto'] == true) {
      return true;
    }
    final String path =
        (cloud[front ? 'idFrontStoragePath' : 'idBackStoragePath'] ?? '')
            .toString();
    return path.isNotEmpty;
  }

  static Map<String, dynamic> coerceRoomJson(Map<String, dynamic> json) {
    const List<String> intKeys = <String>[
      'roomNumber',
      'normalRent',
      'bookingRate',
      'days',
      'advance',
      'futureBookingRate',
      'futureDays',
      'futureAdvance',
    ];
    for (final String key in intKeys) {
      final dynamic value = json[key];
      if (value is num) {
        json[key] = value.toInt();
      }
    }
    return json;
  }

  static List<Room> decodeRoomList(
    List<dynamic> decoded, {
    void Function(Object error, int index)? onError,
  }) {
    final List<Room> rooms = <Room>[];
    for (int i = 0; i < decoded.length; i++) {
      try {
        final Map<String, dynamic> json = coerceRoomJson(
          Map<String, dynamic>.from(decoded[i] as Map),
        );
        rooms.add(Room.fromJson(json));
      } catch (error) {
        onError?.call(error, i);
      }
    }
    return rooms;
  }

  static Map<String, dynamic> firestoreSafeMap(Map<String, dynamic> data) {
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(data)) as Map);
  }

  static String guestId(String customerId) =>
      customerId.trim().isEmpty ? '' : customerId.trim();

  static String billId(String billNumber) => billNumber.trim();

  static String currentBookingId(int roomNumber) => 'bkg_room_$roomNumber';

  static String billBookingId(String billNumber) => 'bkg_$billNumber';

  static String futureBookingId(int roomNumber) => 'fb_room_$roomNumber';

  static String closedRoomId(int roomNumber) => 'closed_$roomNumber';

  static String expenseId(Map<String, dynamic> expense) {
    final String existing = (expense['expenseId'] ?? expense['id'] ?? '')
        .toString()
        .trim();
    if (existing.isNotEmpty) {
      return existing;
    }
    final String dateTime = (expense['dateTime'] ?? '').toString();
    final String amount = '${expense['amount'] ?? ''}';
    final String category = (expense['category'] ?? '').toString();
    final String description = (expense['description'] ?? '').toString();
    return 'exp_${_token(dateTime)}_${_token(amount)}_${_token(category)}_${_token(description)}';
  }

  static String paymentId({
    required String source,
    required Map<String, dynamic> payment,
    required int index,
  }) {
    final String existing = (payment['paymentId'] ?? payment['id'] ?? '')
        .toString()
        .trim();
    if (existing.isNotEmpty) {
      return existing;
    }
    final String dateTime = (payment['dateTime'] ?? '').toString();
    final String amount = '${payment['amount'] ?? ''}';
    final String mode = (payment['paymentMode'] ?? payment['mode'] ?? '')
        .toString();
    return 'pay_${_token(source)}_${index}_${_token(dateTime)}_${_token(amount)}_${_token(mode)}';
  }

  static String extraChargeId({
    required String source,
    required Map<String, dynamic> charge,
    required int index,
  }) {
    final String existing = (charge['chargeId'] ?? charge['id'] ?? '')
        .toString()
        .trim();
    if (existing.isNotEmpty) {
      return existing;
    }
    final String name = (charge['name'] ?? '').toString();
    final String amount = '${charge['amount'] ?? ''}';
    return 'chg_${_token(source)}_${index}_${_token(name)}_${_token(amount)}';
  }

  static String _token(String raw) {
    final String cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (cleaned.isEmpty) {
      return 'x';
    }
    return cleaned.length <= 24 ? cleaned : cleaned.substring(0, 24);
  }

  Map<String, dynamic> envelope(Map<String, dynamic> payload) {
    final int at = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    return <String, dynamic>{
      ...sanitizeForCloud(payload),
      'updatedAtMs': at,
      'deviceId': deviceId,
      'schemaVersion': schemaVersion,
      'deleted': false,
    };
  }

  Map<String, dynamic> tombstone() {
    final int at = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    return <String, dynamic>{
      'updatedAtMs': at,
      'deviceId': deviceId,
      'schemaVersion': schemaVersion,
      'deleted': true,
    };
  }

  Map<String, dynamic> sanitizeForCloud(dynamic value) {
    return _sanitize(value) as Map<String, dynamic>;
  }

  dynamic _sanitize(dynamic value) {
    if (value is Map) {
      final Map<String, dynamic> out = <String, dynamic>{};
      value.forEach((dynamic key, dynamic raw) {
        final String name = key.toString();
        if (HotelPhotoRef.localPhotoKeys.contains(name)) {
          out[name] = HotelPhotoRef.fromLocalValue(raw).toFirestore();
          return;
        }
        out[name] = _sanitize(raw);
      });
      return out;
    }
    if (value is List) {
      return value.map(_sanitize).toList();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    return value;
  }

  /// Rebuild SharedPreferences-safe JSON (ints, ISO dates, empty photo strings).
  dynamic toLocalValue(dynamic value, {String? key}) {
    if (value is Map) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(value);
      if (key != null && HotelPhotoRef.localPhotoKeys.contains(key)) {
        return HotelPhotoRef.fromLocalValue(map).toLocalString();
      }
      if (map.containsKey('hasPhoto') &&
          map.containsKey('storageEnabled') &&
          map.length <= 8) {
        return HotelPhotoRef.fromLocalValue(map).toLocalString();
      }
      final Map<String, dynamic> out = <String, dynamic>{};
      map.forEach((String name, dynamic raw) {
        if (name == 'updatedAtMs' ||
            name == 'deviceId' ||
            name == 'schemaVersion' ||
            name == 'deleted' ||
            name == 'updatedAt') {
          return;
        }
        out[name] = toLocalValue(raw, key: name);
      });
      return out;
    }
    if (value is List) {
      return value.map((dynamic item) => toLocalValue(item, key: key)).toList();
    }
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is num && value is! int && key != 'hotel_gst_tax_rate') {
      if (value == value.roundToDouble()) {
        return value.toInt();
      }
    }
    return value;
  }

  HotelCloudSnapshot build({
    required List<Room> rooms,
    required List<BillRecord> bills,
    required List<Customer> guests,
    required List<Map<String, dynamic>> expenses,
    required Map<String, dynamic> settings,
    Map<String, String> photoStoragePaths = const <String, String>{},
  }) {
    final List<HotelCloudDoc> docs = <HotelCloudDoc>[];
    final Map<String, Set<String>> ids = <String, Set<String>>{
      'rooms': <String>{},
      'bookings': <String>{},
      'guests': <String>{},
      'bills': <String>{},
      'payments': <String>{},
      'futureBookings': <String>{},
      'expenses': <String>{},
      'settings': <String>{'hotel', 'sync'},
      'closedRooms': <String>{},
      'extraCharges': <String>{},
    };

    void add(String collection, String id, Map<String, dynamic> data) {
      if (id.isEmpty) {
        return;
      }
      ids[collection]!.add(id);
      docs.add(
        HotelCloudDoc(collection: collection, id: id, data: envelope(data)),
      );
    }

    for (final Room room in rooms) {
      final String rid = roomId(room.roomNumber);
      add('rooms', rid, Map<String, dynamic>.from(room.toJson()));

      if (room.status == 'BOOKED') {
        add('bookings', currentBookingId(room.roomNumber), <String, dynamic>{
          'bookingId': currentBookingId(room.roomNumber),
          'roomNumber': room.roomNumber,
          'roomType': room.roomType,
          'guestName': room.guestName,
          'mobile': room.mobile,
          'idNumber': room.idNumber,
          'guestAddress': room.guestAddress,
          'bookingDate': room.bookingDate?.toIso8601String(),
          'bookingTime': room.bookingTime?.toIso8601String(),
          'bookingEndTime': room.bookingEndTime?.toIso8601String(),
          'checkoutTime': room.checkoutTime?.toIso8601String(),
          'days': room.days,
          'roomRate': room.bookingRate,
          'advance': room.advance,
          'paymentMode': room.paymentMode,
          'billNumber': room.billNumber,
          'applyGst': room.applyGst,
          'futureBooking': false,
          'charges': room.charges,
          'partPayments': room.partPayments,
          'extraGuests': room.extraGuests,
          'status': room.status,
        });
      }

      if (room.futureBooking) {
        add(
          'futureBookings',
          futureBookingId(room.roomNumber),
          <String, dynamic>{
            'bookingId': futureBookingId(room.roomNumber),
            'roomNumber': room.roomNumber,
            'roomType': room.roomType,
            'guestName': room.futureGuestName,
            'mobile': room.futureMobile,
            'idNumber': room.futureIdNumber,
            'guestAddress': room.futureGuestAddress,
            'bookingDate': room.futureBookingDate?.toIso8601String(),
            'days': room.futureDays,
            'roomRate': room.futureBookingRate,
            'advance': room.futureAdvance,
            'paymentMode': room.futurePaymentMode,
            'futureBooking': true,
            'extraGuests': room.futureExtraGuests,
          },
        );
      }

      if (room.status == 'CLOSED') {
        add('closedRooms', closedRoomId(room.roomNumber), <String, dynamic>{
          'roomNumber': room.roomNumber,
          'roomType': room.roomType,
          'status': room.status,
          'faultReason': room.faultReason,
          'normalRent': room.normalRent,
        });
      }

      for (
        int i = 0;
        room.status == 'BOOKED' && i < room.partPayments.length;
        i++
      ) {
        final Map<String, dynamic> payment = Map<String, dynamic>.from(
          room.partPayments[i],
        );
        add(
          'payments',
          paymentId(source: rid, payment: payment, index: i),
          <String, dynamic>{
            ...payment,
            'source': 'room',
            'roomNumber': room.roomNumber,
            'billNumber': room.billNumber,
            'kind': 'part',
          },
        );
      }

      if (room.advance > 0 && room.status == 'BOOKED') {
        add(
          'payments',
          'pay_adv_${HotelRecordIds.stay(room.mobile, room.bookingTime, room.bookingDate)}',
          <String, dynamic>{
            'amount': room.advance,
            'paymentMode': room.paymentMode,
            'dateTime': room.bookingTime?.toIso8601String(),
            'source': 'room',
            'roomNumber': room.roomNumber,
            'billNumber': room.billNumber,
            'kind': 'advance',
          },
        );
      }

      for (int i = 0; room.status == 'BOOKED' && i < room.charges.length; i++) {
        final Map<String, dynamic> charge = Map<String, dynamic>.from(
          room.charges[i],
        );
        add(
          'extraCharges',
          extraChargeId(source: rid, charge: charge, index: i),
          <String, dynamic>{
            ...charge,
            'source': 'room',
            'roomNumber': room.roomNumber,
            'billNumber': room.billNumber,
          },
        );
      }
    }

    for (final BillRecord bill in bills) {
      final String bid = billId(bill.billNumber);
      add('bills', bid, Map<String, dynamic>.from(bill.toJson()));
      add('bookings', billBookingId(bill.billNumber), <String, dynamic>{
        'bookingId': billBookingId(bill.billNumber),
        'billNumber': bill.billNumber,
        'customerId': bill.customerId,
        'guestName': bill.guestName,
        'mobile': bill.mobile,
        'roomNumber': bill.roomNumber,
        'roomType': bill.roomType,
        'bookingDate': bill.bookingDate?.toIso8601String(),
        'bookingTime': bill.bookingTime?.toIso8601String(),
        'checkoutTime': bill.checkoutTime?.toIso8601String(),
        if (bill.finalStayMinutes != null)
          'stayDurationMinutes': bill.finalStayMinutes,
        'days': bill.bookedDays,
        'roomRate': bill.roomRate,
        'advance': bill.advance,
        'paymentMode': bill.paymentMode,
        'advancePaymentMode': bill.advancePaymentMode,
        'charges': bill.charges,
        'partPayments': bill.partPayments,
        'status': 'CHECKED_OUT',
      });

      for (int i = 0; i < bill.partPayments.length; i++) {
        final Map<String, dynamic> payment = Map<String, dynamic>.from(
          bill.partPayments[i],
        );
        add(
          'payments',
          paymentId(source: bid, payment: payment, index: i),
          <String, dynamic>{
            ...payment,
            'source': 'bill',
            'roomNumber': bill.roomNumber,
            'billNumber': bill.billNumber,
            'kind': 'part',
          },
        );
      }

      if (bill.advance > 0) {
        add(
          'payments',
          'pay_adv_${HotelRecordIds.stay(bill.mobile, bill.bookingTime, bill.bookingDate)}',
          <String, dynamic>{
            'amount': bill.advance,
            'paymentMode': bill.advancePaymentMode.isNotEmpty
                ? bill.advancePaymentMode
                : bill.paymentMode,
            'dateTime': bill.bookingTime?.toIso8601String(),
            'source': 'bill',
            'roomNumber': bill.roomNumber,
            'billNumber': bill.billNumber,
            'kind': 'advance',
          },
        );
      }

      final partTotal = bill.partPayments.fold<int>(
        0,
        (runningTotal, payment) =>
            runningTotal + (int.tryParse('${payment['amount']}') ?? 0),
      );
      final taxable = bill.totalBill - bill.discount;
      final rate = double.tryParse('${settings['hotel_gst_tax_rate']}') ?? 5;
      final tax = bill.applyGst ? (taxable * rate / 100).round() : 0;
      final checkoutAmount = taxable + tax - bill.advance - partTotal;
      if (checkoutAmount > 0) {
        add('payments', 'pay_checkout_$bid', {
          'amount': checkoutAmount,
          'paymentMode': bill.paymentMode,
          'dateTime': bill.checkoutTime?.toIso8601String(),
          'source': 'bill',
          'billNumber': bid,
          'roomNumber': bill.roomNumber,
          'kind': 'checkout',
        });
      }

      for (int i = 0; i < bill.charges.length; i++) {
        final Map<String, dynamic> charge = Map<String, dynamic>.from(
          bill.charges[i],
        );
        add(
          'extraCharges',
          extraChargeId(source: bid, charge: charge, index: i),
          <String, dynamic>{
            ...charge,
            'source': 'bill',
            'roomNumber': bill.roomNumber,
            'billNumber': bill.billNumber,
          },
        );
      }
    }

    for (final Customer guest in guests) {
      final String gid = guestId(guest.customerId);
      final String frontPath =
          photoStoragePaths[HotelPhotoPaths.metaKey(
            guestId: gid,
            side: 'front',
          )] ??
          '';
      final String backPath =
          photoStoragePaths[HotelPhotoPaths.metaKey(
            guestId: gid,
            side: 'back',
          )] ??
          '';
      final HotelPhotoRef frontRef = HotelPhotoRef.fromLocalValue(
        guest.idFrontPhotoPath,
      );
      final HotelPhotoRef backRef = HotelPhotoRef.fromLocalValue(
        guest.idBackPhotoPath,
      );
      final Map<String, dynamic> additionalPhotos = <String, dynamic>{};
      photoStoragePaths.forEach((String key, String path) {
        final List<String> parts = key.split(':');
        if (parts.length != 4 || parts[0] != gid || parts[1] != 'additional') {
          return;
        }
        final String additionalId = parts[2];
        final String side = parts[3];
        final Map<String, dynamic> current = Map<String, dynamic>.from(
          additionalPhotos[additionalId] as Map? ?? <String, dynamic>{},
        );
        if (side == 'back') {
          current['idBackStoragePath'] = path;
          current['hasBackPhoto'] = true;
        } else {
          current['idFrontStoragePath'] = path;
          current['hasFrontPhoto'] = true;
        }
        additionalPhotos[additionalId] = current;
      });
      add('guests', gid, <String, dynamic>{
        'customerId': guest.customerId,
        'mobile': guest.mobile,
        'guestName': guest.guestName,
        'address': guest.address,
        'idType': guest.idType,
        'idNumber': guest.idNumber,
        'idFrontPhotoPath': frontPath.isEmpty
            ? frontRef.toFirestore()
            : frontRef.withStorage(path: frontPath).toFirestore(),
        'idBackPhotoPath': backPath.isEmpty
            ? backRef.toFirestore()
            : backRef.withStorage(path: backPath).toFirestore(),
        'idFrontStoragePath': frontPath.isEmpty ? null : frontPath,
        'idBackStoragePath': backPath.isEmpty ? null : backPath,
        'hasFrontPhoto': frontRef.hasPhoto || frontPath.isNotEmpty,
        'hasBackPhoto': backRef.hasPhoto || backPath.isNotEmpty,
        'photoUpdatedAt': DateTime.now().millisecondsSinceEpoch,
        'idFrontByteLength': frontRef.byteLength,
        'idBackByteLength': backRef.byteLength,
        'idFrontContentType': frontPath.isEmpty
            ? null
            : HotelPhotoRef.jpegContentType,
        'idBackContentType': backPath.isEmpty
            ? null
            : HotelPhotoRef.jpegContentType,
        if (additionalPhotos.isNotEmpty) 'additionalPhotos': additionalPhotos,
        'stayHistory': guest.stayHistory,
      });
    }

    for (final Map<String, dynamic> expense in expenses) {
      add('expenses', expenseId(expense), Map<String, dynamic>.from(expense));
    }

    add('settings', 'hotel', <String, dynamic>{
      'hotel_name': settings['hotel_name'] ?? 'Hotel',
      'hotel_address': settings['hotel_address'] ?? '',
      'hotel_mobile': settings['hotel_mobile'] ?? '',
      'hotel_registration_number': settings['hotel_registration_number'] ?? '',
      'hotel_gst_number': settings['hotel_gst_number'] ?? '',
      'hotel_gst_tax_rate': settings['hotel_gst_tax_rate'] ?? 5,
      'hotel_admin_password': settings['hotel_admin_password'] ?? 'HOTEL2026',
    });

    return HotelCloudSnapshot(docs: docs, idsByCollection: ids);
  }

  List<Room> roomsFromCloud(Iterable<Map<String, dynamic>> docs) {
    final List<Room> rooms = <Room>[];
    for (final Map<String, dynamic> doc in docs) {
      if (doc['deleted'] == true) {
        continue;
      }
      final Map<String, dynamic> local = Map<String, dynamic>.from(
        toLocalValue(doc) as Map,
      );
      if (local['roomNumber'] == null) {
        continue;
      }
      rooms.add(Room.fromJson(_withInts(local)));
    }
    rooms.sort((Room a, Room b) => a.roomNumber.compareTo(b.roomNumber));
    return rooms;
  }

  /// Fill live bookings / future bookings / closed status from companion
  /// collections when the room document is incomplete. Never deletes rooms.
  List<Room> mergeRelatedIntoRooms({
    required List<Room> rooms,
    required Iterable<Map<String, dynamic>> bookings,
    required Iterable<Map<String, dynamic>> futureBookings,
    required Iterable<Map<String, dynamic>> closedRooms,
    Iterable<Map<String, dynamic>> roomDocs = const <Map<String, dynamic>>[],
  }) {
    final Map<int, Room> byNumber = <int, Room>{
      for (final Room room in rooms) room.roomNumber: room,
    };
    // Booking docs are keyed by room number (bkg_room_<n>), so a doc left over
    // from an earlier stay must never override a room that changed after it —
    // whatever the room's current status. A room freshly re-booked must keep
    // its new start time. Booking and room docs are written in one
    // transaction, so the current booking carries the same updatedAtMs and
    // still merges.
    final Map<int, int> roomUpdatedAt = <int, int>{
      for (final Map<String, dynamic> doc in roomDocs)
        if (doc['deleted'] != true &&
            _asIntOrNull(doc['roomNumber']) != null &&
            _asIntOrNull(doc['updatedAtMs']) != null)
          _asIntOrNull(doc['roomNumber'])!: _asIntOrNull(doc['updatedAtMs'])!,
    };

    for (final Map<String, dynamic> doc in bookings) {
      if (doc['deleted'] == true) {
        continue;
      }
      final Map<String, dynamic> local = Map<String, dynamic>.from(
        toLocalValue(doc) as Map,
      );
      final int? roomNumber = _asIntOrNull(local['roomNumber']);
      if (roomNumber == null) {
        continue;
      }
      final Room? room = byNumber[roomNumber];
      if (room == null) {
        continue;
      }
      final int? bookingAt = _asIntOrNull(doc['updatedAtMs']);
      final int? roomAt = roomUpdatedAt[roomNumber];
      if (bookingAt != null && roomAt != null && bookingAt < roomAt) {
        continue;
      }
      _applyLiveBooking(room, local);
    }

    for (final Map<String, dynamic> doc in futureBookings) {
      if (doc['deleted'] == true) {
        continue;
      }
      final Map<String, dynamic> local = Map<String, dynamic>.from(
        toLocalValue(doc) as Map,
      );
      final int? roomNumber = _asIntOrNull(local['roomNumber']);
      if (roomNumber == null) {
        continue;
      }
      final Room? room = byNumber[roomNumber];
      if (room == null) {
        continue;
      }
      _applyFutureBooking(room, local);
    }

    for (final Map<String, dynamic> doc in closedRooms) {
      if (doc['deleted'] == true) {
        continue;
      }
      final Map<String, dynamic> local = Map<String, dynamic>.from(
        toLocalValue(doc) as Map,
      );
      final int? roomNumber = _asIntOrNull(local['roomNumber']);
      if (roomNumber == null) {
        continue;
      }
      final Room? room = byNumber[roomNumber];
      if (room == null || room.status == 'BOOKED') {
        continue;
      }
      if (room.status != 'CLOSED') {
        room.status = 'CLOSED';
        room.faultReason = local['faultReason']?.toString() ?? room.faultReason;
      }
    }

    return rooms;
  }

  void _applyLiveBooking(Room room, Map<String, dynamic> booking) {
    final String status = (booking['status'] ?? '').toString();
    if (status == 'CHECKED_OUT' || booking['futureBooking'] == true) {
      return;
    }
    final String bookingId = (booking['bookingId'] ?? '').toString();
    final bool liveRoomBooking =
        bookingId.startsWith('bkg_room_') || status == 'BOOKED';
    if (!liveRoomBooking) {
      return;
    }

    if (room.status != 'BOOKED') {
      room.status = 'BOOKED';
      room.guestName = booking['guestName']?.toString() ?? room.guestName;
      room.mobile = booking['mobile']?.toString() ?? room.mobile;
      room.idNumber = booking['idNumber']?.toString() ?? room.idNumber;
      room.guestAddress =
          booking['guestAddress']?.toString() ?? room.guestAddress;
      room.bookingRate = _asInt(booking['roomRate'], room.bookingRate);
      room.days = _asInt(booking['days'], room.days);
      room.advance = _asInt(booking['advance'], room.advance);
      room.paymentMode = booking['paymentMode']?.toString() ?? room.paymentMode;
      room.billNumber = booking['billNumber']?.toString() ?? room.billNumber;
      room.applyGst = booking['applyGst'] == true || room.applyGst;
      // The applied stay carries its own start. A value still sitting on the
      // room belongs to an earlier stay of the same room number and must never
      // become this stay's start or frozen checkout. Missing timestamps fall
      // back to booking-day noon, mirroring the dashboard backfill.
      final DateTime? bookingDate = _asDate(booking['bookingDate']);
      final DateTime? bookingTime = _asDate(booking['bookingTime']);
      room.bookingDate = bookingDate ?? bookingTime;
      room.bookingTime = bookingTime ?? bookingStartFallback(bookingDate);
      room.bookingEndTime = _asDate(booking['bookingEndTime']);
      room.checkoutTime = _asDate(booking['checkoutTime']);
    }
    if (room.extraGuests.isEmpty) {
      room.extraGuests = _asMapList(booking['extraGuests']);
    }
    if (room.partPayments.isEmpty) {
      room.partPayments = _asMapList(booking['partPayments']);
    }
    if (room.charges.isEmpty) {
      room.charges = _asMapList(booking['charges']);
    }
  }

  void _applyFutureBooking(Room room, Map<String, dynamic> booking) {
    if (!room.futureBooking) {
      room.futureBooking = true;
      room.futureGuestName =
          booking['guestName']?.toString() ?? room.futureGuestName;
      room.futureMobile = booking['mobile']?.toString() ?? room.futureMobile;
      room.futureIdNumber =
          booking['idNumber']?.toString() ?? room.futureIdNumber;
      room.futureGuestAddress =
          booking['guestAddress']?.toString() ?? room.futureGuestAddress;
      room.futureBookingRate = _asInt(
        booking['roomRate'],
        room.futureBookingRate,
      );
      room.futureDays = _asInt(booking['days'], room.futureDays);
      room.futureAdvance = _asInt(booking['advance'], room.futureAdvance);
      room.futurePaymentMode =
          booking['paymentMode']?.toString() ?? room.futurePaymentMode;
      room.futureBookingDate =
          _asDate(booking['bookingDate']) ?? room.futureBookingDate;
    }
    if (room.futureExtraGuests.isEmpty) {
      room.futureExtraGuests = _asMapList(booking['extraGuests']);
    }
  }

  List<BillRecord> billsFromCloud(Iterable<Map<String, dynamic>> docs) {
    final List<BillRecord> bills = <BillRecord>[];
    for (final Map<String, dynamic> doc in docs) {
      if (doc['deleted'] == true) {
        continue;
      }
      final Map<String, dynamic> local = Map<String, dynamic>.from(
        toLocalValue(doc) as Map,
      );
      if ((local['billNumber'] ?? '').toString().isEmpty) {
        continue;
      }
      bills.add(BillRecord.fromJson(_withInts(local)));
    }
    return bills;
  }

  List<Customer> guestsFromCloud(Iterable<Map<String, dynamic>> docs) {
    final List<Customer> guests = <Customer>[];
    for (final Map<String, dynamic> doc in docs) {
      if (doc['deleted'] == true) {
        continue;
      }
      final Map<String, dynamic> local = Map<String, dynamic>.from(
        toLocalValue(doc) as Map,
      );
      final String id = (local['customerId'] ?? '').toString();
      if (id.isEmpty) {
        continue;
      }
      guests.add(
        Customer(
          customerId: id,
          mobile: local['mobile']?.toString() ?? '',
          guestName: local['guestName']?.toString() ?? '',
          address: local['address']?.toString() ?? '',
          idType: local['idType']?.toString() ?? '',
          idNumber: local['idNumber']?.toString() ?? '',
          idFrontPhotoPath: localPhotoString(local['idFrontPhotoPath']),
          idBackPhotoPath: localPhotoString(local['idBackPhotoPath']),
          stayHistory: (local['stayHistory'] as List<dynamic>? ?? [])
              .map((dynamic item) => Map<String, dynamic>.from(item as Map))
              .toList(),
        ),
      );
    }
    return guests;
  }

  List<Map<String, dynamic>> expensesFromCloud(
    Iterable<Map<String, dynamic>> docs,
  ) {
    final List<Map<String, dynamic>> expenses = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> doc in docs) {
      if (doc['deleted'] == true) {
        continue;
      }
      expenses.add(Map<String, dynamic>.from(toLocalValue(doc) as Map));
    }
    return expenses;
  }

  /// Keep local ID-photo fields empty unless they already hold Base64 bytes.
  static String localPhotoString(dynamic value) {
    if (value is Map) {
      return '';
    }
    final String text = (value ?? '').toString();
    return HotelPhotoRef.looksLikePhotoBytes(text) ? text : '';
  }

  int _asInt(dynamic value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int? _asIntOrNull(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  DateTime? _asDate(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    final String text = value.toString();
    if (text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text);
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) {
      return <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map(
          (Map item) => Map<String, dynamic>.from(
            toLocalValue(Map<String, dynamic>.from(item)) as Map,
          ),
        )
        .toList();
  }

  Map<String, dynamic> _withInts(Map<String, dynamic> json) {
    const List<String> intKeys = <String>[
      'roomNumber',
      'normalRent',
      'bookingRate',
      'days',
      'advance',
      'futureBookingRate',
      'futureDays',
      'futureAdvance',
      'roomRate',
      'bookedDays',
      'roomBill',
      'extraCharges',
      'totalBill',
      'discount',
      'balance',
    ];
    for (final String key in intKeys) {
      final dynamic value = json[key];
      if (value is num) {
        json[key] = value.toInt();
      }
    }
    return json;
  }

  bool mapContainsPhotoBytes(dynamic value) {
    if (value is String && HotelPhotoRef.looksLikePhotoBytes(value)) {
      return true;
    }
    if (value is Map) {
      for (final dynamic raw in value.values) {
        if (mapContainsPhotoBytes(raw)) {
          return true;
        }
      }
    }
    if (value is List) {
      for (final dynamic raw in value) {
        if (mapContainsPhotoBytes(raw)) {
          return true;
        }
      }
    }
    return false;
  }
}

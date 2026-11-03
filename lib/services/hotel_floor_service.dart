import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import '../models/hotel_floor.dart';
import 'hotel_firestore_service.dart';

class HotelFloorService {
  HotelFloorService._();
  static final instance = HotelFloorService._();

  CollectionReference<Map<String, dynamic>> get _floors {
    final business = HotelFirestoreService.instance.businessId;
    if (business == null) throw StateError('Sign in to load floors.');
    return HotelFirestoreService.instance.col(business, 'floors');
  }

  static String idForName(String name) =>
      'floor_${sha256.convert(utf8.encode(name.trim().toLowerCase()))}';
  List<HotelFloor> _decode(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final floors = snapshot.docs
        .where((d) => d.data()['deleted'] != true)
        .map((d) => HotelFloor(id: d.id, name: d.data()['name'] as String))
        .toList();
    floors.sort((a, b) => a.name.compareTo(b.name));
    return floors;
  }

  Stream<List<HotelFloor>> watch() => _floors
      .snapshots(includeMetadataChanges: true)
      .where((s) => !s.metadata.isFromCache && !s.metadata.hasPendingWrites)
      .map(_decode);
  Future<List<HotelFloor>> fetch() async =>
      _decode(await _floors.get(const GetOptions(source: Source.server)));

  Future<void> create(String name) async {
    name = name.trim();
    if (name.isEmpty || name.length > 60) {
      throw ArgumentError('Enter a floor name up to 60 characters.');
    }
    final ref = _floors.doc(idForName(name));
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (existing.exists) throw StateError('This floor already exists.');
      tx.set(ref, {
        'name': name,
        'schemaVersion': 3,
        'createdAt': FieldValue.serverTimestamp(),
        'deleted': false,
      });
    });
  }
}

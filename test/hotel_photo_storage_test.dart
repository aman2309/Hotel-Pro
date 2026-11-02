import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/models/customer.dart';
import 'package:my_first_app/models/room.dart';
import 'package:my_first_app/services/hotel_cloud_codec.dart';
import 'package:my_first_app/services/hotel_photo_ref.dart';
import 'package:my_first_app/services/hotel_photo_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  const String fakePhoto =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

  test('A B storage paths for front and back ID photos', () {
    expect(
      HotelPhotoPaths.front('biz_1', 'CUST-0001'),
      'businesses/biz_1/guests/CUST-0001/id_front.jpg',
    );
    expect(
      HotelPhotoPaths.back('biz_1', 'CUST-0001'),
      'businesses/biz_1/guests/CUST-0001/id_back.jpg',
    );
  });

  test('C additional guest photos use stable unique paths', () {
    final String additional = HotelPhotoPaths.additionalGuestId(
      mobile: '9999999999',
      idNumber: 'AB123',
    );
    expect(additional, 'ag_9999999999_AB123');
    expect(
      HotelPhotoPaths.additionalFront('biz_1', 'CUST-0001', additional),
      'businesses/biz_1/guests/CUST-0001/additional/$additional/id_front.jpg',
    );
    expect(
      HotelPhotoPaths.additionalGuestId(
        mobile: '9999999999',
        idNumber: 'AB123',
      ),
      additional,
    );
  });

  test('JPEG base64 starting with /9j/ is accepted as a photo', () {
    final String jpeg = '/9j/${'A' * 120}';
    expect(HotelPhotoRef.looksLikePhotoBytes(jpeg), isTrue);
    expect(HotelPhotoRef.looksLikePhotoBytes('file:/tmp/id.jpg${'A' * 80}'), isFalse);
    expect(
      HotelPhotoRef.looksLikePhotoBytes('/storage/emulated/0/DCIM/id.jpg'),
      isFalse,
    );
  });

  test('D unchanged photo hash is stable for later retry', () {
    final String? first = HotelPhotoStorageService.sha256OfBase64(fakePhoto);
    final String? second = HotelPhotoStorageService.sha256OfBase64(fakePhoto);
    expect(first, isNotNull);
    expect(first, second);
    expect(HotelPhotoStorageService.decodeBase64Photo('not-a-photo'), isNull);
  });

  test('E replace photo changes hash', () {
    const String other =
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAD0lEQVR42mP8z8BQz0AEYBwACawD/QqH1qQAAAAASUVORK5CYII=';
    expect(
      HotelPhotoStorageService.sha256OfBase64(fakePhoto),
      isNot(HotelPhotoStorageService.sha256OfBase64(other)),
    );
  });

  test('F guest firestore metadata has storage fields not Base64', () {
    final Customer guest = Customer(
      customerId: 'CUST-0009',
      mobile: '8888888888',
      guestName: 'Neha',
      idType: 'Aadhaar',
      idNumber: '1111',
      idFrontPhotoPath: fakePhoto,
      idBackPhotoPath: fakePhoto,
    );
    final String frontPath = HotelPhotoPaths.front('biz_1', 'CUST-0009');
    final HotelCloudSnapshot snap = HotelCloudCodec(
      deviceId: 'devA',
      updatedAtMs: 1,
    ).build(
      rooms: const <Room>[],
      bills: const [],
      guests: <Customer>[guest],
      expenses: const <Map<String, dynamic>>[],
      settings: <String, dynamic>{'hotel_name': 'Park'},
      photoStoragePaths: <String, String>{
        HotelPhotoPaths.metaKey(guestId: 'CUST-0009', side: 'front'): frontPath,
      },
    );
    final HotelCloudDoc doc = snap.docs.firstWhere(
      (HotelCloudDoc item) => item.collection == 'guests',
    );
    expect(doc.data['hasFrontPhoto'], isTrue);
    expect(doc.data['idFrontStoragePath'], frontPath);
    expect(doc.data['idFrontPhotoPath'], isA<Map>());
    expect(
      HotelCloudCodec(deviceId: 'devA').mapContainsPhotoBytes(doc.data),
      isFalse,
    );
  });

  test('G hotel A path cannot equal hotel B path', () {
    expect(
      HotelPhotoPaths.front('biz_a', 'CUST-0001'),
      isNot(HotelPhotoPaths.front('biz_b', 'CUST-0001')),
    );
  });

  test('H missing storage photo restore does not throw', () async {
    await HotelPhotoStorageService.instance.restorePhotos(
      businessId: 'biz_missing',
      guestDocs: <String, Map<String, dynamic>>{
        'CUST-0001': <String, dynamic>{
          'customerId': 'CUST-0001',
          'idFrontStoragePath': 'businesses/biz_missing/guests/CUST-0001/id_front.jpg',
          'hasFrontPhoto': true,
        },
      },
    );
  });

  test('compress keeps bytes under the Storage cap when possible', () {
    final Uint8List tiny = HotelPhotoStorageService.decodeBase64Photo(fakePhoto)!;
    final Uint8List out = compressHotelIdPhoto(tiny);
    expect(out.length, lessThanOrEqualTo(HotelPhotoRef.maxBytes));
  });
}

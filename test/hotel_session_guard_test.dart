import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/models/room.dart';
import 'package:my_first_app/services/hotel_cloud_codec.dart';
import 'package:my_first_app/services/hotel_cloud_policy.dart';
import 'package:my_first_app/services/hotel_license_policy.dart';

void main() {
  const HotelCloudPolicy policy = HotelCloudPolicy();

  test('unowned local data is quarantined and not a migration', () {
    expect(
      policy.quarantineUnownedLocal(
        hasLocalHotelData: true,
        localOwnerUid: null,
        localBusinessId: null,
        sessionUid: 'uid-a',
        sessionBusinessId: 'biz-a',
      ),
      isTrue,
    );
    expect(
      policy.quarantineUnownedLocal(
        hasLocalHotelData: true,
        localOwnerUid: 'uid-old',
        localBusinessId: 'biz-old',
        sessionUid: 'uid-a',
        sessionBusinessId: 'biz-a',
      ),
      isTrue,
    );
    expect(
      policy.quarantineUnownedLocal(
        hasLocalHotelData: true,
        localOwnerUid: 'uid-a',
        localBusinessId: 'biz-a',
        sessionUid: 'uid-a',
        sessionBusinessId: 'biz-a',
      ),
      isFalse,
    );
    expect(
      policy.quarantineUnownedLocal(
        hasLocalHotelData: false,
        localOwnerUid: null,
        localBusinessId: null,
        sessionUid: 'uid-a',
        sessionBusinessId: 'biz-a',
      ),
      isFalse,
    );
    expect(policy.readFailureIsEmptyHotel(), isFalse);
  });

  test('schema 2 rooms are read and new writes use schema 3', () {
    final Room room = Room(roomNumber: 101, roomType: 'AC', normalRent: 1000);
    final Map<String, dynamic> live = room.toJson()
      ..['schemaVersion'] = 2
      ..['deleted'] = false;
    final Map<String, dynamic> hidden = room.toJson()
      ..['schemaVersion'] = 2
      ..['deleted'] = true
      ..['roomNumber'] = 102;
    final HotelCloudCodec codec = HotelCloudCodec(deviceId: 'device-a');
    final List<Room> read = codec.roomsFromCloud(<Map<String, dynamic>>[
      live,
      hidden,
    ]);
    expect(read.map((Room item) => item.roomNumber), <int>[101]);
    expect(codec.envelope(<String, dynamic>{'roomNumber': 101})['schemaVersion'], 3);
    expect(codec.envelope(<String, dynamic>{'roomNumber': 101})['deleted'], isFalse);
    expect(codec.tombstone()['schemaVersion'], 3);
    expect(codec.tombstone()['deleted'], isTrue);
  });

  test('missing license does not become a new trial', () {
    final HotelLicenseAssessment missing = assessHotelLicense(
      readFailed: false,
      documentExists: false,
      trialStart: null,
      activated: false,
      now: DateTime.utc(2026, 10, 22),
    );
    expect(missing.view, HotelLicenseView.missing);
    expect(missing.message, contains('not restarted'));

    final HotelLicenseAssessment failed = assessHotelLicense(
      readFailed: true,
      documentExists: false,
      trialStart: null,
      activated: false,
      now: DateTime.utc(2026, 10, 22),
    );
    expect(failed.view, HotelLicenseView.unreadable);

    final HotelLicenseAssessment expired = assessHotelLicense(
      readFailed: false,
      documentExists: true,
      trialStart: DateTime.utc(2026, 10, 1),
      activated: false,
      now: DateTime.utc(2026, 10, 22),
    );
    expect(expired.view, HotelLicenseView.expired);
  });

  test('photo mismatch keeps the original cloud file', () {
    expect(
      choosePhotoUpload(
        readFailed: false,
        missing: false,
        remoteSha: 'remote',
        localSha: 'local',
      ),
      PhotoUploadChoice.keepOriginal,
    );
    expect(
      photoMetadataMismatched(
        missing: false,
        readFailed: false,
        remoteSha: 'remote',
        localSha: 'local',
      ),
      isTrue,
    );
    expect(
      choosePhotoUpload(
        readFailed: true,
        missing: false,
        remoteSha: null,
        localSha: 'local',
      ),
      PhotoUploadChoice.retryRead,
    );
    expect(
      choosePhotoUpload(
        readFailed: false,
        missing: true,
        remoteSha: null,
        localSha: 'local',
      ),
      PhotoUploadChoice.uploadNew,
    );
  });
}

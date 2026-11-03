import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/services/firebase_owner_identity.dart';
import 'package:my_first_app/services/hotel_photo_storage_service.dart';
import 'package:my_first_app/services/id_card_ocr.dart';
import 'package:my_first_app/services/retryable_task.dart';
import 'package:my_first_app/services/serial_work_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('missing old cloud photos do not block a new confirmed booking', () {
    final photos = HotelPhotoStorageService.instance;
    addTearDown(() {
      photos.lastPhotoError = null;
      photos.lastUploadError = null;
      photos.pendingUploadCount = 0;
    });
    photos.lastPhotoError = '[firebase_storage/object-not-found] old guest';
    photos.lastUploadError = null;
    photos.pendingUploadCount = 0;
    expect(photos.hasPendingUploadFailure, isFalse);
    photos.pendingUploadCount = 1;
    expect(photos.hasPendingUploadFailure, isTrue);
    photos.pendingUploadCount = 0;
    photos.lastUploadError = 'permission-denied';
    expect(photos.hasPendingUploadFailure, isTrue);
  });
  test('restored email users never produce an empty phone document path', () {
    for (final phone in [null, '', '   ', '+']) {
      expect(verifiedPhoneIndexKey(phone), isNull);
    }
    expect(verifiedPhoneIndexKey('+91 90000 00000'), '919000000000');
  });
  test(
    'startup can retry after failure and shares successful initialization',
    () async {
      final task = RetryableTask<int>();
      await expectLater(
        task.run(() async => throw StateError('offline')),
        throwsStateError,
      );
      final pending = Completer<int>();
      final first = task.run(() => pending.future);
      expect(identical(first, task.run(() async => 99)), isTrue);
      pending.complete(7);
      expect(await first, 7);
      expect(await task.run(() async => 99), 7);
      task.reset();
      expect(await task.run(() async => 8), 8);
    },
  );
  test(
    'an upload cannot overwrite photos queued while it is running',
    () async {
      final queue = SerialWorkQueue();
      final jobs = ['front'];
      final started = Completer<void>(), finish = Completer<void>();
      final upload = queue.run(() async {
        final snapshot = List<String>.of(jobs);
        started.complete();
        await finish.future;
        jobs.removeWhere(snapshot.contains);
      });
      await started.future;
      final capture = queue.run(() async => jobs.add('back'));
      finish.complete();
      await Future.wait([upload, capture]);
      expect(jobs, ['back']);
      await expectLater(
        queue.run(() async => throw StateError('offline')),
        throwsStateError,
      );
      await queue.run(() async => jobs.add('retry'));
      expect(jobs, ['back', 'retry']);
    },
  );
  test(
    'OCR temporary image survives until the native scan has completed',
    () async {
      const channel = MethodChannel('hotel_pro/ocr');
      final started = Completer<String>(), finish = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            started.complete(call.arguments as String);
            return finish.future;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final scan = IdCardOcr.scanBytes(Uint8List.fromList([1, 2, 3]));
      final path = await started.future;
      expect(await File(path).exists(), isTrue);
      finish.complete('Name: Test Guest\n1234 5678 9012');
      await scan;
      expect(await File(path).exists(), isFalse);
    },
  );
}

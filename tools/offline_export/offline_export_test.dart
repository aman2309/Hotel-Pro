import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('hotel_pro/offline_export');
  testWidgets('preserves license, photos, pending queue and unknown prefs without defaults', (tester) async {
    final original = <String, dynamic>{
      'flutter.hp1_trial_start': '2026-09-17T10:40:00.000',
      'flutter.hp1_license_on': true,
      'flutter.hp1_license_hash': 'existing-hash-not-redeemed-or-replaced',
      'flutter.hotelpro1_customers': '[{"customerId":"CUST-0001","idFrontPhotoPath":"unchanged-base64-bytes"}]',
      'flutter.hotel_storage_photo_outbox_v3': '[{"bytes":"pending-original"}]',
      'flutter.hotel_name': 'existing hotel',
      'flutter.unknown_legacy_key': 123,
    };
    Map<String, dynamic>? saved;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'readOriginalPreferences') return jsonEncode({'preferences': original, 'rawXml': '<map>original</map>', 'metadata': {'sourceXmlSha256': 'unchanged'}});
      saved = jsonDecode(call.arguments as String) as Map<String, dynamic>;
      return {'verified': true, 'name': 'backup.json', 'bytes': 100, 'sha256': 'mock-test-hash'};
    });
    await tester.pumpWidget(const MaterialApp(home: OfflineExport()));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(calls, ['readOriginalPreferences', 'saveVerifiedBackup']);
    expect(saved!['originalPreferenceKeys'], original);
    final prefs = saved!['preferences'] as Map;
    expect(prefs['hp1_trial_start'], '2026-09-17T10:40:00.000');
    expect(prefs['hp1_license_on'], true);
    expect(prefs['hp1_license_hash'], original['flutter.hp1_license_hash']);
    expect(prefs['hotel_storage_photo_outbox_v3'], original['flutter.hotel_storage_photo_outbox_v3']);
    expect((saved!['data'] as Map).containsKey('hotelpro1_bills'), false);
    expect(saved!['missingKeys'], contains('hotelpro1_bills'));
    expect(find.textContaining('BACKUP VERIFIED'), findsOneWidget);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  testWidgets('absent license is exported as missing and never initialized', (tester) async {
    Map<String, dynamic>? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readOriginalPreferences') return jsonEncode({'preferences': {}, 'rawXml': '<map/>', 'metadata': {}});
      saved = jsonDecode(call.arguments as String) as Map<String, dynamic>;
      return {'verified': true, 'name': 'backup.json', 'bytes': 20, 'sha256': 'mock-test-hash'};
    });
    await tester.pumpWidget(const MaterialApp(home: OfflineExport()));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(saved!['preferences'], isEmpty);
    expect(saved!['data'], isEmpty);
    expect(saved!['missingKeys'], contains('hp1_trial_start'));
    expect(saved!['missingKeys'], contains('hp1_license_on'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}

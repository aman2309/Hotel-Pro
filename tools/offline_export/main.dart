import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Standalone temporary entry point. No normal main, license, auth or sync imports.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: OfflineExport()));
}

class OfflineExport extends StatefulWidget {
  const OfflineExport({super.key});
  @override
  State<OfflineExport> createState() => _OfflineExportState();
}

class _OfflineExportState extends State<OfflineExport> {
  static const channel = MethodChannel('hotel_pro/offline_export');
  bool busy = false;
  String message = 'यह केवल पुरानी preferences पढ़कर backup बनाता है।\n'
      'होटल डेटा, trial और activation नहीं बदले जाएँगे।\n'
      'Airplane mode चालू और Wi-Fi बंद रखें।';

  Future<void> export() async {
    setState(() { busy = true; });
    try {
      final raw = await channel.invokeMethod<String>('readOriginalPreferences');
      if (raw == null) throw StateError('Preferences response missing');
      final native = jsonDecode(raw) as Map<String, dynamic>;
      final original = native['preferences'] as Map<String, dynamic>;
      final decoded = <String, dynamic>{
        for (final e in original.entries)
          e.key.startsWith('flutter.') ? e.key.substring(8) : e.key: e.value,
      };
      final backup = <String, dynamic>{
        'app': 'Hotel Pro 1',
        'backupVersion': 2,
        'backupMode': 'offline-full-preferences',
        'backupDateTime': DateTime.now().toIso8601String(),
        'nativeMetadata': native['metadata'],
        'rawFlutterPreferencesXml': native['rawXml'],
        'originalPreferenceKeys': original,
        'preferences': decoded,
        'data': {
          for (final key in ['hotelpro1_rooms', 'hotelpro1_bills',
            'hotelpro1_customers', 'hotelpro1_expenses'])
            if (decoded.containsKey(key)) key: decoded[key],
        },
        'missingKeys': [
          for (final key in ['hotelpro1_rooms', 'hotelpro1_bills',
            'hotelpro1_customers', 'hotelpro1_expenses', 'hp1_trial_start',
            'hp1_license_on', 'hp1_license_hash'])
            if (!decoded.containsKey(key)) key,
        ],
      };
      final response = await channel.invokeMethod<Map<Object?, Object?>>(
        'saveVerifiedBackup', jsonEncode(backup),
      );
      if (response == null || response['verified'] != true) {
        throw StateError('Saved backup could not be read back');
      }
      if (!mounted) return;
      setState(() {
        message = 'BACKUP VERIFIED\n\nDownloads/HotelProRecovery/\n'
            '${response['name']}\n\n${response['bytes']} bytes\n'
            'SHA-256: ${response['sha256']}\n\n'
            'अब Mac पर copy और तुलना कराएँ।';
      });
    } catch (error) {
      if (mounted) setState(() { message = 'BACKUP FAILED\n$error\nपुराना डेटा नहीं बदला।'; });
    } finally {
      if (mounted) setState(() { busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hotel Pro 1 — Offline Backup')),
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: SingleChildScrollView(child: SelectableText(message))),
        ElevatedButton(onPressed: busy ? null : export,
          child: Text(busy ? 'Backup बन रहा है…' : 'सुरक्षित पूरा backup बनाएँ')),
      ]),
    )),
  );
}

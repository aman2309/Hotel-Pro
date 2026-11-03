import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production app cannot reach cPanel or device business persistence', () {
    final pending = [File('lib/main.dart').absolute];
    final visited = <String>{};
    final imports = RegExp("(?:import|export) ['\"]([^'\"]+)['\"]");
    while (pending.isNotEmpty) {
      final file = pending.removeLast();
      final path = file.resolveSymbolicLinksSync();
      if (!visited.add(path)) continue;
      expect(path, isNot(contains('cpanel_')), reason: path);
      expect(path, isNot(endsWith('backend_config.dart')), reason: path);
      expect(
        path,
        isNot(endsWith('hotel_floor_service.dart')),
        reason: 'Rooms no longer depend on floor queries',
      );
      final source = file.readAsStringSync();
      expect(source, isNot(contains('package:http/')), reason: path);
      if (!path.endsWith('otp_request_gate.dart')) {
        expect(source, isNot(contains('shared_preferences/')), reason: path);
        expect(
          source,
          isNot(contains('flutter_secure_storage/')),
          reason: path,
        );
      }
      for (final match in imports.allMatches(source)) {
        final uri = match.group(1)!;
        if (!uri.contains(':')) {
          pending.add(File.fromUri(file.uri.resolve(uri)));
        }
      }
    }
    expect(visited.length, greaterThan(40));
  });
}

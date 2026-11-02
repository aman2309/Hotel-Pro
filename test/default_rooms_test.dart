import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/data/default_rooms.dart';

void main() {
  test('default rooms match the original shared configuration', () {
    final List<dynamic> raw =
        jsonDecode(File('shared/default_rooms.json').readAsStringSync()) as List<dynamic>;
    expect(kDefaultRoomSpecs, hasLength(raw.length));
    for (var i = 0; i < raw.length; i++) {
      final Map<String, dynamic> spec = Map<String, dynamic>.from(raw[i] as Map);
      expect(kDefaultRoomSpecs[i].roomNumber, spec['roomNumber']);
      expect(kDefaultRoomSpecs[i].roomType, spec['roomType']);
      expect(kDefaultRoomSpecs[i].normalRent, spec['normalRent']);
    }
  });
}

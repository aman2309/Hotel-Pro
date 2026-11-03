/// Temporary UI state while a server transaction is being edited.
/// Business records never go into device preferences; there is no disk fallback.
/// Firebase Auth manages its own sign-in tokens separately.
class HotelDataBuffer {
  HotelDataBuffer._();
  static const bool cloudOnly = true;
  static final Map<String, Object> _memory = {};

  static Future<HotelDataBuffer> getInstance() async => HotelDataBuffer._();

  static Map<String, Object> checkpoint() => Map.of(_memory);
  static void restoreCheckpoint(Map<String, Object> snapshot) {
    _memory
      ..clear()
      ..addAll(snapshot);
  }

  static void clearSession() => _memory.clear();

  Object? get(String key) => _memory[key];

  String? getString(String key) => _memory[key] as String?;
  int? getInt(String key) => _memory[key] as int?;
  double? getDouble(String key) => _memory[key] as double?;
  bool? getBool(String key) => _memory[key] as bool?;
  Set<String> getKeys() => _memory.keys.toSet();
  bool containsKey(String key) => _memory.containsKey(key);
  Future<bool> setString(String key, String value) async {
    _memory[key] = value;
    return true;
  }

  Future<bool> setInt(String key, int value) async {
    _memory[key] = value;
    return true;
  }

  Future<bool> setDouble(String key, double value) async {
    _memory[key] = value;
    return true;
  }

  Future<bool> setBool(String key, bool value) async {
    _memory[key] = value;
    return true;
  }

  Future<bool> remove(String key) async {
    _memory.remove(key);
    return true;
  }
}

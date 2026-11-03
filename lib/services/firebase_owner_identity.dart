/// Email users can have null OR empty phoneNumber after native session restore.
/// Contact mobile entered at signup is never a verified phone-index identity.
String? verifiedPhoneIndexKey(String? phoneNumber) {
  final digits = (phoneNumber ?? '').replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? null : digits;
}

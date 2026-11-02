import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class IdCardScan {
  const IdCardScan({this.name, this.idNumber, this.address});

  final String? name;
  final String? idNumber;
  final String? address;

  bool get isEmpty =>
      (name == null || name!.trim().isEmpty) &&
      (idNumber == null || idNumber!.trim().isEmpty) &&
      (address == null || address!.trim().isEmpty);
}

class IdCardOcr {
  static const MethodChannel _channel = MethodChannel('hotel_pro/ocr');

  static const List<String> _placeWords = [
    'village',
    'vill',
    'dist',
    'district',
    'tehsil',
    'taluka',
    'taluk',
    'nagar',
    'colony',
    'road',
    'street',
    'near',
    'post',
    'thana',
    'house',
    'plot',
    'ward',
    'mohalla',
    'galli',
    'lane',
    'block',
    'sector',
    'city',
    'town',
    'state',
    'pradesh',
    'pin',
    'pincode',
    'po ',
    'p.o',
    'ps ',
    'p.s',
  ];

  static Future<IdCardScan> scanFile(String path) async {
    if (path.trim().isEmpty) {
      return const IdCardScan();
    }

    try {
      final String text =
          await _channel.invokeMethod<String>('recognizeText', path) ?? '';
      return parse(text);
    } catch (error) {
      debugPrint('ID OCR failed: $error');
      return const IdCardScan();
    }
  }

  static Future<IdCardScan> scanBytes(Uint8List bytes) async {
    final File file = File(
      '${Directory.systemTemp.path}/id_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    try {
      return scanFile(file.path);
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  static IdCardScan parse(String rawText) {
    final List<String> lines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    return IdCardScan(
      idNumber: _idNumberFrom(rawText),
      name: _nameFrom(lines),
      address: _addressFrom(lines),
    );
  }

  static bool shouldReplaceName(String current, String? incoming) {
    final String next = incoming?.trim() ?? '';
    if (next.isEmpty || !_looksLikePersonName(next)) {
      return false;
    }
    final String old = current.trim();
    if (old.isEmpty) {
      return true;
    }
    if (_looksLikeAddress(old) && _looksLikePersonName(next)) {
      return true;
    }
    return _nameScore(next) >= _nameScore(old) + 4;
  }

  static bool shouldReplaceId(String current, String? incoming) {
    final String next = incoming?.trim() ?? '';
    if (next.isEmpty) {
      return false;
    }
    final String old = current.trim();
    if (old.isEmpty) {
      return true;
    }
    if (_isTrustedId(next) && !_isTrustedId(old)) {
      return true;
    }
    return false;
  }

  static bool shouldReplaceAddress(String current, String? incoming) {
    final String next = incoming?.trim() ?? '';
    if (next.isEmpty || !_looksLikeAddress(next)) {
      return false;
    }
    final String old = current.trim();
    if (old.isEmpty) {
      return true;
    }
    if (_looksLikePersonName(old) && !_looksLikeAddress(old)) {
      return true;
    }
    final int nextScore = _addressScore(next);
    final int oldScore = _addressScore(old);
    if (nextScore >= oldScore + 4) {
      return true;
    }
    return nextScore > oldScore && next.length > old.length + 12;
  }

  static String? _idNumberFrom(String rawText) {
    final String? aadhaar = _aadhaarFrom(rawText);
    if (aadhaar != null) {
      return aadhaar;
    }
    return _panFrom(rawText) ?? _voterFrom(rawText) ?? _dlFrom(rawText);
  }

  static String? _aadhaarFrom(String rawText) {
    final String compact = rawText
        .replaceAll(RegExp(r'[Oo]'), '0')
        .replaceAll(RegExp(r'[Il|]'), '1');

    final List<String> candidates = [];
    final Iterable<RegExpMatch> grouped = RegExp(
      r'(?<![0-9])(\d{4})[\s\-./]*(\d{4})[\s\-./]*(\d{4})(?![0-9])',
    ).allMatches(compact);
    for (final RegExpMatch match in grouped) {
      candidates.add('${match[1]}${match[2]}${match[3]}');
    }

    for (final Match match in RegExp(
      r'(?<![0-9])(\d{12})(?![0-9])',
    ).allMatches(compact)) {
      candidates.add(match[1]!);
    }

    final List<String> unique = [];
    for (final String digits in candidates) {
      if (_looksLikeAadhaar(digits) && !unique.contains(digits)) {
        unique.add(digits);
      }
    }

    for (final String digits in unique) {
      if (_verhoeffOk(digits)) {
        return _formatAadhaar(digits);
      }
    }

    return null;
  }

  static String _formatAadhaar(String digits) {
    return '${digits.substring(0, 4)} ${digits.substring(4, 8)} ${digits.substring(8, 12)}';
  }

  static bool _looksLikeAadhaar(String digits) {
    if (digits.length != 12) {
      return false;
    }
    if (RegExp(r'^(\d)\1{11}$').hasMatch(digits)) {
      return false;
    }
    if (digits.startsWith('0') || digits.startsWith('1')) {
      return false;
    }
    if (RegExp(
      r'^(19|20)\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])$',
    ).hasMatch(digits)) {
      return false;
    }
    return true;
  }

  static String? _panFrom(String rawText) {
    final Iterable<RegExpMatch> matches = RegExp(
      r'\b([A-Z]{5}[0-9]{4}[A-Z])\b',
    ).allMatches(rawText.toUpperCase());
    for (final RegExpMatch match in matches) {
      final String pan = match[1]!;
      if (RegExp(r'^[A-Z]{3}[PCHFATBLJ][A-Z][0-9]{4}[A-Z]$').hasMatch(pan)) {
        return pan;
      }
    }
    return matches.isEmpty ? null : matches.first[1];
  }

  static String? _voterFrom(String rawText) {
    final Match? match = RegExp(
      r'\b([A-Z]{3}[0-9]{7})\b',
    ).firstMatch(rawText.toUpperCase());
    return match?[1];
  }

  static String? _dlFrom(String rawText) {
    final Match? match = RegExp(
      r'\b([A-Z]{2}[\s-]?\d{2}[\s-]?\d{4}[\s-]?\d{5,7})\b',
    ).firstMatch(rawText.toUpperCase());
    return match?[1]?.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _isTrustedId(String value) {
    final String digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 &&
        _looksLikeAadhaar(digits) &&
        _verhoeffOk(digits)) {
      return true;
    }
    final String upper = value.toUpperCase().replaceAll(' ', '');
    return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(upper);
  }

  static String? _nameFrom(List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final Match? labeled = RegExp(
        r'^(?:name|naam|नाम)\s*[:.\-]?\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(lines[i]);
      if (labeled != null) {
        final String? name = _asPersonName(labeled[1]!);
        if (name != null) {
          return name;
        }
      }
    }

    for (int i = 0; i < lines.length; i++) {
      if (!_isNameAnchor(lines[i])) {
        continue;
      }
      for (int j = i + 1; j < lines.length && j <= i + 3; j++) {
        final String? name = _asPersonName(lines[j]);
        if (name != null) {
          return name;
        }
      }
    }

    for (int i = 0; i < lines.length; i++) {
      if (!_isGenderOrDob(lines[i]) || i == 0) {
        continue;
      }
      final String? name = _asPersonName(lines[i - 1]);
      if (name != null) {
        return name;
      }
      if (i >= 2) {
        final String? hindiThenEnglish =
            _asPersonName(lines[i - 1], allowHindi: false) ??
            _asPersonName(lines[i - 2]);
        if (hindiThenEnglish != null) {
          return hindiThenEnglish;
        }
      }
    }

    String? best;
    int bestScore = 4;
    for (int i = 0; i < lines.length; i++) {
      final String? name = _asPersonName(lines[i]);
      if (name == null) {
        continue;
      }
      int score = _nameScore(name);
      if (i + 1 < lines.length && _isGenderOrDob(lines[i + 1])) {
        score += 6;
      }
      if (i > 0 && _isNameAnchor(lines[i - 1])) {
        score += 6;
      }
      if (score > bestScore) {
        bestScore = score;
        best = name;
      }
    }
    return best;
  }

  static bool _isNameAnchor(String line) {
    final String lower = line.toLowerCase().trim();
    return RegExp(r'^(name|naam|to|नाम)$').hasMatch(lower);
  }

  static bool _isGenderOrDob(String line) {
    final String lower = line.toLowerCase();
    return RegExp(
      r'\b(male|female|transgender|dob|date of birth|year of birth|जन्म)\b',
    ).hasMatch(lower);
  }

  static String? _asPersonName(String line, {bool allowHindi = true}) {
    if (_isBoilerplate(line) ||
        _isGenderOrDob(line) ||
        _looksLikeRelation(line)) {
      return null;
    }
    if (RegExp(r'\d{3,}').hasMatch(line)) {
      return null;
    }

    final String cleaned = line
        .replaceAll(
          RegExp(r'^(name|naam|to|नाम)\s*[:.\-]?\s*', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r"[^A-Za-z\u0900-\u097F .']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.length < 3 || cleaned.length > 42) {
      return null;
    }

    final int words = cleaned
        .split(' ')
        .where((word) => word.isNotEmpty)
        .length;
    if (words < 1 || words > 4) {
      return null;
    }
    if (_looksLikeAddress(cleaned)) {
      return null;
    }

    final bool hindi = RegExp(r'^[\u0900-\u097F .]+$').hasMatch(cleaned);
    if (hindi) {
      if (!allowHindi || cleaned.replaceAll(' ', '').length < 4) {
        return null;
      }
      return cleaned;
    }

    if (!RegExp(r"^[A-Za-z][A-Za-z .']{1,40}$").hasMatch(cleaned)) {
      return null;
    }
    if (cleaned.replaceAll(' ', '').length < 4) {
      return null;
    }
    if (_nameScore(cleaned) < 3) {
      return null;
    }
    return cleaned.toUpperCase();
  }

  static int _nameScore(String value) {
    final String cleaned = value.trim();
    if (cleaned.isEmpty) {
      return 0;
    }
    final List<String> words = cleaned
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    int score = 0;
    if (words.length >= 2 && words.length <= 4) {
      score += 6;
    } else if (words.length == 1 && cleaned.length >= 5) {
      score += 2;
    } else {
      score -= 4;
    }
    if (_looksLikeAddress(cleaned)) {
      score -= 10;
    }
    if (_looksLikePersonName(cleaned)) {
      score += 4;
    }
    for (final String word in words) {
      if (word.length <= 1) {
        score -= 3;
      }
    }
    return score;
  }

  static bool _looksLikePersonName(String value) {
    final String cleaned = value
        .replaceAll(RegExp(r"[^A-Za-z\u0900-\u097F .']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.length < 3 || cleaned.length > 42) {
      return false;
    }
    if (_looksLikeAddress(cleaned) ||
        _looksLikeRelation(cleaned) ||
        _isBoilerplate(cleaned)) {
      return false;
    }
    final int words = cleaned.split(' ').length;
    return words >= 1 && words <= 4;
  }

  static bool _looksLikeRelation(String line) {
    return RegExp(
      r'\b(s\/o|d\/o|w\/o|c\/o|s\.o|d\.o|w\.o|c\.o|son of|wife of|daughter of)\b',
      caseSensitive: false,
    ).hasMatch(line);
  }

  static bool _looksLikeAddress(String value) {
    final String lower = value.toLowerCase();
    if (_looksLikeRelation(lower)) {
      return true;
    }
    if (RegExp(r'\b\d{6}\b').hasMatch(value)) {
      return true;
    }
    if (RegExp(r'\d{1,4}\s*[/\-]').hasMatch(value) && value.length > 12) {
      return true;
    }
    int hits = 0;
    for (final String word in _placeWords) {
      if (lower.contains(word)) {
        hits += 1;
      }
    }
    return hits >= 1 && value.split(RegExp(r'\s+')).length >= 3;
  }

  static int _addressScore(String value) {
    final String lower = value.toLowerCase();
    int score = 0;
    if (_looksLikeRelation(lower)) {
      score += 6;
    }
    if (RegExp(r'\b\d{6}\b').hasMatch(value)) {
      score += 8;
    }
    for (final String word in _placeWords) {
      if (lower.contains(word)) {
        score += 2;
      }
    }
    if (value.length > 24) {
      score += 2;
    }
    if (value.length > 50) {
      score += 2;
    }
    return score;
  }

  static bool _isBoilerplate(String line) {
    final String lower = line.toLowerCase();
    const List<String> phrases = [
      'government of india',
      'unique identification',
      'authority of india',
      'government',
      'bharat sarkar',
      'uidai',
      'www.',
      'help@',
      '1947',
      'download',
      'aadhaar',
      'aadhar',
      'enrollment',
      'enrolment',
      'virtual id',
      'vid ',
      'issue date',
      'govt of',
    ];
    if (phrases.any(lower.contains)) {
      return true;
    }
    return RegExp(
      r'\b(india|bharat|sarkar|uidai|male|female|dob|birth|help|enroll|mobile|www|http|govt)\b',
    ).hasMatch(lower);
  }

  static String? _addressFrom(List<String> lines) {
    int start = -1;
    for (int i = 0; i < lines.length; i++) {
      final String lower = lines[i].toLowerCase();
      if (lower.contains('address') ||
          lower.contains('पता') ||
          _looksLikeRelation(lower)) {
        start = i;
        break;
      }
    }

    if (start < 0) {
      for (int i = 0; i < lines.length; i++) {
        if (RegExp(r'\b\d{6}\b').hasMatch(lines[i]) &&
            !_isAadhaarLine(lines[i]) &&
            lines[i].replaceAll(RegExp(r'\d'), '').trim().length >= 6) {
          start = i > 0 ? i - 1 : i;
          break;
        }
      }
    }

    if (start < 0) {
      return null;
    }

    final List<String> collected = [];
    for (int i = start; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.isEmpty ||
          _isAadhaarLine(line) ||
          _isBoilerplate(line) ||
          _isGenderOrDob(line)) {
        if (_isAadhaarLine(line) ||
            line.toLowerCase().contains('unique identification')) {
          break;
        }
        continue;
      }

      line = line.replaceFirst(
        RegExp(r'^(address|पता)\s*[:.\-]?\s*', caseSensitive: false),
        '',
      );
      if (line.isEmpty) {
        continue;
      }
      if (!_looksLikeRelation(line) &&
          !_looksLikeAddress(line) &&
          _asPersonName(line) != null) {
        continue;
      }

      collected.add(line);
      if (RegExp(r'\b\d{6}\b').hasMatch(line) ||
          collected.join(' ').length > 220) {
        break;
      }
    }

    final String text = collected
        .join(', ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r',\s*,+'), ',')
        .replaceAll(RegExp(r'^[,\s]+|[,\s]+$'), '')
        .trim();

    if (text.replaceAll(RegExp(r'[^A-Za-z\u0900-\u097F0-9]'), '').length < 10) {
      return null;
    }
    if (_looksLikePersonName(text) && !_looksLikeAddress(text)) {
      return null;
    }

    return text.toUpperCase();
  }

  static bool _isAadhaarLine(String line) {
    final String digits = line.replaceAll(RegExp(r'\D'), '');
    return digits.length == 12 && _looksLikeAadhaar(digits);
  }

  static bool _verhoeffOk(String number) {
    const List<List<int>> d = [
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
      [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
      [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
      [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
      [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
      [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
      [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
      [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
      [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
      [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
    ];
    const List<List<int>> p = [
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
      [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
      [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
      [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
      [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
      [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
      [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
      [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
    ];

    int c = 0;
    final List<int> reversed = number
        .split('')
        .reversed
        .map(int.parse)
        .toList();
    for (int i = 0; i < reversed.length; i++) {
      c = d[c][p[i % 8][reversed[i]]];
    }
    return c == 0;
  }
}

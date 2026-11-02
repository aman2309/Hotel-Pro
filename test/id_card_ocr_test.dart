import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/services/id_card_ocr.dart';

String validAadhaar() {
  for (int last = 0; last <= 9; last++) {
    final String digits = '23451234567$last';
    final IdCardScan scan = IdCardOcr.parse(
      'GOVERNMENT OF INDIA\nRAJESH KUMAR\nMALE\n'
      '${digits.substring(0, 4)} ${digits.substring(4, 8)} ${digits.substring(8, 12)}',
    );
    if (scan.idNumber?.replaceAll(' ', '') == digits) {
      return digits;
    }
  }
  fail('Could not build a Verhoeff-valid Aadhaar');
}

void main() {
  late String aadhaar;

  setUpAll(() {
    aadhaar = validAadhaar();
  });

  String spaced(String digits) =>
      '${digits.substring(0, 4)} ${digits.substring(4, 8)} ${digits.substring(8, 12)}';

  test('reads Aadhaar front name, number, and skips government text', () {
    final IdCardScan scan = IdCardOcr.parse('''
GOVERNMENT OF INDIA
भारत सरकार
VIDYA SHARMA
DOB: 12/03/1991
FEMALE
${spaced(aadhaar)}
''');

    expect(scan.name, 'VIDYA SHARMA');
    expect(scan.idNumber, spaced(aadhaar));
    expect(scan.address, isNull);
  });

  test('does not treat a village line as the guest name', () {
    final IdCardScan scan = IdCardOcr.parse('''
GOVERNMENT OF INDIA
To
RAJESH KUMAR
S/O RAM KUMAR
NEAR BUS STAND VILLAGE RAMPUR
DISTRICT JAIPUR
RAJASTHAN 302001
${spaced(aadhaar)}
''');

    expect(scan.name, 'RAJESH KUMAR');
    expect(scan.idNumber, spaced(aadhaar));
    expect(scan.address, contains('S/O RAM KUMAR'));
    expect(scan.address, contains('302001'));
    expect(scan.name, isNot(contains('VILLAGE')));
  });

  test('rejects a 12-digit number that fails the Aadhaar checksum', () {
    final IdCardScan scan = IdCardOcr.parse('''
RAJESH KUMAR
MALE
9999 8888 7777
''');

    expect(scan.idNumber, isNull);
    expect(scan.name, 'RAJESH KUMAR');
  });


  test('reads PAN instead of inventing an Aadhaar', () {
    final IdCardScan scan = IdCardOcr.parse('''
INCOME TAX DEPARTMENT
GOVT OF INDIA
Permanent Account Number
ABCDE1234F
Name
ANITA DEVI
''');

    expect(scan.idNumber, 'ABCDE1234F');
    expect(scan.name, 'ANITA DEVI');
  });

  test('back photo address replaces a front-photo name leftover', () {
    expect(
      IdCardOcr.shouldReplaceAddress(
        'RAJESH KUMAR',
        'S/O RAM KUMAR, VILLAGE RAMPUR, JAIPUR 302001',
      ),
      isTrue,
    );
    expect(
      IdCardOcr.shouldReplaceName(
        'NEAR BUS STAND VILLAGE RAMPUR',
        'RAJESH KUMAR',
      ),
      isTrue,
    );
    expect(
      IdCardOcr.shouldReplaceName('RAJESH KUMAR', 'NEAR BUS STAND VILLAGE'),
      isFalse,
    );
  });

  test('does not overwrite a valid Aadhaar with weaker text', () {
    expect(
      IdCardOcr.shouldReplaceId(spaced(aadhaar), 'ABCDE1234F'),
      isFalse,
    );
    expect(
      IdCardOcr.shouldReplaceId('1234', spaced(aadhaar)),
      isTrue,
    );
  });
}

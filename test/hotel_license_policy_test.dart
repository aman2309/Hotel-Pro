import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/services/hotel_license_policy.dart';

void main() {
  test('only reviewed administrator reset allows returning fresh setup', () {
    requireVerifiedLicenseOrigin(
      cloudLicenseExists: false,
      createdBusinessThisSession: false,
      administratorApprovedReset: true,
    );
  });
  test(
    'reinstall of returning hotel cannot silently restart missing trial',
    () {
      expect(
        () => requireVerifiedLicenseOrigin(
          cloudLicenseExists: false,
          createdBusinessThisSession: false,
        ),
        throwsStateError,
      );
    },
  );
  test('verified new hotel can establish its first trial', () {
    requireVerifiedLicenseOrigin(
      cloudLicenseExists: false,
      createdBusinessThisSession: true,
    );
  });
  test('returning hotel keeps its existing cloud trial and activation', () {
    requireVerifiedLicenseOrigin(
      cloudLicenseExists: true,
      createdBusinessThisSession: false,
    );
  });

  test('missing license is not a new trial', () {
    final HotelLicenseAssessment assessment = assessHotelLicense(
      readFailed: false,
      documentExists: false,
      trialStart: null,
      activated: false,
      now: DateTime.utc(2026, 10, 23),
    );
    expect(assessment.view, HotelLicenseView.missing);
  });

  test('annual license shows expiry and remaining time', () {
    final HotelLicenseAssessment assessment = assessHotelLicense(
      readFailed: false,
      documentExists: true,
      trialStart: DateTime.utc(2026, 1, 1),
      activated: true,
      now: DateTime.utc(2026, 10, 23, 6),
      expiresAt: DateTime.utc(2027, 10, 23, 6),
    );
    expect(assessment.view, HotelLicenseView.activated);
    expect(assessment.message, contains('23 Oct 2027'));
    expect(assessment.message, contains('365 din'));
    expect(assessment.message, contains('Renew with a license key'));
  });

  test('expired license asks for a PIN and keeps the record readable', () {
    final HotelLicenseAssessment assessment = assessHotelLicense(
      readFailed: false,
      documentExists: true,
      trialStart: DateTime.utc(2026, 1, 1),
      activated: false,
      now: DateTime.utc(2026, 1, 12),
      trialEndsAt: DateTime.utc(2026, 1, 11),
    );
    expect(assessment.view, HotelLicenseView.expired);
    expect(assessment.message, contains('License key'));
  });

  test('29 February display uses the dated expiry', () {
    final String label = formatLicenseDate(DateTime.utc(2029, 2, 28, 8, 30));
    expect(label, '28 Feb 2029');
  });
}

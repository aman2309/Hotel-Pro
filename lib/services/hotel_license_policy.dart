enum HotelLicenseView { missing, trial, expired, activated, unreadable }

class HotelLicenseAssessment {
  const HotelLicenseAssessment(this.view, this.message);

  final HotelLicenseView view;
  final String message;
}

String formatLicenseRemaining(Duration left) {
  if (left <= Duration.zero) return '0 minute baki';
  if (left.inDays >= 1) {
    return '${left.inDays} din ${left.inHours % 24} ghante baki';
  }
  return '${left.inHours} ghante ${left.inMinutes % 60} minute baki';
}

String formatLicenseDate(DateTime date) {
  const months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final DateTime utc = date.toUtc();
  return '${utc.day} ${months[utc.month - 1]} ${utc.year}';
}

/// Reads an existing license. Never invents a trial start.
HotelLicenseAssessment assessHotelLicense({
  required bool readFailed,
  required bool documentExists,
  required DateTime? trialStart,
  required bool activated,
  required DateTime now,
  int trialDays = 10,
  DateTime? trialEndsAt,
  DateTime? expiresAt,
}) {
  if (readFailed) {
    return const HotelLicenseAssessment(
      HotelLicenseView.unreadable,
      'License could not be read. Retry. No trial was started.',
    );
  }
  if (!documentExists) {
    return const HotelLicenseAssessment(
      HotelLicenseView.missing,
      'Cloud license record is missing. Trial was not restarted.',
    );
  }
  if (expiresAt != null && now.isBefore(expiresAt)) {
    final Duration left = expiresAt.difference(now);
    return HotelLicenseAssessment(
      HotelLicenseView.activated,
      'License ${formatLicenseDate(expiresAt)} tak. ${formatLicenseRemaining(left)}. Renew with PIN',
    );
  }
  if (expiresAt != null || (activated && expiresAt == null)) {
    return const HotelLicenseAssessment(
      HotelLicenseView.expired,
      'License khatam. Renew with PIN. Purana data safe hai.',
    );
  }
  final DateTime? trialEnd =
      trialEndsAt ?? trialStart?.add(Duration(days: trialDays));
  if (trialEnd != null && now.isBefore(trialEnd)) {
    return HotelLicenseAssessment(
      HotelLicenseView.trial,
      'Trial ${formatLicenseRemaining(trialEnd.difference(now))}',
    );
  }
  if (trialEnd != null) {
    return const HotelLicenseAssessment(
      HotelLicenseView.expired,
      'Trial khatam. 8 digit PIN daalein. Purana data safe hai.',
    );
  }
  return const HotelLicenseAssessment(
    HotelLicenseView.missing,
    'Cloud license record is missing. Trial was not restarted.',
  );
}

/// A fresh device is not evidence that an existing hotel's trial is new.
void requireVerifiedLicenseOrigin({
  required bool cloudLicenseExists,
  required bool createdBusinessThisSession,
  bool administratorApprovedReset = false,
}) {
  if (!cloudLicenseExists &&
      !createdBusinessThisSession &&
      !administratorApprovedReset) {
    throw StateError(
      'पुराने होटल का cloud trial/PIN record नहीं मिला। सुरक्षित backup से '
      'activation recovery की समीक्षा जरूरी है। नया trial शुरू नहीं किया गया।',
    );
  }
}

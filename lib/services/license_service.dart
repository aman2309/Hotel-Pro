import 'package:cloud_firestore/cloud_firestore.dart';
import 'hotel_firestore_service.dart';
import 'hotel_license_policy.dart';
import 'hotel_license_client.dart';
import 'phone_auth_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'hotel_data_buffer.dart';

/// Firebase-managed trial and month/year license keys for Hotel Pro.
class LicenseService extends ChangeNotifier {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  static const _kStart = 'hp1_trial_start';
  static const _kOn = 'hp1_license_on';
  static const _kDevice = 'hp1_license_device';
  static const _kPinHash = 'hp1_license_hash';
  static const trialDays = 10;
  static const buildStamp = 'HP1_SALE_1001';

  bool loaded = false;
  bool activated = false;
  DateTime? trialStart;
  DateTime? trialEndsAt;
  DateTime? expiresAt;

  /// Paid plan name from the redeemed key, e.g. "3 months".
  String planLabel = '';
  String statusMessage = '';
  String? lastError;
  String? pinHash;
  HotelLicenseView cloudView = HotelLicenseView.unreadable;

  bool get canEditHotel =>
      cloudView == HotelLicenseView.trial ||
      cloudView == HotelLicenseView.activated;

  bool get opensHotel =>
      cloudView == HotelLicenseView.trial ||
      cloudView == HotelLicenseView.activated ||
      cloudView == HotelLicenseView.missing ||
      cloudView == HotelLicenseView.expired;

  Duration get trialLength => const Duration(days: trialDays);

  DateTime? get trialEnd => trialStart?.add(trialLength);

  Duration get remaining {
    final DateTime? end = expiresAt ?? trialEndsAt ?? trialEnd;
    if (end == null) return Duration.zero;
    final Duration left = end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  int get daysLeft {
    final Duration left = remaining;
    if (left <= Duration.zero) return 0;
    final int days = left.inDays;
    return days > 0 ? days : 1;
  }

  bool get expired => cloudView == HotelLicenseView.expired;

  bool get canUseApp => opensHotel;

  String get statusLine {
    if (statusMessage.isNotEmpty) return statusMessage;
    if (cloudView == HotelLicenseView.missing) {
      return 'License missing. Trial was not restarted.';
    }
    if (cloudView == HotelLicenseView.unreadable) {
      return 'License could not be read. Retry.';
    }
    if (activated && expiresAt != null) {
      return 'License ${formatLicenseDate(expiresAt!)} tak. ${formatLicenseRemaining(remaining)}. Renew with a license key';
    }
    if (expired) {
      return 'License khatam. Renew with a license key. Purana data safe hai.';
    }
    if (trialStart == null) return 'Trial shuru nahi hui';
    return 'Trial ${formatLicenseRemaining(remaining)}';
  }

  String get warningLine {
    if (cloudView == HotelLicenseView.activated) return statusLine;
    if (cloudView == HotelLicenseView.missing ||
        cloudView == HotelLicenseView.unreadable ||
        expired) {
      return statusLine;
    }
    return 'Free trial: $statusLine.';
  }

  /// English, Hindi, and Arabic-Indic digits → 0-9.
  static String asciiDigits(String raw) {
    const devanagari = '०१२३४५६७८९';
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    final buf = StringBuffer();
    for (final r in raw.runes) {
      if (r >= 48 && r <= 57) {
        buf.writeCharCode(r);
        continue;
      }
      final c = String.fromCharCode(r);
      var i = devanagari.indexOf(c);
      if (i >= 0) {
        buf.write(i);
        continue;
      }
      i = arabicIndic.indexOf(c);
      if (i >= 0) buf.write(i);
    }
    return buf.toString();
  }

  Future<void> init() async {
    try {
      final prefs = await HotelDataBuffer.getInstance();
      activated = prefs.getBool(_kOn) ?? false;
      pinHash = prefs.getString(_kPinHash);
      final startRaw = prefs.getString(_kStart);
      if (startRaw != null) {
        trialStart = DateTime.tryParse(startRaw);
      }
      if ((prefs.getString(_kDevice) ?? '').isEmpty) {
        await prefs.setString(
          _kDevice,
          'hp1_${DateTime.now().millisecondsSinceEpoch}',
        );
      }
    } catch (_) {}
    loaded = true;
    notifyListeners();
  }

  void reportFailure(String message) {
    lastError = message;
    notifyListeners();
  }

  /// Server read only. Does not create or restart a trial.
  Future<void> readCloudLicense(String businessId) async {
    try {
      final snap = await HotelFirestoreService.instance
          .col(businessId, 'settings')
          .doc('license')
          .get(const GetOptions(source: Source.server));
      final data = snap.data();
      final start = data?['trialStart'];
      final end = data?['trialEndsAt'];
      final expiry = data?['expiresAt'];
      final DateTime? cloudStart = start is Timestamp ? start.toDate() : null;
      final DateTime? cloudTrialEnd = end is Timestamp ? end.toDate() : null;
      final DateTime? cloudExpiry = expiry is Timestamp
          ? expiry.toDate()
          : null;
      final bool cloudActivated =
          data?['activated'] == true &&
          const [
            'hotelpro-license-server-v1',
            'hotelpro-license-server-v2',
          ].contains(data?['issuer']);
      final HotelLicenseAssessment assessment = assessHotelLicense(
        readFailed: false,
        documentExists: snap.exists,
        trialStart: cloudStart,
        activated: cloudActivated,
        now: DateTime.now(),
        trialDays: trialDays,
        trialEndsAt: cloudTrialEnd,
        expiresAt: cloudExpiry,
      );
      cloudView = assessment.view;
      statusMessage = assessment.message;
      expiresAt = cloudExpiry;
      planLabel = '${data?['planLabel'] ?? ''}'.trim();
      trialEndsAt = cloudTrialEnd;
      activated = assessment.view == HotelLicenseView.activated;
      if (cloudStart != null &&
          (assessment.view == HotelLicenseView.trial ||
              assessment.view == HotelLicenseView.expired ||
              assessment.view == HotelLicenseView.activated)) {
        trialStart = cloudStart;
      }
      lastError =
          assessment.view == HotelLicenseView.trial ||
              assessment.view == HotelLicenseView.activated
          ? null
          : assessment.message;
    } catch (error) {
      final HotelLicenseAssessment assessment = assessHotelLicense(
        readFailed: true,
        documentExists: false,
        trialStart: null,
        activated: false,
        now: DateTime.now(),
      );
      cloudView = assessment.view;
      statusMessage = assessment.message;
      lastError = assessment.message;
      debugPrint('[LICENSE] read failed: $error');
    }
    notifyListeners();
  }

  /// One permanent trial/activation record per verified business.
  Future<void> bindBusiness(String businessId) async {
    final prefs = await HotelDataBuffer.getInstance();
    final ref = HotelFirestoreService.instance
        .col(businessId, 'settings')
        .doc('license');
    final data = await FirebaseFirestore.instance.runTransaction((
      transaction,
    ) async {
      final snap = await transaction.get(ref);
      final existing = snap.data();
      final business = await transaction.get(
        HotelFirestoreService.instance.businessDoc(businessId),
      );
      requireVerifiedLicenseOrigin(
        cloudLicenseExists: existing != null,
        createdBusinessThisSession: HotelFirestoreService.instance
            .wasBusinessCreatedThisSession(businessId),
        administratorApprovedReset: false,
      );
      if (existing != null) {
        if (existing['trialStart'] is! Timestamp) {
          throw StateError(
            'Cloud trial date needs recovery review. Local activation is unchanged.',
          );
        }
        return existing;
      }
      final origin =
          business.data()?['dataResetAt'] ?? business.data()?['createdAt'];
      if (origin is! Timestamp) {
        throw StateError(
          'Verified hotel trial date is missing. Review required.',
        );
      }
      final initial = <String, dynamic>{
        'trialStart': origin,
        'activated': false,
        'pinHash': null,
        'setupVersion': 1,
        'createdAt': FieldValue.serverTimestamp(),
      };
      transaction.set(ref, initial);
      return initial;
    });
    // Resolve the server timestamp; client clocks never establish a new trial.
    final persisted =
        (await ref.get(const GetOptions(source: Source.server))).data() ?? data;
    final cloudStart = (persisted['trialStart'] as Timestamp).toDate();
    trialStart = cloudStart;
    activated =
        persisted['activated'] == true &&
        const [
          'hotelpro-license-server-v1',
          'hotelpro-license-server-v2',
        ].contains(persisted['issuer']) &&
        persisted['expiresAt'] is Timestamp &&
        (persisted['expiresAt'] as Timestamp).toDate().isAfter(DateTime.now());
    pinHash = activated ? persisted['pinHash'] as String? : null;
    await prefs.setString('hp1_license_owner_uid', PhoneAuthSession.uid!);
    await prefs.setString(_kStart, cloudStart.toIso8601String());
    await prefs.setBool(_kOn, activated);
    if (pinHash != null) await prefs.setString(_kPinHash, pinHash!);
    notifyListeners();
  }

  Future<bool> redeem(String rawPin) async {
    lastError = null;
    final key = rawPin.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^HP[A-F0-9]{32}$').hasMatch(key)) {
      lastError = 'Enter a valid Hotel Pro license key (HP-…).';
      notifyListeners();
      return false;
    }
    if (cloudView == HotelLicenseView.unreadable) {
      lastError = 'License read ke bina key activate nahi hoga.';
      notifyListeners();
      return false;
    }
    final String? businessId =
        PhoneAuthSession.businessId ??
        HotelFirestoreService.instance.businessId;
    if (businessId == null || businessId.isEmpty) {
      lastError = 'Hotel mapping missing. Key se naya hotel nahi banta.';
      notifyListeners();
      return false;
    }
    try {
      final Map<String, dynamic> result = await HotelLicenseClient.instance
          .redeem(key);
      if (result['activated'] != true || result['businessId'] != businessId) {
        lastError = 'Activation unsuccessful. Try later or contact the seller.';
        notifyListeners();
        return false;
      }
      await readCloudLicense(businessId);
      return cloudView == HotelLicenseView.activated;
    } on FirebaseFunctionsException catch (error) {
      lastError = error.code == 'resource-exhausted'
          ? 'Bahut attempts. Thodi der baad try karein.'
          : (error.message ??
                'Key activate nahi hui. Contact your administrator.');
      notifyListeners();
      return false;
    }
  }
}

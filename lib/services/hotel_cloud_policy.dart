/// First-run / restore / push decisions. Pure logic so tests can cover A–J.
class HotelCloudPolicy {
  const HotelCloudPolicy();

  static const int schemaVersion = 3;

  bool localHasHotelData({
    required bool roomsMissingOrEmpty,
    required int roomCount,
    required int billCount,
    required int guestCount,
    required int expenseCount,
    required bool anyOccupiedOrClosedRoom,
    bool looksLikeFreshDefault = false,
  }) {
    if (looksLikeFreshDefault &&
        billCount == 0 &&
        guestCount == 0 &&
        expenseCount == 0) {
      return false;
    }
    if (!roomsMissingOrEmpty &&
        roomCount > 0 &&
        (billCount > 0 ||
            guestCount > 0 ||
            expenseCount > 0 ||
            anyOccupiedOrClosedRoom)) {
      return true;
    }
    if (!roomsMissingOrEmpty && roomCount > 0) {
      return true;
    }
    return billCount > 0 || guestCount > 0 || expenseCount > 0;
  }

  bool cloudHasHotelData({
    required bool migrationCompleted,
    required int liveRoomCount,
    required int liveBillCount,
    required int liveGuestCount,
  }) {
    if (migrationCompleted) {
      return true;
    }
    return liveRoomCount > 0 || liveBillCount > 0 || liveGuestCount > 0;
  }

  HotelCloudBootstrapAction decide({
    required bool localHasData,
    required bool cloudHasData,
    required bool localMigrationCompleted,
  }) {
    if (cloudHasData && !localHasData) {
      return HotelCloudBootstrapAction.restore;
    }
    if (!cloudHasData && localHasData) {
      return HotelCloudBootstrapAction.migrate;
    }
    if (cloudHasData && localHasData) {
      if (!localMigrationCompleted) {
        return HotelCloudBootstrapAction.restore;
      }
      return HotelCloudBootstrapAction.incrementalSync;
    }
    return HotelCloudBootstrapAction.idle;
  }

  bool allowPushToCloud({
    required bool cloudHasData,
    required bool localHasData,
    required bool restoreFailed,
  }) {
    if (cloudHasData && !localHasData) {
      return false;
    }
    if (cloudHasData && restoreFailed && !localHasData) {
      return false;
    }
    return true;
  }

  /// Local records with no verified owner, or with a different owner, are
  /// archived and kept off the signed-in hotel. They are never a migration.
  bool quarantineUnownedLocal({
    required bool hasLocalHotelData,
    required String? localOwnerUid,
    required String? localBusinessId,
    required String sessionUid,
    required String sessionBusinessId,
  }) {
    if (!hasLocalHotelData) return false;
    final String owner = (localOwnerUid ?? '').trim();
    final String business = (localBusinessId ?? '').trim();
    if (owner.isEmpty || business.isEmpty) return true;
    return owner != sessionUid || business != sessionBusinessId;
  }

  /// A failed cloud read is not an empty hotel and must not start migration.
  bool readFailureIsEmptyHotel() => false;

  /// Last valid writer wins. Equal timestamps keep cloud (no silent clobber).
  bool localWinsConflict({
    required int localUpdatedAtMs,
    required int? cloudUpdatedAtMs,
  }) {
    if (cloudUpdatedAtMs == null) {
      return true;
    }
    return localUpdatedAtMs > cloudUpdatedAtMs;
  }
}

enum HotelCloudBootstrapAction { migrate, restore, incrementalSync, idle }

/// Whether a stored photo may be replaced. A mismatch or a failed read keeps
/// the original cloud bytes.
enum PhotoUploadChoice { uploadNew, keepOriginal, retryRead }

PhotoUploadChoice choosePhotoUpload({
  required bool readFailed,
  required bool missing,
  required String? remoteSha,
  required String localSha,
}) {
  if (readFailed) return PhotoUploadChoice.retryRead;
  if (missing) return PhotoUploadChoice.uploadNew;
  if (remoteSha != null && remoteSha == localSha) {
    return PhotoUploadChoice.keepOriginal;
  }
  return PhotoUploadChoice.keepOriginal;
}

bool photoMetadataMismatched({
  required bool missing,
  required bool readFailed,
  required String? remoteSha,
  required String localSha,
}) =>
    !missing &&
    !readFailed &&
    remoteSha != null &&
    localSha.isNotEmpty &&
    remoteSha != localSha;

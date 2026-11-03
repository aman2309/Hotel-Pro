import '../theme/custom_colors.dart';
import 'package:flutter/material.dart';

import '../services/hotel_cloud_sync_service.dart';
import '../services/hotel_photo_storage_service.dart';

/// Compact AppBar chip. Does not change dashboard layout.
class HotelCloudStatusChip extends StatelessWidget {
  const HotelCloudStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        HotelCloudSyncService.instance,
        HotelPhotoStorageService.instance,
      ]),
      builder: (BuildContext context, _) {
        final HotelCloudSyncService sync = HotelCloudSyncService.instance;
        final photos = HotelPhotoStorageService.instance;
        final _ChipLook look =
            photos.hasRestoreFailures ||
                photos.lastPhotoError != null ||
                photos.pendingUploadCount > 0
            ? const _ChipLook(
                'Photos pending',
                Icons.photo_rounded,
                CustomColors.booked,
              )
            : _look(sync.status);
        return Tooltip(
          message: sync.lastError ?? photos.lastPhotoError ?? look.label,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: ActionChip(
              onPressed: () {
                HotelCloudSyncService.instance.retry();
              },
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: look.color.withValues(alpha: 0.18),
              side: BorderSide(color: look.color),
              label: Text(
                look.label,
                style: TextStyle(
                  color: CustomColors.button,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              avatar: Icon(look.icon, size: 14, color: CustomColors.button),
            ),
          ),
        );
      },
    );
  }

  _ChipLook _look(HotelCloudStatus status) {
    switch (status) {
      case HotelCloudStatus.synced:
        return const _ChipLook(
          'Synced',
          Icons.cloud_done_rounded,
          CustomColors.primary,
        );
      case HotelCloudStatus.syncing:
      case HotelCloudStatus.migrating:
      case HotelCloudStatus.restoring:
        return const _ChipLook(
          'Pending',
          Icons.cloud_sync_rounded,
          CustomColors.primary,
        );
      case HotelCloudStatus.offline:
        return const _ChipLook(
          'Pending',
          Icons.cloud_off_rounded,
          CustomColors.gold,
        );
      case HotelCloudStatus.error:
        return const _ChipLook(
          'Failed',
          Icons.cloud_off_rounded,
          CustomColors.booked,
        );
    }
  }
}

class _ChipLook {
  const _ChipLook(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

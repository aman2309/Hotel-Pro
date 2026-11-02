import 'package:flutter/material.dart';

import '../config/backend_config.dart';
import '../services/cpanel_sync_service.dart';
import '../services/hotel_cloud_sync_service.dart';
import '../services/hotel_photo_storage_service.dart';
import '../dialogs/hotel_sync_review_dialog.dart';

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
            ? const _ChipLook('Photos pending', Icons.photo, Color(0xFFEF9A9A))
            : _look(sync.status);
        return Tooltip(
          message: sync.lastError ?? photos.lastPhotoError ?? look.label,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: ActionChip(
              onPressed: () {
                if (hotelUsesCpanel) {
                  final conflicts = CpanelSyncService.instance.pendingConflicts;
                  if (conflicts.isNotEmpty) {
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Sync conflict'),
                        content: const Text(
                          'This phone and the server both changed a bill or payment. Choose which copy to keep. The hotel is not deleted.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              CpanelSyncService.instance.useServerCopy();
                            },
                            child: const Text('Keep server'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              CpanelSyncService.instance.keepThisPhone();
                            },
                            child: const Text('Keep this phone'),
                          ),
                        ],
                      ),
                    );
                    return;
                  }
                  CpanelSyncService.instance.retry();
                  return;
                }
                showHotelSyncReview(context);
              },
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: look.color.withValues(alpha: 0.18),
              side: BorderSide(color: look.color),
              label: Text(
                look.label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              avatar: Icon(look.icon, size: 14, color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  _ChipLook _look(HotelCloudStatus status) {
    switch (status) {
      case HotelCloudStatus.synced:
        return const _ChipLook('Synced', Icons.cloud_done, Color(0xFF81C784));
      case HotelCloudStatus.syncing:
      case HotelCloudStatus.migrating:
      case HotelCloudStatus.restoring:
        return const _ChipLook('Pending', Icons.cloud_sync, Color(0xFF64B5F6));
      case HotelCloudStatus.offline:
        return const _ChipLook('Pending', Icons.cloud_off, Color(0xFFFFCC80));
      case HotelCloudStatus.error:
        return const _ChipLook('Failed', Icons.cloud_off, Color(0xFFEF9A9A));
    }
  }
}

class _ChipLook {
  const _ChipLook(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

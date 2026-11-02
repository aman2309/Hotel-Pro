import 'dart:convert';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/hotel_cloud_sync_service.dart';
import '../services/phone_auth_service.dart';
import '../services/hotel_photo_storage_service.dart';

Future<void> showHotelSyncReview(BuildContext context) async {
  final sync = HotelCloudSyncService.instance;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Hotel sync / saved records'),
      content: SingleChildScrollView(
        child: Text(
          '${sync.lastError ?? HotelPhotoStorageService.instance.lastPhotoError ?? 'Cloud changes update automatically.'}\n\n'
          'Offline changes are provisional until Synced appears. A conflict is not a confirmed booking or payment. '
          'Export saved copies before reviewing. Use cloud keeps your pending copy in the archive; '
          'reconcile any physical payment with the cloud records before entering it again.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            final archives = <String, dynamic>{};
            for (final key in prefs.getKeys().where(
              (key) => key.startsWith('hotel_archive_'),
            )) {
              final raw = prefs.getString(key);
              if (raw == null) continue;
              final data = jsonDecode(raw) as Map;
              if (data['ownerUid'] == PhoneAuthSession.uid) {
                archives[key] = data;
              }
            }
            await FileSaver.instance.saveFile(
              name: 'Hotel_Pro_saved_copies',
              bytes: Uint8List.fromList(utf8.encode(jsonEncode(archives))),
              fileExtension: 'json',
              mimeType: MimeType.json,
            );
          },
          child: const Text('Export saved copies'),
        ),
        TextButton(
          onPressed: () async {
            try {
              await sync.retry();
            } catch (_) {
              /* Error remains visible. */
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          child: const Text('Retry sync'),
        ),
        if (sync.lastError != null ||
            HotelPhotoStorageService.instance.lastPhotoError != null)
          TextButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: dialogContext,
                builder: (confirmContext) => AlertDialog(
                  title: const Text('Use cloud after review?'),
                  content: const Text(
                    'Your pending changes remain in a saved archive. '
                    'Check both copies, especially bookings and received payments, before continuing.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(confirmContext, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(confirmContext, true),
                      child: const Text('Keep archive and use cloud'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              try {
                await HotelPhotoStorageService.instance
                    .keepCloudPhotosAfterReview();
                await sync.useCloudAfterReview();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(SnackBar(content: Text(error.toString())));
                }
              }
            },
            child: const Text('Review / use cloud'),
          ),
      ],
    ),
  );
}

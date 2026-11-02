import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cloud_sync_service.dart';
import '../services/hotel_cloud_sync_service.dart';

Future<void> showBackupRestoreDialog(
  BuildContext context, {
  required Future<void> Function() onRestoreCompleted,
}) async {
  const String roomKey = CloudSyncService.roomKey;
  const String billKey = CloudSyncService.billKey;
  const String customerKey = CloudSyncService.customerKey;
  const String expenseKey = CloudSyncService.expenseKey;

  Future<void> createBackup(BuildContext dialogContext) async {
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();

      final Map<String, dynamic> backup = {
        "app": "Hotel Pro 1",
        "backupVersion": 1,
        "backupDateTime": DateTime.now().toIso8601String(),
        "data": {
          roomKey: prefs.getString(roomKey) ?? "[]",
          billKey: prefs.getString(billKey) ?? "[]",
          customerKey: prefs.getString(customerKey) ?? "[]",
          expenseKey: prefs.getString(expenseKey) ?? "[]",
        },
      };

      final String jsonText = const JsonEncoder.withIndent(
        "  ",
      ).convert(backup);

      final Uint8List bytes = Uint8List.fromList(
        utf8.encode(jsonText),
      );

      final DateTime now = DateTime.now();

      final String date =
          "${now.year}-"
          "${now.month.toString().padLeft(2, "0")}-"
          "${now.day.toString().padLeft(2, "0")}";

      await FileSaver.instance.saveFile(
        name: "Hotel_Pro_1_Backup_$date",
        bytes: bytes,
        fileExtension: "json",
        mimeType: MimeType.json,
      );

      if (!dialogContext.mounted) {
        return;
      }

      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(
          content: Text("BACKUP CREATED SUCCESSFULLY"),
        ),
      );
    } catch (error) {
      if (!dialogContext.mounted) {
        return;
      }

      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(
          content: Text("BACKUP FAILED : $error"),
        ),
      );
    }
  }

  Future<void> restoreBackup(BuildContext dialogContext) async {
    try {
      final FilePickerResult? result =
          await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["json"],
        withData: true,
      );

      if (result == null) {
        return;
      }

      final Uint8List? bytes = result.files.single.bytes;

      if (bytes == null) {
        throw Exception("Unable to read backup file");
      }

      final dynamic decoded = jsonDecode(
        utf8.decode(bytes),
      );

      if (decoded is! Map) {
        throw Exception("Invalid backup format");
      }

      final Map<String, dynamic> backup =
          Map<String, dynamic>.from(decoded);

      if (backup["app"] != "Hotel Pro 1") {
        throw Exception("This is not a Hotel Pro 1 backup");
      }

      final dynamic rawData = backup["data"];

      if (rawData is! Map) {
        throw Exception("Backup data is missing");
      }

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(rawData);

      if (!dialogContext.mounted) {
        return;
      }

      final bool? confirmed = await showDialog<bool>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (BuildContext confirmContext) {
          return AlertDialog(
            title: const Text("RESTORE FROM FILE"),
            content: const Text(
              "Current Rooms, Bills, Customers and Expenses "
              "will be replaced by the selected backup file.\n\n"
              "This does not use cloud restore. Do you want to continue?",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(confirmContext, false);
                },
                child: const Text("CANCEL"),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(confirmContext, true);
                },
                icon: const Icon(Icons.restore),
                label: const Text("RESTORE FROM FILE"),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      final SharedPreferences prefs =
          await SharedPreferences.getInstance();

      await prefs.setString(
        roomKey,
        data[roomKey]?.toString() ?? "[]",
      );

      await prefs.setString(
        billKey,
        data[billKey]?.toString() ?? "[]",
      );

      await prefs.setString(
        customerKey,
        data[customerKey]?.toString() ?? "[]",
      );

      await prefs.setString(
        expenseKey,
        data[expenseKey]?.toString() ?? "[]",
      );

      await onRestoreCompleted();
      await CloudSyncService.markDirty();
      await CloudSyncService.syncIfEnabled(force: true);
      await HotelCloudSyncService.instance.notifyLocalChanged();

      if (!dialogContext.mounted) {
        return;
      }

      Navigator.pop(dialogContext);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "BACKUP RESTORED SUCCESSFULLY",
          ),
        ),
      );
    } catch (error) {
      if (!dialogContext.mounted) {
        return;
      }

      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(
          content: Text("RESTORE FAILED : $error"),
        ),
      );
    }
  }

  await showDialog(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text("BACKUP / RESTORE DATA"),
        content: const SizedBox(
          width: 500,
          child: Text(
            "BACKUP DATA saves Rooms, Bills, Customers and "
            "Hotel Expenses in one JSON backup file.\n\n"
            "RESTORE FROM FILE replaces current hotel data with "
            "the selected Hotel Pro 1 backup file.\n\n"
            "Cloud restore after Phone OTP on a new phone is automatic "
            "and does not open this file picker.",
            style: TextStyle(fontSize: 16),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              restoreBackup(dialogContext);
            },
            icon: const Icon(Icons.restore),
            label: const Text("RESTORE FROM FILE"),
          ),
          ElevatedButton.icon(
            onPressed: () {
              createBackup(dialogContext);
            },
            icon: const Icon(Icons.backup),
            label: const Text("BACKUP DATA"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text("CLOSE"),
          ),
        ],
      );
    },
  );
}

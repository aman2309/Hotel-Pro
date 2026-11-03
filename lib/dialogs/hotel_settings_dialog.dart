import 'package:flutter/material.dart';
import '../widgets/custom_bottom_sheet.dart';
import '../widgets/custom_dialog.dart';
import '../widgets/hotel_settings_form.dart';

Future<bool> showHotelSettingsDialog(BuildContext context) async =>
    await showCustomBottomSheet<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CustomDialog(
        title: const Text('Hotel settings'),
        content: HotelSettingsForm(
          onSaved: () => Navigator.pop(context, true),
          onCancel: () => Navigator.pop(context, false),
        ),
      ),
    ) ??
    false;

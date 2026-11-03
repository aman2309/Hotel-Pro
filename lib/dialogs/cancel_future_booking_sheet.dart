import 'package:flutter/material.dart';
import '../models/room.dart';
import '../widgets/custom_bottom_sheet.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_dialog.dart';

Future<bool?> showCancelFutureBookingSheet(BuildContext context, Room room) {
  return showCustomBottomSheet<bool>(
    context: context,
    builder: (context) => CustomDialog(
      title: Text('Cancel future booking · ${room.roomNumber}'),
      content: Text(
        'Remove the future booking for ${room.futureGuestName}?\n\n'
        '${room.status == 'EMPTY' ? 'The room will be available for a new booking.' : 'The current room status and ongoing stay will be kept.'}'
        '${room.futureAdvance > 0 ? '\n\nAdvance received: ₹${room.futureAdvance}. Arrange any refund separately.' : ''}',
      ),
      actions: [
        CustomButton.text(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep booking'),
        ),
        CustomButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.event_busy_rounded),
          label: const Text('Cancel future booking'),
        ),
      ],
    ),
  );
}

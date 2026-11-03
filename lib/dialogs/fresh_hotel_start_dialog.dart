import '../widgets/custom_bottom_sheet.dart';
import '../theme/custom_colors.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_dialog.dart';
import '../widgets/custom_text_field.dart';
import 'package:flutter/material.dart';

import '../stores/hotel_settings_store.dart';

Future<bool> showFreshHotelStartDialog(BuildContext context) async {
  final TextEditingController passwordController = TextEditingController();

  final FocusNode passwordFocus = FocusNode();
  final FocusNode continueFocus = FocusNode();

  final bool? passwordAccepted = await showCustomBottomSheet<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext warningContext) {
      return CustomDialog(
        title: const Text("Fresh hotel start"),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 60,
                color: CustomColors.error,
              ),
              const SizedBox(height: 12),
              const Text(
                "Warning",
                style: TextStyle(
                  color: CustomColors.error,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "This will permanently clear:\n\n"
                "• Current and Future Room Bookings\n"
                "• Bills and Reports Data\n"
                "• Customers and Stay History\n"
                "• Hotel Expenses\n\n"
                "Room Number, Room Type and Normal Rent "
                "will remain safe.\n\n"
                "CREATE A BACKUP BEFORE CONTINUING.",
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 18),
              CustomTextField(
                controller: passwordController,
                focusNode: passwordFocus,
                autofocus: true,
                obscureText: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: "Admin Password",
                  prefixIcon: Icon(Icons.lock_rounded),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  continueFocus.requestFocus();
                },
              ),
            ],
          ),
        ),
        actions: [
          CustomButton.text(
            onPressed: () {
              Navigator.pop(warningContext, false);
            },
            child: const Text("Cancel"),
          ),
          CustomButton.icon(
            focusNode: continueFocus,
            onPressed: () {
              if (passwordController.text != HotelSettingsStore.adminPassword) {
                ScaffoldMessenger.of(warningContext).showSnackBar(
                  const SnackBar(content: Text("Invalid admin password")),
                );

                passwordFocus.requestFocus();
                return;
              }

              Navigator.pop(warningContext, true);
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text("Continue"),
          ),
        ],
      );
    },
  );

  passwordFocus.dispose();
  continueFocus.dispose();

  if (passwordAccepted != true || !context.mounted) {
    return false;
  }

  final bool? finalConfirmed = await showCustomBottomSheet<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext confirmContext) {
      return CustomDialog(
        title: const Text("Final confirmation"),
        content: const SizedBox(
          width: 480,
          child: Text(
            "All hotel test data will now be permanently deleted.\n\n"
            "This action cannot be undone without a backup.\n\n"
            "Are you absolutely sure you want to start with fresh data?",
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
        actions: [
          CustomButton.text(
            onPressed: () {
              Navigator.pop(confirmContext, false);
            },
            child: const Text("NO, CANCEL"),
          ),
          CustomButton.icon(
            onPressed: () {
              Navigator.pop(confirmContext, true);
            },
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text("YES, CLEAR ALL TEST DATA"),
          ),
        ],
      );
    },
  );

  return finalConfirmed == true;
}

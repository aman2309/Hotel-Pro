import 'package:flutter/material.dart';

import '../stores/hotel_settings_store.dart';

Future<bool> showFreshHotelStartDialog(
  BuildContext context,
) async {
  final TextEditingController passwordController =
      TextEditingController();

  final FocusNode passwordFocus = FocusNode();
  final FocusNode continueFocus = FocusNode();

  final bool? passwordAccepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext warningContext) {
      return AlertDialog(
        title: const Text("FRESH HOTEL START"),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 60,
                color: Colors.red,
              ),
              const SizedBox(height: 12),
              const Text(
                "WARNING",
                style: TextStyle(
                  color: Colors.red,
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
              TextField(
                controller: passwordController,
                focusNode: passwordFocus,
                autofocus: true,
                obscureText: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: "Admin Password",
                  prefixIcon: Icon(Icons.lock),
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
          TextButton(
            onPressed: () {
              Navigator.pop(warningContext, false);
            },
            child: const Text("CANCEL"),
          ),
          ElevatedButton.icon(
            focusNode: continueFocus,
            onPressed: () {
              if (passwordController.text !=
                  HotelSettingsStore.adminPassword) {
                ScaffoldMessenger.of(warningContext).showSnackBar(
                  const SnackBar(
                    content: Text("INVALID ADMIN PASSWORD"),
                  ),
                );

                passwordFocus.requestFocus();
                return;
              }

              Navigator.pop(warningContext, true);
            },
            icon: const Icon(Icons.arrow_forward),
            label: const Text("CONTINUE"),
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

  final bool? finalConfirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext confirmContext) {
      return AlertDialog(
        title: const Text("FINAL CONFIRMATION"),
        content: const SizedBox(
          width: 480,
          child: Text(
            "All hotel test data will now be permanently deleted.\n\n"
            "This action cannot be undone without a backup.\n\n"
            "Are you absolutely sure you want to start with fresh data?",
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(confirmContext, false);
            },
            child: const Text("NO, CANCEL"),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(confirmContext, true);
            },
            icon: const Icon(Icons.delete_forever),
            label: const Text("YES, CLEAR ALL TEST DATA"),
          ),
        ],
      );
    },
  );

  return finalConfirmed == true;
}

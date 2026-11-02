import 'package:flutter/material.dart';

import '../services/cloud_sync_service.dart';
import '../stores/hotel_settings_store.dart';

Future<bool> showHotelSettingsDialog(BuildContext context) async {
  final TextEditingController hotelNameController = TextEditingController(
    text: HotelSettingsStore.hotelName,
  );

  final TextEditingController addressController = TextEditingController(
    text: HotelSettingsStore.hotelAddress,
  );

  final TextEditingController mobileController = TextEditingController(
    text: HotelSettingsStore.hotelMobile,
  );

  final TextEditingController registrationController = TextEditingController(
    text: HotelSettingsStore.registrationNumber,
  );

  final TextEditingController gstController = TextEditingController(
    text: HotelSettingsStore.gstNumber,
  );

  final TextEditingController gstTaxRateController = TextEditingController(
    text: HotelSettingsStore.gstTaxRate.toString().replaceFirst(
      RegExp(r'\.0$'),
      '',
    ),
  );

  final TextEditingController passwordController = TextEditingController(
    text: HotelSettingsStore.adminPassword,
  );

  final FocusNode hotelNameFocus = FocusNode();
  final FocusNode addressFocus = FocusNode();
  final FocusNode mobileFocus = FocusNode();
  final FocusNode registrationFocus = FocusNode();
  final FocusNode gstFocus = FocusNode();
  final FocusNode gstTaxRateFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();
  final FocusNode saveFocus = FocusNode();

  bool hidePassword = true;

  final bool? saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter updateDialog) {
          Future<void> saveSettings() async {
            final String hotelName = hotelNameController.text.trim();

            final String password = passwordController.text;

            if (hotelName.isEmpty) {
              ScaffoldMessenger.of(
                dialogContext,
              ).showSnackBar(const SnackBar(content: Text("ENTER HOTEL NAME")));

              hotelNameFocus.requestFocus();
              return;
            }

            if (password.length < 4) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text("ADMIN PASSWORD MUST BE AT LEAST 4 CHARACTERS"),
                ),
              );

              passwordFocus.requestFocus();
              return;
            }

            await HotelSettingsStore.saveSettings(
              hotelNameValue: hotelName,
              hotelAddressValue: addressController.text,
              hotelMobileValue: mobileController.text,
              registrationNumberValue: registrationController.text,
              gstNumberValue: gstController.text,
              gstTaxRateValue:
                  double.tryParse(
                    gstTaxRateController.text
                        .trim()
                        .replaceAll('%', '')
                        .replaceAll(',', ''),
                  ) ??
                  HotelSettingsStore.gstTaxRate,
              adminPasswordValue: password,
            );
            await CloudSyncService.markDirty();
            await CloudSyncService.syncIfEnabled(force: true);

            if (!dialogContext.mounted) {
              return;
            }

            Navigator.pop(dialogContext, true);
          }

          return AlertDialog(
            title: const Text("HOTEL SETTINGS"),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: hotelNameController,
                      focusNode: hotelNameFocus,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "Hotel Name",
                        prefixIcon: Icon(Icons.hotel),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        addressFocus.requestFocus();
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: addressController,
                      focusNode: addressFocus,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "Hotel Address",
                        prefixIcon: Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        mobileFocus.requestFocus();
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: mobileController,
                      focusNode: mobileFocus,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "Hotel Mobile Number",
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        registrationFocus.requestFocus();
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: registrationController,
                      focusNode: registrationFocus,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "Registration No.",
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        gstFocus.requestFocus();
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: gstController,
                      focusNode: gstFocus,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "GST No.",
                        prefixIcon: Icon(Icons.receipt_long),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        gstTaxRateFocus.requestFocus();
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: gstTaxRateController,
                      focusNode: gstTaxRateFocus,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "GST Tax Rate (%)",
                        hintText: "5",
                        prefixIcon: Icon(Icons.percent),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        passwordFocus.requestFocus();
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: passwordController,
                      focusNode: passwordFocus,
                      obscureText: hidePassword,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: "Admin Password",
                        prefixIcon: const Icon(Icons.lock),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () {
                            updateDialog(() {
                              hidePassword = !hidePassword;
                            });
                          },
                          icon: Icon(
                            hidePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                      onSubmitted: (value) {
                        saveFocus.requestFocus();
                        saveSettings();
                      },
                    ),
                    const SizedBox(height: 18),
                    const Divider(),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "CLOUD AUTO SYNC",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Same OTP owner ke Android phones par Firestore data sync hota hai.",
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<Object?>>(
                      future: Future.wait([
                        CloudSyncService.localRevision(),
                        CloudSyncService.lastSyncAt(),
                      ]),
                      builder: (context, snapshot) {
                        final rev = snapshot.data?[0] ?? 0;
                        final last = snapshot.data?[1]?.toString() ?? '-';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Firestore sync • ${rev == 0 ? 'Owner login required' : rev}',
                            ),
                            Text(
                              'Last sync: $last',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text("CANCEL"),
              ),
              ElevatedButton.icon(
                focusNode: saveFocus,
                onPressed: saveSettings,
                icon: const Icon(Icons.save),
                label: const Text("SAVE SETTINGS"),
              ),
            ],
          );
        },
      );
    },
  );

  hotelNameController.dispose();
  addressController.dispose();
  mobileController.dispose();
  registrationController.dispose();
  gstController.dispose();
  gstTaxRateController.dispose();
  passwordController.dispose();

  hotelNameFocus.dispose();
  addressFocus.dispose();
  mobileFocus.dispose();
  registrationFocus.dispose();
  gstFocus.dispose();
  gstTaxRateFocus.dispose();
  passwordFocus.dispose();
  saveFocus.dispose();

  return saved == true;
}

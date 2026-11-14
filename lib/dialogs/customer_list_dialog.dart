import '../utils/stay_duration.dart' as stay_time;
import '../widgets/custom_bottom_sheet.dart';
import '../theme/custom_colors.dart';
import '../widgets/hotel_ui.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/customer.dart';
import '../services/hotel_photo_bytes.dart';
import '../services/hotel_photo_storage_service.dart';
import '../services/id_card_ocr.dart';
import '../stores/customer_store.dart';
import '../stores/hotel_settings_store.dart';
import '../services/document_output.dart';

Future<void> printCustomerId(Customer customer) async {
  final pw.Document pdf = pw.Document();

  // Photos are not kept in memory after login; fetch them only for this print.
  await HotelPhotoStorageService.instance.hydrateGuestPhotos(customer);

  pw.MemoryImage? frontImage;
  pw.MemoryImage? backImage;

  try {
    final Uint8List? front = hotelPhotoBytes(customer.idFrontPhotoPath);
    if (front != null) frontImage = pw.MemoryImage(front);
  } catch (error) {
    frontImage = null;
  }

  try {
    final Uint8List? back = hotelPhotoBytes(customer.idBackPhotoPath);
    if (back != null) backImage = pw.MemoryImage(back);
  } catch (error) {
    backImage = null;
  }

  pw.Widget idPhotoBox(String title, pw.MemoryImage? image) {
    return pw.Expanded(
      child: pw.Container(
        height: 220,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey),
        ),
        child: pw.Column(
          children: [
            pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Expanded(
              child: image == null
                  ? pw.Center(child: pw.Text("NOT AVAILABLE"))
                  : pw.Image(image, fit: pw.BoxFit.contain),
            ),
          ],
        ),
      ),
    );
  }

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                HotelSettingsStore.hotelName.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                HotelSettingsStore.hotelAddress.isEmpty
                    ? "-"
                    : HotelSettingsStore.hotelAddress.toUpperCase(),
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                "Mobile: ${HotelSettingsStore.hotelMobile.isEmpty ? "-" : HotelSettingsStore.hotelMobile}",
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Center(
              child: pw.Text(
                "CUSTOMER ID RECORD",
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text(
              "CUSTOMER ID : ${customer.customerId}",
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text("GUEST NAME : ${customer.guestName}"),
            pw.SizedBox(height: 6),
            pw.Text("MOBILE NUMBER : ${customer.mobile}"),
            pw.SizedBox(height: 6),
            pw.Text("ID TYPE : ${customer.idType}"),
            pw.SizedBox(height: 6),
            pw.Text("ID NUMBER : ${customer.idNumber}"),
            pw.SizedBox(height: 6),
            pw.Text(
              "ADDRESS : ${customer.address.isEmpty ? "-" : customer.address}",
            ),
            pw.SizedBox(height: 18),
            pw.Row(
              children: [
                idPhotoBox("ID FRONT PHOTO", frontImage),
                pw.SizedBox(width: 12),
                idPhotoBox("ID BACK PHOTO", backImage),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.Center(
              child: pw.Text(
                "Customer identification record maintained by the hotel",
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        );
      },
    ),
  );

  await DocumentOutput.printPdf(
    await pdf.save(),
    name: "Customer_ID_${customer.customerId}.pdf",
  );
}

Future<void> showCustomerStayHistoryDialog(
  BuildContext context,
  Customer customer,
) async {
  String formatHistoryDateTime(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return "-";
    }

    try {
      final DateTime date = DateTime.parse(value.toString());

      final String day = date.day.toString().padLeft(2, "0");
      final String month = date.month.toString().padLeft(2, "0");

      int hour = date.hour;
      final String period = hour >= 12 ? "PM" : "AM";

      hour = hour % 12;

      if (hour == 0) {
        hour = 12;
      }

      final String minute = date.minute.toString().padLeft(2, "0");

      return "$day-$month-${date.year}  "
          "$hour:$minute $period";
    } catch (error) {
      return "-";
    }
  }

  String historyDuration(dynamic bookingValue, dynamic checkoutValue) {
    if (bookingValue == null || checkoutValue == null) return '-';
    final start = DateTime.tryParse(bookingValue.toString());
    final end = DateTime.tryParse(checkoutValue.toString());
    if (start == null || end == null) return '-';
    return stay_time.stayDurationLabel(start, checkout: end);
  }

  await showCustomBottomSheet(
    context: context,
    builder: (BuildContext historyContext) {
      final List<Map<String, dynamic>> history = customer.stayHistory.reversed
          .toList();

      return CustomDialog(
        icon: const CustomIconBadge(Icons.history_rounded),
        title: CustomSheetTitle(
          "Stay history",
          subtitle:
              "${customer.guestName.isEmpty ? "Guest" : customer.guestName} · ${history.length} ${history.length == 1 ? "stay" : "stays"}",
        ),
        content: SizedBox(
          width: 720,
          child: history.isEmpty
              ? const CustomEmptyState(
                  title: "No stays yet",
                  message: "Past stays appear here after the guest checks out.",
                  icon: Icons.history_rounded,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int index = 0; index < history.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: CustomSurface(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      "Stay ${history.length - index}",
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  CustomStatusBadge(
                                    label:
                                        "Room ${history[index]["roomNumber"] ?? "-"}",
                                    color: CustomColors.primary,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              CustomDetailRow(
                                "Booked on",
                                formatHistoryDateTime(
                                  history[index]["bookingDate"],
                                ),
                              ),
                              CustomDetailRow(
                                "Check-in",
                                formatHistoryDateTime(
                                  history[index]["bookingTime"],
                                ),
                              ),
                              CustomDetailRow(
                                "Check-out",
                                formatHistoryDateTime(
                                  history[index]["checkoutTime"],
                                ),
                              ),
                              CustomDetailRow(
                                "Stay duration",
                                historyDuration(
                                  history[index]["bookingTime"],
                                  history[index]["checkoutTime"],
                                ),
                                strong: true,
                              ),
                              const CustomDetailDivider(),
                              CustomDetailRow(
                                "Room rate",
                                "₹${history[index]["roomRate"] ?? 0} / day",
                              ),
                              CustomDetailRow(
                                "Booked days",
                                "${history[index]["days"] ?? 0}",
                              ),
                              CustomDetailRow(
                                "Room bill",
                                "₹${history[index]["roomBill"] ?? 0}",
                              ),
                              CustomDetailRow(
                                "Extra charges",
                                "₹${history[index]["extraCharges"] ?? 0}",
                              ),
                              CustomDetailRow(
                                "Advance",
                                "₹${history[index]["advance"] ?? 0}",
                              ),
                              CustomDetailRow(
                                "Balance",
                                "₹${history[index]["balance"] ?? 0}",
                              ),
                              CustomDetailRow(
                                "Payment mode",
                                "${history[index]["paymentMode"] ?? "-"}",
                              ),
                              const CustomDetailDivider(),
                              CustomDetailRow(
                                "Total bill",
                                "₹${history[index]["totalBill"] ?? 0}",
                                strong: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          CustomButton.text(
            autofocus: true,
            onPressed: () {
              Navigator.pop(historyContext);
            },
            child: const Text("Close"),
          ),
        ],
      );
    },
  );
}

Future<bool?> showEditCustomerDialog(
  BuildContext context,
  Customer customer,
) async {
  final mobileController = TextEditingController(text: customer.mobile);

  final nameController = TextEditingController(text: customer.guestName);

  final idTypeController = TextEditingController(text: customer.idType);

  final idController = TextEditingController(text: customer.idNumber);

  final addressController = TextEditingController(text: customer.address);

  final mobileFocus = FocusNode();
  final nameFocus = FocusNode();
  final idTypeFocus = FocusNode();
  final idFocus = FocusNode();
  final addressFocus = FocusNode();
  final frontPhotoFocus = FocusNode();
  final backPhotoFocus = FocusNode();
  final saveFocus = FocusNode();

  final ImagePicker imagePicker = ImagePicker();

  // Editing works on the photo bytes, so fetch them only when this opens.
  await HotelPhotoStorageService.instance.hydrateGuestPhotos(customer);
  if (!context.mounted) return null;

  String idFrontPhoto = customer.idFrontPhotoPath;
  String idBackPhoto = customer.idBackPhotoPath;

  Uint8List? editPhotoBytes(String photoData) => hotelPhotoBytes(photoData);

  final bool? result = await showCustomBottomSheet<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext editContext) {
      return StatefulBuilder(
        builder: (BuildContext dialogContext, StateSetter updateEditForm) {
          Future<ImageSource?> choosePhotoSource() async {
            return showCustomBottomSheet<ImageSource>(
              context: dialogContext,
              builder: (BuildContext sheetContext) {
                return SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.camera_alt_rounded),
                        title: const Text("Camera"),
                        onTap: () {
                          Navigator.pop(sheetContext, ImageSource.camera);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.photo_library_rounded),
                        title: const Text("Gallery"),
                        onTap: () {
                          Navigator.pop(sheetContext, ImageSource.gallery);
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          }

          Future<XFile?> pickIdPhoto() async {
            final ImageSource? source = await choosePhotoSource();
            if (source == null) {
              return null;
            }
            await Future<void>.delayed(const Duration(milliseconds: 200));
            if (!dialogContext.mounted) {
              return null;
            }
            return imagePicker.pickImage(
              source: source,
              imageQuality: 92,
              maxWidth: 2200,
              maxHeight: 2200,
            );
          }

          Future<void> fillFromIdPhoto(String path, Uint8List bytes) async {
            IdCardScan scan = path.isNotEmpty
                ? await IdCardOcr.scanFile(path)
                : const IdCardScan();
            if (scan.isEmpty) {
              scan = await IdCardOcr.scanBytes(bytes);
            }
            if (!dialogContext.mounted || scan.isEmpty) {
              return;
            }

            updateEditForm(() {
              if (IdCardOcr.shouldReplaceName(nameController.text, scan.name)) {
                nameController.text = scan.name!;
              }
              if (IdCardOcr.shouldReplaceId(idController.text, scan.idNumber)) {
                idController.text = scan.idNumber!;
              }
              if (IdCardOcr.shouldReplaceAddress(
                addressController.text,
                scan.address,
              )) {
                addressController.text = scan.address!;
              }
            });
          }

          Future<void> pickFrontPhoto() async {
            final XFile? image = await pickIdPhoto();

            if (image == null) {
              return;
            }

            final Uint8List bytes = await image.readAsBytes();

            updateEditForm(() {
              idFrontPhoto = base64Encode(bytes);
            });

            await fillFromIdPhoto(image.path, bytes);
            backPhotoFocus.requestFocus();
          }

          Future<void> pickBackPhoto() async {
            final XFile? image = await pickIdPhoto();

            if (image == null) {
              return;
            }

            final Uint8List bytes = await image.readAsBytes();

            updateEditForm(() {
              idBackPhoto = base64Encode(bytes);
            });

            await fillFromIdPhoto(image.path, bytes);
            saveFocus.requestFocus();
          }

          Future<void> saveCustomerChanges() async {
            final String mobile = mobileController.text.trim();
            final String guestName = nameController.text.trim();
            final String idType = idTypeController.text.trim();
            final String idNumber = idController.text.trim();
            final String address = addressController.text.trim();

            if (mobile.isEmpty ||
                guestName.isEmpty ||
                idType.isEmpty ||
                idNumber.isEmpty) {
              ScaffoldMessenger.of(editContext).showSnackBar(
                const SnackBar(
                  content: Text("Please fill all customer details"),
                ),
              );

              return;
            }

            if (idFrontPhoto.isEmpty || idBackPhoto.isEmpty) {
              ScaffoldMessenger.of(editContext).showSnackBar(
                const SnackBar(
                  content: Text("Please select ID Front and Back Photo"),
                ),
              );

              return;
            }

            final bool updated = await CustomerStore.updateCustomer(
              customer,
              mobile: mobile,
              guestName: guestName,
              address: address,
              idType: idType,
              idNumber: idNumber,
              idFrontPhotoPath: idFrontPhoto,
              idBackPhotoPath: idBackPhoto,
            );

            if (!editContext.mounted) {
              return;
            }

            if (!updated) {
              ScaffoldMessenger.of(editContext).showSnackBar(
                const SnackBar(
                  content: Text(
                    "This mobile number already belongs to another customer",
                  ),
                ),
              );

              return;
            }

            Navigator.pop(editContext, true);
          }

          Widget editPhotoBox(
            String title,
            String photoData,
            VoidCallback onPressed,
            FocusNode focusNode,
          ) {
            final Uint8List? bytes = editPhotoBytes(photoData);

            return Expanded(
              child: Column(
                children: [
                  Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: CustomColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: bytes == null
                        ? Center(
                            child: Text(
                              "$title\nNot Available",
                              textAlign: TextAlign.center,
                            ),
                          )
                        : Image.memory(bytes, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: CustomButton.outlineIcon(
                      focusNode: focusNode,
                      onPressed: onPressed,
                      icon: const Icon(Icons.photo_library_rounded),
                      label: Text("CHANGE $title"),
                    ),
                  ),
                ],
              ),
            );
          }

          return CustomDialog(
            title: const Text("Edit guest"),
            content: SizedBox(
              width: 650,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomTextField(
                      controller: mobileController,
                      focusNode: mobileFocus,
                      autofocus: true,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "Mobile Number",
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        nameFocus.requestFocus();
                      },
                    ),
                    const SizedBox(height: 10),
                    CustomTextField(
                      controller: nameController,
                      focusNode: nameFocus,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "Guest Name",
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        idTypeFocus.requestFocus();
                      },
                    ),
                    const SizedBox(height: 10),
                    CustomTextField(
                      controller: idTypeController,
                      focusNode: idTypeFocus,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "ID Type",
                        hintText: "Aadhaar / Passport / Driving Licence",
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        idFocus.requestFocus();
                      },
                    ),
                    const SizedBox(height: 10),
                    CustomTextField(
                      controller: idController,
                      focusNode: idFocus,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "ID Number",
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        addressFocus.requestFocus();
                      },
                    ),
                    const SizedBox(height: 10),
                    CustomTextField(
                      controller: addressController,
                      focusNode: addressFocus,
                      minLines: 2,
                      maxLines: 3,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "Address",
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        frontPhotoFocus.requestFocus();
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        editPhotoBox(
                          "ID FRONT PHOTO",
                          idFrontPhoto,
                          pickFrontPhoto,
                          frontPhotoFocus,
                        ),
                        const SizedBox(width: 12),
                        editPhotoBox(
                          "ID BACK PHOTO",
                          idBackPhoto,
                          pickBackPhoto,
                          backPhotoFocus,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              CustomButton.text(
                onPressed: () {
                  Navigator.pop(editContext, false);
                },
                child: const Text("Cancel"),
              ),
              CustomButton.icon(
                focusNode: saveFocus,
                onPressed: saveCustomerChanges,
                icon: const Icon(Icons.save_rounded),
                label: const Text("Save changes"),
              ),
            ],
          );
        },
      );
    },
  );

  mobileFocus.dispose();
  nameFocus.dispose();
  idTypeFocus.dispose();
  idFocus.dispose();
  addressFocus.dispose();
  frontPhotoFocus.dispose();
  backPhotoFocus.dispose();
  saveFocus.dispose();

  return result;
}

/// Full guest details with edit, print and stay-history actions.
/// Returns true when the guest was edited so the list can refresh.
Future<bool> showGuestDetailsSheet(
  BuildContext context,
  Customer customer,
) async {
  bool edited = false;

  // ID photos live in Storage, not in the in-memory guest list. Download them
  // when this sheet opens instead of on every login.
  final Future<void> photosReady = HotelPhotoStorageService.instance
      .hydrateGuestPhotos(customer);

  Widget photoBox(String title, bool front) {
    return Expanded(
      child: FutureBuilder<void>(
        future: photosReady,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          final bool loading = snapshot.connectionState != ConnectionState.done;
          final bytes = hotelPhotoBytes(
            front ? customer.idFrontPhotoPath : customer.idBackPhotoPath,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 110,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: CustomColors.background,
                  border: Border.all(color: CustomColors.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: loading
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : bytes == null
                    ? const Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: CustomColors.muted,
                        ),
                      )
                    : Image.memory(bytes, fit: BoxFit.cover),
              ),
              const SizedBox(height: 4),
              Text(
                loading
                    ? "$title · loading"
                    : bytes == null
                    ? "$title · not added"
                    : title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: CustomColors.muted),
              ),
            ],
          );
        },
      ),
    );
  }

  await showCustomBottomSheet(
    context: context,
    builder: (BuildContext sheetContext) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter updateSheet) {
          final String name = customer.guestName.trim();

          return CustomDialog(
            icon: CircleAvatar(
              radius: 20,
              backgroundColor: CustomColors.neutralTint,
              foregroundColor: CustomColors.text,
              child: Text(
                name.isEmpty ? "?" : name[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            title: CustomSheetTitle(
              name.isEmpty ? "Guest" : name,
              subtitle: customer.mobile,
            ),
            content: SizedBox(
              width: 620,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CustomDetailCard(
                    children: [
                      CustomDetailRow("Mobile number", customer.mobile),
                      CustomDetailRow("ID type", customer.idType),
                      CustomDetailRow("ID number", customer.idNumber),
                      if (customer.address.isNotEmpty)
                        CustomDetailRow("Address", customer.address),
                    ],
                  ),
                  const CustomSectionTitle("ID photos"),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      photoBox("ID front", true),
                      const SizedBox(width: 10),
                      photoBox("ID back", false),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CustomIconBadge(Icons.history_rounded),
                    title: const Text("Stay history"),
                    subtitle: Text(
                      "${customer.stayHistory.length} ${customer.stayHistory.length == 1 ? "stay" : "stays"}",
                      style: const TextStyle(
                        fontSize: 12,
                        color: CustomColors.muted,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () =>
                        showCustomerStayHistoryDialog(sheetContext, customer),
                  ),
                ],
              ),
            ),
            actions: [
              CustomButton.outlineIcon(
                onPressed: () => printCustomerId(customer),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text("Print ID"),
              ),
              CustomButton.icon(
                onPressed: () async {
                  final bool? result = await showEditCustomerDialog(
                    sheetContext,
                    customer,
                  );
                  if (result == true) {
                    edited = true;
                    updateSheet(() {});
                  }
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text("Edit"),
              ),
            ],
          );
        },
      );
    },
  );

  return edited;
}

Future<void> showCustomerListDialog(BuildContext context) async {
  final searchController = TextEditingController();

  List<Customer> filteredCustomers = List<Customer>.from(
    CustomerStore.customers,
  );

  await showCustomBottomSheet(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter updateDialog) {
          void searchCustomer(String value) {
            final search = value.trim().toLowerCase();

            updateDialog(() {
              if (search.isEmpty) {
                filteredCustomers = List<Customer>.from(
                  CustomerStore.customers,
                );

                return;
              }

              filteredCustomers = CustomerStore.customers.where((customer) {
                return customer.idNumber.toLowerCase().contains(search) ||
                    customer.mobile.toLowerCase().contains(search) ||
                    customer.guestName.toLowerCase().contains(search);
              }).toList();
            });
          }

          Widget guestTile(Customer customer) {
            final String name = customer.guestName.trim();

            return CustomSurface(
              padding: EdgeInsets.zero,
              child: InkWell(
                onTap: () async {
                  final bool edited = await showGuestDetailsSheet(
                    dialogContext,
                    customer,
                  );
                  if (edited) {
                    searchCustomer(searchController.text);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: CustomColors.neutralTint,
                        foregroundColor: CustomColors.text,
                        child: Text(
                          name.isEmpty ? "?" : name[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? "Guest" : name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              customer.idNumber.isEmpty
                                  ? "ID not added"
                                  : "ID ${customer.idNumber}",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: CustomColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: CustomColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return CustomDialog(
            icon: const CustomIconBadge(Icons.people_outline_rounded),
            title: CustomSheetTitle(
              "Guests",
              subtitle: searchController.text.trim().isEmpty
                  ? "${CustomerStore.customers.length} saved"
                  : "${filteredCustomers.length} of ${CustomerStore.customers.length} match",
            ),
            content: SizedBox(
              width: 850,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CustomTextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: "Search name, mobile or ID number",
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: "Clear search",
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                searchController.clear();
                                searchCustomer("");
                              },
                            ),
                    ),
                    onChanged: searchCustomer,
                  ),
                  if (filteredCustomers.isEmpty)
                    CustomEmptyState(
                      title: CustomerStore.customers.isEmpty
                          ? "No guests yet"
                          : "No match",
                      message: CustomerStore.customers.isEmpty
                          ? "Guests are saved automatically when you book a room."
                          : "Try a different name, mobile or ID number.",
                      icon: Icons.person_search_rounded,
                    )
                  else
                    for (final customer in filteredCustomers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: guestTile(customer),
                      ),
                ],
              ),
            ),
            actions: [
              CustomButton.text(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text("Close"),
              ),
            ],
          );
        },
      );
    },
  );
}

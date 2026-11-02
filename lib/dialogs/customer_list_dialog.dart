import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/customer.dart';
import '../services/hotel_photo_bytes.dart';
import '../services/id_card_ocr.dart';
import '../stores/customer_store.dart';
import '../stores/hotel_settings_store.dart';

Future<void> printCustomerId(Customer customer) async {
  final pw.Document pdf = pw.Document();

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
            pw.Text(
              title,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
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
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
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

  await Printing.layoutPdf(
    name: "Customer_ID_${customer.customerId}.pdf",
    dynamicLayout: false,
    onLayout: (PdfPageFormat format) async => pdf.save(),
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
    if (bookingValue == null || checkoutValue == null) {
      return "-";
    }

    try {
      final DateTime bookingTime = DateTime.parse(bookingValue.toString());

      final DateTime checkoutTime = DateTime.parse(checkoutValue.toString());

      final Duration duration = checkoutTime.difference(bookingTime);

      final int totalMinutes = duration.inMinutes;
      final int days = totalMinutes ~/ 1440;
      final int hours = (totalMinutes % 1440) ~/ 60;
      final int minutes = totalMinutes % 60;

      final List<String> parts = [];

      if (days > 0) {
        parts.add("$days D");
      }

      if (hours > 0) {
        parts.add("$hours H");
      }

      parts.add("$minutes M");

      return parts.join(" ");
    } catch (error) {
      return "-";
    }
  }

  await showDialog(
    context: context,
    builder: (BuildContext historyContext) {
      final List<Map<String, dynamic>> history = customer.stayHistory.reversed
          .toList();

      return AlertDialog(
        title: Text("${customer.customerId} - STAY HISTORY"),
        content: SizedBox(
          width: 720,
          height: 520,
          child: history.isEmpty
              ? const Center(
                  child: Text(
                    "NO STAY HISTORY AVAILABLE",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                )
              : ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Map<String, dynamic> stay = history[index];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "STAY ${history.length - index}",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Divider(),
                            Text(
                              "Room Number : "
                              "${stay["roomNumber"] ?? "-"}",
                            ),
                            Text(
                              "Booking Date : "
                              "${formatHistoryDateTime(stay["bookingDate"])}",
                            ),
                            Text(
                              "Booking Time : "
                              "${formatHistoryDateTime(stay["bookingTime"])}",
                            ),
                            Text(
                              "Checkout Time : "
                              "${formatHistoryDateTime(stay["checkoutTime"])}",
                            ),
                            Text(
                              "Stay Duration : "
                              "${historyDuration(stay["bookingTime"], stay["checkoutTime"])}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Room Rate : "
                              "₹${stay["roomRate"] ?? 0}",
                            ),
                            Text(
                              "Booked Days : "
                              "${stay["days"] ?? 0}",
                            ),
                            Text(
                              "Room Bill : "
                              "₹${stay["roomBill"] ?? 0}",
                            ),
                            Text(
                              "Extra Charges : "
                              "₹${stay["extraCharges"] ?? 0}",
                            ),
                            Text(
                              "Total Bill : "
                              "₹${stay["totalBill"] ?? 0}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "Advance : "
                              "₹${stay["advance"] ?? 0}",
                            ),
                            Text(
                              "Balance : "
                              "₹${stay["balance"] ?? 0}",
                            ),
                            Text(
                              "Payment Mode : "
                              "${stay["paymentMode"] ?? "-"}",
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () {
              Navigator.pop(historyContext);
            },
            child: const Text("CLOSE"),
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
  final mobileController = TextEditingController(
    text: customer.mobile,
  );

  final nameController = TextEditingController(
    text: customer.guestName,
  );

  final idTypeController = TextEditingController(
    text: customer.idType,
  );

  final idController = TextEditingController(
    text: customer.idNumber,
  );

  final addressController = TextEditingController(
    text: customer.address,
  );

  final mobileFocus = FocusNode();
  final nameFocus = FocusNode();
  final idTypeFocus = FocusNode();
  final idFocus = FocusNode();
  final addressFocus = FocusNode();
  final frontPhotoFocus = FocusNode();
  final backPhotoFocus = FocusNode();
  final saveFocus = FocusNode();

  final ImagePicker imagePicker = ImagePicker();

  String idFrontPhoto = customer.idFrontPhotoPath;
  String idBackPhoto = customer.idBackPhotoPath;

  Uint8List? editPhotoBytes(String photoData) => hotelPhotoBytes(photoData);

  final bool? result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext editContext) {
      return StatefulBuilder(
        builder: (
          BuildContext dialogContext,
          StateSetter updateEditForm,
        ) {
          Future<ImageSource?> choosePhotoSource() async {
            return showModalBottomSheet<ImageSource>(
              context: dialogContext,
              builder: (BuildContext sheetContext) {
                return SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.camera_alt),
                        title: const Text("Camera"),
                        onTap: () {
                          Navigator.pop(sheetContext, ImageSource.camera);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.photo_library),
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
                  content: Text(
                    "Please select ID Front and Back Photo",
                  ),
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
                      border: Border.all(
                        color: Colors.grey.shade400,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: bytes == null
                        ? Center(
                            child: Text(
                              "$title\nNot Available",
                              textAlign: TextAlign.center,
                            ),
                          )
                        : Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                          ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      focusNode: focusNode,
                      onPressed: onPressed,
                      icon: const Icon(Icons.photo_library),
                      label: Text("CHANGE $title"),
                    ),
                  ),
                ],
              ),
            );
          }

          return AlertDialog(
            title: Text(
              "EDIT CUSTOMER - ${customer.customerId}",
            ),
            content: SizedBox(
              width: 650,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
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
                    TextField(
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
                    TextField(
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
                    TextField(
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
                    TextField(
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
              TextButton(
                onPressed: () {
                  Navigator.pop(editContext, false);
                },
                child: const Text("CANCEL"),
              ),
              ElevatedButton.icon(
                focusNode: saveFocus,
                onPressed: saveCustomerChanges,
                icon: const Icon(Icons.save),
                label: const Text("SAVE CHANGES"),
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

Future<void> showCustomerListDialog(BuildContext context) async {
  final searchController = TextEditingController();

  List<Customer> filteredCustomers = List<Customer>.from(
    CustomerStore.customers,
  );

  Uint8List? photoBytes(String photoData) => hotelPhotoBytes(photoData);

  await showDialog(
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
                return customer.customerId.toLowerCase().contains(search) ||
                    customer.mobile.toLowerCase().contains(search) ||
                    customer.guestName.toLowerCase().contains(search);
              }).toList();
            });
          }

          Widget photoBox(String title, String photoData) {
            final bytes = photoBytes(photoData);

            return Expanded(
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: bytes == null
                    ? Center(
                        child: Text(
                          "$title\nNot Available",
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Image.memory(bytes, fit: BoxFit.contain),
                          ),
                        ],
                      ),
              ),
            );
          }

          return AlertDialog(
            title: const Text("CUSTOMER LIST / SEARCH"),
            content: SizedBox(
              width: 850,
              height: 600,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: "Search Customer ID / Mobile / Guest Name",
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: searchCustomer,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredCustomers.isEmpty
                        ? const Center(child: Text("No Customer Found"))
                        : ListView.builder(
                            itemCount: filteredCustomers.length,
                            itemBuilder: (BuildContext context, int index) {
                              final customer = filteredCustomers[index];

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customer.customerId,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        "Guest Name : "
                                        "${customer.guestName}",
                                      ),
                                      Text(
                                        "Mobile Number : "
                                        "${customer.mobile}",
                                      ),
                                      Text(
                                        "ID Type : "
                                        "${customer.idType}",
                                      ),
                                      Text(
                                        "ID Number : "
                                        "${customer.idNumber}",
                                      ),
                                      if (customer.address.isNotEmpty)
                                        Text(
                                          "Address : ${customer.address}",
                                        ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          photoBox(
                                            "ID FRONT PHOTO",
                                            customer.idFrontPhotoPath,
                                          ),
                                          const SizedBox(width: 12),
                                          photoBox(
                                            "ID BACK PHOTO",
                                            customer.idBackPhotoPath,
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 10),

                                      Row(
                                        children: [
                                          Expanded(
                                            child: SizedBox(
                                              height: 64,
                                              child: ElevatedButton(
                                                onPressed: () async {
                                                  final bool? edited =
                                                      await showEditCustomerDialog(
                                                    dialogContext,
                                                    customer,
                                                  );

                                                  if (edited == true) {
                                                    updateDialog(() {
                                                      filteredCustomers =
                                                          List<Customer>.from(
                                                        CustomerStore.customers,
                                                      );
                                                    });
                                                  }
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 4,
                                                  ),
                                                ),
                                                child: const Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.edit, size: 16),
                                                    SizedBox(height: 2),
                                                    Text(
                                                      "EDIT\nCUSTOMER",
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 2,
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        height: 1.1,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: SizedBox(
                                              height: 64,
                                              child: ElevatedButton(
                                                onPressed: () async {
                                                  await printCustomerId(
                                                    customer,
                                                  );
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 4,
                                                  ),
                                                ),
                                                child: const Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.print,
                                                      size: 16,
                                                    ),
                                                    SizedBox(height: 2),
                                                    Text(
                                                      "PRINT\nCUSTOMER ID",
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 2,
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        height: 1.1,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: SizedBox(
                                              height: 64,
                                              child: ElevatedButton(
                                                onPressed: () async {
                                                  await showCustomerStayHistoryDialog(
                                                    dialogContext,
                                                    customer,
                                                  );
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 4,
                                                  ),
                                                ),
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(
                                                      Icons.history,
                                                      size: 16,
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      "VIEW STAY\nHISTORY (${customer.stayHistory.length})",
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 2,
                                                      style: const TextStyle(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        height: 1.1,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                autofocus: true,
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text("CLOSE"),
              ),
            ],
          );
        },
      );
    },
  );
}

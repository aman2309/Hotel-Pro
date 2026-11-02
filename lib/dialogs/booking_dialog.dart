import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/customer.dart';
import '../models/room.dart';
import '../services/hotel_photo_bytes.dart';
import '../services/hotel_photo_upload_debug.dart';
import '../services/id_card_ocr.dart';
import '../stores/customer_store.dart';

TimeOfDay _quarterHour(TimeOfDay time) {
  final int total = time.hour * 60 + time.minute;
  final int rounded = ((total + 7) ~/ 15) * 15;
  final int mins = rounded % (24 * 60);
  return TimeOfDay(hour: mins ~/ 60, minute: mins % 60);
}

Future<bool?> showBookingDialog(BuildContext context, Room room) {
  final mobileController = TextEditingController();
  final nameController = TextEditingController();
  final idController = TextEditingController();
  final addressController = TextEditingController();

  final rentController = TextEditingController(
    text: room.normalRent.toString(),
  );

  final daysController = TextEditingController();

  final advanceController = TextEditingController(text: "0");

  final mobileFocus = FocusNode();
  final nameFocus = FocusNode();
  final idFocus = FocusNode();
  final addressFocus = FocusNode();

  final frontPhotoFocus = FocusNode();
  final backPhotoFocus = FocusNode();

  final rentFocus = FocusNode();
  final dateFocus = FocusNode();
  final daysFocus = FocusNode();
  final advanceFocus = FocusNode();
  final paymentFocus = FocusNode();
  final confirmFocus = FocusNode();

  final ImagePicker imagePicker = ImagePicker();

  DateTime dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool isToday(DateTime date) {
    return dateOnly(date) == dateOnly(DateTime.now());
  }

  DateTime selectedBookingDate = dateOnly(DateTime.now());
  TimeOfDay fromTime = _quarterHour(TimeOfDay.now());
  TimeOfDay toTime = const TimeOfDay(hour: 11, minute: 0);

  String paymentMode = "Cash";

  String idFrontPhoto = "";
  String idBackPhoto = "";

  final List<Map<String, dynamic>> extraGuestControllers = [];

  String lastLookedUpMobile = "";

  String formatDate(DateTime date) {
    String day = date.day.toString().padLeft(2, "0");
    String month = date.month.toString().padLeft(2, "0");

    return "$day-$month-${date.year}";
  }

  String formatTimeOfDay(TimeOfDay time) {
    int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final String minute = time.minute.toString().padLeft(2, "0");
    final String period = time.period == DayPeriod.am ? "AM" : "PM";
    return "$hour:$minute $period";
  }

  DateTime atTime(DateTime day, TimeOfDay time) {
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  DateTime selectedFromDateTime() {
    return atTime(selectedBookingDate, fromTime);
  }

  DateTime selectedToDateTime(int days) {
    return atTime(selectedBookingDate.add(Duration(days: days)), toTime);
  }

  Uint8List? photoBytes(String photoData) => hotelPhotoBytes(photoData);

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext bookingContext) {
      return StatefulBuilder(
        builder: (BuildContext dialogContext, StateSetter updateBookingForm) {
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

          Future<void> fillFromIdPhoto({
            required String path,
            required Uint8List bytes,
            required TextEditingController nameField,
            required TextEditingController idField,
            required TextEditingController addressField,
          }) async {
            IdCardScan scan = path.isNotEmpty
                ? await IdCardOcr.scanFile(path)
                : const IdCardScan();

            if (scan.isEmpty) {
              scan = await IdCardOcr.scanBytes(bytes);
            }

            if (!dialogContext.mounted) {
              return;
            }

            if (scan.isEmpty) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Could not read this ID clearly. Take a straight, sharp photo and try again.",
                  ),
                ),
              );
              return;
            }

            bool filled = false;

            updateBookingForm(() {
              if (IdCardOcr.shouldReplaceName(nameField.text, scan.name)) {
                nameField.text = scan.name!;
                filled = true;
              }
              if (IdCardOcr.shouldReplaceId(idField.text, scan.idNumber)) {
                idField.text = scan.idNumber!;
                filled = true;
              }
              if (IdCardOcr.shouldReplaceAddress(
                addressField.text,
                scan.address,
              )) {
                addressField.text = scan.address!;
                filled = true;
              }
            });

            if (filled && dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text("Name / Aadhaar / Address filled from ID photo"),
                ),
              );
            }
          }

          Future<void> pickFrontPhoto() async {
            final XFile? image = await pickIdPhoto();

            if (image == null) {
              return;
            }

            final Uint8List bytes = await image.readAsBytes();

            updateBookingForm(() {
              idFrontPhoto = base64Encode(bytes);
            });

            await fillFromIdPhoto(
              path: image.path,
              bytes: bytes,
              nameField: nameController,
              idField: idController,
              addressField: addressController,
            );

            backPhotoFocus.requestFocus();
          }

          Future<void> pickBackPhoto() async {
            final XFile? image = await pickIdPhoto();

            if (image == null) {
              return;
            }

            final Uint8List bytes = await image.readAsBytes();

            updateBookingForm(() {
              idBackPhoto = base64Encode(bytes);
            });

            await fillFromIdPhoto(
              path: image.path,
              bytes: bytes,
              nameField: nameController,
              idField: idController,
              addressField: addressController,
            );

            rentFocus.requestFocus();
          }

          void searchCustomer() {
            final String mobile = CustomerStore.normalizedMobile(
              mobileController.text,
            );

            if (mobile.length < 10) {
              nameFocus.requestFocus();
              return;
            }

            final bool alreadyLookedUp = mobile == lastLookedUpMobile;
            lastLookedUpMobile = mobile;

            final Customer? oldCustomer = CustomerStore.findByMobile(mobile);

            if (oldCustomer != null) {
              updateBookingForm(() {
                nameController.text = oldCustomer.guestName;
                idController.text = oldCustomer.idNumber;
                addressController.text = oldCustomer.address;
                if (idFrontPhoto.isEmpty) {
                  idFrontPhoto = oldCustomer.idFrontPhotoPath;
                }
                if (idBackPhoto.isEmpty) {
                  idBackPhoto = oldCustomer.idBackPhotoPath;
                }
              });

              if (!alreadyLookedUp) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text("Welcome Back ${oldCustomer.guestName}"),
                  ),
                );
              }

              rentFocus.requestFocus();
            } else if (!alreadyLookedUp) {
              nameFocus.requestFocus();
            }
          }

          Future<void> selectBookingDate() async {
            final DateTime today = dateOnly(DateTime.now());
            final DateTime initialDate = selectedBookingDate.isBefore(today)
                ? today
                : selectedBookingDate;

            DateTime? pickedDate = await showDatePicker(
              context: dialogContext,
              initialDate: initialDate,
              firstDate: today,
              lastDate: DateTime(DateTime.now().year + 3),
            );

            if (pickedDate != null) {
              updateBookingForm(() {
                selectedBookingDate = dateOnly(pickedDate);
              });
            }

            daysFocus.requestFocus();
          }

          Future<void> confirmBooking() async {
            String mobile = mobileController.text.trim();

            String guestName = nameController.text.trim();

            String idNumber = idController.text.trim();

            String guestAddress = addressController.text.trim();

            int bookingRate = int.tryParse(rentController.text) ?? 0;

            int days = int.tryParse(daysController.text) ?? 0;

            int advance = int.tryParse(advanceController.text) ?? 0;

            if (mobile.isEmpty ||
                guestName.isEmpty ||
                idNumber.isEmpty ||
                bookingRate <= 0 ||
                days <= 0) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text("Please fill all required fields"),
                ),
              );

              return;
            }

            if (idFrontPhoto.isEmpty || idBackPhoto.isEmpty) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text("Please select ID Front and Back Photo"),
                ),
              );

              return;
            }

            HotelPhotoUploadDebug.stage('1 Booking/customer save triggered', <String, Object?>{
              'roomNumber': room.roomNumber,
              'futureBooking': room.status == 'BOOKED',
            });
            HotelPhotoUploadDebug.stage(
              '2 Front photo exists locally',
              HotelPhotoUploadDebug.photoPresence(idFrontPhoto),
            );
            HotelPhotoUploadDebug.stage(
              '3 Back photo exists locally',
              HotelPhotoUploadDebug.photoPresence(idBackPhoto),
            );

            final List<Map<String, dynamic>> extraGuests = [];

            for (final guest in extraGuestControllers) {
              final String guestMobile =
                  (guest["mobile"] as TextEditingController).text.trim();

              final String guestName = (guest["name"] as TextEditingController)
                  .text
                  .trim();

              final String guestIdNumber =
                  (guest["idNumber"] as TextEditingController).text.trim();

              final String guestAddress =
                  (guest["address"] as TextEditingController).text.trim();

              final String guestFrontPhoto = guest["frontPhoto"] as String;

              final String guestBackPhoto = guest["backPhoto"] as String;

              if (guestMobile.isEmpty ||
                  guestName.isEmpty ||
                  guestIdNumber.isEmpty ||
                  guestFrontPhoto.isEmpty ||
                  guestBackPhoto.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Please complete all Additional Guest details and ID Photos",
                    ),
                  ),
                );

                return;
              }

              extraGuests.add({
                "mobile": guestMobile,
                "name": guestName,
                "idNumber": guestIdNumber,
                "address": guestAddress,
                "idFrontPhoto": guestFrontPhoto,
                "idBackPhoto": guestBackPhoto,
              });
            }

            debugPrint("EXTRA GUEST COUNT = ${extraGuests.length}");

            debugPrint("EXTRA GUEST DATA = $extraGuests");

            if (isToday(selectedBookingDate)) {
              if (room.futureBooking && room.futureBookingDate != null) {
                DateTime stayCheckoutDate = dateOnly(selectedBookingDate).add(
                  Duration(days: days),
                );

                DateTime futureDate = dateOnly(room.futureBookingDate!);

                if (!stayCheckoutDate.isBefore(futureDate)) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        "ROOM NOT AVAILABLE - Future Booking on "
                        "${formatDate(futureDate)}",
                      ),
                    ),
                  );

                  return;
                }
              }

              room.mobile = mobile;
              room.guestName = guestName;
              room.idNumber = idNumber;
              room.guestAddress = guestAddress;
              room.bookingRate = bookingRate;
              room.bookingDate = dateOnly(selectedBookingDate);
              room.bookingTime = selectedFromDateTime();
              room.bookingEndTime = selectedToDateTime(days);
              room.checkoutTime = null;
              room.days = days;
              room.advance = advance;
              room.paymentMode = paymentMode;
              room.charges = [];
              room.partPayments = [];
              room.extraGuests = extraGuests;

              room.status = "BOOKED";
            } else {
              if (room.futureBooking) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text("This room already has a Future Booking"),
                  ),
                );

                return;
              }

              room.futureMobile = mobile;
              room.futureGuestName = guestName;
              room.futureIdNumber = idNumber;
              room.futureGuestAddress = guestAddress;
              room.futureBookingRate = bookingRate;
              room.futureBookingDate = selectedFromDateTime();
              room.futureBookingEnd = selectedToDateTime(days);
              room.futureDays = days;
              room.futureAdvance = advance;
              room.futurePaymentMode = paymentMode;
              room.futureExtraGuests = extraGuests;

              room.futureBooking = true;
            }

            await CustomerStore.saveCustomer(
              Customer(
                mobile: mobile,
                guestName: guestName,
                address: guestAddress,
                idType: "Aadhaar / Other ID",
                idNumber: idNumber,
                idFrontPhotoPath: idFrontPhoto,
                idBackPhotoPath: idBackPhoto,
              ),
            );

            for (final guest in extraGuests) {
              final String extraMobile = guest["mobile"] as String;

              await CustomerStore.saveCustomer(
                Customer(
                  mobile: extraMobile,
                  guestName: guest["name"] as String,
                  address: guest["address"] as String? ?? "",
                  idType: "Aadhaar / Other ID",
                  idNumber: guest["idNumber"] as String,
                  idFrontPhotoPath: guest["idFrontPhoto"] as String,
                  idBackPhotoPath: guest["idBackPhoto"] as String,
                ),
              );

              final Customer? savedExtraCustomer = CustomerStore.findByMobile(
                extraMobile,
              );

              debugPrint(
                "EXTRA CUSTOMER SAVED = "
                "${savedExtraCustomer?.customerId} | "
                "${savedExtraCustomer?.mobile} | "
                "${savedExtraCustomer?.guestName}",
              );
            }

            if (dialogContext.mounted) {
              Navigator.pop(dialogContext, true);
            }
          }

          Widget photoButton({
            required String title,
            required String photoData,
            required FocusNode focusNode,
            required Future<void> Function() onPressed,
          }) {
            Uint8List? bytes = photoBytes(photoData);

            return Expanded(
              child: Focus(
                focusNode: focusNode,
                onKeyEvent: (FocusNode node, KeyEvent event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter) {
                    onPressed();

                    return KeyEventResult.handled;
                  }

                  return KeyEventResult.ignored;
                },
                child: OutlinedButton(
                  onPressed: onPressed,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(6),
                  ),
                  child: SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: bytes == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_a_photo, size: 30),
                              const SizedBox(height: 5),
                              Text(title, textAlign: TextAlign.center),
                              const SizedBox(height: 3),
                              const Text(
                                "CAMERA / GALLERY",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(bytes, fit: BoxFit.cover),
                              ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(4),
                                  color: Colors.black54,
                                  child: Text(
                                    title,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            title: Text("Book Room ${room.roomNumber}"),
            content: SizedBox(
              width: 520,
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
                        labelText: "Mobile Number *",
                        prefixIcon: Icon(Icons.phone),
                      ),
                      onChanged: (value) {
                        if (CustomerStore.normalizedMobile(value).length >= 10) {
                          searchCustomer();
                        }
                      },
                      onSubmitted: (value) {
                        searchCustomer();
                      },
                    ),

                    TextField(
                      controller: nameController,
                      focusNode: nameFocus,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "Guest Name *",
                        prefixIcon: Icon(Icons.person),
                      ),
                      onSubmitted: (value) {
                        idFocus.requestFocus();
                      },
                    ),

                    TextField(
                      controller: idController,
                      focusNode: idFocus,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "Aadhaar / Other ID Number *",
                        prefixIcon: Icon(Icons.badge),
                      ),
                      onSubmitted: (value) {
                        addressFocus.requestFocus();
                      },
                    ),

                    TextField(
                      controller: addressController,
                      focusNode: addressFocus,
                      minLines: 2,
                      maxLines: 3,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "Address",
                        prefixIcon: Icon(Icons.home_outlined),
                      ),
                      onSubmitted: (value) {
                        frontPhotoFocus.requestFocus();
                      },
                    ),

                    const SizedBox(height: 15),

                    Row(
                      children: [
                        photoButton(
                          title: "ID FRONT PHOTO",
                          photoData: idFrontPhoto,
                          focusNode: frontPhotoFocus,
                          onPressed: pickFrontPhoto,
                        ),
                        const SizedBox(width: 10),
                        photoButton(
                          title: "ID BACK PHOTO",
                          photoData: idBackPhoto,
                          focusNode: backPhotoFocus,
                          onPressed: pickBackPhoto,
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final mobileFocus = FocusNode();
                          final nameFocus = FocusNode();
                          final idFocus = FocusNode();
                          final addressFocus = FocusNode();
                          final frontFocus = FocusNode();
                          final backFocus = FocusNode();

                          updateBookingForm(() {
                            extraGuestControllers.add({
                              "mobile": TextEditingController(),
                              "name": TextEditingController(),
                              "idNumber": TextEditingController(),
                              "address": TextEditingController(),
                              "mobileFocus": mobileFocus,
                              "nameFocus": nameFocus,
                              "idFocus": idFocus,
                              "addressFocus": addressFocus,
                              "frontFocus": frontFocus,
                              "backFocus": backFocus,
                              "frontPhoto": "",
                              "backPhoto": "",
                            });
                          });

                          Future.delayed(const Duration(milliseconds: 100), () {
                            mobileFocus.requestFocus();
                          });
                        },
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text("ADD GUEST"),
                      ),
                    ),

                    ...extraGuestControllers.asMap().entries.map((entry) {
                      final index = entry.key;
                      final guest = entry.value;

                      Future<void> searchExtraCustomer() async {
                        final mobile = CustomerStore.normalizedMobile(
                          (guest["mobile"] as TextEditingController).text,
                        );

                        if (mobile.length < 10) {
                          (guest["nameFocus"] as FocusNode).requestFocus();
                          return;
                        }

                        final String last =
                            guest["lookedUp"] as String? ?? "";
                        final bool alreadyLookedUp = last == mobile;
                        guest["lookedUp"] = mobile;

                        final oldCustomer = CustomerStore.findByMobile(mobile);

                        if (oldCustomer != null) {
                          updateBookingForm(() {
                            (guest["name"] as TextEditingController).text =
                                oldCustomer.guestName;

                            (guest["idNumber"] as TextEditingController).text =
                                oldCustomer.idNumber;

                            (guest["address"] as TextEditingController).text =
                                oldCustomer.address;

                            if ((guest["frontPhoto"] as String).isEmpty) {
                              guest["frontPhoto"] =
                                  oldCustomer.idFrontPhotoPath;
                            }

                            if ((guest["backPhoto"] as String).isEmpty) {
                              guest["backPhoto"] = oldCustomer.idBackPhotoPath;
                            }
                          });

                          if (!alreadyLookedUp) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  "Welcome Back ${oldCustomer.guestName} - ${oldCustomer.customerId}",
                                ),
                              ),
                            );
                          }

                          (guest["idFocus"] as FocusNode).requestFocus();
                        } else if (!alreadyLookedUp) {
                          (guest["nameFocus"] as FocusNode).requestFocus();
                        }
                      }

                      Future<void> pickExtraFrontPhoto() async {
                        final XFile? image = await pickIdPhoto();

                        if (image == null) {
                          return;
                        }

                        final Uint8List bytes = await image.readAsBytes();

                        updateBookingForm(() {
                          guest["frontPhoto"] = base64Encode(bytes);
                        });

                        await fillFromIdPhoto(
                          path: image.path,
                          bytes: bytes,
                          nameField: guest["name"] as TextEditingController,
                          idField: guest["idNumber"] as TextEditingController,
                          addressField:
                              guest["address"] as TextEditingController,
                        );

                        (guest["backFocus"] as FocusNode).requestFocus();
                      }

                      Future<void> pickExtraBackPhoto() async {
                        final XFile? image = await pickIdPhoto();

                        if (image == null) {
                          return;
                        }

                        final Uint8List bytes = await image.readAsBytes();

                        updateBookingForm(() {
                          guest["backPhoto"] = base64Encode(bytes);
                        });

                        await fillFromIdPhoto(
                          path: image.path,
                          bytes: bytes,
                          nameField: guest["name"] as TextEditingController,
                          idField: guest["idNumber"] as TextEditingController,
                          addressField:
                              guest["address"] as TextEditingController,
                        );

                        if (index < extraGuestControllers.length - 1) {
                          final nextGuest = extraGuestControllers[index + 1];

                          (nextGuest["mobileFocus"] as FocusNode)
                              .requestFocus();
                        } else {
                          rentFocus.requestFocus();
                        }
                      }

                      return Card(
                        margin: const EdgeInsets.only(top: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      "GUEST ${index + 2}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: "REMOVE GUEST",
                                    onPressed: () {
                                      updateBookingForm(() {
                                        extraGuestControllers.removeAt(index);
                                      });
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              TextField(
                                controller: guest["mobile"],
                                focusNode: guest["mobileFocus"],
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: "Mobile Number",
                                  prefixIcon: Icon(Icons.phone),
                                ),
                                onChanged: (value) {
                                  if (CustomerStore.normalizedMobile(
                                        value,
                                      ).length >=
                                      10) {
                                    searchExtraCustomer();
                                  }
                                },
                                onSubmitted: (value) {
                                  searchExtraCustomer();
                                },
                              ),
                              TextField(
                                controller: guest["name"],
                                focusNode: guest["nameFocus"],
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: "Guest Name",
                                  prefixIcon: Icon(Icons.person),
                                ),
                                onSubmitted: (value) {
                                  (guest["idFocus"] as FocusNode)
                                      .requestFocus();
                                },
                              ),
                              TextField(
                                controller: guest["idNumber"],
                                focusNode: guest["idFocus"],
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: "Aadhaar / Other ID Number",
                                  prefixIcon: Icon(Icons.badge),
                                ),
                                onSubmitted: (value) {
                                  (guest["addressFocus"] as FocusNode)
                                      .requestFocus();
                                },
                              ),
                              TextField(
                                controller: guest["address"],
                                focusNode: guest["addressFocus"],
                                minLines: 2,
                                maxLines: 3,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: "Address",
                                  prefixIcon: Icon(Icons.home_outlined),
                                ),
                                onSubmitted: (value) {
                                  (guest["frontFocus"] as FocusNode)
                                      .requestFocus();
                                },
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  photoButton(
                                    title: "ID FRONT PHOTO",
                                    photoData: guest["frontPhoto"] as String,
                                    focusNode: guest["frontFocus"] as FocusNode,
                                    onPressed: pickExtraFrontPhoto,
                                  ),
                                  const SizedBox(width: 10),
                                  photoButton(
                                    title: "ID BACK PHOTO",
                                    photoData: guest["backPhoto"] as String,
                                    focusNode: guest["backFocus"] as FocusNode,
                                    onPressed: pickExtraBackPhoto,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 15),

                    TextField(
                      controller: rentController,
                      focusNode: rentFocus,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "Room Rent Per Day *",
                        prefixIcon: Icon(Icons.currency_rupee),
                      ),
                      onSubmitted: (value) {
                        dateFocus.requestFocus();
                      },
                    ),

                    const SizedBox(height: 8),

                    Focus(
                      focusNode: dateFocus,
                      onKeyEvent: (FocusNode node, KeyEvent event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter) {
                          daysFocus.requestFocus();

                          return KeyEventResult.handled;
                        }

                        return KeyEventResult.ignored;
                      },
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_month),
                        title: const Text("Booking Date"),
                        subtitle: Text(formatDate(selectedBookingDate)),
                        trailing: const Icon(Icons.edit),
                        onTap: selectBookingDate,
                      ),
                    ),

                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.schedule),
                        const SizedBox(width: 12),
                        Text(
                          "${formatTimeOfDay(fromTime)} to ${formatTimeOfDay(toTime)}",
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _TimeChoice(
                      label: "From",
                      time: fromTime,
                      onChanged: (TimeOfDay time) {
                        updateBookingForm(() => fromTime = time);
                      },
                    ),
                    const SizedBox(height: 8),
                    _TimeChoice(
                      label: "To",
                      time: toTime,
                      onChanged: (TimeOfDay time) {
                        updateBookingForm(() => toTime = time);
                      },
                    ),

                    TextField(
                      controller: daysController,
                      focusNode: daysFocus,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "Number of Days *",
                        prefixIcon: Icon(Icons.nights_stay),
                      ),
                      onSubmitted: (value) {
                        advanceFocus.requestFocus();
                      },
                    ),

                    TextField(
                      controller: advanceController,
                      focusNode: advanceFocus,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: "Advance Payment",
                        prefixIcon: Icon(Icons.payments),
                      ),
                      onSubmitted: (value) {
                        paymentFocus.requestFocus();
                      },
                    ),

                    const SizedBox(height: 15),

                    DropdownButtonFormField<String>(
                      focusNode: paymentFocus,
                      initialValue: paymentMode,
                      decoration: const InputDecoration(
                        labelText: "Payment Mode",
                        prefixIcon: Icon(Icons.payment),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: "Cash", child: Text("Cash")),
                        DropdownMenuItem(value: "UPI", child: Text("UPI")),
                        DropdownMenuItem(value: "Card", child: Text("Card")),
                        DropdownMenuItem(
                          value: "Bank Transfer",
                          child: Text("Bank Transfer"),
                        ),
                      ],
                      onChanged: (String? value) {
                        if (value != null) {
                          paymentMode = value;

                          Future.delayed(const Duration(milliseconds: 100), () {
                            confirmFocus.requestFocus();
                          });
                        }
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
              ElevatedButton(
                focusNode: confirmFocus,
                onPressed: confirmBooking,
                child: const Text("CONFIRM BOOKING"),
              ),
            ],
          );
        },
      );
    },
  );
}

class _TimeChoice extends StatelessWidget {
  const _TimeChoice({
    required this.label,
    required this.time,
    required this.onChanged,
  });

  final String label;
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  Widget build(BuildContext context) {
    final int hour12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final int minute = const [0, 15, 30, 45].contains(time.minute)
        ? time.minute
        : 0;
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        _part<int>(
          hour12,
          List<int>.generate(12, (int index) => index + 1),
          (int value) => onChanged(_clock(value, minute, time.period)),
          (int value) => "$value",
        ),
        const Text(" : "),
        _part<int>(
          minute,
          const [0, 15, 30, 45],
          (int value) => onChanged(_clock(hour12, value, time.period)),
          (int value) => value.toString().padLeft(2, "0"),
        ),
        const SizedBox(width: 6),
        _part<DayPeriod>(
          time.period,
          const [DayPeriod.am, DayPeriod.pm],
          (DayPeriod value) => onChanged(_clock(hour12, minute, value)),
          (DayPeriod value) => value == DayPeriod.am ? "AM" : "PM",
        ),
      ],
    );
  }

  TimeOfDay _clock(int hour12, int minute, DayPeriod period) {
    int hour = hour12 % 12;
    if (period == DayPeriod.pm) hour += 12;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Widget _part<T>(
    T value,
    List<T> options,
    ValueChanged<T> onPick,
    String Function(T value) labelFor,
  ) {
    return DropdownButton<T>(
      value: value,
      isDense: true,
      items: options
          .map(
            (T option) => DropdownMenuItem<T>(
              value: option,
              child: Text(labelFor(option)),
            ),
          )
          .toList(),
      onChanged: (T? picked) {
        if (picked != null) onPick(picked);
      },
    );
  }
}

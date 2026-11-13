import '../widgets/date_time_field.dart';
import '../widgets/app_toast.dart';
import '../widgets/custom_bottom_sheet.dart';
import '../theme/custom_colors.dart';
import '../widgets/hotel_ui.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/customer.dart';
import '../models/room.dart';
import '../services/hotel_photo_bytes.dart';
import '../services/hotel_photo_storage_service.dart';
import '../services/hotel_photo_upload_debug.dart';
import '../services/id_card_ocr.dart';
import '../stores/customer_store.dart';

Future<bool?> showBookingDialog(
  BuildContext context,
  Room sourceRoom, {
  Future<void> Function()? prepareGuests,
  Future<void> Function(Room draft)? saveBooking,
}) {
  final originalRoom = sourceRoom.toJson();
  final room = Room.fromJson(originalRoom);
  bool saving = false;
  String? saveError;
  String saveStage = 'Saving guest ID photos…';
  final mobileController = TextEditingController();
  final nameController = TextEditingController();
  final idController = TextEditingController();
  final addressController = TextEditingController();

  final rentController = TextEditingController(
    text: room.normalRent > 0 ? room.normalRent.toString() : '',
  );

  final daysController = TextEditingController(text: '1');

  final advanceController = TextEditingController(text: "0");

  final mobileFocus = FocusNode();
  final nameFocus = FocusNode();
  final idFocus = FocusNode();
  final addressFocus = FocusNode();

  final frontPhotoFocus = FocusNode();
  final backPhotoFocus = FocusNode();

  final rentFocus = FocusNode();
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
  TimeOfDay fromTime = const TimeOfDay(hour: 12, minute: 0);
  bool customTimes = false;
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

  int stayDays() {
    final days = int.tryParse(daysController.text) ?? 1;
    return days > 0 ? days : 1;
  }

  DateTime selectedToDateTime(int days) {
    return atTime(selectedBookingDate.add(Duration(days: days)), toTime);
  }

  Uint8List? photoBytes(String photoData) => hotelPhotoBytes(photoData);

  return showCustomBottomSheet<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext bookingContext) {
      return StatefulBuilder(
        builder: (BuildContext dialogContext, StateSetter updateBookingForm) {
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

            try {
              return await imagePicker.pickImage(
                source: source,
                imageQuality: 92,
                maxWidth: 2200,
                maxHeight: 2200,
              );
            } catch (error) {
              if (dialogContext.mounted) {
                showAppToast(
                  dialogContext,
                  'Could not open camera or gallery. Check photo permissions and try again.',
                );
              }
              debugPrint('[BOOKING] Photo picker failed: $error');
              return null;
            }
          }

          Future<Uint8List?> readIdPhoto(XFile image) async {
            try {
              final bytes = await image.readAsBytes();
              if (bytes.isEmpty) throw StateError('Empty image');
              return bytes;
            } catch (error) {
              if (dialogContext.mounted) {
                showAppToast(
                  dialogContext,
                  'Could not read this photo. Select it again from camera or gallery.',
                );
              }
              debugPrint('[BOOKING] Photo read failed: $error');
              return null;
            }
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

            if (!dialogContext.mounted || saving) {
              return;
            }

            if (scan.isEmpty) {
              showAppToast(
                dialogContext,
                'Photo selected. Could not auto-read the ID; enter the guest details manually.',
                error: false,
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
              showAppToast(
                dialogContext,
                'Guest details filled from ID photo.',
                error: false,
              );
            }
          }

          Future<void> pickFrontPhoto() async {
            final XFile? image = await pickIdPhoto();

            if (image == null) {
              return;
            }

            final Uint8List? bytes = await readIdPhoto(image);
            if (bytes == null || !dialogContext.mounted || saving) return;

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

            final Uint8List? bytes = await readIdPhoto(image);
            if (bytes == null || !dialogContext.mounted || saving) return;

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

            nameFocus.requestFocus();
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

              // Saved photos stay in Storage until this booking needs them.
              unawaited(() async {
                await HotelPhotoStorageService.instance.hydrateGuestPhotos(
                  oldCustomer,
                );
                if (!dialogContext.mounted) return;
                updateBookingForm(() {
                  if (idFrontPhoto.isEmpty) {
                    idFrontPhoto = oldCustomer.idFrontPhotoPath;
                  }
                  if (idBackPhoto.isEmpty) {
                    idBackPhoto = oldCustomer.idBackPhotoPath;
                  }
                });
              }());

              if (!alreadyLookedUp) {
                showAppToast(
                  dialogContext,
                  'Saved guest details loaded.',
                  error: false,
                );
              }

              rentFocus.requestFocus();
            } else if (!alreadyLookedUp) {
              frontPhotoFocus.requestFocus();
            }
          }

          Future<void> selectBookingDate() async {
            final DateTime today = dateOnly(DateTime.now());
            final DateTime initialDate = selectedBookingDate.isBefore(today)
                ? today
                : selectedBookingDate;

            DateTime? pickedDate = await showCustomDateSheet(
              context: dialogContext,
              initialDate: initialDate,
              firstDate: today,
              lastDate: DateTime(DateTime.now().year + 3),
            );

            if (!dialogContext.mounted) return;
            if (pickedDate != null) {
              updateBookingForm(() {
                selectedBookingDate = dateOnly(pickedDate);
              });
            }

            FocusScope.of(dialogContext).unfocus();
          }

          Future<void> selectCheckoutDate() async {
            final days = stayDays();
            final first = selectedBookingDate.add(const Duration(days: 1));
            final picked = await showCustomDateSheet(
              context: dialogContext,
              initialDate: selectedBookingDate.add(Duration(days: days)),
              firstDate: first,
              lastDate: selectedBookingDate.add(
                Duration(days: days > 1095 ? days : 1095),
              ),
            );
            if (picked != null && dialogContext.mounted) {
              updateBookingForm(
                () => daysController.text = picked
                    .difference(selectedBookingDate)
                    .inDays
                    .toString(),
              );
            }
          }

          Future<void> pickTime(bool checkin) async {
            final picked = await showCustomTimeSheet(
              context: dialogContext,
              initialTime: checkin ? fromTime : toTime,
              title: checkin ? 'Check-in time' : 'Check-out time',
            );
            if (picked != null && dialogContext.mounted) {
              updateBookingForm(() {
                if (checkin) {
                  fromTime = picked;
                } else {
                  toTime = picked;
                }
              });
            }
          }

          void bookingError(String message) {
            if (!dialogContext.mounted) return;
            updateBookingForm(() => saveError = message);
            showAppToast(dialogContext, message);
            debugPrint('[BOOKING] Save blocked: $message');
          }

          Future<void> confirmBooking() async {
            if (saving) return;
            hideAppToast();
            room.copyFrom(Room.fromJson(originalRoom));
            updateBookingForm(() => saveError = null);
            String mobile = mobileController.text.trim();

            String guestName = nameController.text.trim();

            String idNumber = idController.text.trim();

            String guestAddress = addressController.text.trim();

            int bookingRate = int.tryParse(rentController.text) ?? 0;

            int days = int.tryParse(daysController.text) ?? 0;

            int advance = int.tryParse(advanceController.text) ?? 0;

            String? invalid;
            if (CustomerStore.normalizedMobile(mobile).length != 10) {
              invalid = 'Enter a valid 10-digit guest mobile number.';
            } else if (guestName.isEmpty) {
              invalid = 'Enter the guest name.';
            } else if (idNumber.isEmpty) {
              invalid = 'Enter the guest ID number.';
            } else if (bookingRate <= 0) {
              invalid = 'Enter a room rent greater than zero.';
            } else if (days <= 0) {
              invalid = 'Enter a valid number of days.';
            } else if (int.tryParse(advanceController.text.trim()) == null ||
                advance < 0) {
              invalid = 'Enter a valid advance amount (zero or more).';
            } else if (photoBytes(idFrontPhoto) == null ||
                photoBytes(idBackPhoto) == null) {
              invalid = 'Select both front and back ID photos.';
            }
            if (invalid != null) {
              bookingError(invalid);
              return;
            }

            HotelPhotoUploadDebug.stage(
              '1 Booking/customer save triggered',
              <String, Object?>{
                'roomNumber': room.roomNumber,
                'futureBooking': !isToday(selectedBookingDate),
              },
            );
            HotelPhotoUploadDebug.stage(
              '2 Front photo exists locally',
              HotelPhotoUploadDebug.photoPresence(idFrontPhoto),
            );
            HotelPhotoUploadDebug.stage(
              '3 Back photo exists locally',
              HotelPhotoUploadDebug.photoPresence(idBackPhoto),
            );

            final List<Map<String, dynamic>> extraGuests = [];
            final seenMobiles = {CustomerStore.normalizedMobile(mobile)};

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

              if ([
                guestMobile,
                guestName,
                guestIdNumber,
                guestAddress,
                guestFrontPhoto,
                guestBackPhoto,
              ].every((value) => value.isEmpty)) {
                continue;
              }
              if (CustomerStore.normalizedMobile(guestMobile).length != 10 ||
                  guestName.isEmpty ||
                  guestIdNumber.isEmpty ||
                  photoBytes(guestFrontPhoto) == null ||
                  photoBytes(guestBackPhoto) == null) {
                bookingError(
                  'Complete additional guest details and both ID photos, or remove the unused guest.',
                );

                return;
              }

              if (!seenMobiles.add(
                CustomerStore.normalizedMobile(guestMobile),
              )) {
                bookingError('Each guest must have a different mobile number.');
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

            if (isToday(selectedBookingDate)) {
              if (room.futureBooking && room.futureBookingDate != null) {
                DateTime stayCheckoutDate = selectedToDateTime(days);

                DateTime futureDate = room.futureBookingDate!;

                if (stayCheckoutDate.isAfter(futureDate)) {
                  bookingError(
                    'This stay overlaps the existing future booking on ${formatDate(futureDate)}. Choose an earlier checkout.',
                  );

                  return;
                }
              }

              room.mobile = mobile;
              room.guestName = guestName;
              room.idNumber = idNumber;
              room.guestAddress = guestAddress;
              room.bookingRate = bookingRate;
              // Every new stay gets its own start: the moment this booking is
              // confirmed. Never reuse a time left on the room from an
              // earlier stay or the default 12:00 PM check-in slot.
              final DateTime confirmedAt = DateTime.now();
              room.bookingDate = dateOnly(confirmedAt);
              room.bookingTime = confirmedAt;
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
                bookingError('This room already has a future booking.');

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

            updateBookingForm(() {
              saving = true;
              saveStage = 'Saving guest ID photos…';
            });
            FocusScope.of(dialogContext).unfocus();
            try {
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
              }
              await prepareGuests?.call();
              if (!dialogContext.mounted) return;
              updateBookingForm(() => saveStage = 'Saving booking…');
              if (saveBooking != null) {
                await saveBooking(room);
              } else {
                sourceRoom.copyFrom(room);
              }
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, true);
              }
            } catch (error) {
              if (dialogContext.mounted) {
                bookingError(
                  error is StateError
                      ? error.message.toString()
                      : 'Could not save booking. Check your connection and retry.',
                );
                debugPrint('[BOOKING] Save failed: $error');
              }
            } finally {
              if (dialogContext.mounted) {
                updateBookingForm(() => saving = false);
              }
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
                child: CustomButton.outline(
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
                              const Icon(Icons.add_a_photo_outlined, size: 26),
                              const SizedBox(height: 5),
                              Text(title, textAlign: TextAlign.center),
                              const SizedBox(height: 3),
                              const Text(
                                "Camera or gallery",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: CustomColors.muted,
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
                                  color: CustomColors.text.withValues(
                                    alpha: .6,
                                  ),
                                  child: Text(
                                    title,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: CustomColors.surface,
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

          return PopScope(
            canPop: !saving,
            child: CustomDialog(
              canClose: !saving,
              notice: saveError == null
                  ? null
                  : Text(
                      saveError!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: CustomColors.error,
                      ),
                    ),
              icon: const CustomIconBadge(Icons.add_home_outlined),
              title: CustomSheetTitle(
                "Book room ${room.roomNumber}",
                subtitle: isToday(selectedBookingDate)
                    ? 'Check-in today · ${room.roomType}'
                    : 'Future booking · ${formatDate(selectedBookingDate)}',
              ),
              content: AbsorbPointer(
                absorbing: saving,
                child: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CustomSectionTitle(
                          'Guest details',
                          padding: EdgeInsets.fromLTRB(2, 0, 2, 12),
                        ),
                        CustomTextField(
                          controller: mobileController,
                          focusNode: mobileFocus,
                          autofocus: true,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: "Mobile Number *",
                            prefixIcon: Icon(Icons.phone_rounded),
                          ),
                          onChanged: (value) {
                            if (CustomerStore.normalizedMobile(value).length >=
                                10) {
                              searchCustomer();
                            }
                          },
                          onSubmitted: (value) {
                            searchCustomer();
                          },
                        ),

                        Row(
                          children: [
                            photoButton(
                              title: "ID front photo",
                              photoData: idFrontPhoto,
                              focusNode: frontPhotoFocus,
                              onPressed: pickFrontPhoto,
                            ),
                            const SizedBox(width: 10),
                            photoButton(
                              title: "ID back photo",
                              photoData: idBackPhoto,
                              focusNode: backPhotoFocus,
                              onPressed: pickBackPhoto,
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        CustomTextField(
                          controller: nameController,
                          focusNode: nameFocus,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: "Guest Name *",
                            prefixIcon: Icon(Icons.person_rounded),
                          ),
                          onSubmitted: (value) {
                            idFocus.requestFocus();
                          },
                        ),

                        CustomTextField(
                          controller: idController,
                          focusNode: idFocus,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: "Aadhaar / Other ID Number *",
                            prefixIcon: Icon(Icons.badge_rounded),
                          ),
                          onSubmitted: (value) {
                            addressFocus.requestFocus();
                          },
                        ),

                        CustomTextField(
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
                            rentFocus.requestFocus();
                          },
                        ),

                        const SizedBox(height: 16),

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

                            final oldCustomer = CustomerStore.findByMobile(
                              mobile,
                            );

                            if (oldCustomer != null) {
                              await HotelPhotoStorageService.instance
                                  .hydrateGuestPhotos(oldCustomer);
                              if (!dialogContext.mounted) return;
                              updateBookingForm(() {
                                (guest["name"] as TextEditingController).text =
                                    oldCustomer.guestName;

                                (guest["idNumber"] as TextEditingController)
                                        .text =
                                    oldCustomer.idNumber;

                                (guest["address"] as TextEditingController)
                                        .text =
                                    oldCustomer.address;

                                if ((guest["frontPhoto"] as String).isEmpty) {
                                  guest["frontPhoto"] =
                                      oldCustomer.idFrontPhotoPath;
                                }

                                if ((guest["backPhoto"] as String).isEmpty) {
                                  guest["backPhoto"] =
                                      oldCustomer.idBackPhotoPath;
                                }
                              });

                              if (!alreadyLookedUp) {
                                showAppToast(
                                  dialogContext,
                                  'Saved guest details loaded.',
                                  error: false,
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

                            final Uint8List? bytes = await readIdPhoto(image);
                            if (bytes == null ||
                                !dialogContext.mounted ||
                                saving) {
                              return;
                            }

                            updateBookingForm(() {
                              guest["frontPhoto"] = base64Encode(bytes);
                            });

                            await fillFromIdPhoto(
                              path: image.path,
                              bytes: bytes,
                              nameField: guest["name"] as TextEditingController,
                              idField:
                                  guest["idNumber"] as TextEditingController,
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

                            final Uint8List? bytes = await readIdPhoto(image);
                            if (bytes == null ||
                                !dialogContext.mounted ||
                                saving) {
                              return;
                            }

                            updateBookingForm(() {
                              guest["backPhoto"] = base64Encode(bytes);
                            });

                            await fillFromIdPhoto(
                              path: image.path,
                              bytes: bytes,
                              nameField: guest["name"] as TextEditingController,
                              idField:
                                  guest["idNumber"] as TextEditingController,
                              addressField:
                                  guest["address"] as TextEditingController,
                            );

                            if (index < extraGuestControllers.length - 1) {
                              final nextGuest =
                                  extraGuestControllers[index + 1];

                              (nextGuest["mobileFocus"] as FocusNode)
                                  .requestFocus();
                            } else {
                              rentFocus.requestFocus();
                            }
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: CustomSurface(
                              padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          "Guest ${index + 2}",
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: "Remove guest",
                                        color: CustomColors.error,
                                        onPressed: () {
                                          updateBookingForm(() {
                                            extraGuestControllers.removeAt(
                                              index,
                                            );
                                          });
                                        },
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                  CustomTextField(
                                    controller: guest["mobile"],
                                    focusNode: guest["mobileFocus"],
                                    keyboardType: TextInputType.phone,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: "Mobile Number",
                                      prefixIcon: Icon(Icons.phone_rounded),
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
                                  Row(
                                    children: [
                                      photoButton(
                                        title: "ID front photo",
                                        photoData:
                                            guest["frontPhoto"] as String,
                                        focusNode:
                                            guest["frontFocus"] as FocusNode,
                                        onPressed: pickExtraFrontPhoto,
                                      ),
                                      const SizedBox(width: 10),
                                      photoButton(
                                        title: "ID back photo",
                                        photoData: guest["backPhoto"] as String,
                                        focusNode:
                                            guest["backFocus"] as FocusNode,
                                        onPressed: pickExtraBackPhoto,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  CustomTextField(
                                    controller: guest["name"],
                                    focusNode: guest["nameFocus"],
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: "Guest Name",
                                      prefixIcon: Icon(Icons.person_rounded),
                                    ),
                                    onSubmitted: (value) {
                                      (guest["idFocus"] as FocusNode)
                                          .requestFocus();
                                    },
                                  ),
                                  CustomTextField(
                                    controller: guest["idNumber"],
                                    focusNode: guest["idFocus"],
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: "Aadhaar / Other ID Number",
                                      prefixIcon: Icon(Icons.badge_rounded),
                                    ),
                                    onSubmitted: (value) {
                                      (guest["addressFocus"] as FocusNode)
                                          .requestFocus();
                                    },
                                  ),
                                  CustomTextField(
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
                                ],
                              ),
                            ),
                          );
                        }),

                        Align(
                          alignment: Alignment.centerRight,
                          child: CustomButton.outlineIcon(
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

                              Future.delayed(
                                const Duration(milliseconds: 100),
                                () {
                                  mobileFocus.requestFocus();
                                },
                              );
                            },
                            icon: const Icon(
                              Icons.person_add_rounded,
                              size: 18,
                            ),
                            label: const Text("Add guest"),
                          ),
                        ),

                        const CustomSectionTitle('Rent & payment'),

                        CustomTextField(
                          controller: rentController,
                          focusNode: rentFocus,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: "Room Rent Per Day *",
                            prefixIcon: Icon(Icons.currency_rupee_rounded),
                          ),
                          onSubmitted: (value) {
                            daysFocus.requestFocus();
                          },
                        ),

                        CustomTextField(
                          controller: daysController,
                          onChanged: (_) => updateBookingForm(() {}),
                          focusNode: daysFocus,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: "Number of Days *",
                            prefixIcon: Icon(Icons.nights_stay_rounded),
                          ),
                          onSubmitted: (value) {
                            advanceFocus.requestFocus();
                          },
                        ),

                        CustomTextField(
                          controller: advanceController,
                          focusNode: advanceFocus,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: "Advance Payment",
                            prefixIcon: Icon(Icons.payments_rounded),
                          ),
                          onSubmitted: (value) {
                            paymentFocus.requestFocus();
                          },
                        ),

                        const SizedBox(height: 15),

                        CustomDropdown<String>(
                          focusNode: paymentFocus,
                          initialValue: paymentMode,
                          decoration: const InputDecoration(
                            labelText: "Payment Mode",
                            prefixIcon: Icon(Icons.payment_rounded),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: "Cash",
                              child: Text("Cash"),
                            ),
                            DropdownMenuItem(value: "UPI", child: Text("UPI")),
                            DropdownMenuItem(
                              value: "Card",
                              child: Text("Card"),
                            ),
                            DropdownMenuItem(
                              value: "Bank Transfer",
                              child: Text("Bank Transfer"),
                            ),
                          ],
                          onChanged: (String? value) {
                            if (value != null) {
                              paymentMode = value;

                              Future.delayed(
                                const Duration(milliseconds: 100),
                                () {
                                  confirmFocus.requestFocus();
                                },
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 24),

                        const CustomSectionTitle(
                          'Stay dates & times',
                          padding: EdgeInsets.fromLTRB(2, 0, 2, 12),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            children: [
                              ActionChip(
                                label: const Text('Today'),
                                onPressed: () => updateBookingForm(
                                  () => selectedBookingDate = dateOnly(
                                    DateTime.now(),
                                  ),
                                ),
                              ),
                              ActionChip(
                                label: const Text('Tomorrow'),
                                onPressed: () => updateBookingForm(
                                  () => selectedBookingDate = dateOnly(
                                    DateTime.now().add(const Duration(days: 1)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        DateTimeField(
                          label: 'Check-in date',
                          value: formatDate(selectedBookingDate),
                          icon: Icons.calendar_month_rounded,
                          onTap: selectBookingDate,
                        ),
                        DateTimeField(
                          label: 'Check-out date',
                          value: formatDate(
                            selectedBookingDate.add(Duration(days: stayDays())),
                          ),
                          icon: Icons.event_available_rounded,
                          onTap: selectCheckoutDate,
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Set custom times'),
                          subtitle: Text(
                            isToday(selectedBookingDate)
                                ? 'Check-in starts when you confirm · default check-out 11:00 AM'
                                : 'Default: check-in 12:00 PM · check-out 11:00 AM',
                          ),
                          value: customTimes,
                          onChanged: (value) => updateBookingForm(() {
                            customTimes = value;
                            if (!value) {
                              fromTime = const TimeOfDay(hour: 12, minute: 0);
                              toTime = const TimeOfDay(hour: 11, minute: 0);
                            }
                          }),
                        ),
                        if (customTimes) ...[
                          if (!isToday(selectedBookingDate))
                            DateTimeField(
                              label: 'Check-in time',
                              value: formatTimeOfDay(fromTime),
                              icon: Icons.login_rounded,
                              onTap: () => pickTime(true),
                            ),
                          DateTimeField(
                            label: 'Check-out time',
                            value: formatTimeOfDay(toTime),
                            icon: Icons.logout_rounded,
                            onTap: () => pickTime(false),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                CustomButton.text(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.pop(dialogContext, false);
                        },
                  child: const Text("Cancel"),
                ),
                CustomButton(
                  focusNode: confirmFocus,
                  onPressed: saving ? null : confirmBooking,
                  child: Text(
                    saving
                        ? saveStage
                        : isToday(selectedBookingDate)
                        ? 'Confirm booking'
                        : 'Confirm future booking',
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

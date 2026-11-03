import '../widgets/live_stay_duration.dart';
import '../widgets/custom_bottom_sheet.dart';
import '../theme/custom_colors.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_dialog.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../models/room.dart';
import '../services/hotel_photo_bytes.dart';
import '../stores/customer_store.dart';
import 'booking_slip_dialog.dart';

Future<void> showBookingViewDialog(
  BuildContext context,
  Room room, {
  bool showFutureBooking = false,
}) async {
  final bool isFuture = showFutureBooking;

  final String guestMobile = isFuture ? room.futureMobile : room.mobile;

  final String guestName = isFuture ? room.futureGuestName : room.guestName;

  final String guestIdNumber = isFuture ? room.futureIdNumber : room.idNumber;

  final int bookingRate = isFuture ? room.futureBookingRate : room.bookingRate;

  final DateTime? bookingDate = isFuture
      ? room.futureBookingDate
      : room.bookingDate;

  final int bookingDays = isFuture ? room.futureDays : room.days;

  final int bookingAdvance = isFuture ? room.futureAdvance : room.advance;

  final String bookingPaymentMode = isFuture
      ? room.futurePaymentMode
      : room.paymentMode;

  Customer? customer = CustomerStore.findByMobile(guestMobile);

  final String roomAddress = isFuture
      ? room.futureGuestAddress
      : room.guestAddress;
  final String guestAddress = roomAddress.trim().isNotEmpty
      ? roomAddress
      : (customer?.address ?? "");

  String idFrontPhoto = customer?.idFrontPhotoPath ?? "";

  String idBackPhoto = customer?.idBackPhotoPath ?? "";

  Uint8List? photoBytes(String photoData) => hotelPhotoBytes(photoData);

  String formatDate(DateTime? date) {
    if (date == null) {
      return "-";
    }

    String day = date.day.toString().padLeft(2, "0");

    String month = date.month.toString().padLeft(2, "0");

    return "$day-$month-${date.year}";
  }

  String formatTime(DateTime? date) {
    if (date == null) {
      return "-";
    }

    int hour = date.hour;
    String period = hour >= 12 ? "PM" : "AM";

    hour = hour % 12;

    if (hour == 0) {
      hour = 12;
    }

    String minute = date.minute.toString().padLeft(2, "0");

    return "$hour:$minute $period";
  }

  Future<void> openLargePhoto(
    BuildContext dialogContext,
    String title,
    String photoData,
  ) async {
    Uint8List? bytes = photoBytes(photoData);

    if (bytes == null) {
      ScaffoldMessenger.of(
        dialogContext,
      ).showSnackBar(const SnackBar(content: Text("Photo not available")));

      return;
    }

    await showCustomBottomSheet(
      context: dialogContext,
      builder: (BuildContext photoContext) {
        return CustomSheetPanel(
          child: SizedBox(
            width: 750,
            height: 550,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(photoContext);
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: Center(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget bookingDetail(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final label = Text(
            title,
            style: const TextStyle(fontSize: 12, color: CustomColors.muted),
          );
          final detail = Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: CustomColors.text,
            ),
          );
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 4), detail],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 150, child: label),
              Expanded(child: detail),
            ],
          );
        },
      ),
    );
  }

  Widget photoBox(BuildContext dialogContext, String title, String photoData) {
    Uint8List? bytes = photoBytes(photoData);

    return Expanded(
      child: InkWell(
        onTap: () {
          openLargePhoto(dialogContext, title, photoData);
        },
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            border: Border.all(color: CustomColors.muted),
            borderRadius: BorderRadius.circular(10),
          ),
          child: bytes == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.image_not_supported_rounded, size: 35),
                    const SizedBox(height: 5),
                    Text(title),
                    const Text(
                      "Photo not available",
                      style: TextStyle(fontSize: 10),
                    ),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.memory(bytes, fit: BoxFit.cover),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(6),
                        color: CustomColors.muted,
                        child: Text(
                          "$title • CLICK TO VIEW",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: CustomColors.surface,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  await showCustomBottomSheet(
    context: context,
    builder: (BuildContext dialogContext) {
      return CustomDialog(
        title: Text(
          isFuture
              ? "Future Booking - Room ${room.roomNumber}"
              : "Booking Details - Room ${room.roomNumber}",
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isFuture
                        ? CustomColors.neutralTint
                        : CustomColors.bookedTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isFuture ? "● FUTURE BOOKING" : "● CURRENT BOOKING",
                    style: TextStyle(
                      color: isFuture
                          ? CustomColors.primary
                          : CustomColors.error,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                bookingDetail("Guest Name", guestName),

                bookingDetail("Mobile Number", guestMobile),

                bookingDetail("ID Number", guestIdNumber),

                if (guestAddress.isNotEmpty)
                  bookingDetail("Address", guestAddress),

                bookingDetail("Room Number", room.roomNumber.toString()),

                bookingDetail("Room Type", room.roomType),

                bookingDetail("Room Rent", "₹$bookingRate / Day"),

                bookingDetail(
                  'Check-in date',
                  formatDate(
                    isFuture
                        ? room.futureBookingDate
                        : room.bookingTime ?? bookingDate,
                  ),
                ),
                bookingDetail(
                  'Check-in time',
                  formatTime(
                    isFuture ? room.futureBookingDate : room.bookingTime,
                  ),
                ),
                bookingDetail(
                  'Check-out date',
                  formatDate(
                    isFuture ? room.futureBookingEnd : room.bookingEndTime,
                  ),
                ),
                bookingDetail(
                  'Check-out time',
                  formatTime(
                    isFuture ? room.futureBookingEnd : room.bookingEndTime,
                  ),
                ),

                if (!isFuture)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Stay Duration',
                          style: TextStyle(
                            fontSize: 12,
                            color: CustomColors.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        LiveStayDuration(
                          start: room.bookingTime,
                          checkout: room.checkoutTime,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                bookingDetail("Number of Days", bookingDays.toString()),

                bookingDetail("Advance", "₹$bookingAdvance"),

                bookingDetail(
                  "Payment Mode",
                  bookingPaymentMode.isEmpty ? "-" : bookingPaymentMode,
                ),

                const Divider(),

                const Text(
                  "Guest ID Photos",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    photoBox(dialogContext, "ID FRONT PHOTO", idFrontPhoto),
                    const SizedBox(width: 12),
                    photoBox(dialogContext, "ID BACK PHOTO", idBackPhoto),
                  ],
                ),

                const Divider(),

                if ((showFutureBooking
                        ? room.futureExtraGuests
                        : room.extraGuests)
                    .isNotEmpty) ...[
                  const Text(
                    "Additional guests",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 8),

                  ...(showFutureBooking
                          ? room.futureExtraGuests
                          : room.extraGuests)
                      .asMap()
                      .entries
                      .map((entry) {
                        final index = entry.key;
                        final guest = entry.value;

                        final String extraMobile =
                            guest["mobile"]?.toString() ?? "";

                        final Customer? extraCustomer =
                            CustomerStore.findByMobile(extraMobile);

                        final String extraCustomerId =
                            extraCustomer?.customerId ?? "-";

                        final String extraFrontPhoto =
                            guest["idFrontPhoto"]?.toString() ??
                            extraCustomer?.idFrontPhotoPath ??
                            "";

                        final String extraBackPhoto =
                            guest["idBackPhoto"]?.toString() ??
                            extraCustomer?.idBackPhotoPath ??
                            "";

                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            border: Border.all(color: CustomColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "GUEST ${index + 2}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text("Customer ID : $extraCustomerId"),
                              Text(
                                "Guest Name : "
                                "${guest["name"] ?? "-"}",
                              ),
                              Text(
                                "Mobile Number : "
                                "${guest["mobile"] ?? "-"}",
                              ),
                              Text(
                                "ID Number : "
                                "${guest["idNumber"] ?? "-"}",
                              ),
                              if ((guest["address"] ?? "")
                                  .toString()
                                  .trim()
                                  .isNotEmpty)
                                Text("Address : ${guest["address"]}"),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  photoBox(
                                    dialogContext,
                                    "GUEST ${index + 2} ID FRONT PHOTO",
                                    extraFrontPhoto,
                                  ),
                                  const SizedBox(width: 12),
                                  photoBox(
                                    dialogContext,
                                    "GUEST ${index + 2} ID BACK PHOTO",
                                    extraBackPhoto,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),

                  const Divider(),
                ],
              ],
            ),
          ),
        ),
        actions: [
          CustomButton.text(
            autofocus: true,
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text("Close"),
          ),
          CustomButton.outlineIcon(
            onPressed: () => showBookingSlipPrintView(dialogContext, room),
            icon: const Icon(Icons.preview_rounded),
            label: const Text("Print view"),
          ),
          CustomButton.icon(
            onPressed: () => printBookingSlip(room),
            icon: const Icon(Icons.print_rounded),
            label: const Text("Print"),
          ),
        ],
      );
    },
  );
}

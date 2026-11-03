import '../widgets/live_stay_duration.dart';
import '../widgets/custom_bottom_sheet.dart';
import '../theme/custom_colors.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_dialog.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../widgets/app_toast.dart';

import '../models/customer.dart';
import '../models/room.dart';
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
    Uint8List? bytes,
  ) async {
    if (bytes == null) {
      showAppToast(
        dialogContext,
        'Photo not available. Refresh your hotel to retry.',
      );

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
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      CustomButton.outlineIcon(
                        onPressed: () => runBookingDocumentAction(
                          photoContext,
                          () async {
                            final pdf = await buildGuestPhotoPdf(title, bytes);
                            await Printing.sharePdf(
                              bytes: pdf,
                              filename: 'Guest-ID-Photo.pdf',
                            );
                          },
                        ),
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('Send photo PDF'),
                      ),
                      CustomButton.icon(
                        onPressed: () => runBookingDocumentAction(
                          photoContext,
                          () async {
                            final pdf = await buildGuestPhotoPdf(title, bytes);
                            await Printing.layoutPdf(
                              onLayout: (_) async => pdf,
                              name: 'Guest-ID-Photo',
                            );
                          },
                        ),
                        icon: const Icon(Icons.print_rounded),
                        label: const Text('Print photo'),
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
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, error, stack) =>
                            const Text('Photo could not be read'),
                      ),
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

  Widget photoBox(
    BuildContext dialogContext,
    String title,
    String photoData,
    String mobile,
    bool front,
  ) {
    return Expanded(
      child: FutureBuilder<Uint8List?>(
        future: resolveBookingPhoto(photoData, mobile, front),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          final loading = snapshot.connectionState != ConnectionState.done;
          return InkWell(
            onTap: loading
                ? null
                : () => openLargePhoto(dialogContext, title, bytes),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 150,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border.all(color: CustomColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : bytes == null
                        ? Center(
                            child: Text(
                              snapshot.hasError
                                  ? 'Could not load photo'
                                  : 'Photo not available',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            errorBuilder: (_, error, stack) => const Center(
                              child: Text('Photo could not be read'),
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '$title · Tap to view',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
                    photoBox(
                      dialogContext,
                      "ID FRONT PHOTO",
                      idFrontPhoto,
                      guestMobile,
                      true,
                    ),
                    const SizedBox(width: 12),
                    photoBox(
                      dialogContext,
                      "ID BACK PHOTO",
                      idBackPhoto,
                      guestMobile,
                      false,
                    ),
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
                                    extraMobile,
                                    true,
                                  ),
                                  const SizedBox(width: 12),
                                  photoBox(
                                    dialogContext,
                                    "GUEST ${index + 2} ID BACK PHOTO",
                                    extraBackPhoto,
                                    extraMobile,
                                    false,
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
            onPressed: () => showBookingSlipPrintView(
              dialogContext,
              room,
              showFutureBooking: isFuture,
            ),
            icon: const Icon(Icons.preview_rounded),
            label: const Text("Print view"),
          ),
          CustomButton.outlineIcon(
            onPressed: () => runBookingDocumentAction(
              dialogContext,
              () => shareBookingSlip(room, showFutureBooking: isFuture),
            ),
            icon: const Icon(Icons.share_rounded),
            label: const Text('Send PDF'),
          ),
          CustomButton.icon(
            onPressed: () => runBookingDocumentAction(
              dialogContext,
              () => printBookingSlip(room, showFutureBooking: isFuture),
            ),
            icon: const Icon(Icons.print_rounded),
            label: const Text("Print"),
          ),
        ],
      );
    },
  );
}

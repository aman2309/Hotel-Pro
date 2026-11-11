import '../widgets/live_stay_duration.dart';
import '../widgets/custom_bottom_sheet.dart';
import '../theme/custom_colors.dart';
import '../widgets/hotel_ui.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../widgets/app_toast.dart';

import '../models/customer.dart';
import '../models/room.dart';
import '../stores/customer_store.dart';
import 'booking_slip_dialog.dart';
import '../services/document_output.dart';

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
                            await DocumentOutput.sharePdf(
                              pdf,
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
                            await DocumentOutput.printPdf(
                              pdf,
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

  Widget photoBox(
    BuildContext dialogContext,
    String title,
    String photoData,
    String mobile,
    bool front, {
    String? caption,
  }) {
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
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 150,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: CustomColors.background,
                border: Border.all(color: CustomColors.border),
                borderRadius: BorderRadius.circular(16),
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
                              style: const TextStyle(
                                fontSize: 11,
                                color: CustomColors.muted,
                              ),
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
                      '${caption ?? title} · tap to view',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: CustomColors.muted,
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
        icon: CustomIconBadge(
          isFuture ? Icons.event_rounded : Icons.hotel_rounded,
          color: isFuture ? CustomColors.button : CustomColors.booked,
        ),
        title: CustomSheetTitle(
          "Room ${room.roomNumber} · ${guestName.isEmpty ? "Guest" : guestName}",
          subtitle: isFuture
              ? "Future booking · ${room.roomType}"
              : "Current booking · ${room.roomType}",
        ),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isFuture
                      ? CustomColors.neutralTint
                      : CustomColors.bookedTint,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Check-in",
                            style: TextStyle(
                              fontSize: 11,
                              color: CustomColors.muted,
                            ),
                          ),
                          Text(
                            formatDate(
                              isFuture
                                  ? room.futureBookingDate
                                  : room.bookingTime ?? bookingDate,
                            ),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            formatTime(
                              isFuture
                                  ? room.futureBookingDate
                                  : room.bookingTime,
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: CustomColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: isFuture
                          ? CustomColors.muted
                          : CustomColors.booked,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            "Check-out",
                            style: TextStyle(
                              fontSize: 11,
                              color: CustomColors.muted,
                            ),
                          ),
                          Text(
                            formatDate(
                              isFuture
                                  ? room.futureBookingEnd
                                  : room.bookingEndTime,
                            ),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            formatTime(
                              isFuture
                                  ? room.futureBookingEnd
                                  : room.bookingEndTime,
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: CustomColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!isFuture) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      size: 16,
                      color: CustomColors.muted,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      "Staying for ",
                      style: TextStyle(fontSize: 12, color: CustomColors.muted),
                    ),
                    LiveStayDuration(
                      start: room.bookingTime,
                      checkout: room.checkoutTime,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              const CustomSectionTitle("Guest"),
              CustomDetailCard(
                children: [
                  CustomDetailRow("Guest name", guestName),
                  CustomDetailRow("Mobile number", guestMobile),
                  CustomDetailRow("ID number", guestIdNumber),
                  if (guestAddress.isNotEmpty)
                    CustomDetailRow("Address", guestAddress),
                ],
              ),
              const CustomSectionTitle("Room & payment"),
              CustomDetailCard(
                children: [
                  CustomDetailRow(
                    "Room",
                    "${room.roomNumber} · ${room.roomType}",
                  ),
                  CustomDetailRow("Number of days", bookingDays.toString()),
                  CustomDetailRow("Advance", "₹$bookingAdvance"),
                  CustomDetailRow(
                    "Payment mode",
                    bookingPaymentMode.isEmpty ? "-" : bookingPaymentMode,
                  ),
                ],
              ),
              const CustomSectionTitle("Guest ID photos"),
              Row(
                children: [
                  photoBox(
                    dialogContext,
                    "ID FRONT PHOTO",
                    idFrontPhoto,
                    guestMobile,
                    true,
                    caption: "ID front",
                  ),
                  const SizedBox(width: 10),
                  photoBox(
                    dialogContext,
                    "ID BACK PHOTO",
                    idBackPhoto,
                    guestMobile,
                    false,
                    caption: "ID back",
                  ),
                ],
              ),
              if ((showFutureBooking
                      ? room.futureExtraGuests
                      : room.extraGuests)
                  .isNotEmpty) ...[
                const CustomSectionTitle("Additional guests"),
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

                      // Synced room docs carry an empty photo slot; fall
                      // back to the guest record, which holds the bytes.
                      final String extraFrontPhoto =
                          (guest["idFrontPhoto"]?.toString() ?? "")
                              .trim()
                              .isNotEmpty
                          ? guest["idFrontPhoto"].toString()
                          : extraCustomer?.idFrontPhotoPath ?? "";

                      // Synced room docs carry an empty photo slot; fall
                      // back to the guest record, which holds the bytes.
                      final String extraBackPhoto =
                          (guest["idBackPhoto"]?.toString() ?? "")
                              .trim()
                              .isNotEmpty
                          ? guest["idBackPhoto"].toString()
                          : extraCustomer?.idBackPhotoPath ?? "";

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: CustomSurface(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      "${guest["name"] ?? "Guest ${index + 2}"}",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  CustomStatusBadge(
                                    label: "Guest ${index + 2}",
                                    color: CustomColors.primary,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              CustomDetailRow(
                                "Mobile number",
                                "${guest["mobile"] ?? "-"}",
                              ),
                              CustomDetailRow(
                                "ID number",
                                "${guest["idNumber"] ?? "-"}",
                              ),
                              if ((guest["address"] ?? "")
                                  .toString()
                                  .trim()
                                  .isNotEmpty)
                                CustomDetailRow(
                                  "Address",
                                  "${guest["address"]}",
                                ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  photoBox(
                                    dialogContext,
                                    "GUEST ${index + 2} ID FRONT PHOTO",
                                    extraFrontPhoto,
                                    extraMobile,
                                    true,
                                    caption: "ID front",
                                  ),
                                  const SizedBox(width: 10),
                                  photoBox(
                                    dialogContext,
                                    "GUEST ${index + 2} ID BACK PHOTO",
                                    extraBackPhoto,
                                    extraMobile,
                                    false,
                                    caption: "ID back",
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
              ],
            ],
          ),
        ),
        actions: [
          CustomButton.outlineIcon(
            onPressed: () => showBookingSlipPrintView(
              dialogContext,
              room,
              showFutureBooking: isFuture,
            ),
            icon: const Icon(Icons.preview_rounded),
            label: const Text("Preview"),
          ),
          CustomButton.outlineIcon(
            onPressed: () => runBookingDocumentAction(
              dialogContext,
              () => shareBookingSlip(room, showFutureBooking: isFuture),
            ),
            icon: const Icon(Icons.share_rounded),
            label: const Text('Send'),
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

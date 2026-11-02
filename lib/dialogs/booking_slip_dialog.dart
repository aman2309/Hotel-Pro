import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/customer.dart';
import '../models/room.dart';
import '../services/hotel_photo_bytes.dart';
import '../stores/customer_store.dart';
import '../stores/hotel_settings_store.dart';

Future<void> showBookingSlipDialog(BuildContext context, Room room) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return BookingSlipDialog(room: room);
    },
  );
}

Future<void> showBookingSlipPrintView(BuildContext context, Room room) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 720,
          height: 640,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Room ${room.roomNumber} Print View",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PdfPreview(
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  allowSharing: false,
                  pdfFileName: "Booking-Slip-Room-${room.roomNumber}.pdf",
                  build: (PdfPageFormat format) => buildBookingSlipPdf(room),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> printBookingSlip(Room room) async {
  final Uint8List bytes = await buildBookingSlipPdf(room);
  await Printing.layoutPdf(
    name: "Booking-Slip-Room-${room.roomNumber}",
    dynamicLayout: false,
    onLayout: (PdfPageFormat format) async => bytes,
  );
}

class _SlipGuest {
  const _SlipGuest({
    required this.name,
    required this.mobile,
    required this.idNumber,
    required this.frontPhoto,
    required this.backPhoto,
  });

  final String name;
  final String mobile;
  final String idNumber;
  final String frontPhoto;
  final String backPhoto;
}

class _SlipBooking {
  const _SlipBooking({
    required this.title,
    required this.guestName,
    required this.mobile,
    required this.idNumber,
    required this.address,
    required this.roomLabel,
    required this.bookingDate,
    required this.bookingDay,
    required this.bookingTime,
    required this.stay,
    required this.frontPhoto,
    required this.backPhoto,
    required this.guests,
  });

  final String title;
  final String guestName;
  final String mobile;
  final String idNumber;
  final String address;
  final String roomLabel;
  final String bookingDate;
  final String bookingDay;
  final String bookingTime;
  final String stay;
  final String frontPhoto;
  final String backPhoto;
  final List<_SlipGuest> guests;
}

String _formatDate(DateTime? date) {
  if (date == null) return "-";
  final String day = date.day.toString().padLeft(2, "0");
  final String month = date.month.toString().padLeft(2, "0");
  return "$day-$month-${date.year}";
}

String _formatClock(DateTime? date) {
  if (date == null) return "-";
  int hour = date.hour;
  final String period = hour >= 12 ? "PM" : "AM";
  hour = hour % 12;
  if (hour == 0) hour = 12;
  final String minute = date.minute.toString().padLeft(2, "0");
  return "$hour:$minute $period";
}

String _timeRange(DateTime? from, DateTime? to) {
  final String start = _formatClock(from);
  final String end = _formatClock(to);
  if (end == "-") return start;
  return "$start to $end";
}

Uint8List? _photoBytes(String photoData) => hotelPhotoBytes(photoData);

String _photo(String direct, String? fallback) {
  if (direct.trim().isNotEmpty) return direct;
  return fallback ?? "";
}

_SlipGuest _guestFromMap(Map<String, dynamic> guest) {
  final Customer? saved = CustomerStore.findByMobile(
    guest["mobile"]?.toString() ?? "",
  );
  return _SlipGuest(
    name: guest["name"]?.toString().trim().isNotEmpty == true
        ? guest["name"].toString().trim()
        : "-",
    mobile: guest["mobile"]?.toString().trim().isNotEmpty == true
        ? guest["mobile"].toString().trim()
        : "-",
    idNumber: guest["idNumber"]?.toString().trim().isNotEmpty == true
        ? guest["idNumber"].toString().trim()
        : "-",
    frontPhoto: _photo(
      guest["idFrontPhoto"]?.toString() ?? "",
      saved?.idFrontPhotoPath,
    ),
    backPhoto: _photo(
      guest["idBackPhoto"]?.toString() ?? "",
      saved?.idBackPhotoPath,
    ),
  );
}

List<_SlipBooking> _slipBookings(Room room) {
  final List<_SlipBooking> bookings = [];
  final bool hasCurrent =
      room.guestName.trim().isNotEmpty || room.mobile.trim().isNotEmpty;
  if (hasCurrent) {
    final Customer? customer = CustomerStore.findByMobile(room.mobile);
    bookings.add(
      _SlipBooking(
        title: "BOOKING",
        guestName: room.guestName.isEmpty ? "-" : room.guestName,
        mobile: room.mobile.isEmpty ? "-" : room.mobile,
        idNumber: room.idNumber.isEmpty ? "-" : room.idNumber,
        address: room.guestAddress.trim(),
        roomLabel: "${room.roomNumber}  •  ${room.roomType}",
        bookingDate: _formatDate(room.bookingDate),
        bookingDay: "${room.days}",
        bookingTime: _timeRange(room.bookingTime, room.bookingEndTime),
        stay: room.stayDurationLabel(),
        frontPhoto: customer?.idFrontPhotoPath ?? "",
        backPhoto: customer?.idBackPhotoPath ?? "",
        guests: room.extraGuests.map(_guestFromMap).toList(),
      ),
    );
  }
  if (room.futureBooking &&
      (room.futureGuestName.trim().isNotEmpty ||
          room.futureMobile.trim().isNotEmpty)) {
    final Customer? customer = CustomerStore.findByMobile(room.futureMobile);
    bookings.add(
      _SlipBooking(
        title: "BOOKING",
        guestName: room.futureGuestName.isEmpty ? "-" : room.futureGuestName,
        mobile: room.futureMobile.isEmpty ? "-" : room.futureMobile,
        idNumber: room.futureIdNumber.isEmpty ? "-" : room.futureIdNumber,
        address: room.futureGuestAddress.trim(),
        roomLabel: "${room.roomNumber}  •  ${room.roomType}",
        bookingDate: _formatDate(room.futureBookingDate),
        bookingDay: "${room.futureDays}",
        bookingTime: _timeRange(room.futureBookingDate, room.futureBookingEnd),
        stay: "-",
        frontPhoto: customer?.idFrontPhotoPath ?? "",
        backPhoto: customer?.idBackPhotoPath ?? "",
        guests: room.futureExtraGuests.map(_guestFromMap).toList(),
      ),
    );
  }
  for (var i = 0; i < bookings.length; i++) {
    bookings[i] = _SlipBooking(
      title: "BOOKING ${i + 1}",
      guestName: bookings[i].guestName,
      mobile: bookings[i].mobile,
      idNumber: bookings[i].idNumber,
      address: bookings[i].address,
      roomLabel: bookings[i].roomLabel,
      bookingDate: bookings[i].bookingDate,
      bookingDay: bookings[i].bookingDay,
      bookingTime: bookings[i].bookingTime,
      stay: bookings[i].stay,
      frontPhoto: bookings[i].frontPhoto,
      backPhoto: bookings[i].backPhoto,
      guests: bookings[i].guests,
    );
  }
  return bookings;
}

Future<Uint8List> buildBookingSlipPdf(Room room) async {
  final pw.Document document = pw.Document();
  final List<_SlipBooking> bookings = _slipBookings(room);

  pw.Widget line(String title, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(
              title,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  pw.Widget pdfPhoto(String title, String data) {
    final Uint8List? bytes = _photoBytes(data);
    final pw.MemoryImage? image = bytes == null ? null : pw.MemoryImage(bytes);
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            if (image == null)
              pw.Text("No photo")
            else
              pw.Expanded(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ],
        ),
      ),
    );
  }

  pw.Widget photoRow(String front, String back) {
    return pw.SizedBox(
      height: 210,
      child: pw.Row(
        children: [
          pdfPhoto("AADHAAR FRONT", front),
          pw.SizedBox(width: 12),
          pdfPhoto("AADHAAR BACK", back),
        ],
      ),
    );
  }

  final List<pw.Widget> body = [
    pw.Center(
      child: pw.Text(
        HotelSettingsStore.hotelName.toUpperCase(),
        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
      ),
    ),
    if (HotelSettingsStore.hotelAddress.trim().isNotEmpty) ...[
      pw.SizedBox(height: 4),
      pw.Center(child: pw.Text(HotelSettingsStore.hotelAddress)),
    ],
    if (HotelSettingsStore.hotelMobile.trim().isNotEmpty) ...[
      pw.SizedBox(height: 2),
      pw.Center(child: pw.Text(HotelSettingsStore.hotelMobile)),
    ],
    pw.SizedBox(height: 14),
    pw.Center(
      child: pw.Text(
        "BOOKING SLIP",
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
      ),
    ),
    pw.SizedBox(height: 4),
    pw.Center(child: pw.Text("ID and booking details. No amount.")),
    pw.SizedBox(height: 8),
  ];

  if (bookings.isEmpty) {
    body.add(pw.Text("No booking"));
  }

  for (final _SlipBooking booking in bookings) {
    body.addAll([
      pw.Divider(),
      pw.Text(
        booking.title,
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      line("ID / Guest", booking.guestName),
      line("Mobile", booking.mobile),
      line("ID Number", booking.idNumber),
      if (booking.address.isNotEmpty) line("Address", booking.address),
      line("Room", booking.roomLabel),
      line("Booking Date", booking.bookingDate),
      line("Booking Day", booking.bookingDay),
      line("Booking Time", booking.bookingTime),
      line("Stay", booking.stay),
      pw.SizedBox(height: 8),
      pw.Text(
        "AADHAAR PHOTOS",
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      photoRow(booking.frontPhoto, booking.backPhoto),
    ]);
    for (var i = 0; i < booking.guests.length; i++) {
      final _SlipGuest guest = booking.guests[i];
      body.addAll([
        pw.SizedBox(height: 10),
        pw.Text(
          "GUEST ${i + 2}",
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        line("Name", guest.name),
        line("Mobile", guest.mobile),
        line("ID Number", guest.idNumber),
        pw.SizedBox(height: 6),
        photoRow(guest.frontPhoto, guest.backPhoto),
      ]);
    }
  }

  body.addAll([
    pw.SizedBox(height: 16),
    pw.Divider(),
    pw.Center(
      child: pw.Text(
        HotelSettingsStore.hotelName.toUpperCase(),
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
    ),
  ]);

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(35),
      build: (pw.Context context) => body,
    ),
  );
  return document.save();
}

class BookingSlipDialog extends StatelessWidget {
  const BookingSlipDialog({super.key, required this.room});

  final Room room;

  Widget screenPhoto(String title, String data) {
    final Uint8List? bytes = _photoBytes(data);
    return Expanded(
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Container(
            height: 140,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: bytes == null
                ? const Text("No photo")
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
          ),
        ],
      ),
    );
  }

  Widget detail(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _bookingBlock(_SlipBooking booking) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text(
          booking.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        detail("ID / Guest", booking.guestName),
        detail("Mobile", booking.mobile),
        detail("ID Number", booking.idNumber),
        if (booking.address.isNotEmpty) detail("Address", booking.address),
        detail("Room", booking.roomLabel),
        detail("Booking Date", booking.bookingDate),
        detail("Booking Day", booking.bookingDay),
        detail("Booking Time", booking.bookingTime),
        detail("Stay", booking.stay),
        const SizedBox(height: 8),
        const Text(
          "AADHAAR PHOTOS",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            screenPhoto("AADHAAR FRONT", booking.frontPhoto),
            const SizedBox(width: 10),
            screenPhoto("AADHAAR BACK", booking.backPhoto),
          ],
        ),
        for (var i = 0; i < booking.guests.length; i++) ...[
          const SizedBox(height: 12),
          Text(
            "GUEST ${i + 2}",
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          detail("Name", booking.guests[i].name),
          detail("Mobile", booking.guests[i].mobile),
          detail("ID Number", booking.guests[i].idNumber),
          const SizedBox(height: 8),
          Row(
            children: [
              screenPhoto("FRONT", booking.guests[i].frontPhoto),
              const SizedBox(width: 10),
              screenPhoto("BACK", booking.guests[i].backPhoto),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<_SlipBooking> bookings = _slipBookings(room);
    return AlertDialog(
      title: Text("Room ${room.roomNumber} Booking Slip"),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                HotelSettingsStore.hotelName.toUpperCase(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (HotelSettingsStore.hotelAddress.trim().isNotEmpty)
                Text(HotelSettingsStore.hotelAddress),
              const SizedBox(height: 8),
              Text(
                bookings.length > 1
                    ? "${bookings.length} bookings on this slip. Amount is not shown."
                    : "ID, booking day and time. Amount is not shown.",
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (bookings.isEmpty) const Text("No booking"),
              ...bookings.map(_bookingBlock),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("CLOSE"),
        ),
        OutlinedButton.icon(
          onPressed: () => showBookingSlipPrintView(context, room),
          icon: const Icon(Icons.preview),
          label: const Text("PRINT VIEW"),
        ),
        ElevatedButton.icon(
          onPressed: () => printBookingSlip(room),
          icon: const Icon(Icons.print),
          label: const Text("PRINT"),
        ),
      ],
    );
  }
}

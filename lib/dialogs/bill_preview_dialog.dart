import '../widgets/custom_bottom_sheet.dart';
import '../theme/custom_colors.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_dialog.dart';
import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_record.dart';
import '../models/room.dart';
import '../stores/hotel_settings_store.dart';

Future<void> showBillPreviewDialog(
  BuildContext context,
  BillRecord bill, {
  bool applyGst = false,
}) async {
  await showCustomBottomSheet(
    context: context,
    builder: (BuildContext dialogContext) {
      return BillPreviewDialog(bill: bill, applyGst: applyGst);
    },
  );
}

class BillPreviewDialog extends StatefulWidget {
  const BillPreviewDialog({
    super.key,
    required this.bill,
    this.applyGst = false,
  });

  final BillRecord bill;
  final bool applyGst;

  @override
  State<BillPreviewDialog> createState() => _BillPreviewDialogState();
}

class _BillPreviewDialogState extends State<BillPreviewDialog> {
  late bool gstOnBill;

  BillRecord get bill => widget.bill;

  @override
  void initState() {
    super.initState();
    gstOnBill = widget.applyGst || bill.applyGst;
  }

  String formatDateTime(DateTime? date) {
    if (date == null) {
      return "-";
    }

    final String day = date.day.toString().padLeft(2, "0");
    final String month = date.month.toString().padLeft(2, "0");

    int hour = date.hour;
    final String period = hour >= 12 ? "PM" : "AM";

    hour = hour % 12;

    if (hour == 0) {
      hour = 12;
    }

    final String minute = date.minute.toString().padLeft(2, "0");

    return "$day-$month-${date.year}  $hour:$minute $period";
  }

  String formatPartPaymentDateTime(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return "-";
    }

    try {
      return formatDateTime(DateTime.parse(value.toString()));
    } catch (error) {
      return "-";
    }
  }

  int totalPartPayments() {
    int total = 0;

    for (final payment in bill.partPayments) {
      total += payment["amount"] as int? ?? 0;
    }

    return total;
  }

  int subtotal() {
    return bill.totalBill - bill.discount;
  }

  int gstAmount() {
    if (!gstOnBill) {
      return 0;
    }
    return (subtotal() * HotelSettingsStore.gstTaxRate / 100).round();
  }

  int grandTotal() {
    return subtotal() + gstAmount();
  }

  bool get isCheckedOut => bill.checkoutTime != null;

  int amountReceived() {
    final int received = bill.advance + totalPartPayments();
    if (isCheckedOut) {
      return received + bill.balance;
    }
    return received;
  }

  int balanceDue() {
    final int due = grandTotal() - amountReceived();
    return due < 0 ? 0 : due;
  }

  String gstRateLabel() {
    return HotelSettingsStore.gstTaxRate.toString().replaceFirst(
      RegExp(r'\.0$'),
      '',
    );
  }

  String stayDuration() => bill.stayDurationLabel();

  Future<void> printBill() async {
    final pw.Document document = pw.Document();
    final bool showGst = gstOnBill;
    final int gst = gstAmount();
    final int total = grandTotal();
    final int received = amountReceived();
    final int due = balanceDue();
    final bool checkedOut = isCheckedOut;

    pw.Widget billLine(String title, String value, {bool bold = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(title),
            pw.Text(
              value,
              style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
            ),
          ],
        ),
      );
    }

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(35),
        build: (pw.Context pdfContext) {
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
              pw.SizedBox(height: 5),
              pw.Center(
                child: pw.Text(
                  "FINAL ROOM BILL",
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text(
                  HotelSettingsStore.hotelAddress.toUpperCase(),
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Center(
                child: pw.Text(
                  "Mobile: ${HotelSettingsStore.hotelMobile.isEmpty ? "-" : HotelSettingsStore.hotelMobile}",
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Center(
                child: pw.Text(
                  "Registration No.: ${HotelSettingsStore.registrationNumber.isEmpty ? "-" : HotelSettingsStore.registrationNumber}",
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Center(
                child: pw.Text(
                  "GST No.: ${HotelSettingsStore.gstNumber.isEmpty ? "-" : HotelSettingsStore.gstNumber}",
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: showGst
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  ),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Divider(),
              billLine("Bill No.", bill.billNumber, bold: true),
              billLine("Customer ID", bill.customerId),
              billLine("Guest Name", bill.guestName),
              billLine("Mobile Number", bill.mobile),
              pw.Divider(),
              billLine("Room", "${bill.roomNumber} - ${bill.roomType}"),
              billLine(
                "Booking Date / Time",
                formatDateTime(bill.bookingTime ?? bill.bookingDate),
              ),
              billLine(
                "Checkout Date / Time",
                formatDateTime(bill.checkoutTime),
              ),
              billLine("Stay Duration", stayDuration(), bold: true),
              pw.Divider(),
              billLine("Room Rate", "Rs. ${bill.roomRate} / Day"),
              billLine("Booked Days", bill.bookedDays.toString()),
              billLine("Room Bill", "Rs. ${bill.roomBill}"),
              pw.SizedBox(height: 8),
              pw.Text(
                "EXTRA CHARGES",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 5),
              if (bill.charges.isEmpty) pw.Text("No Extra Charges"),
              ...bill.charges.map(
                (charge) => billLine(
                  Room.extraChargeTitle(charge),
                  "Rs. ${charge["amount"] ?? 0}",
                ),
              ),
              pw.Divider(),
              billLine("TOTAL BILL", "Rs. ${bill.totalBill}", bold: true),
              billLine("DISCOUNT", "Rs. ${bill.discount}"),
              if (showGst) ...[
                billLine("TAXABLE AMOUNT", "Rs. ${subtotal()}", bold: true),
                billLine("GST (${gstRateLabel()}%)", "Rs. $gst", bold: true),
                billLine("GRAND TOTAL", "Rs. $total", bold: true),
              ] else
                billLine(
                  "FINAL BILL",
                  "Rs. ${bill.totalBill - bill.discount}",
                  bold: true,
                ),
              pw.SizedBox(height: 8),
              pw.Text(
                "PAYMENT SUMMARY",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 5),
              billLine(
                "ADVANCE",
                "Rs. ${bill.advance}  (${bill.advancePaymentMode.isEmpty ? "-" : bill.advancePaymentMode})",
              ),
              if (bill.partPayments.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text(
                  "PART PAYMENT HISTORY",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                ...bill.partPayments.map(
                  (payment) => billLine(
                    "${formatPartPaymentDateTime(payment["dateTime"])}  •  ${payment["paymentMode"] ?? "-"}",
                    "Rs. ${payment["amount"] ?? 0}",
                  ),
                ),
                billLine(
                  "TOTAL PART PAYMENT",
                  "Rs. ${totalPartPayments()}",
                  bold: true,
                ),
              ],
              pw.SizedBox(height: 6),
              if (checkedOut)
                billLine(
                  "FINAL BALANCE PAID",
                  "Rs. ${bill.balance}  (${bill.paymentMode.isEmpty ? "-" : bill.paymentMode})",
                  bold: true,
                )
              else
                billLine("BALANCE DUE", "Rs. $due", bold: true),
              pw.Divider(),
              billLine("TOTAL RECEIVED", "Rs. $received", bold: true),
              pw.SizedBox(height: 30),
              pw.Divider(),
              pw.Center(
                child: pw.Text(
                  "Thank You For Staying With Us",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Center(
                child: pw.Text(HotelSettingsStore.hotelName.toUpperCase()),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      name: bill.billNumber,
      dynamicLayout: false,
      onLayout: (PdfPageFormat format) async {
        return document.save();
      },
    );
  }

  Widget detail(String title, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 190,
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomDialog(
      titlePadding: EdgeInsets.zero,
      title: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(color: AppColors.ink),
        child: Column(
          children: [
            Text(
              HotelSettingsStore.hotelName.toUpperCase(),
              style: const TextStyle(
                color: CustomColors.surface,
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Final room bill",
              style: TextStyle(color: CustomColors.surface, fontSize: 15),
            ),
            const SizedBox(height: 7),
            Text(
              HotelSettingsStore.hotelAddress.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: CustomColors.surface, fontSize: 11),
            ),
            const SizedBox(height: 3),
            Text(
              "Mobile: ${HotelSettingsStore.hotelMobile.isEmpty ? "-" : HotelSettingsStore.hotelMobile}",
              style: const TextStyle(color: CustomColors.surface, fontSize: 11),
            ),
            const SizedBox(height: 3),
            Text(
              "Registration No.: ${HotelSettingsStore.registrationNumber.isEmpty ? "-" : HotelSettingsStore.registrationNumber}",
              textAlign: TextAlign.center,
              style: const TextStyle(color: CustomColors.surface, fontSize: 11),
            ),
            const SizedBox(height: 3),
            Text(
              "GST No.: ${HotelSettingsStore.gstNumber.isEmpty ? "-" : HotelSettingsStore.gstNumber}",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CustomColors.surface,
                fontSize: 11,
                fontWeight: gstOnBill ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              detail("Bill Number", bill.billNumber, bold: true),
              detail("Customer ID", bill.customerId),
              detail("Guest Name", bill.guestName),
              detail("Mobile Number", bill.mobile),
              const Divider(),
              detail("Room", "${bill.roomNumber} - ${bill.roomType}"),
              detail(
                "Booking Date / Time",
                formatDateTime(bill.bookingTime ?? bill.bookingDate),
              ),
              detail("Checkout Date / Time", formatDateTime(bill.checkoutTime)),
              detail("Stay Duration", stayDuration(), bold: true),
              const Divider(),
              detail("Room Rate", "₹${bill.roomRate} / Day"),
              detail("Booked Days", bill.bookedDays.toString()),
              detail("Room Bill", "₹${bill.roomBill}"),
              const SizedBox(height: 10),
              const Text(
                "Extra charges",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              if (bill.charges.isEmpty) const Text("No Extra Charges"),
              ...bill.charges.map(
                (charge) => detail(
                  Room.extraChargeTitle(charge),
                  "₹${charge["amount"] ?? 0}",
                ),
              ),
              const Divider(),
              detail("TOTAL BILL", "₹${bill.totalBill}", bold: true),
              detail("DISCOUNT", "₹${bill.discount}"),
              if (gstOnBill) ...[
                detail("TAXABLE AMOUNT", "₹${subtotal()}", bold: true),
                detail(
                  "GST (${gstRateLabel()}%)",
                  "₹${gstAmount()}",
                  bold: true,
                ),
                detail("GRAND TOTAL", "₹${grandTotal()}", bold: true),
              ] else
                detail(
                  "FINAL BILL",
                  "₹${bill.totalBill - bill.discount}",
                  bold: true,
                ),
              const SizedBox(height: 8),
              const Text(
                "Payment summary",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              detail(
                "ADVANCE",
                "₹${bill.advance}  (${bill.advancePaymentMode.isEmpty ? "-" : bill.advancePaymentMode})",
              ),
              if (bill.partPayments.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  "Part payment history",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ...bill.partPayments.map(
                  (payment) => detail(
                    "${formatPartPaymentDateTime(payment["dateTime"])}  •  ${payment["paymentMode"] ?? "-"}",
                    "₹${payment["amount"] ?? 0}",
                  ),
                ),
                detail(
                  "TOTAL PART PAYMENT",
                  "₹${totalPartPayments()}",
                  bold: true,
                ),
              ],
              const SizedBox(height: 6),
              if (isCheckedOut)
                detail(
                  "FINAL BALANCE PAID",
                  "₹${bill.balance}  (${bill.paymentMode.isEmpty ? "-" : bill.paymentMode})",
                  bold: true,
                )
              else
                detail("BALANCE DUE", "₹${balanceDue()}", bold: true),
              const Divider(),
              detail("TOTAL RECEIVED", "₹${amountReceived()}", bold: true),
              const SizedBox(height: 15),
              const Center(
                child: Text(
                  "Thank You For Staying With Us",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        CustomButton.text(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text("Close"),
        ),
        CustomButton.icon(
          onPressed: printBill,
          icon: const Icon(Icons.print_rounded),
          label: const Text("Print"),
        ),
      ],
    );
  }
}

import '../widgets/custom_bottom_sheet.dart';
import '../theme/custom_colors.dart';
import '../widgets/hotel_ui.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/bill_record.dart';
import '../models/room.dart';
import '../stores/hotel_settings_store.dart';
import '../services/document_output.dart';

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

    await DocumentOutput.printPdf(await document.save(), name: bill.billNumber);
  }

  Widget hotelLine(String text, {bool bold = false}) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        height: 1.5,
        color: bold ? CustomColors.text : CustomColors.muted,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int payable = gstOnBill
        ? grandTotal()
        : bill.totalBill - bill.discount;
    final int due = isCheckedOut ? 0 : balanceDue();

    return CustomDialog(
      icon: const CustomIconBadge(Icons.receipt_long_rounded),
      title: CustomSheetTitle(
        "Bill ${bill.billNumber}",
        subtitle: "Room ${bill.roomNumber} · ${bill.guestName}",
      ),
      content: SizedBox(
        width: 650,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: CustomColors.neutralTint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Text(
                    HotelSettingsStore.hotelName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (HotelSettingsStore.hotelAddress.isNotEmpty)
                    hotelLine(HotelSettingsStore.hotelAddress),
                  hotelLine(
                    [
                      if (HotelSettingsStore.hotelMobile.isNotEmpty)
                        "Mobile ${HotelSettingsStore.hotelMobile}",
                      if (HotelSettingsStore.registrationNumber.isNotEmpty)
                        "Reg. ${HotelSettingsStore.registrationNumber}",
                    ].join(" · "),
                  ),
                  if (HotelSettingsStore.gstNumber.isNotEmpty)
                    hotelLine(
                      "GST ${HotelSettingsStore.gstNumber}",
                      bold: gstOnBill,
                    ),
                  const SizedBox(height: 14),
                  Text(
                    gstOnBill ? "Grand total" : "Final bill",
                    style: const TextStyle(
                      fontSize: 12,
                      color: CustomColors.muted,
                    ),
                  ),
                  Text(
                    "₹$payable",
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  CustomStatusBadge(
                    label: due > 0
                        ? "Balance due ₹$due"
                        : isCheckedOut
                        ? "Paid · Checked out"
                        : "Fully paid",
                    color: due > 0
                        ? CustomColors.error
                        : CustomColors.available,
                  ),
                ],
              ),
            ),
            const CustomSectionTitle("Guest"),
            CustomDetailCard(
              children: [
                CustomDetailRow("Guest name", bill.guestName),
                CustomDetailRow("Mobile number", bill.mobile),
              ],
            ),
            const CustomSectionTitle("Stay"),
            CustomDetailCard(
              children: [
                CustomDetailRow(
                  "Room",
                  "${bill.roomNumber} · ${bill.roomType}",
                ),
                CustomDetailRow(
                  "Check-in",
                  formatDateTime(bill.bookingTime ?? bill.bookingDate),
                ),
                CustomDetailRow("Check-out", formatDateTime(bill.checkoutTime)),
                CustomDetailRow("Stay duration", stayDuration(), strong: true),
              ],
            ),
            const CustomSectionTitle("Charges"),
            CustomDetailCard(
              children: [
                CustomDetailRow("Room rate", "₹${bill.roomRate} / day"),
                CustomDetailRow("Booked days", bill.bookedDays.toString()),
                CustomDetailRow("Room bill", "₹${bill.roomBill}"),
                if (bill.charges.isEmpty)
                  const CustomDetailRow("Extra charges", "None")
                else
                  ...bill.charges.map(
                    (charge) => CustomDetailRow(
                      Room.extraChargeTitle(charge),
                      "₹${charge["amount"] ?? 0}",
                    ),
                  ),
                const CustomDetailDivider(),
                CustomDetailRow("Total bill", "₹${bill.totalBill}"),
                CustomDetailRow(
                  "Discount",
                  bill.discount > 0 ? "− ₹${bill.discount}" : "₹0",
                  valueColor: bill.discount > 0 ? CustomColors.available : null,
                ),
                if (gstOnBill) ...[
                  CustomDetailRow("Taxable amount", "₹${subtotal()}"),
                  CustomDetailRow(
                    "GST (${gstRateLabel()}%)",
                    "₹${gstAmount()}",
                  ),
                  const CustomDetailDivider(),
                  CustomDetailRow(
                    "Grand total",
                    "₹${grandTotal()}",
                    strong: true,
                  ),
                ] else ...[
                  const CustomDetailDivider(),
                  CustomDetailRow(
                    "Final bill",
                    "₹${bill.totalBill - bill.discount}",
                    strong: true,
                  ),
                ],
              ],
            ),
            const CustomSectionTitle("Payments"),
            CustomDetailCard(
              children: [
                CustomDetailRow(
                  "Advance",
                  "₹${bill.advance} · ${bill.advancePaymentMode.isEmpty ? "-" : bill.advancePaymentMode}",
                ),
                ...bill.partPayments.map(
                  (payment) => CustomDetailRow(
                    "Part payment\n${formatPartPaymentDateTime(payment["dateTime"])}",
                    "₹${payment["amount"] ?? 0} · ${payment["paymentMode"] ?? "-"}",
                  ),
                ),
                if (bill.partPayments.isNotEmpty)
                  CustomDetailRow(
                    "Total part payment",
                    "₹${totalPartPayments()}",
                  ),
                if (isCheckedOut)
                  CustomDetailRow(
                    "Final balance paid",
                    "₹${bill.balance} · ${bill.paymentMode.isEmpty ? "-" : bill.paymentMode}",
                  )
                else
                  CustomDetailRow(
                    "Balance due",
                    "₹${balanceDue()}",
                    valueColor: balanceDue() > 0 ? CustomColors.error : null,
                  ),
                const CustomDetailDivider(),
                CustomDetailRow(
                  "Total received",
                  "₹${amountReceived()}",
                  strong: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              "Thank you for staying with us",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: CustomColors.muted),
            ),
          ],
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

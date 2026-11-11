import '../widgets/custom_bottom_sheet.dart';
import '../theme/custom_colors.dart';
import '../widgets/date_time_field.dart';
import '../widgets/hotel_ui.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_record.dart';
import '../stores/bill_store.dart';
import '../stores/hotel_settings_store.dart';
import 'bill_preview_dialog.dart';
import '../services/document_output.dart';

bool _isSameDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

String _formatDate(DateTime date) {
  final String day = date.day.toString().padLeft(2, "0");
  final String month = date.month.toString().padLeft(2, "0");

  return "$day-$month-${date.year}";
}

String _periodLabel(DateTime from, DateTime to) {
  final DateTime now = DateTime.now();
  if (_isSameDay(from, to)) {
    if (_isSameDay(from, now)) return "Today";
    if (_isSameDay(from, now.subtract(const Duration(days: 1)))) {
      return "Yesterday";
    }
    return _formatDate(from);
  }
  return "${_formatDate(from)} – ${_formatDate(to)}";
}

String _formatDateTime(DateTime? date) {
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

  return "$day-$month-${date.year} $hour:$minute $period";
}

List<BillRecord> _billsForRange(DateTime startDate, DateTime endDate) {
  final DateTime start = DateTime(
    startDate.year,
    startDate.month,
    startDate.day,
  );

  final DateTime end = DateTime(
    endDate.year,
    endDate.month,
    endDate.day,
    23,
    59,
    59,
    999,
  );

  final List<BillRecord> bills = BillStore.bills.where((bill) {
    final DateTime? when = bill.checkoutTime;
    if (when == null) {
      return false;
    }
    return !when.isBefore(start) && !when.isAfter(end);
  }).toList();

  bills.sort((first, second) {
    final DateTime a =
        first.checkoutTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final DateTime b =
        second.checkoutTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    return b.compareTo(a);
  });

  return bills;
}

Map<String, int> _calculateTotals(List<BillRecord> bills) {
  int roomRevenue = 0;
  int extraCharges = 0;
  int totalCollection = 0;
  int cash = 0;
  int upi = 0;
  int card = 0;
  int bankTransfer = 0;

  for (final BillRecord bill in bills) {
    roomRevenue += bill.roomBill;
    extraCharges += bill.extraCharges;
    totalCollection += bill.totalBill;

    void addPayment(String paymentMode, int amount) {
      final String mode = paymentMode.trim().toLowerCase();

      if (mode == "cash") {
        cash += amount;
      } else if (mode == "upi") {
        upi += amount;
      } else if (mode == "card") {
        card += amount;
      } else if (mode == "bank transfer") {
        bankTransfer += amount;
      }
    }

    if (bill.advance > 0) {
      addPayment(bill.advancePaymentMode, bill.advance);
    }

    int totalPartPayments = 0;

    for (final payment in bill.partPayments) {
      final dynamic rawAmount = payment["amount"];
      final int amount = rawAmount is int
          ? rawAmount
          : rawAmount is num
          ? rawAmount.toInt()
          : int.tryParse(rawAmount?.toString() ?? "") ?? 0;
      final String paymentMode = payment["paymentMode"]?.toString() ?? "";

      totalPartPayments += amount;
      addPayment(paymentMode, amount);
    }

    final int checkoutPayment =
        bill.totalBill - bill.advance - totalPartPayments;

    if (checkoutPayment > 0) {
      addPayment(bill.paymentMode, checkoutPayment);
    }
  }

  return {
    "roomRevenue": roomRevenue,
    "extraCharges": extraCharges,
    "totalCollection": totalCollection,
    "cash": cash,
    "upi": upi,
    "card": card,
    "bankTransfer": bankTransfer,
  };
}

Map<int, Map<String, int>> _calculateRoomWiseTotals(List<BillRecord> bills) {
  final Map<int, Map<String, int>> roomTotals = {};

  for (final BillRecord bill in bills) {
    roomTotals.putIfAbsent(
      bill.roomNumber,
      () => {
        "bills": 0,
        "roomRevenue": 0,
        "extraCharges": 0,
        "totalCollection": 0,
      },
    );

    final Map<String, int> totals = roomTotals[bill.roomNumber]!;

    totals["bills"] = totals["bills"]! + 1;
    totals["roomRevenue"] = totals["roomRevenue"]! + bill.roomBill;
    totals["extraCharges"] = totals["extraCharges"]! + bill.extraCharges;
    totals["totalCollection"] = totals["totalCollection"]! + bill.totalBill;
  }

  return roomTotals;
}

Future<void> _showRoomWiseReport(
  BuildContext context,
  DateTime fromDate,
  DateTime toDate,
  List<BillRecord> bills,
) async {
  final Map<int, Map<String, int>> roomTotals = _calculateRoomWiseTotals(bills);

  final List<int> roomNumbers = roomTotals.keys.toList()..sort();

  await showCustomBottomSheet(
    context: context,
    builder: (BuildContext roomReportContext) {
      return CustomDialog(
        icon: const CustomIconBadge(Icons.meeting_room_rounded),
        title: CustomSheetTitle(
          "Room-wise report",
          subtitle:
              "${HotelSettingsStore.hotelName} · ${_periodLabel(fromDate, toDate)}",
        ),
        content: roomNumbers.isEmpty
            ? const CustomEmptyState(
                title: "No rooms billed",
                message: "No bills were closed in this period.",
                icon: Icons.meeting_room_outlined,
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final int roomNumber in roomNumbers)
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
                                    "Room $roomNumber",
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                CustomStatusBadge(
                                  label:
                                      "${roomTotals[roomNumber]!["bills"]} ${roomTotals[roomNumber]!["bills"] == 1 ? "bill" : "bills"}",
                                  color: CustomColors.primary,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            CustomDetailRow(
                              "Room revenue",
                              "₹${roomTotals[roomNumber]!["roomRevenue"]}",
                            ),
                            CustomDetailRow(
                              "Extra charges",
                              "₹${roomTotals[roomNumber]!["extraCharges"]}",
                            ),
                            const CustomDetailDivider(),
                            CustomDetailRow(
                              "Total collection",
                              "₹${roomTotals[roomNumber]!["totalCollection"]}",
                              strong: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
        actions: [
          CustomButton.text(
            autofocus: true,
            onPressed: () {
              Navigator.pop(roomReportContext);
            },
            child: const Text("Close"),
          ),
        ],
      );
    },
  );
}

Future<void> _printReport(
  BuildContext context,
  DateTime reportFromDate,
  DateTime reportToDate,
  List<BillRecord> bills,
  Map<String, int> totals,
) async {
  try {
    pw.Font? baseFont;
    pw.Font? boldFont;

    try {
      baseFont = await PdfGoogleFonts.notoSansRegular();
      boldFont = await PdfGoogleFonts.notoSansBold();
    } catch (error) {
      debugPrint("PDF font download failed: $error");
    }

    final pw.Document pdf = pw.Document();

    pw.Widget summaryLine(String title, String value, {bool bold = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: bold ? boldFont : baseFont,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
            pw.Text(
              value,
              style: pw.TextStyle(
                font: bold ? boldFont : baseFont,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: baseFont != null && boldFont != null
            ? pw.ThemeData.withFont(base: baseFont, bold: boldFont)
            : null,
        build: (pw.Context pdfContext) {
          return [
            pw.Center(
              child: pw.Text(
                HotelSettingsStore.hotelName.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Center(
              child: pw.Text(
                HotelSettingsStore.hotelAddress.isEmpty
                    ? "-"
                    : HotelSettingsStore.hotelAddress.toUpperCase(),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                "Mobile: ${HotelSettingsStore.hotelMobile.isEmpty ? "-" : HotelSettingsStore.hotelMobile}",
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                "Property / Registration No.: ${HotelSettingsStore.registrationNumber.isEmpty ? "-" : HotelSettingsStore.registrationNumber}",
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                _isSameDay(reportFromDate, reportToDate)
                    ? "DAILY REPORT - ${_formatDate(reportFromDate)}"
                    : "REPORT ${_formatDate(reportFromDate)} TO ${_formatDate(reportToDate)}",
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Divider(),
            summaryLine("TOTAL BILLS", bills.length.toString(), bold: true),
            summaryLine("ROOM REVENUE", "Rs. ${totals["roomRevenue"]}"),
            summaryLine("EXTRA CHARGES", "Rs. ${totals["extraCharges"]}"),
            summaryLine(
              "TOTAL COLLECTION",
              "Rs. ${totals["totalCollection"]}",
              bold: true,
            ),
            summaryLine("CASH", "Rs. ${totals["cash"]}"),
            summaryLine("UPI", "Rs. ${totals["upi"]}"),
            summaryLine("CARD", "Rs. ${totals["card"]}"),
            summaryLine("BANK TRANSFER", "Rs. ${totals["bankTransfer"]}"),
            pw.SizedBox(height: 12),
            pw.Divider(),
            pw.Text(
              "BILL DETAILS",
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            if (bills.isEmpty)
              pw.Center(child: pw.Text("No Bills Found For Selected Date")),
            if (bills.isNotEmpty)
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: const {
                  0: pw.FlexColumnWidth(1.4),
                  1: pw.FlexColumnWidth(1.4),
                  2: pw.FlexColumnWidth(0.7),
                  3: pw.FlexColumnWidth(1.2),
                  4: pw.FlexColumnWidth(1.1),
                  5: pw.FlexColumnWidth(0.8),
                  6: pw.FlexColumnWidth(0.9),
                },
                children: [
                  pw.TableRow(
                    children:
                        [
                          "Bill No.",
                          "Guest",
                          "Room",
                          "Checkout",
                          "Duration",
                          "Mode",
                          "Amount",
                        ].map((title) {
                          return pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              title,
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 8,
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                  ...bills.map((bill) {
                    return pw.TableRow(
                      children:
                          [
                            bill.billNumber,
                            bill.guestName,
                            bill.roomNumber.toString(),
                            _formatDateTime(bill.checkoutTime),
                            bill.stayDurationLabel(),
                            bill.paymentMode,
                            "Rs. ${bill.totalBill}",
                          ].map((value) {
                            return pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(
                                value,
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                            );
                          }).toList(),
                    );
                  }),
                ],
              ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.Center(
              child: pw.Text(
                "${HotelSettingsStore.hotelName.toUpperCase()} - DAILY REPORT",
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                ),
              ),
            ),
          ];
        },
      ),
    );

    final Uint8List pdfBytes = await pdf.save();
    final String reportName = _isSameDay(reportFromDate, reportToDate)
        ? "Silver_Cloud_Report_${_formatDate(reportFromDate)}"
        : "Silver_Cloud_Report_${_formatDate(reportFromDate)}_to_${_formatDate(reportToDate)}";

    try {
      await DocumentOutput.printPdf(pdfBytes, name: reportName);
    } catch (layoutError) {
      debugPrint("PDF layout failed, trying share: $layoutError");
      await DocumentOutput.sharePdf(pdfBytes, filename: "$reportName.pdf");
    }
  } catch (error) {
    debugPrint("PRINT PDF REPORT ERROR: $error");

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("PDF print failed: $error")));
    }
  }
}

Widget _paymentRow(String label, int amount, IconData icon) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(icon, size: 18, color: CustomColors.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: CustomColors.muted),
          ),
        ),
        Text(
          "₹$amount",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: amount == 0 ? CustomColors.muted : CustomColors.text,
          ),
        ),
      ],
    ),
  );
}

Widget _billTile(BuildContext dialogContext, BillRecord bill) {
  return CustomSurface(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: () =>
          showBillPreviewDialog(dialogContext, bill, applyGst: bill.applyGst),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CustomColors.neutralTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Room",
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.2,
                      color: CustomColors.muted,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      "${bill.roomNumber}",
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bill.guestName.isEmpty ? "Guest" : bill.guestName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    "${bill.billNumber} · ${_formatDateTime(bill.checkoutTime)}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: CustomColors.muted,
                    ),
                  ),
                  Text(
                    "${bill.stayDurationLabel()} · ${bill.paymentMode.isEmpty ? "-" : bill.paymentMode}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: CustomColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              "₹${bill.totalBill}",
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: CustomColors.muted,
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showReportsDialog(BuildContext context) async {
  await showCustomBottomSheet(
    context: context,
    builder: (BuildContext dialogContext) {
      return CustomDialog(
        icon: const CustomIconBadge(Icons.insights_rounded),
        title: CustomSheetTitle(
          "Reports",
          subtitle: HotelSettingsStore.hotelName,
        ),
        content: const ReportsPanel(),
        actions: [
          CustomButton.text(
            autofocus: true,
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text("Close"),
          ),
        ],
      );
    },
  );
}

/// Date-range report: shared by the Reports tab and the Reports sheet.
class ReportsPanel extends StatefulWidget {
  const ReportsPanel({super.key});

  @override
  State<ReportsPanel> createState() => _ReportsPanelState();
}

class _ReportsPanelState extends State<ReportsPanel> {
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();

  void setRange(DateTime from, DateTime to) {
    setState(() {
      fromDate = from;
      toDate = to;
    });
  }

  Future<void> pickFromDate() async {
    final DateTime? pickedDate = await showCustomDateSheet(
      context: context,
      initialDate: fromDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null && mounted) {
      setState(() {
        fromDate = pickedDate;

        if (toDate.isBefore(fromDate)) {
          toDate = fromDate;
        }
      });
    }
  }

  Future<void> pickToDate() async {
    final DateTime? pickedDate = await showCustomDateSheet(
      context: context,
      initialDate: toDate,
      firstDate: fromDate,
      lastDate: DateTime.now(),
    );

    if (pickedDate != null && mounted) {
      setState(() {
        toDate = pickedDate;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<BillRecord> selectedBills = _billsForRange(fromDate, toDate);

    final Map<String, int> totals = _calculateTotals(selectedBills);

    final DateTime today = DateTime.now();
    final DateTime yesterday = today.subtract(const Duration(days: 1));
    final DateTime weekStart = today.subtract(const Duration(days: 6));

    final bool showingToday =
        _isSameDay(fromDate, today) && _isSameDay(toDate, today);

    final bool showingYesterday =
        _isSameDay(fromDate, yesterday) && _isSameDay(toDate, yesterday);

    final bool showingWeek =
        _isSameDay(fromDate, weekStart) && _isSameDay(toDate, today);

    final int reportDays =
        DateTime(toDate.year, toDate.month, toDate.day)
            .difference(DateTime(fromDate.year, fromDate.month, fromDate.day))
            .inDays +
        1;

    final Widget fromField = DateTimeField(
      label: "From",
      value: _formatDate(fromDate),
      icon: Icons.date_range_rounded,
      onTap: pickFromDate,
    );

    final Widget toField = DateTimeField(
      label: "To",
      value: _formatDate(toDate),
      icon: Icons.event_available_rounded,
      onTap: pickToDate,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text("Today"),
              selected: showingToday,
              onSelected: (_) => setRange(today, today),
            ),
            ChoiceChip(
              label: const Text("Yesterday"),
              selected: showingYesterday,
              onSelected: (_) => setRange(yesterday, yesterday),
            ),
            ChoiceChip(
              label: const Text("Last 7 days"),
              selected: showingWeek,
              onSelected: (_) => setRange(weekStart, today),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (constraints.maxWidth < 480) {
              return Column(children: [fromField, toField]);
            }
            return Row(
              children: [
                Expanded(child: fromField),
                const SizedBox(width: 10),
                Expanded(child: toField),
              ],
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  "${_periodLabel(fromDate, toDate)} · $reportDays ${reportDays == 1 ? "day" : "days"}",
                  style: const TextStyle(
                    fontSize: 12,
                    color: CustomColors.muted,
                  ),
                ),
              ),
              CustomButton.outlineIcon(
                onPressed: () => _printReport(
                  context,
                  fromDate,
                  toDate,
                  selectedBills,
                  totals,
                ),
                icon: const Icon(Icons.print_rounded, size: 18),
                label: const Text("Print PDF"),
              ),
            ],
          ),
        ),
        CustomStatGrid(
          children: [
            CustomStatCard(
              label: "Collection",
              value: "₹${totals["totalCollection"]}",
              color: CustomColors.available,
              icon: Icons.currency_rupee_rounded,
            ),
            CustomStatCard(
              label: selectedBills.length == 1 ? "Bill" : "Bills",
              value: selectedBills.length.toString(),
              color: CustomColors.primary,
              icon: Icons.receipt_long_rounded,
            ),
            CustomStatCard(
              label: "Room revenue",
              value: "₹${totals["roomRevenue"]}",
              color: CustomColors.booked,
              icon: Icons.hotel_rounded,
            ),
            CustomStatCard(
              label: "Extra charges",
              value: "₹${totals["extraCharges"]}",
              color: CustomColors.cleaning,
              icon: Icons.add_card_rounded,
            ),
          ],
        ),
        const CustomSectionTitle("Payments received"),
        CustomDetailCard(
          children: [
            _paymentRow("Cash", totals["cash"]!, Icons.payments_rounded),
            _paymentRow("UPI", totals["upi"]!, Icons.qr_code_rounded),
            _paymentRow("Card", totals["card"]!, Icons.credit_card_rounded),
            _paymentRow(
              "Bank transfer",
              totals["bankTransfer"]!,
              Icons.account_balance_rounded,
            ),
          ],
        ),
        CustomSectionTitle(
          selectedBills.isEmpty ? "Bills" : "Bills (${selectedBills.length})",
          trailing: selectedBills.isEmpty
              ? null
              : CustomButton.text(
                  onPressed: () => _showRoomWiseReport(
                    context,
                    fromDate,
                    toDate,
                    selectedBills,
                  ),
                  child: const Text("Room-wise"),
                ),
        ),
        if (selectedBills.isEmpty)
          const CustomEmptyState(
            title: "No bills yet",
            message: "Bills appear here once guests check out in this period.",
            icon: Icons.receipt_long_outlined,
          )
        else
          for (final BillRecord bill in selectedBills)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _billTile(context, bill),
            ),
      ],
    );
  }
}

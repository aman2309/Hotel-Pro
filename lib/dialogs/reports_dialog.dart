import '../widgets/custom_bottom_sheet.dart';
import '../theme/custom_colors.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_dialog.dart';
import '../theme/app_theme.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/bill_record.dart';
import '../stores/bill_store.dart';
import '../stores/hotel_settings_store.dart';
import 'bill_preview_dialog.dart';

Future<void> showReportsDialog(BuildContext context) async {
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();

  bool isSameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  String formatDate(DateTime date) {
    final String day = date.day.toString().padLeft(2, "0");
    final String month = date.month.toString().padLeft(2, "0");

    return "$day-$month-${date.year}";
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

    return "$day-$month-${date.year} $hour:$minute $period";
  }

  List<BillRecord> billsForRange(DateTime startDate, DateTime endDate) {
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

  Map<String, int> calculateTotals(List<BillRecord> bills) {
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

  Map<int, Map<String, int>> calculateRoomWiseTotals(List<BillRecord> bills) {
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

  Future<void> showRoomWiseReport(
    BuildContext context,
    DateTime fromDate,
    DateTime toDate,
    List<BillRecord> bills,
  ) async {
    final Map<int, Map<String, int>> roomTotals = calculateRoomWiseTotals(
      bills,
    );

    final List<int> roomNumbers = roomTotals.keys.toList()..sort();

    await showCustomBottomSheet(
      context: context,
      builder: (BuildContext roomReportContext) {
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
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Room-wise report",
                  style: const TextStyle(
                    color: CustomColors.surface,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  "${formatDate(fromDate)} TO ${formatDate(toDate)}",
                  style: const TextStyle(
                    color: CustomColors.surface,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          content: SizedBox(
            width: 800,
            height: 550,
            child: roomNumbers.isEmpty
                ? const Center(
                    child: Text(
                      "No Room Data Found For Selected Period",
                      style: TextStyle(fontSize: 17),
                    ),
                  )
                : ListView.separated(
                    itemCount: roomNumbers.length,
                    separatorBuilder: (BuildContext context, int index) {
                      return const Divider();
                    },
                    itemBuilder: (BuildContext context, int index) {
                      final int roomNumber = roomNumbers[index];

                      final Map<String, int> totals = roomTotals[roomNumber]!;

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "ROOM $roomNumber",
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 25,
                                runSpacing: 8,
                                children: [
                                  Text("Bills : ${totals["bills"]}"),
                                  Text(
                                    "Room Revenue : ₹${totals["roomRevenue"]}",
                                  ),
                                  Text(
                                    "Extra Charges : ₹${totals["extraCharges"]}",
                                  ),
                                  Text(
                                    "Total Collection : ₹${totals["totalCollection"]}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
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

  Future<void> printReport(
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
                  isSameDay(reportFromDate, reportToDate)
                      ? "DAILY REPORT - ${formatDate(reportFromDate)}"
                      : "REPORT ${formatDate(reportFromDate)} TO ${formatDate(reportToDate)}",
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
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
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
                              formatDateTime(bill.checkoutTime),
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
      final String reportName = isSameDay(reportFromDate, reportToDate)
          ? "Silver_Cloud_Report_${formatDate(reportFromDate)}"
          : "Silver_Cloud_Report_${formatDate(reportFromDate)}_to_${formatDate(reportToDate)}";

      try {
        await Printing.layoutPdf(
          name: reportName,
          dynamicLayout: false,
          onLayout: (PdfPageFormat format) async => pdfBytes,
        );
      } catch (layoutError) {
        debugPrint("PDF layout failed, trying share: $layoutError");
        await Printing.sharePdf(bytes: pdfBytes, filename: "$reportName.pdf");
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

  Widget reportBox(String title, String value, IconData icon) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: CustomColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Text(title, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  await showCustomBottomSheet(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter updateDialog) {
          final List<BillRecord> selectedBills = billsForRange(
            fromDate,
            toDate,
          );

          final Map<String, int> totals = calculateTotals(selectedBills);

          final DateTime today = DateTime.now();
          final DateTime yesterday = today.subtract(const Duration(days: 1));

          final bool showingToday =
              isSameDay(fromDate, today) && isSameDay(toDate, today);

          final bool showingYesterday =
              isSameDay(fromDate, yesterday) && isSameDay(toDate, yesterday);

          final bool singleDate = isSameDay(fromDate, toDate);

          final int reportDays =
              DateTime(toDate.year, toDate.month, toDate.day)
                  .difference(
                    DateTime(fromDate.year, fromDate.month, fromDate.day),
                  )
                  .inDays +
              1;

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
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    showingToday
                        ? "TODAY REPORT"
                        : showingYesterday
                        ? "YESTERDAY REPORT"
                        : singleDate
                        ? "REPORT - ${formatDate(fromDate)}"
                        : "REPORT ${formatDate(fromDate)} TO ${formatDate(toDate)}",
                    style: const TextStyle(
                      color: CustomColors.surface,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            content: SizedBox(
              width: MediaQuery.of(dialogContext).size.width * 0.92,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 46),
                          child: CustomButton.icon(
                            onPressed: () {
                              updateDialog(() {
                                fromDate = DateTime.now();
                                toDate = DateTime.now();
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.today_rounded, size: 16),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                "Today",
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 46),
                          child: CustomButton.icon(
                            onPressed: () {
                              updateDialog(() {
                                final DateTime day = DateTime.now().subtract(
                                  const Duration(days: 1),
                                );
                                fromDate = day;
                                toDate = day;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.history_rounded, size: 16),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                "Yesterday",
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      CustomButton.icon(
                        onPressed: () async {
                          final DateTime? pickedDate =
                              await showCustomDateSheet(
                                context: dialogContext,
                                initialDate: fromDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );

                          if (pickedDate != null) {
                            updateDialog(() {
                              fromDate = pickedDate;

                              if (toDate.isBefore(fromDate)) {
                                toDate = fromDate;
                              }
                            });
                          }
                        },
                        icon: const Icon(Icons.date_range_rounded),
                        label: Text("FROM : ${formatDate(fromDate)}"),
                      ),
                      CustomButton.icon(
                        onPressed: () async {
                          final DateTime? pickedDate =
                              await showCustomDateSheet(
                                context: dialogContext,
                                initialDate: toDate,
                                firstDate: fromDate,
                                lastDate: DateTime.now(),
                              );

                          if (pickedDate != null) {
                            updateDialog(() {
                              toDate = pickedDate;
                            });
                          }
                        },
                        icon: const Icon(Icons.event_available_rounded),
                        label: Text("TO : ${formatDate(toDate)}"),
                      ),
                      CustomButton.icon(
                        onPressed: () async {
                          await printReport(
                            dialogContext,
                            fromDate,
                            toDate,
                            selectedBills,
                            totals,
                          );
                        },
                        icon: const Icon(Icons.print_rounded),
                        label: const Text("Print PDF report"),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: CustomColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "DURATION : $reportDays ${reportDays == 1 ? "DAY" : "DAYS"}",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      CustomButton.icon(
                        onPressed: () async {
                          await showRoomWiseReport(
                            dialogContext,
                            fromDate,
                            toDate,
                            selectedBills,
                          );
                        },
                        icon: const Icon(Icons.meeting_room_rounded),
                        label: const Text("Room-wise report"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        reportBox(
                          showingToday
                              ? "TODAY BILLS"
                              : showingYesterday
                              ? "YESTERDAY BILLS"
                              : "TOTAL BILLS",
                          selectedBills.length.toString(),
                          Icons.receipt_long_rounded,
                        ),
                        const SizedBox(width: 10),
                        reportBox(
                          "ROOM REVENUE",
                          "₹${totals["roomRevenue"]}",
                          Icons.hotel_rounded,
                        ),
                        const SizedBox(width: 10),
                        reportBox(
                          "EXTRA CHARGES",
                          "₹${totals["extraCharges"]}",
                          Icons.add_card_rounded,
                        ),
                        const SizedBox(width: 10),
                        reportBox(
                          "TOTAL COLLECTION",
                          "₹${totals["totalCollection"]}",
                          Icons.currency_rupee_rounded,
                        ),
                        const SizedBox(width: 10),
                        reportBox(
                          "CASH",
                          "₹${totals["cash"]}",
                          Icons.payments_rounded,
                        ),
                        const SizedBox(width: 10),
                        reportBox(
                          "UPI",
                          "₹${totals["upi"]}",
                          Icons.qr_code_rounded,
                        ),
                        const SizedBox(width: 10),
                        reportBox(
                          "CARD",
                          "₹${totals["card"]}",
                          Icons.credit_card_rounded,
                        ),
                        const SizedBox(width: 10),
                        reportBox(
                          "BANK TRANSFER",
                          "₹${totals["bankTransfer"]}",
                          Icons.account_balance_rounded,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    showingToday
                        ? "TODAY BILLS"
                        : showingYesterday
                        ? "YESTERDAY BILLS"
                        : singleDate
                        ? "BILLS - ${formatDate(fromDate)}"
                        : "BILLS ${formatDate(fromDate)} TO ${formatDate(toDate)}",
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  SizedBox(
                    height: (MediaQuery.sizeOf(dialogContext).height * .5)
                        .clamp(180.0, 400.0),
                    child: selectedBills.isEmpty
                        ? Center(
                            child: Text(
                              singleDate
                                  ? "No Bills Found For ${formatDate(fromDate)}"
                                  : "No Bills Found From ${formatDate(fromDate)} To ${formatDate(toDate)}",
                              style: const TextStyle(fontSize: 17),
                            ),
                          )
                        : ListView.separated(
                            itemCount: selectedBills.length,
                            separatorBuilder:
                                (BuildContext context, int index) {
                                  return const Divider();
                                },
                            itemBuilder: (BuildContext context, int index) {
                              final BillRecord bill = selectedBills[index];

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${bill.billNumber} · ${bill.guestName}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Room ${bill.roomNumber} · ${formatDateTime(bill.checkoutTime)} · ${bill.stayDurationLabel()} · ${bill.paymentMode}',
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 14,
                                      runSpacing: 10,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          '₹${bill.totalBill}',
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        CustomButton.outlineIcon(
                                          onPressed: () =>
                                              showBillPreviewDialog(
                                                dialogContext,
                                                bill,
                                                applyGst: bill.applyGst,
                                              ),
                                          icon: const Icon(
                                            Icons.visibility_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('View bill'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
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
            ],
          );
        },
      );
    },
  );
}

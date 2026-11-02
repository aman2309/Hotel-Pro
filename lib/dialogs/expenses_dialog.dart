import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../stores/expense_store.dart';
import '../stores/hotel_settings_store.dart';

Future<void> showExpensesDialog(BuildContext context) async {
  await ExpenseStore.loadExpenses();

  if (!context.mounted) {
    return;
  }

  final TextEditingController descriptionController =
      TextEditingController();

  final TextEditingController amountController =
      TextEditingController();

  final FocusNode descriptionFocus = FocusNode();
  final FocusNode amountFocus = FocusNode();
  final FocusNode paymentFocus = FocusNode();
  final FocusNode saveFocus = FocusNode();

  String category = "Cleaning";
  String paymentMode = "Cash";

  String formatDateTime(String value) {
    try {
      final DateTime date = DateTime.parse(value);

      final String day = date.day.toString().padLeft(2, "0");
      final String month = date.month.toString().padLeft(2, "0");

      return "$day-$month-${date.year}";
    } catch (error) {
      return "-";
    }
  }

  await showDialog(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (
          BuildContext context,
          StateSetter updateDialog,
        ) {
          int totalExpenses() {
            int total = 0;

            for (final expense in ExpenseStore.expenses) {
              total += expense["amount"] as int;
            }

            return total;
          }

          Future<void> saveExpense() async {
            final String description =
                descriptionController.text.trim();

            final int amount =
                int.tryParse(amountController.text.trim()) ?? 0;

            if (description.isEmpty || amount <= 0) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Please enter description and valid amount",
                  ),
                ),
              );

              return;
            }

            await ExpenseStore.addExpense({
              "dateTime": DateTime.now().toIso8601String(),
              "category": category,
              "description": description,
              "amount": amount,
              "paymentMode": paymentMode,
            });

            descriptionController.clear();
            amountController.clear();

            updateDialog(() {
              category = "Cleaning";
              paymentMode = "Cash";
            });

            descriptionFocus.requestFocus();

            if (!dialogContext.mounted) {
              return;
            }

            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(
                content: Text("EXPENSE SAVED SUCCESSFULLY"),
              ),
            );
          }

          Future<void> printExpenseReport() async {
            final pw.Document pdf = pw.Document();

            pdf.addPage(
              pw.MultiPage(
                pageFormat: PdfPageFormat.a4,
                margin: const pw.EdgeInsets.all(30),
                build: (pw.Context context) {
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
                    pw.SizedBox(height: 4),
                    pw.Center(
                      child: pw.Text(
                        "HOTEL EXPENSE REPORT",
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 5),
                  pw.Center(
                    child: pw.Text(
                      HotelSettingsStore.hotelAddress.toUpperCase(),
                      textAlign: pw.TextAlign.center,
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
                      "Registration No.: ${HotelSettingsStore.registrationNumber.isEmpty ? "-" : HotelSettingsStore.registrationNumber}",
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Center(
                    child: pw.Text(
                      "GST No.: ${HotelSettingsStore.gstNumber.isEmpty ? "-" : HotelSettingsStore.gstNumber}",
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                  pw.SizedBox(height: 15),
                    pw.TableHelper.fromTextArray(
                      headers: const [
                        "DATE",
                        "CATEGORY",
                        "DESCRIPTION",
                        "PAYMENT MODE",
                        "AMOUNT",
                      ],
                      data: ExpenseStore.expenses.reversed.map((expense) {
                        return [
                          formatDateTime(
                            expense["dateTime"].toString(),
                          ),
                          expense["category"].toString(),
                          expense["description"].toString(),
                          expense["paymentMode"].toString(),
                          "Rs. ${expense["amount"]}",
                        ];
                      }).toList(),
                      headerStyle: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                      ),
                      cellPadding: const pw.EdgeInsets.all(6),
                    ),
                    pw.SizedBox(height: 15),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        "TOTAL EXPENSES : Rs. ${totalExpenses()}",
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ];
                },
              ),
            );

            await Printing.layoutPdf(
              name: "Silver_Cloud_Expense_Report.pdf",
              dynamicLayout: false,
              onLayout: (PdfPageFormat format) async => pdf.save(),
            );
          }

          return AlertDialog(
            title: const Text("HOTEL EXPENSES"),
            content: SizedBox(
              width:
                  MediaQuery.of(dialogContext).size.width * 0.85,
              height:
                  MediaQuery.of(dialogContext).size.height * 0.75,
              child: Column(
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          initialValue: category,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: "Category",
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: "Cleaning",
                              child: Text("Cleaning"),
                            ),
                            DropdownMenuItem(
                              value: "Salary",
                              child: Text("Salary"),
                            ),
                            DropdownMenuItem(
                              value: "Electricity",
                              child: Text("Electricity"),
                            ),
                            DropdownMenuItem(
                              value: "Water",
                              child: Text("Water"),
                            ),
                            DropdownMenuItem(
                              value: "Laundry",
                              child: Text("Laundry"),
                            ),
                            DropdownMenuItem(
                              value: "Maintenance",
                              child: Text("Maintenance"),
                            ),
                            DropdownMenuItem(
                              value: "Food Purchase",
                              child: Text("Food Purchase"),
                            ),
                            DropdownMenuItem(
                              value: "Petrol",
                              child: Text("Petrol"),
                            ),
                            DropdownMenuItem(
                              value: "Miscellaneous",
                              child: Text("Miscellaneous"),
                            ),
                          ],
                          onChanged: (String? value) {
                            if (value != null) {
                              updateDialog(() {
                                category = value;
                              });

                              descriptionFocus.requestFocus();
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: descriptionController,
                          focusNode: descriptionFocus,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: "Expense Description",
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (value) {
                            amountFocus.requestFocus();
                          },
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: amountController,
                          focusNode: amountFocus,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: "Amount",
                            prefixIcon:
                                Icon(Icons.currency_rupee),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (value) {
                            paymentFocus.requestFocus();
                          },
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          initialValue: paymentMode,
                          focusNode: paymentFocus,
                          decoration: const InputDecoration(
                            labelText: "Payment Mode",
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: "Cash",
                              child: Text("Cash"),
                            ),
                            DropdownMenuItem(
                              value: "UPI",
                              child: Text("UPI"),
                            ),
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
                              updateDialog(() {
                                paymentMode = value;
                              });

                              saveFocus.requestFocus();
                            }
                          },
                        ),
                      ),
                      ElevatedButton.icon(
                        focusNode: saveFocus,
                        onPressed: saveExpense,
                        icon: const Icon(Icons.save),
                        label: const Text("SAVE EXPENSE"),
                      ),
                      OutlinedButton.icon(
                        onPressed: printExpenseReport,
                        icon: const Icon(Icons.print),
                        label: const Text("PRINT EXPENSE REPORT"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.red.shade300,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "TOTAL EXPENSES : ₹${totalExpenses()}",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ExpenseStore.expenses.isEmpty
                        ? const Center(
                            child: Text("No Expenses Found"),
                          )
                        : ListView.builder(
                            itemCount:
                                ExpenseStore.expenses.length,
                            itemBuilder: (
                              BuildContext context,
                              int index,
                            ) {
                              final expense =
                                  ExpenseStore.expenses.reversed
                                      .toList()[index];

                              return Card(
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.payments_outlined,
                                  ),
                                  title: Text(
                                    expense["description"].toString(),
                                  ),
                                  subtitle: Text(
                                    "${expense["category"]}  •  "
                                    "${expense["paymentMode"]}  •  "
                                    "${formatDateTime(expense["dateTime"].toString())}",
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "₹${expense["amount"]}",
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: "DELETE EXPENSE",
                                        onPressed: () async {
                                          await ExpenseStore.deleteExpense(
                                            expense,
                                          );

                                          updateDialog(() {});
                                        },
                                        icon: const Icon(
                                          Icons.delete_outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text("CLOSE"),
              ),
            ],
          );
        },
      );
    },
  );

  descriptionFocus.dispose();
  amountFocus.dispose();
  paymentFocus.dispose();
  saveFocus.dispose();
}

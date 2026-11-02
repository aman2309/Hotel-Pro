import '../services/hotel_record_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/room.dart';
import '../models/bill_record.dart';
import '../models/customer.dart';
import '../stores/bill_store.dart';
import '../stores/customer_store.dart';
import '../stores/hotel_settings_store.dart';
import 'bill_preview_dialog.dart';
import 'booking_slip_dialog.dart';
import 'booking_view_dialog.dart';

Future<String?> showRoomControlDialog(BuildContext context, Room room) {
  int roomBill() {
    return room.bookingRate * room.days;
  }

  int extraCharges() {
    int total = 0;

    for (final charge in room.charges) {
      total += Room.extraChargeInt(charge["amount"]);
    }

    return total;
  }

  int totalBill() {
    return roomBill() + extraCharges();
  }

  int gstAmount() {
    if (!room.applyGst) {
      return 0;
    }
    return HotelSettingsStore.taxOn(totalBill());
  }

  int grandTotal() {
    return totalBill() + gstAmount();
  }

  int paymentAmount(Map<String, dynamic> payment) {
    final dynamic amount = payment["amount"];

    if (amount is int) {
      return amount;
    }

    if (amount is num) {
      return amount.toInt();
    }

    return int.tryParse(amount?.toString() ?? "") ?? 0;
  }

  int totalPartPayments() {
    int total = 0;

    for (final payment in room.partPayments) {
      total += paymentAmount(payment);
    }

    return total;
  }

  int balance() {
    return grandTotal() - room.advance - totalPartPayments();
  }

  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter updateDialog) {
          Future<void> addBilling() async {
            final Map<String, dynamic>? charge =
                await showDialog<Map<String, dynamic>>(
                  context: dialogContext,
                  useRootNavigator: true,
                  builder: (BuildContext billingContext) {
                    return const AddBillingDialog();
                  },
                );

            if (charge == null) {
              return;
            }

            room.charges.add(Map<String, dynamic>.from(charge));
            await Future<void>.delayed(const Duration(milliseconds: 50));
            if (dialogContext.mounted) {
              updateDialog(() {});
            }
          }

          Future<void> addDays() async {
            final daysController = TextEditingController();

            final bool? daysAdded = await showDialog<bool>(
              context: dialogContext,
              builder: (BuildContext daysContext) {
                void saveDays() {
                  final int additionalDays =
                      int.tryParse(daysController.text.trim()) ?? 0;

                  if (additionalDays <= 0) {
                    ScaffoldMessenger.of(daysContext).showSnackBar(
                      const SnackBar(
                        content: Text("Enter valid number of days"),
                      ),
                    );
                    return;
                  }

                  room.days += additionalDays;

                  Navigator.pop(daysContext, true);
                }

                return AlertDialog(
                  title: const Text("ADD DAYS"),
                  content: SizedBox(
                    width: 400,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "CURRENT STAY : ${room.days} DAYS",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "CURRENT BILL : ₹${totalBill()}",
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: daysController,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: "Additional Days",
                            prefixIcon: Icon(Icons.add),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (value) {
                            saveDays();
                          },
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(daysContext, false);
                      },
                      child: const Text("CANCEL"),
                    ),
                    ElevatedButton.icon(
                      onPressed: saveDays,
                      icon: const Icon(Icons.add_circle),
                      label: const Text("ADD DAYS"),
                    ),
                  ],
                );
              },
            );

            if (daysAdded == true) {
              updateDialog(() {});
            }
          }

          Future<void> addPartPayment() async {
            final amountController = TextEditingController();
            final amountFocus = FocusNode();
            final paymentModeFocus = FocusNode();
            final savePaymentFocus = FocusNode();

            String paymentMode = "Cash";

            final bool? paymentSaved = await showDialog<bool>(
              context: dialogContext,
              builder: (BuildContext paymentContext) {
                return StatefulBuilder(
                  builder:
                      (BuildContext context, StateSetter updatePaymentDialog) {
                        void savePayment() {
                          final int amount =
                              int.tryParse(amountController.text.trim()) ?? 0;

                          if (amount <= 0 || amount > balance()) {
                            ScaffoldMessenger.of(paymentContext).showSnackBar(
                              const SnackBar(
                                content: Text("Enter a valid payment amount"),
                              ),
                            );
                            return;
                          }

                          room.partPayments.add({
                            "paymentId": HotelRecordIds.create("pay"),
                            "amount": amount,
                            "paymentMode": paymentMode,
                            "dateTime": DateTime.now().toIso8601String(),
                          });

                          Navigator.pop(paymentContext, true);
                        }

                        return AlertDialog(
                          title: const Text("PART PAYMENT"),
                          content: SizedBox(
                            width: 400,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "CURRENT BALANCE : ₹${balance()}",
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextField(
                                  controller: amountController,
                                  focusNode: amountFocus,
                                  autofocus: true,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: "Payment Amount",
                                    prefixIcon: Icon(Icons.currency_rupee),
                                  ),
                                  onSubmitted: (value) {
                                    paymentModeFocus.requestFocus();
                                  },
                                ),
                                const SizedBox(height: 15),
                                DropdownButtonFormField<String>(
                                  initialValue: paymentMode,
                                  focusNode: paymentModeFocus,
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
                                      updatePaymentDialog(() {
                                        paymentMode = value;
                                      });

                                      savePaymentFocus.requestFocus();
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(paymentContext, false);
                              },
                              child: const Text("CANCEL"),
                            ),
                            ElevatedButton.icon(
                              focusNode: savePaymentFocus,
                              onPressed: savePayment,
                              icon: const Icon(Icons.save),
                              label: const Text("SAVE PAYMENT"),
                            ),
                          ],
                        );
                      },
                );
              },
            );

            amountFocus.dispose();
            paymentModeFocus.dispose();
            savePaymentFocus.dispose();

            if (paymentSaved == true) {
              updateDialog(() {});
            }
          }

          BillRecord draftBill() {
            final Customer? customer = CustomerStore.findByMobile(room.mobile);
            return BillRecord(
              billNumber: room.billNumber.isNotEmpty
                  ? room.billNumber
                  : BillStore.nextBillNumber(),
              customerId: customer?.customerId ?? "-",
              guestName: room.guestName,
              mobile: room.mobile,
              roomNumber: room.roomNumber,
              roomType: room.roomType,
              bookingDate: room.bookingDate,
              bookingTime: room.bookingTime,
              checkoutTime: null,
              roomRate: room.bookingRate,
              bookedDays: room.days,
              roomBill: roomBill(),
              charges: List<Map<String, dynamic>>.from(room.charges),
              partPayments: List<Map<String, dynamic>>.from(room.partPayments),
              extraCharges: extraCharges(),
              totalBill: totalBill(),
              discount: 0,
              advance: room.advance,
              advancePaymentMode: room.paymentMode,
              balance: balance(),
              paymentMode: room.paymentMode,
              applyGst: room.applyGst,
            );
          }

          Future<void> printBillOptions() async {
            await showBillPreviewDialog(
              dialogContext,
              draftBill(),
              applyGst: room.applyGst,
            );
          }

          void setGst(bool enabled) {
            room.applyGst = enabled;
            updateDialog(() {});
          }

          void viewBill() {
            showDialog(
              context: dialogContext,
              builder: (BuildContext billContext) {
                return StatefulBuilder(
                  builder: (BuildContext context, StateSetter setBill) {
                    return AlertDialog(
                      title: Text("Room ${room.roomNumber} Bill"),
                      content: SizedBox(
                        width: 430,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Guest : ${room.guestName}"),
                              Text("Mobile : ${room.mobile}"),
                              const Divider(),
                              Text(
                                "Room Rent : "
                                "₹${room.bookingRate} × "
                                "${room.days} Days",
                              ),
                              Text("Room Bill : ₹${roomBill()}"),
                              const Divider(),
                              const Text(
                                "Extra Charges",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if (room.charges.isEmpty)
                                const Text("No Extra Charges"),
                              ...room.charges.map<Widget>((charge) {
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(Room.extraChargeTitle(charge)),
                                  trailing: Text("₹${charge["amount"]}"),
                                );
                              }),
                              const Divider(),
                              Text(
                                "TOTAL BILL : ₹${totalBill()}",
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (room.applyGst) ...[
                                GestureDetector(
                                  onDoubleTap: () {
                                    setGst(false);
                                    setBill(() {});
                                  },
                                  child: Text(
                                    "GST ${HotelSettingsStore.gstRateLabel()}% : ₹${gstAmount()}",
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  "GRAND TOTAL : ₹${grandTotal()}",
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                              Text("ADVANCE : ₹${room.advance}"),
                              const Divider(),
                              const Text(
                                "PART PAYMENTS",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if (room.partPayments.isEmpty)
                                const Text("No Part Payments"),
                              ...room.partPayments.map<Widget>((payment) {
                                final DateTime paymentDate = DateTime.parse(
                                  payment["dateTime"].toString(),
                                );

                                final String dateTime =
                                    "${paymentDate.day.toString().padLeft(2, "0")}-"
                                    "${paymentDate.month.toString().padLeft(2, "0")}-"
                                    "${paymentDate.year} "
                                    "${paymentDate.hour.toString().padLeft(2, "0")}:"
                                    "${paymentDate.minute.toString().padLeft(2, "0")}";

                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    "${payment["paymentMode"]} • $dateTime",
                                  ),
                                  trailing: Text("₹${payment["amount"]}"),
                                );
                              }),
                              Text(
                                "TOTAL PART PAYMENT : ₹${totalPartPayments()}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "BALANCE : ₹${balance()}",
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(billContext);
                          },
                          child: const Text("CLOSE"),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          }

          return AlertDialog(
            title: Text("ROOM ${room.roomNumber}"),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "● BOOKED",
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(),
                    Text("Guest Name : ${room.guestName}"),
                    Text("Mobile : ${room.mobile}"),
                    Text("ID Number : ${room.idNumber}"),
                    if (room.guestAddress.isNotEmpty)
                      Text("Address : ${room.guestAddress}"),
                    Text("Room Type : ${room.roomType}"),
                    Text("Room Rent : ₹${room.bookingRate} / Day"),
                    if (room.bookingDate != null)
                      Text(
                        "Booking Date : "
                        "${room.bookingDate!.day.toString().padLeft(2, "0")}-"
                        "${room.bookingDate!.month.toString().padLeft(2, "0")}-"
                        "${room.bookingDate!.year}",
                      ),
                    Text("Stay : ${room.days} Days"),
                    const Divider(),
                    Text(
                      "Current Bill : ₹${totalBill()}",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (room.applyGst) ...[
                      GestureDetector(
                        onDoubleTap: () => setGst(false),
                        child: Text(
                          "GST ${HotelSettingsStore.gstRateLabel()}% : ₹${gstAmount()}",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        "Grand Total : ₹${grandTotal()}",
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    Text("Advance : ₹${room.advance}"),
                    Text(
                      "Balance : ₹${balance()}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: addDays,
                        icon: const Icon(Icons.more_time),
                        label: const Text("ADD DAYS"),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: addBilling,
                        icon: const Icon(Icons.add_card),
                        label: const Text("ADD BILLING"),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: viewBill,
                        icon: const Icon(Icons.receipt_long),
                        label: const Text("VIEW BILL"),
                      ),
                    ),
                    const SizedBox(height: 4),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: addPartPayment,
                        icon: const Icon(Icons.payments),
                        label: const Text("PART PAYMENT"),
                      ),
                    ),

                    const SizedBox(height: 4),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await showBookingViewDialog(dialogContext, room);
                        },
                        icon: const Icon(Icons.visibility),
                        label: const Text("VIEW BOOKING"),
                      ),
                    ),

                    const SizedBox(height: 4),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await showBookingSlipDialog(dialogContext, room);
                        },
                        icon: const Icon(Icons.badge_outlined),
                        label: const Text("BOOKING SLIP"),
                      ),
                    ),

                    const SizedBox(height: 4),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext, "CHANGE_ROOM");
                        },
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text("CHANGE ROOM"),
                      ),
                    ),

                    const SizedBox(height: 4),

                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: room.applyGst ? null : () => setGst(true),
                      onDoubleTap: room.applyGst ? () => setGst(false) : null,
                      child: IgnorePointer(
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.percent),
                            label: Text(
                              room.applyGst
                                  ? "GST ${HotelSettingsStore.gstRateLabel()}% ADDED"
                                  : "ADD GST (${HotelSettingsStore.gstRateLabel()}%)",
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: printBillOptions,
                        icon: const Icon(Icons.print),
                        label: const Text("PRINT BILL"),
                      ),
                    ),

                    const SizedBox(height: 4),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext, "CHECKOUT");
                        },
                        icon: const Icon(Icons.payment),
                        label: const Text("CHECKOUT & PAYMENT"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, "CLOSE");
                },
                child: const Text("CLOSE"),
              ),
            ],
          );
        },
      );
    },
  );
}

class AddBillingDialog extends StatefulWidget {
  const AddBillingDialog({super.key});

  @override
  State<AddBillingDialog> createState() => _AddBillingDialogState();
}

class _AddBillingDialogState extends State<AddBillingDialog> {
  String particular = "";
  String rateText = "";
  String quantityText = "1";

  int get rate => int.tryParse(rateText.trim()) ?? 0;
  int get quantity => int.tryParse(quantityText.trim()) ?? 0;
  int get amount => rate * quantity;

  void saveCharge() {
    if (particular.trim().isEmpty || rate <= 0 || quantity <= 0) {
      return;
    }

    Navigator.of(context).pop(<String, dynamic>{
      "chargeId": HotelRecordIds.create("chg"),
      "name": particular.trim(),
      "rate": rate,
      "quantity": quantity,
      "amount": amount,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Add Billing / Charge"),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: "Particular",
                hintText: "Food / Spa / Laundry",
              ),
              onChanged: (value) {
                particular = value;
              },
            ),
            TextField(
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: "Rate",
                prefixText: "₹ ",
              ),
              onChanged: (value) {
                setState(() {
                  rateText = value;
                });
              },
            ),
            TextField(
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: "Quantity",
                hintText: "1",
              ),
              onChanged: (value) {
                setState(() {
                  quantityText = value.isEmpty ? "1" : value;
                });
              },
              onSubmitted: (value) {
                saveCharge();
              },
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Amount : ₹$amount",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text("CANCEL"),
        ),
        ElevatedButton(onPressed: saveCharge, child: const Text("ADD CHARGE")),
      ],
    );
  }
}

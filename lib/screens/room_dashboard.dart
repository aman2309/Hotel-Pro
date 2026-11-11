import '../widgets/available_room_actions.dart';
import '../widgets/custom_bottom_sheet.dart';
import 'hotel_dashboard_view.dart';
import '../widgets/hotel_ui.dart';
import '../widgets/future_booking_badge.dart';
import '../theme/custom_colors.dart';
import '../theme/app_theme.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/hotel_data_buffer.dart';

import '../services/phone_auth_service.dart';
import 'cloud_gate.dart';
import '../services/cloud_sync_service.dart';
import '../services/hotel_cloud_sync_service.dart';
import '../services/hotel_sync_plan.dart';
import '../dialogs/booking_view_dialog.dart';
import '../dialogs/cancel_future_booking_sheet.dart';
import '../dialogs/contact_us_dialog.dart';
import '../dialogs/bill_preview_dialog.dart';
import '../dialogs/booking_dialog.dart';
import '../models/room.dart';
import '../models/customer.dart';
import '../models/bill_record.dart';
import '../utils/stay_duration.dart';
import '../stores/bill_store.dart';
import '../stores/customer_store.dart';
import '../stores/expense_store.dart';
import '../stores/hotel_settings_store.dart';
import '../dialogs/room_control_dialog.dart';
import '../dialogs/customer_list_dialog.dart';
import '../dialogs/reports_dialog.dart';
import '../dialogs/expenses_dialog.dart';
import '../dialogs/backup_restore_dialog.dart';
import '../dialogs/fresh_hotel_start_dialog.dart';
import '../dialogs/hotel_settings_dialog.dart';
import '../services/license_service.dart';
import '../widgets/trial_banner.dart';

class RoomDashboard extends StatefulWidget {
  const RoomDashboard({super.key});

  @override
  State<RoomDashboard> createState() {
    return _RoomDashboardState();
  }
}

class _RoomDashboardState extends State<RoomDashboard>
    with WidgetsBindingObserver {
  Timer? _stayTimer;
  Timer? _cloudPoll;
  bool _syncInFlight = false;
  bool _refreshing = false;
  bool _roomsLoading = true;
  final List<Room> rooms = [];

  int _seenRemoteRevision = 0;
  int _roomActionDepth = 0;
  bool _pendingCloudReload = false;

  Room liveRoom(Room room) {
    for (final Room current in rooms) {
      if (current.roomNumber == room.roomNumber) {
        return current;
      }
    }
    return room;
  }

  Future<T> _runRoomAction<T>(Future<T> Function() action) async {
    final sync = HotelCloudSyncService.instance;
    await sync.beginLocalAction();
    _roomActionDepth++;
    var cancelled = false;
    try {
      return await action();
    } catch (_) {
      if (HotelDataBuffer.cloudOnly) {
        await sync.cancelLocalAction();
        cancelled = true;
        await loadRooms();
      }
      rethrow;
    } finally {
      _roomActionDepth--;
      if (!cancelled) {
        try {
          await sync.endLocalAction();
        } catch (_) {
          if (HotelDataBuffer.cloudOnly) await loadRooms();
          rethrow;
        }
      }
      if (_roomActionDepth == 0) {
        _showSaveResult();
      }
      if (_roomActionDepth == 0 && _pendingCloudReload && mounted) {
        _pendingCloudReload = false;
        await _reloadAfterCloudApply();
      }
    }
  }

  Future<void> _reloadAfterCloudApply() async {
    if (_roomActionDepth > 0) {
      _pendingCloudReload = true;
      return;
    }
    await loadRooms();
    await BillStore.loadBills();
    await CustomerStore.loadCustomers();
    await ExpenseStore.loadExpenses();
    await HotelSettingsStore.loadSettings();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _autoSync() async {
    if (_syncInFlight || _roomActionDepth > 0) return;
    _syncInFlight = true;
    try {
      if (HotelCloudSyncService.instance.bootstrapped) {
        await HotelCloudSyncService.instance.retry();
      }
    } finally {
      _syncInFlight = false;
    }
  }

  void _onCloudChanged() {
    final revision = HotelCloudSyncService.instance.remoteRevision;
    if (revision != _seenRemoteRevision) {
      _seenRemoteRevision = revision;
      unawaited(_reloadAfterCloudApply());
    }
  }

  void _onLicenseChanged() {
    if (!mounted) return;
    if (LicenseService.instance.activated) {
      unawaited(_reloadAfterCloudApply());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadRooms();
    LicenseService.instance.addListener(_onLicenseChanged);
    HotelCloudSyncService.instance.addListener(_onCloudChanged);
    unawaited(_autoSync());
    _cloudPoll = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_autoSync());
    });

    _stayTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (mounted) {
        super.setState(() {});
      }
    });
  }

  @override
  void dispose() {
    LicenseService.instance.removeListener(_onLicenseChanged);
    HotelCloudSyncService.instance.removeListener(_onCloudChanged);
    WidgetsBinding.instance.removeObserver(this);
    _cloudPoll?.cancel();
    _stayTimer?.cancel();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_autoSync());
    } else if (state == AppLifecycleState.paused) {}
  }

  void _showSaveResult() {
    final String? message = HotelCloudSyncService.instance.lastError;
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> saveRooms() async {
    final prefs = await HotelDataBuffer.getInstance();

    final roomData = rooms.map((room) => room.toJson()).toList();

    await prefs.setString(CloudSyncService.roomKey, jsonEncode(roomData));
    await CloudSyncService.markDirty();
    unawaited(CloudSyncService.syncIfEnabled(force: true, pullOnly: false));
    await HotelCloudSyncService.instance.notifyLocalChanged();
    if (_roomActionDepth == 0) _showSaveResult();
  }

  Future<void> loadRooms() async {
    final prefs = await HotelDataBuffer.getInstance();

    final savedData = prefs.getString(CloudSyncService.roomKey);

    // Missing data means it has not arrived yet, not an empty hotel.
    if (savedData == null) return;

    final decoded = jsonDecode(savedData) as List<dynamic>;

    final loadedRooms = decoded
        .map((item) => Room.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();

    if (!mounted) {
      return;
    }

    setState(() {
      final Map<int, Room> existingByNumber = {
        for (final Room room in rooms) room.roomNumber: room,
      };

      final List<Room> nextRooms = [];
      for (final Room loaded in loadedRooms) {
        final Room? existing = existingByNumber[loaded.roomNumber];
        if (existing == null) {
          nextRooms.add(loaded);
        } else {
          existing.copyFrom(loaded);
          nextRooms.add(existing);
        }
      }

      rooms
        ..clear()
        ..addAll(nextRooms);
      _roomsLoading = false;

      for (final Room room in rooms) {
        if (room.status == "BOOKED" && room.bookingTime == null) {
          // Legacy stays without a recorded start: booking-day noon, which is
          // stable across reloads, instead of a reset-prone DateTime.now().
          room.bookingTime = bookingStartFallback(room.bookingDate);
        }
      }
    });
  }

  Color getRoomColor(String status) {
    if (status == "EMPTY") {
      return AppColors.available;
    }

    if (status == "BOOKED") {
      return AppColors.booked;
    }

    if (status == "CLEANING") {
      return AppColors.cleaning;
    }

    return AppColors.closed;
  }

  int countStatus(String status) {
    return rooms.where((room) {
      return room.status == status;
    }).length;
  }

  String formatDate(DateTime date) {
    String day = date.day.toString().padLeft(2, "0");

    String month = date.month.toString().padLeft(2, "0");

    return "$day-$month-${date.year}";
  }

  String formatClock(DateTime date) {
    int hour = date.hour;
    final String period = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    if (hour == 0) hour = 12;
    final String minute = date.minute.toString().padLeft(2, "0");
    return "$hour:$minute $period";
  }

  String formatTimeRange(DateTime start, DateTime? end) {
    if (end == null) return formatClock(start);
    return "${formatClock(start)} to ${formatClock(end)}";
  }

  Future<void> changeRoom(Room oldRoom) async {
    List<Room> availableRooms = rooms.where((room) {
      return room.status == "EMPTY" &&
          room.roomNumber != oldRoom.roomNumber &&
          room.futureBooking == false;
    }).toList();

    if (availableRooms.isEmpty) {
      if (!mounted) {
        return;
      }

      await showCustomBottomSheet(
        context: context,
        builder: (BuildContext dialogContext) {
          return CustomDialog(
            title: const Text("No Room Available"),
            content: const Text("No empty room is available for room change."),
            actions: [
              CustomButton.text(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text("OK"),
              ),
            ],
          );
        },
      );

      return;
    }

    Room? selectedRoom;

    bool? changeConfirmed = await showCustomBottomSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter updateDialog) {
            return CustomDialog(
              title: Text("Change Room ${oldRoom.roomNumber}"),
              content: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Guest : ${oldRoom.guestName}",
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text("Current Room : ${oldRoom.roomNumber}"),

                    const SizedBox(height: 20),

                    CustomDropdown<Room>(
                      initialValue: selectedRoom,
                      decoration: const InputDecoration(
                        labelText: "Select New Room",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.hotel_rounded),
                      ),
                      items: availableRooms.map((Room room) {
                        return DropdownMenuItem<Room>(
                          value: room,
                          child: Text(
                            "Room ${room.roomNumber}  |  "
                            "${room.roomType}  |  "
                            "₹${room.normalRent}",
                          ),
                        );
                      }).toList(),
                      onChanged: (Room? room) {
                        updateDialog(() {
                          selectedRoom = room;
                        });
                      },
                    ),

                    if (selectedRoom != null) ...[
                      const SizedBox(height: 20),

                      const Divider(),

                      Text(
                        "New Room : "
                        "${selectedRoom!.roomNumber}",
                      ),

                      Text(
                        "Room Type : "
                        "${selectedRoom!.roomType}",
                      ),

                      Text(
                        "Normal Rent : "
                        "₹${selectedRoom!.normalRent} / Day",
                      ),

                      const SizedBox(height: 10),

                      const Text(
                        "Guest and current billing will be transferred to the new room.",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                CustomButton.text(
                  onPressed: () {
                    Navigator.pop(dialogContext, false);
                  },
                  child: const Text("Cancel"),
                ),

                CustomButton.icon(
                  onPressed: selectedRoom == null
                      ? null
                      : () {
                          Navigator.pop(dialogContext, true);
                        },
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text("Confirm room change"),
                ),
              ],
            );
          },
        );
      },
    );

    if (changeConfirmed != true || selectedRoom == null) {
      return;
    }

    final int oldRoomNumber = oldRoom.roomNumber;
    final int newRoomNumber = selectedRoom!.roomNumber;

    // Capture all guest billing data first, then move it to the new room.
    final String transferMobile = oldRoom.mobile;
    final String transferGuestName = oldRoom.guestName;
    final String transferIdNumber = oldRoom.idNumber;
    final String transferGuestAddress = oldRoom.guestAddress;
    final int transferBookingRate = oldRoom.bookingRate;
    final DateTime? transferBookingDate = oldRoom.bookingDate;
    final DateTime? transferBookingTime = oldRoom.bookingTime;
    final int transferDays = oldRoom.days;
    final int transferAdvance = oldRoom.advance;
    final String transferPaymentMode = oldRoom.paymentMode;
    final List<Map<String, dynamic>> transferCharges = oldRoom.charges
        .map((charge) => Map<String, dynamic>.from(charge))
        .toList();
    final List<Map<String, dynamic>> transferPartPayments = oldRoom.partPayments
        .map((payment) => Map<String, dynamic>.from(payment))
        .toList();
    final List<Map<String, dynamic>> transferExtraGuests = oldRoom.extraGuests
        .map((guest) => Map<String, dynamic>.from(guest))
        .toList();

    final int transferPartPaymentTotal = transferPartPayments.fold<int>(0, (
      total,
      payment,
    ) {
      final dynamic amount = payment["amount"];
      if (amount is int) {
        return total + amount;
      }
      if (amount is num) {
        return total + amount.toInt();
      }
      return total + (int.tryParse(amount?.toString() ?? "") ?? 0);
    });

    setState(() {
      final Room liveTarget = rooms.firstWhere(
        (room) => room.roomNumber == newRoomNumber,
      );
      final Room liveSource = rooms.firstWhere(
        (room) => room.roomNumber == oldRoomNumber,
      );

      liveTarget.mobile = transferMobile;
      liveTarget.guestName = transferGuestName;
      liveTarget.idNumber = transferIdNumber;
      liveTarget.guestAddress = transferGuestAddress;
      liveTarget.bookingRate = transferBookingRate;
      liveTarget.bookingDate = transferBookingDate;
      liveTarget.bookingTime = transferBookingTime;
      liveTarget.days = transferDays;
      liveTarget.advance = transferAdvance;
      liveTarget.paymentMode = transferPaymentMode;
      liveTarget.charges = transferCharges;
      liveTarget.partPayments = transferPartPayments;
      liveTarget.extraGuests = transferExtraGuests;
      liveTarget.status = "BOOKED";
      liveTarget.checkoutTime = null;

      liveSource.clearCurrentStay();
      liveSource.status = "EMPTY";
    });

    await saveRooms();

    if (!mounted) {
      return;
    }

    await showCustomBottomSheet(
      context: context,
      builder: (BuildContext successContext) {
        return CustomDialog(
          title: const Text("Room Changed Successfully"),
          content: Text(
            "Guest : $transferGuestName\n\n"
            "Old Room : $oldRoomNumber\n"
            "New Room : $newRoomNumber\n\n"
            "Part Payments transferred : ₹$transferPartPaymentTotal\n\n"
            "Room $oldRoomNumber is now EMPTY.\n"
            "Room $newRoomNumber is now BOOKED.",
          ),
          actions: [
            CustomButton.text(
              autofocus: true,
              onPressed: () {
                Navigator.pop(successContext);
              },
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  Future<void> checkoutRoom(Room room) async {
    CloudSyncService.autoSyncPaused = true;
    _roomActionDepth++;
    try {
      final int roomBill = room.bookingRate * room.days;

      int extraCharges = 0;

      for (final charge in room.charges) {
        extraCharges += Room.extraChargeInt(charge["amount"]);
      }

      final int totalBill = roomBill + extraCharges;

      int gstForDiscount(int discountValue) {
        if (!room.applyGst) {
          return 0;
        }
        final int taxable = totalBill - discountValue;
        return HotelSettingsStore.taxOn(taxable < 0 ? 0 : taxable);
      }

      int totalPartPayments = 0;

      for (final payment in room.partPayments) {
        final dynamic amount = payment["amount"];
        if (amount is int) {
          totalPartPayments += amount;
        } else if (amount is num) {
          totalPartPayments += amount.toInt();
        } else {
          totalPartPayments += int.tryParse(amount?.toString() ?? "") ?? 0;
        }
      }

      int discount = 0;
      int gstAmount = gstForDiscount(discount);
      int balance =
          totalBill - discount + gstAmount - room.advance - totalPartPayments;

      final TextEditingController discountController = TextEditingController(
        text: "0",
      );
      final FocusNode discountFocus = FocusNode();
      final FocusNode paymentModeFocus = FocusNode();
      final FocusNode checkoutButtonFocus = FocusNode();

      String paymentMode = "Cash";

      bool? paymentConfirmed = await showCustomBottomSheet<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter updateDialog) {
              return CustomDialog(
                title: Text("Checkout Room ${room.roomNumber}"),
                content: SizedBox(
                  width: 480,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Guest : ${room.guestName}",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        Text("Mobile : ${room.mobile}"),

                        const Divider(),

                        Text(
                          "Room Rent : "
                          "₹${room.bookingRate} × "
                          "${room.days} Days",
                        ),

                        Text("Room Bill : ₹$roomBill"),

                        const SizedBox(height: 10),

                        const Text(
                          "Extra Charges",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),

                        if (room.charges.isEmpty)
                          const Text("No Extra Charges"),

                        ...room.charges.map<Widget>((charge) {
                          return Text(
                            "${Room.extraChargeTitle(charge)} : "
                            "₹${charge["amount"]}",
                          );
                        }),

                        const Divider(),

                        Text(
                          "TOTAL BILL : ₹$totalBill",
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        if (room.applyGst)
                          Text(
                            "GST ${HotelSettingsStore.gstRateLabel()}% : ₹$gstAmount",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                        const SizedBox(height: 10),

                        CustomTextField(
                          controller: discountController,
                          focusNode: discountFocus,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) {
                            paymentModeFocus.requestFocus();
                          },
                          decoration: const InputDecoration(
                            labelText: "Discount",
                            prefixText: "₹ ",
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            updateDialog(() {
                              discount = int.tryParse(value) ?? 0;
                              if (discount < 0) discount = 0;
                              if (discount > totalBill) discount = totalBill;
                              gstAmount = gstForDiscount(discount);
                              balance =
                                  totalBill -
                                  discount +
                                  gstAmount -
                                  room.advance -
                                  totalPartPayments;
                              if (balance < 0) balance = 0;
                            });
                          },
                        ),

                        const SizedBox(height: 10),

                        Text(
                          "FINAL BILL : ₹${totalBill - discount + gstAmount}",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        Text("ADVANCE : ₹${room.advance}"),

                        Text(
                          "PART PAYMENT : ₹$totalPartPayments",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),

                        Text(
                          "BALANCE PAYMENT : ₹$balance",
                          style: const TextStyle(
                            color: CustomColors.error,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 20),

                        CustomDropdown<String>(
                          focusNode: paymentModeFocus,
                          initialValue: paymentMode,
                          decoration: const InputDecoration(
                            labelText: "Balance Payment Mode",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.payment_rounded),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: "Cash",
                              child: Text("Cash"),
                            ),
                            DropdownMenuItem(value: "UPI", child: Text("UPI")),
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
                              checkoutButtonFocus.requestFocus();
                            }
                          },
                        ),

                        const SizedBox(height: 15),

                        const Text(
                          "After payment, room status will change to CLEANING.",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  CustomButton.text(
                    onPressed: () {
                      Navigator.pop(dialogContext, false);
                    },
                    child: const Text("Cancel"),
                  ),

                  CustomButton.icon(
                    autofocus: true,
                    focusNode: checkoutButtonFocus,
                    onPressed: () {
                      Navigator.pop(dialogContext, true);
                    },
                    icon: const Icon(Icons.check_circle_rounded),
                    label: Text("RECEIVE ₹$balance & CHECKOUT"),
                  ),
                ],
              );
            },
          );
        },
      );

      if (paymentConfirmed != true) {
        return;
      }

      final Room live = liveRoom(room);
      final advancePaymentMode = live.paymentMode;

      setState(() {
        live.checkoutTime = DateTime.now();
        live.status = "CLEANING";
      });

      await saveRooms();

      final Customer? billCustomer = CustomerStore.findByMobile(live.mobile);

      final String billNumber = BillStore.nextBillNumber();

      final BillRecord finalBill = BillRecord(
        billNumber: billNumber,
        customerId: billCustomer?.customerId ?? "-",
        guestName: live.guestName,
        mobile: live.mobile,
        roomNumber: live.roomNumber,
        roomType: live.roomType,
        bookingDate: live.bookingDate,
        bookingTime: live.bookingTime,
        checkoutTime: live.checkoutTime!,
        roomRate: live.bookingRate,
        bookedDays: live.days,
        roomBill: roomBill,
        charges: List<Map<String, dynamic>>.from(live.charges),
        partPayments: List<Map<String, dynamic>>.from(live.partPayments),
        extraCharges: extraCharges,
        totalBill: totalBill,
        discount: discount,
        advance: live.advance,
        advancePaymentMode: advancePaymentMode,
        balance: balance,
        paymentMode: paymentMode,
        applyGst: live.applyGst,
      );

      await BillStore.saveBill(finalBill);

      await CustomerStore.addStayHistory(live.mobile, {
        "billNumber": billNumber,
        "roomNumber": live.roomNumber,
        "bookingDate": live.bookingDate?.toIso8601String(),
        "bookingTime": live.bookingTime?.toIso8601String(),
        "checkoutTime": live.checkoutTime?.toIso8601String(),
        "stayDurationMinutes": finalBill.finalStayMinutes,
        "roomRate": live.bookingRate,
        "days": live.days,
        "roomBill": roomBill,
        "extraCharges": extraCharges,
        "charges": List<Map<String, dynamic>>.from(live.charges),
        "totalBill": totalBill,
        "discount": discount,
        "advance": live.advance,
        "balance": balance,
        "paymentMode": paymentMode,
      });

      for (final Map<String, dynamic> guest in live.extraGuests) {
        final String extraMobile = guest["mobile"]?.toString() ?? "";

        if (extraMobile.isEmpty) {
          continue;
        }

        await CustomerStore.addStayHistory(extraMobile, {
          "roomNumber": live.roomNumber,
          "bookingDate": live.bookingDate?.toIso8601String(),
          "bookingTime": live.bookingTime?.toIso8601String(),
          "checkoutTime": live.checkoutTime?.toIso8601String(),
          "stayDurationMinutes": finalBill.finalStayMinutes,
          "roomRate": live.bookingRate,
          "days": live.days,
          "roomBill": roomBill,
          "extraCharges": extraCharges,
          "charges": List<Map<String, dynamic>>.from(live.charges),
          "totalBill": totalBill,
          "advance": live.advance,
          "balance": balance,
          "paymentMode": paymentMode,
          "sharedStay": true,
          "primaryGuestMobile": live.mobile,
        });
      }

      if (!mounted) {
        return;
      }

      await showBillPreviewDialog(
        context,
        finalBill,
        applyGst: finalBill.applyGst,
      );
    } finally {
      _roomActionDepth--;
      CloudSyncService.autoSyncPaused = false;
      if (_roomActionDepth == 0 && _pendingCloudReload && mounted) {
        _pendingCloudReload = false;
        await _reloadAfterCloudApply();
      }
    }
  }

  Future<void> completeCleaning(Room room) async {
    bool? confirmed = await showCustomBottomSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return CustomDialog(
          title: Text("Room ${room.roomNumber} Cleaning"),
          content: const Text(
            "Is room cleaning complete?\n\n"
            "Guest and old billing data will be cleared.",
          ),
          actions: [
            CustomButton.text(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text("Cancel"),
            ),
            CustomButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.cleaning_services_rounded),
              label: const Text("Cleaning complete"),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      final Room live = liveRoom(room);
      live.clearCurrentStay();
      live.status = "EMPTY";
    });

    await saveRooms();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Room ${room.roomNumber} is now EMPTY")),
    );
  }

  Future<void> manageClosedRoom(Room room) async {
    String selectedFault = room.faultReason.isEmpty
        ? "Technical Fault"
        : room.faultReason;

    String? action = await showCustomBottomSheet<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter updateDialog) {
            return CustomDialog(
              title: Text("ROOM ${room.roomNumber} - CLOSED"),
              content: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "● ROOM CLOSED",
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 15),

                    CustomDropdown<String>(
                      initialValue: selectedFault,
                      decoration: const InputDecoration(
                        labelText: "Fault / Closing Reason",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.build_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: "Technical Fault",
                          child: Text("Technical Fault"),
                        ),
                        DropdownMenuItem(
                          value: "AC Fault",
                          child: Text("AC Fault"),
                        ),
                        DropdownMenuItem(
                          value: "Electrical Fault",
                          child: Text("Electrical Fault"),
                        ),
                        DropdownMenuItem(
                          value: "Plumbing Fault",
                          child: Text("Plumbing Fault"),
                        ),
                        DropdownMenuItem(
                          value: "Renovation",
                          child: Text("Renovation"),
                        ),
                        DropdownMenuItem(value: "Other", child: Text("Other")),
                      ],
                      onChanged: (String? value) {
                        if (value != null) {
                          updateDialog(() {
                            selectedFault = value;
                          });
                        }
                      },
                    ),

                    const SizedBox(height: 15),

                    Text(
                      "Current Reason : $selectedFault",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              actions: [
                CustomButton.text(
                  onPressed: () {
                    Navigator.pop(dialogContext, "CLOSE");
                  },
                  child: const Text("Close"),
                ),

                CustomButton.outlineIcon(
                  onPressed: () {
                    room.faultReason = selectedFault;

                    Navigator.pop(dialogContext, "SAVED");
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text("Save fault"),
                ),

                CustomButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext, "REPAIRED");
                  },
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text("Room repaired / open room"),
                ),
              ],
            );
          },
        );
      },
    );

    if (action == "SAVED") {
      setState(() {
        room.faultReason = selectedFault;
      });

      await saveRooms();

      return;
    }

    if (action == "REPAIRED") {
      setState(() {
        room.status = "EMPTY";
        room.faultReason = "";
      });

      await saveRooms();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Room ${room.roomNumber} is repaired and now EMPTY"),
        ),
      );
    }
  }

  Future<void> openRoom(Room room) async {
    try {
      await _runRoomAction(() => _openRoom(room));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<bool?> _bookRoomAndConfirm(Room source) {
    final expected = hotelRecordFingerprint(source.toJson());
    final sync = HotelCloudSyncService.instance;
    return showBookingDialog(
      context,
      source,
      prepareGuests: () => sync.commitActionCheckpoint(requirePhotos: true),
      saveBooking: (draft) async {
        final current = liveRoom(source);
        final actual = hotelRecordFingerprint(current.toJson());
        if (!rooms.contains(current) ||
            (actual != expected &&
                actual != hotelRecordFingerprint(draft.toJson()))) {
          throw StateError(
            'This room changed while you were booking. Close this form and refresh.',
          );
        }
        current.copyFrom(draft);
        try {
          await saveRooms();
          await sync.commitActionCheckpoint(requirePhotos: true);
        } catch (_) {
          await loadRooms();
          rethrow;
        }
      },
    );
  }

  Future<void> _cancelFutureBooking(Room room) async {
    if (!room.futureBooking) return;
    final confirmed = await showCancelFutureBookingSheet(context, room);
    if (confirmed != true || !mounted) return;
    room = liveRoom(room);
    room.clearFutureBooking();
    await saveRooms();
    await HotelCloudSyncService.instance.commitActionCheckpoint();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Future booking cancelled.')));
  }

  Future<void> _openRoom(Room room) async {
    room = liveRoom(room);

    if (room.status == "CLEANING") {
      await completeCleaning(room);
      return;
    }
    if (room.status == "CLOSED") {
      await manageClosedRoom(room);
      return;
    }
    if (room.futureBooking && room.status != "BOOKED") {
      String? futureAction = await showCustomBottomSheet<String>(
        context: context,
        builder: (BuildContext futureContext) {
          return CustomDialog(
            title: Text("ROOM ${room.roomNumber}"),
            content: FutureBookingBadge(room),
            actions: [
              CustomButton.text(
                onPressed: () {
                  Navigator.pop(futureContext, "CLOSE");
                },
                child: const Text("Close"),
              ),
              CustomButton.outlineIcon(
                onPressed: () {
                  Navigator.pop(futureContext, "VIEW");
                },
                icon: const Icon(Icons.visibility_rounded),
                label: const Text("View future booking"),
              ),
              CustomButton.outlineIcon(
                onPressed: () => Navigator.pop(futureContext, 'CANCEL_FUTURE'),
                icon: const Icon(Icons.event_busy_rounded),
                label: const Text('Cancel future booking'),
              ),
              CustomButton.icon(
                onPressed: () {
                  Navigator.pop(futureContext, "NEW_BOOKING");
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text("New booking"),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      if (futureAction == 'CANCEL_FUTURE') {
        await _cancelFutureBooking(room);
        return;
      }

      if (futureAction == "VIEW") {
        await showBookingViewDialog(context, room, showFutureBooking: true);

        return;
      }

      if (futureAction == "NEW_BOOKING") {
        bool? booked = await _bookRoomAndConfirm(room);

        if (booked == true && mounted) {
          setState(() {});
          await saveRooms();
        }

        return;
      }

      return;
    }
    if (room.status == "BOOKED") {
      String? action = await showRoomControlDialog(context, room);

      // Save part payments / charges / days added inside room control.
      await saveRooms();

      if (action == 'CANCEL_FUTURE') {
        await _cancelFutureBooking(room);
        return;
      }

      if (action == "CHANGE_ROOM") {
        await changeRoom(room);
        return;
      }

      if (action == "CHECKOUT") {
        await checkoutRoom(room);
        return;
      }

      if (mounted) {
        setState(() {});
      }

      return;
    }

    bool? openBooking = await showCustomBottomSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return CustomDialog(
          title: Text("ROOM ${room.roomNumber}"),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Status : ${room.status}",
                  style: TextStyle(
                    color: getRoomColor(room.status),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Divider(),
                Text("Room Type : ${room.roomType}"),
                Text("Normal Rent : ₹${room.normalRent} / Day"),
                if (room.futureBooking && room.futureBookingDate != null) ...[
                  const SizedBox(height: 15),
                  FutureBookingBadge(room),
                  const SizedBox(height: 6),
                  Text(
                    "Booking Time : "
                    "${formatTimeRange(room.futureBookingDate!, room.futureBookingEnd)}",
                  ),
                  Text("Guest : ${room.futureGuestName}"),
                ],
                const SizedBox(height: 20),
                if (room.status == 'EMPTY')
                  AvailableRoomActions(
                    onBook: () => Navigator.pop(dialogContext, true),
                    onClose: () async {
                      setState(() {
                        room.status = 'CLOSED';
                        room.faultReason = 'Technical Fault';
                      });
                      await saveRooms();
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, false);
                      }
                    },
                  ),
              ],
            ),
          ),
          actions: [
            CustomButton.text(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text("Close"),
            ),
          ],
        );
      },
    );

    if (openBooking == true && mounted) {
      bool? bookingSaved = await _bookRoomAndConfirm(room);

      if (bookingSaved == true && mounted) {
        setState(() {});
        await saveRooms();
      }
    }
  }

  int nextInternalRoomNumber() {
    int highest = 0;
    for (final Room room in rooms) {
      if (room.roomNumber > highest) {
        highest = room.roomNumber;
      }
    }
    return highest + 1;
  }

  Future<void> _refreshHotel() async {
    if (_refreshing || _roomActionDepth > 0) return;
    setState(() => _refreshing = true);
    try {
      await HotelCloudSyncService.instance.retry();
      if (HotelCloudSyncService.instance.lastError != null) {
        throw StateError(HotelCloudSyncService.instance.lastError!);
      }
      await _reloadAfterCloudApply();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Refresh failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> addRoom() async {
    final roomNumberController = TextEditingController();
    final roomTypeController = TextEditingController();
    final roomRentController = TextEditingController();

    final typeFocus = FocusNode();
    final rentFocus = FocusNode();

    await showCustomBottomSheet(
      context: context,
      builder: (BuildContext dialogContext) {
        Future<void> saveRoom() async {
          final String rawNumber = roomNumberController.text.trim();
          final String roomType = roomTypeController.text.trim();
          final int? roomRent = int.tryParse(roomRentController.text.trim());
          final int? parsedNumber = int.tryParse(rawNumber);

          if (rawNumber.isEmpty ||
              roomType.isEmpty ||
              roomRent == null ||
              roomRent <= 0) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(
                content: Text("Room number / name, type and rent enter karein"),
              ),
            );
            return;
          }

          final int roomNumber = parsedNumber ?? nextInternalRoomNumber();
          final String roomName = parsedNumber == null ? rawNumber : "";

          final bool roomAlreadyExists = rooms.any((room) {
            if (parsedNumber != null && room.roomNumber == parsedNumber) {
              return true;
            }
            if (roomName.isNotEmpty &&
                room.label.toLowerCase() == roomName.toLowerCase()) {
              return true;
            }
            return false;
          });

          if (roomAlreadyExists) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              SnackBar(content: Text("$rawNumber already exists")),
            );
            return;
          }

          setState(() {
            rooms.add(
              Room(
                roomNumber: roomNumber,
                roomName: roomName,
                roomType: roomType,
                normalRent: roomRent,
              ),
            );

            rooms.sort((firstRoom, secondRoom) {
              return firstRoom.roomNumber.compareTo(secondRoom.roomNumber);
            });
          });

          await saveRooms();

          if (!dialogContext.mounted) {
            return;
          }

          Navigator.pop(dialogContext);
        }

        return CustomDialog(
          title: const Text("Add New Room"),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomTextField(
                  controller: roomNumberController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: "Room Number / Name",
                    hintText: "101  or  Hall 1",
                  ),
                  onSubmitted: (value) {
                    typeFocus.requestFocus();
                  },
                ),
                CustomTextField(
                  controller: roomTypeController,
                  focusNode: typeFocus,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: "Room Type"),
                  onSubmitted: (value) {
                    rentFocus.requestFocus();
                  },
                ),
                CustomTextField(
                  controller: roomRentController,
                  focusNode: rentFocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: "Normal Rent Per Day",
                  ),
                  onSubmitted: (value) {
                    saveRoom();
                  },
                ),
              ],
            ),
          ),
          actions: [
            CustomButton.text(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text("Cancel"),
            ),
            CustomButton.icon(
              onPressed: saveRoom,
              icon: const Icon(Icons.add_rounded),
              label: const Text("Add room"),
            ),
          ],
        );
      },
    );
  }

  Future<void> deleteRoom([Room? targetRoom]) async {
    final emptyRooms = rooms.where((room) {
      return room.status != "BOOKED" && !room.futureBooking;
    }).toList();

    if (emptyRooms.isEmpty) {
      return;
    }

    if (targetRoom != null &&
        (targetRoom.status == 'BOOKED' || targetRoom.futureBooking)) {
      throw StateError(
        'Finish or cancel the room booking before editing or deleting it.',
      );
    }
    Room? selectedRoom = targetRoom;
    if (selectedRoom == null) {
      final roomSelected = await showCustomBottomSheet<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter updateDialog) {
              return CustomDialog(
                title: const Text("Select Room To Delete"),
                content: SizedBox(
                  width: 420,
                  child: CustomDropdown<Room>(
                    decoration: const InputDecoration(
                      labelText: "Select room",
                      border: OutlineInputBorder(),
                    ),
                    items: emptyRooms.map((room) {
                      return DropdownMenuItem<Room>(
                        value: room,
                        child: Text("${room.label} - ${room.roomType}"),
                      );
                    }).toList(),
                    onChanged: (Room? room) {
                      updateDialog(() {
                        selectedRoom = room;
                      });
                    },
                  ),
                ),
                actions: [
                  CustomButton.text(
                    onPressed: () {
                      Navigator.pop(dialogContext, false);
                    },
                    child: const Text("Cancel"),
                  ),
                  CustomButton.icon(
                    onPressed: selectedRoom == null
                        ? null
                        : () {
                            Navigator.pop(dialogContext, true);
                          },
                    icon: const Icon(Icons.delete_rounded),
                    label: const Text("Delete"),
                  ),
                ],
              );
            },
          );
        },
      );

      if (roomSelected != true || selectedRoom == null || !mounted) {
        return;
      }
    }

    final room = selectedRoom!;

    final deleteConfirmed = await showCustomBottomSheet<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return CustomDialog(
          title: const Text("Delete Room?"),
          content: Text(
            "Are you sure you want to delete Room ${room.roomNumber}?",
          ),
          actions: [
            CustomButton.text(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text("NO"),
            ),
            CustomButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text("YES, DELETE"),
            ),
          ],
        );
      },
    );

    if (deleteConfirmed == true && mounted) {
      setState(() {
        rooms.remove(room);
      });

      await saveRooms();
    }
  }

  Future<void> editRoom([Room? targetRoom]) async {
    final editableRooms = rooms.where((room) {
      return room.status != "BOOKED" && !room.futureBooking;
    }).toList();

    if (editableRooms.isEmpty) {
      return;
    }

    if (targetRoom != null &&
        (targetRoom.status == 'BOOKED' || targetRoom.futureBooking)) {
      throw StateError(
        'Finish or cancel the room booking before editing or deleting it.',
      );
    }
    Room? selectedRoom = targetRoom;
    if (selectedRoom == null) {
      bool? roomSelected = await showCustomBottomSheet<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter updateDialog) {
              return CustomDialog(
                title: const Text("Select Room To Edit"),
                content: SizedBox(
                  width: 420,
                  child: CustomDropdown<Room>(
                    decoration: const InputDecoration(
                      labelText: "Select room",
                      border: OutlineInputBorder(),
                    ),
                    items: editableRooms.map((room) {
                      return DropdownMenuItem<Room>(
                        value: room,
                        child: Text("${room.label} - ${room.roomType}"),
                      );
                    }).toList(),
                    onChanged: (Room? room) {
                      updateDialog(() {
                        selectedRoom = room;
                      });
                    },
                  ),
                ),
                actions: [
                  CustomButton.text(
                    onPressed: () {
                      Navigator.pop(dialogContext, false);
                    },
                    child: const Text("Cancel"),
                  ),
                  CustomButton.icon(
                    onPressed: selectedRoom == null
                        ? null
                        : () {
                            Navigator.pop(dialogContext, true);
                          },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text("Edit"),
                  ),
                ],
              );
            },
          );
        },
      );

      if (roomSelected != true || selectedRoom == null || !mounted) {
        return;
      }
    }

    final room = selectedRoom!;

    final roomNumberController = TextEditingController(text: room.label);
    final roomTypeController = TextEditingController(text: room.roomType);
    final roomRentController = TextEditingController(
      text: room.normalRent.toString(),
    );

    final typeFocus = FocusNode();
    final rentFocus = FocusNode();

    await showCustomBottomSheet(
      context: context,
      builder: (BuildContext dialogContext) {
        Future<void> saveRoomChanges() async {
          final String rawNumber = roomNumberController.text.trim();
          final String roomType = roomTypeController.text.trim();
          final int? roomRent = int.tryParse(roomRentController.text.trim());
          final int? parsedNumber = int.tryParse(rawNumber);

          if (rawNumber.isEmpty ||
              roomType.isEmpty ||
              roomRent == null ||
              roomRent <= 0) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(
                content: Text("Room number / name, type and rent enter karein"),
              ),
            );
            return;
          }

          final int roomNumber = parsedNumber ?? room.roomNumber;
          final String roomName = parsedNumber == null ? rawNumber : "";

          final bool roomAlreadyExists = rooms.any((otherRoom) {
            if (otherRoom == room) {
              return false;
            }
            if (parsedNumber != null && otherRoom.roomNumber == parsedNumber) {
              return true;
            }
            if (roomName.isNotEmpty &&
                otherRoom.label.toLowerCase() == roomName.toLowerCase()) {
              return true;
            }
            return false;
          });

          if (roomAlreadyExists) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              SnackBar(content: Text("$rawNumber already exists")),
            );
            return;
          }

          setState(() {
            room.roomNumber = roomNumber;
            room.roomName = roomName;
            room.roomType = roomType;
            room.normalRent = roomRent;
            room.bookingRate = roomRent;
            room.futureBookingRate = roomRent;

            rooms.sort((firstRoom, secondRoom) {
              return firstRoom.roomNumber.compareTo(secondRoom.roomNumber);
            });
          });

          await saveRooms();

          if (!dialogContext.mounted) {
            return;
          }

          Navigator.pop(dialogContext);
        }

        return CustomDialog(
          title: Text("Edit Room ${room.label}"),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomTextField(
                  controller: roomNumberController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: "Room Number / Name",
                    hintText: "101  or  Hall 1",
                  ),
                  onSubmitted: (value) {
                    typeFocus.requestFocus();
                  },
                ),
                CustomTextField(
                  controller: roomTypeController,
                  focusNode: typeFocus,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: "Room Type"),
                  onSubmitted: (value) {
                    rentFocus.requestFocus();
                  },
                ),
                CustomTextField(
                  controller: roomRentController,
                  focusNode: rentFocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: "Normal Rent Per Day",
                  ),
                  onSubmitted: (value) {
                    saveRoomChanges();
                  },
                ),
              ],
            ),
          ),
          actions: [
            CustomButton.text(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text("Cancel"),
            ),
            CustomButton.icon(
              onPressed: saveRoomChanges,
              icon: const Icon(Icons.save_rounded),
              label: const Text("Save changes"),
            ),
          ],
        );
      },
    );
  }

  Future<void> freshHotelStart() async {
    if (HotelCloudSyncService.instance.isReady) {
      await showCustomBottomSheet<void>(
        context: context,
        builder: (dialogContext) => CustomDialog(
          title: const Text('Shared hotel records are protected'),
          content: const Text(
            'Fresh start cannot erase a shared cloud hotel. Export a backup and request a reviewed archive/reset before starting a new hotel.',
          ),
          actions: [
            CustomButton.text(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    final bool confirmed = await showFreshHotelStartDialog(context);

    if (!confirmed || !mounted) {
      return;
    }

    CloudSyncService.autoSyncPaused = true;

    final prefs = await HotelDataBuffer.getInstance();

    await prefs.remove(CloudSyncService.billKey);
    await prefs.remove(CloudSyncService.customerKey);
    await prefs.remove(CloudSyncService.expenseKey);

    BillStore.bills.clear();
    CustomerStore.customers.clear();
    ExpenseStore.expenses.clear();

    setState(() {
      for (final Room room in rooms) {
        room.status = "EMPTY";
        room.faultReason = "";

        room.mobile = "";
        room.guestName = "";
        room.idNumber = "";
        room.guestAddress = "";

        room.bookingRate = room.normalRent;
        room.bookingDate = null;
        room.bookingTime = null;
        room.checkoutTime = null;
        room.days = 0;
        room.advance = 0;
        room.paymentMode = "";

        room.futureBooking = false;
        room.futureMobile = "";
        room.futureGuestName = "";
        room.futureIdNumber = "";
        room.futureGuestAddress = "";
        room.futureBookingRate = room.normalRent;
        room.futureBookingDate = null;
        room.futureDays = 0;
        room.futureAdvance = 0;
        room.futurePaymentMode = "";

        room.charges = [];
        room.partPayments = [];
        room.extraGuests = [];
        room.futureExtraGuests = [];
      }
    });

    await saveRooms();
    CloudSyncService.autoSyncPaused = false;
    await CloudSyncService.markDirty();
    await CloudSyncService.syncNow(forcePush: true);

    if (!mounted) {
      return;
    }

    await showCustomBottomSheet(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext successContext) {
        return CustomDialog(
          title: const Text("Fresh hotel start complete"),
          content: const Text(
            "All test data has been cleared successfully.\n\n"
            "Hotel is now ready for fresh real data.",
          ),
          actions: [
            CustomButton(
              autofocus: true,
              onPressed: () {
                Navigator.pop(successContext);
              },
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  Widget summaryBox(String title, int number, Color color) {
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: CustomColors.surface,
        border: Border.all(color: color.withValues(alpha: .18)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            "$number",
            style: TextStyle(
              color: color,
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            title,
            maxLines: 1,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Future<void> openHotelSettings() async {
    final bool saved = await showHotelSettingsDialog(context);

    if (!mounted) {
      return;
    }

    if (saved) {
      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Hotel settings saved successfully")),
      );
    }
  }

  Future<void> openBackupRestore() async {
    await showBackupRestoreDialog(
      context,
      onRestoreCompleted: () async {
        await loadRooms();
        await BillStore.loadBills();
        await CustomerStore.loadCustomers();

        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  Future<void> _manageSelectedRoom(Room room, {required bool delete}) async {
    try {
      final current = liveRoom(room);
      if (!rooms.contains(current)) {
        throw StateError('This room no longer exists. Refresh the list.');
      }
      await _runRoomAction(
        () => delete ? deleteRoom(current) : editRoom(current),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> handleMenuAction(String action) async {
    try {
      if (const {
        'logout',
        'reports',
        'customers',
        'expenses',
        'settings',
        'backup',
        'fresh',
        'contact',
      }.contains(action)) {
        await _handleMenuAction(action);
      } else {
        await _runRoomAction(() => _handleMenuAction(action));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _handleMenuAction(String action) async {
    switch (action) {
      case "logout":
        final leave = await showCustomBottomSheet<bool>(
          context: context,
          builder: (dialogContext) => CustomDialog(
            icon: Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: CustomColors.neutralTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: CustomColors.button,
                size: 30,
              ),
            ),
            title: const Text(
              'See you again soon',
              textAlign: TextAlign.center,
            ),
            content: const Text(
              'Sign out of Hotel Pro? Your saved hotel data will be here when you return.',
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              CustomButton.text(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Stay here'),
              ),
              CustomButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Sign out'),
              ),
            ],
          ),
        );
        if (leave != true || !mounted) return;
        _cloudPoll?.cancel();
        {
          await HotelCloudSyncService.instance.retainDataForNextLogin();
          await PhoneAuthService.instance.signOutAuthOnly();
          HotelDataBuffer.clearSession();
          BillStore.bills.clear();
          CustomerStore.customers.clear();
          ExpenseStore.expenses.clear();
        }
        if (!mounted) return;
        if (kIsWeb) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => const CloudGate(firebaseReady: true),
          ),
          (_) => false,
        );
        break;
      case "add":
        await addRoom();
        break;
      case "edit":
        await editRoom();
        break;
      case "customers":
        await showCustomerListDialog(context);
        break;
      case "reports":
        await showReportsDialog(context);
        break;
      case "expenses":
        await showExpensesDialog(context);
        break;
      case "backup":
        await openBackupRestore();
        break;
      case "fresh":
        await freshHotelStart();
        break;
      case "settings":
        await openHotelSettings();
        break;
      case "delete":
        await deleteRoom();
        break;
      case "contact":
        await showContactUsDialog(context);
        break;
    }
  }

  @override
  Widget build(BuildContext context) => HotelDashboardView(
    hotelName: HotelSettingsStore.hotelName,
    rooms: rooms,
    roomsLoading: _roomsLoading,
    onAction: handleMenuAction,
    onOpenRoom: openRoom,
    onEditRoom: (room) => _manageSelectedRoom(room, delete: false),
    onDeleteRoom: (room) => _manageSelectedRoom(room, delete: true),
    onSettingsSaved: () {
      if (mounted) setState(() {});
    },
    onRefresh: _refreshHotel,
    membershipBanner: TrialBanner(onActivated: _reloadAfterCloudApply),
  );
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/backend_config.dart';
import '../services/cloud_sync_service.dart';
import '../services/cpanel_sync_service.dart';
import '../services/hotel_cloud_sync_service.dart';
import '../dialogs/booking_view_dialog.dart';
import '../dialogs/bill_preview_dialog.dart';
import '../dialogs/booking_dialog.dart';
import '../data/default_rooms.dart';
import '../models/room.dart';
import '../models/customer.dart';
import '../models/bill_record.dart';
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
import '../widgets/hotel_cloud_status_chip.dart';
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
  final List<Room> rooms = [
    for (final DefaultRoomSpec spec in kDefaultRoomSpecs)
      Room(
        roomNumber: spec.roomNumber,
        roomType: spec.roomType,
        normalRent: spec.normalRent,
      ),
  ];

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
    try {
      return await action();
    } finally {
      _roomActionDepth--;
      await sync.endLocalAction();
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
      if (hotelUsesCpanel) {
        await CpanelSyncService.instance.retry();
        return;
      }
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
      if (hotelUsesCpanel) unawaited(_autoSync());
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> saveRooms() async {
    final prefs = await SharedPreferences.getInstance();

    final roomData = rooms.map((room) => room.toJson()).toList();

    await prefs.setString(CloudSyncService.roomKey, jsonEncode(roomData));
    await CloudSyncService.markDirty();
    unawaited(CloudSyncService.syncIfEnabled(force: true, pullOnly: false));
    await HotelCloudSyncService.instance.notifyLocalChanged();
    if (_roomActionDepth == 0) _showSaveResult();
  }

  Future<void> loadRooms() async {
    final prefs = await SharedPreferences.getInstance();

    final savedData = prefs.getString(CloudSyncService.roomKey);

    if (savedData == null) {
      if (!LicenseService.instance.canEditHotel) return;
      await saveRooms();
      return;
    }

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

      for (final Room room in rooms) {
        if (room.status == "BOOKED" && room.bookingTime == null) {
          room.bookingTime = room.bookingDate ?? DateTime.now();
        }
      }
    });
  }

  Color getRoomColor(String status) {
    if (status == "EMPTY") {
      return Colors.green.shade700;
    }

    if (status == "BOOKED") {
      return Colors.red.shade700;
    }

    if (status == "CLEANING") {
      return Colors.amber.shade700;
    }

    return const Color(0xFF800000);
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

      await showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text("No Room Available"),
            content: const Text("No empty room is available for room change."),
            actions: [
              TextButton(
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

    bool? changeConfirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter updateDialog) {
            return AlertDialog(
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

                    DropdownButtonFormField<Room>(
                      initialValue: selectedRoom,
                      decoration: const InputDecoration(
                        labelText: "Select New Room",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.hotel),
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
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, false);
                  },
                  child: const Text("CANCEL"),
                ),

                ElevatedButton.icon(
                  onPressed: selectedRoom == null
                      ? null
                      : () {
                          Navigator.pop(dialogContext, true);
                        },
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text("CONFIRM ROOM CHANGE"),
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

    await showDialog(
      context: context,
      builder: (BuildContext successContext) {
        return AlertDialog(
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
            TextButton(
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

      bool? paymentConfirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter updateDialog) {
              return AlertDialog(
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

                        TextField(
                          controller: discountController,
                          focusNode: discountFocus,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) {
                            paymentModeFocus.requestFocus();
                          },
                          decoration: const InputDecoration(
                            labelText: "DISCOUNT",
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
                            color: Colors.red,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 20),

                        DropdownButtonFormField<String>(
                          focusNode: paymentModeFocus,
                          initialValue: paymentMode,
                          decoration: const InputDecoration(
                            labelText: "Balance Payment Mode",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.payment),
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
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext, false);
                    },
                    child: const Text("CANCEL"),
                  ),

                  ElevatedButton.icon(
                    autofocus: true,
                    focusNode: checkoutButtonFocus,
                    onPressed: () {
                      Navigator.pop(dialogContext, true);
                    },
                    icon: const Icon(Icons.check_circle),
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
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text("Room ${room.roomNumber} Cleaning"),
          content: const Text(
            "Is room cleaning complete?\n\n"
            "Guest and old billing data will be cleared.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text("CANCEL"),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.cleaning_services),
              label: const Text("CLEANING COMPLETE"),
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

    String? action = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter updateDialog) {
            return AlertDialog(
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
                        color: Color(0xFF800000),
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 15),

                    DropdownButtonFormField<String>(
                      initialValue: selectedFault,
                      decoration: const InputDecoration(
                        labelText: "Fault / Closing Reason",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.build),
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
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, "CLOSE");
                  },
                  child: const Text("CLOSE"),
                ),

                OutlinedButton.icon(
                  onPressed: () {
                    room.faultReason = selectedFault;

                    Navigator.pop(dialogContext, "SAVED");
                  },
                  icon: const Icon(Icons.save),
                  label: const Text("SAVE FAULT"),
                ),

                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext, "REPAIRED");
                  },
                  icon: const Icon(Icons.check_circle),
                  label: const Text("ROOM REPAIRED / OPEN ROOM"),
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
      String? futureAction = await showDialog<String>(
        context: context,
        builder: (BuildContext futureContext) {
          return AlertDialog(
            title: Text("ROOM ${room.roomNumber}"),
            content: const Text("This room has a Future Booking"),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(futureContext, "CLOSE");
                },
                child: const Text("CLOSE"),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(futureContext, "VIEW");
                },
                icon: const Icon(Icons.visibility),
                label: const Text("VIEW FUTURE BOOKING"),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(futureContext, "NEW_BOOKING");
                },
                icon: const Icon(Icons.add),
                label: const Text("NEW BOOKING"),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      if (futureAction == "VIEW") {
        await showBookingViewDialog(context, room, showFutureBooking: true);

        return;
      }

      if (futureAction == "NEW_BOOKING") {
        bool? booked = await showBookingDialog(context, room);

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

    bool? openBooking = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
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
                  Text(
                    "FUTURE BOOKING",
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "Booking Date : "
                    "${formatDate(room.futureBookingDate!)}",
                  ),
                  Text(
                    "Booking Time : "
                    "${formatTimeRange(room.futureBookingDate!, room.futureBookingEnd)}",
                  ),
                  Text("Guest : ${room.futureGuestName}"),
                ],
                const SizedBox(height: 20),
                if (room.status == "EMPTY")
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext, true);
                      },
                      icon: const Icon(Icons.book_online),
                      label: const Text("BOOK ROOM"),
                    ),
                  ),

                if (room.status == "EMPTY") ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      height: 36,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            room.status = "CLOSED";
                            room.faultReason = "Technical Fault";
                          });

                          saveRooms();

                          Navigator.pop(dialogContext, false);
                        },
                        icon: const Icon(Icons.lock_outline, size: 16),
                        label: const Text(
                          "TEMPORARY CLOSED",
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text("CLOSE"),
            ),
          ],
        );
      },
    );

    if (openBooking == true && mounted) {
      bool? bookingSaved = await showBookingDialog(context, room);

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

  Future<void> addRoom() async {
    final roomNumberController = TextEditingController();
    final roomTypeController = TextEditingController();
    final roomRentController = TextEditingController();

    final typeFocus = FocusNode();
    final rentFocus = FocusNode();

    await showDialog(
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

        return AlertDialog(
          title: const Text("Add New Room"),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
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
                TextField(
                  controller: roomTypeController,
                  focusNode: typeFocus,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: "Room Type"),
                  onSubmitted: (value) {
                    rentFocus.requestFocus();
                  },
                ),
                TextField(
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
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text("CANCEL"),
            ),
            ElevatedButton.icon(
              onPressed: saveRoom,
              icon: const Icon(Icons.add),
              label: const Text("ADD ROOM"),
            ),
          ],
        );
      },
    );
  }

  Future<void> deleteRoom() async {
    final emptyRooms = rooms.where((room) {
      return room.status == "EMPTY";
    }).toList();

    if (emptyRooms.isEmpty) {
      return;
    }

    Room? selectedRoom;

    final roomSelected = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter updateDialog) {
            return AlertDialog(
              title: const Text("Select Room To Delete"),
              content: SizedBox(
                width: 420,
                child: DropdownButtonFormField<Room>(
                  decoration: const InputDecoration(
                    labelText: "Select EMPTY Room",
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
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, false);
                  },
                  child: const Text("CANCEL"),
                ),
                ElevatedButton.icon(
                  onPressed: selectedRoom == null
                      ? null
                      : () {
                          Navigator.pop(dialogContext, true);
                        },
                  icon: const Icon(Icons.delete),
                  label: const Text("DELETE"),
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

    final room = selectedRoom!;

    final deleteConfirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Delete Room?"),
          content: Text(
            "Are you sure you want to delete Room ${room.roomNumber}?",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text("NO"),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.delete_forever),
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

  Future<void> editRoom() async {
    final editableRooms = rooms.where((room) {
      return room.status == "EMPTY";
    }).toList();

    if (editableRooms.isEmpty) {
      return;
    }

    Room? selectedRoom;

    bool? roomSelected = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter updateDialog) {
            return AlertDialog(
              title: const Text("Select Room To Edit"),
              content: SizedBox(
                width: 420,
                child: DropdownButtonFormField<Room>(
                  decoration: const InputDecoration(
                    labelText: "Select EMPTY Room",
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
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, false);
                  },
                  child: const Text("CANCEL"),
                ),
                ElevatedButton.icon(
                  onPressed: selectedRoom == null
                      ? null
                      : () {
                          Navigator.pop(dialogContext, true);
                        },
                  icon: const Icon(Icons.edit),
                  label: const Text("EDIT"),
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

    final room = selectedRoom!;

    final roomNumberController = TextEditingController(text: room.label);
    final roomTypeController = TextEditingController(text: room.roomType);
    final roomRentController = TextEditingController(
      text: room.normalRent.toString(),
    );

    final typeFocus = FocusNode();
    final rentFocus = FocusNode();

    await showDialog(
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

        return AlertDialog(
          title: Text("Edit Room ${room.label}"),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
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
                TextField(
                  controller: roomTypeController,
                  focusNode: typeFocus,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: "Room Type"),
                  onSubmitted: (value) {
                    rentFocus.requestFocus();
                  },
                ),
                TextField(
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
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text("CANCEL"),
            ),
            ElevatedButton.icon(
              onPressed: saveRoomChanges,
              icon: const Icon(Icons.save),
              label: const Text("SAVE CHANGES"),
            ),
          ],
        );
      },
    );
  }

  Future<void> freshHotelStart() async {
    if (HotelCloudSyncService.instance.isReady) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Shared hotel records are protected'),
          content: const Text(
            'Fresh start cannot erase a shared cloud hotel. Export a backup and request a reviewed archive/reset before starting a new hotel.',
          ),
          actions: [
            TextButton(
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

    final prefs = await SharedPreferences.getInstance();

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

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext successContext) {
        return AlertDialog(
          title: const Text("FRESH HOTEL START COMPLETE"),
          content: const Text(
            "All test data has been cleared successfully.\n\n"
            "Hotel is now ready for fresh real data.",
          ),
          actions: [
            ElevatedButton(
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
      width: 62,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            "$number",
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            maxLines: 1,
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
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
        const SnackBar(content: Text("HOTEL SETTINGS SAVED SUCCESSFULLY")),
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

  Future<void> handleMenuAction(String action) async {
    try {
      await _runRoomAction(() => _handleMenuAction(action));
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool isCompact = screenWidth < 720;
    final String hotelName = HotelSettingsStore.hotelName;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        titleSpacing: isCompact ? 12 : null,
        title: Text(
          hotelName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: isCompact ? 16 : 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: isCompact
            ? [
                const HotelCloudStatusChip(),
                IconButton(
                  tooltip: "REPORTS",
                  onPressed: () {
                    handleMenuAction("reports");
                  },
                  icon: const Icon(Icons.bar_chart),
                ),
                IconButton(
                  tooltip: "CUSTOMERS",
                  onPressed: () {
                    handleMenuAction("customers");
                  },
                  icon: const Icon(Icons.people),
                ),
                PopupMenuButton<String>(
                  tooltip: "MORE",
                  onSelected: handleMenuAction,
                  itemBuilder: (BuildContext menuContext) {
                    return const [
                      PopupMenuItem(value: "add", child: Text("ADD ROOM")),
                      PopupMenuItem(value: "edit", child: Text("EDIT ROOM")),
                      PopupMenuItem(
                        value: "expenses",
                        child: Text("HOTEL EXPENSES"),
                      ),
                      PopupMenuItem(
                        value: "backup",
                        child: Text("BACKUP / RESTORE"),
                      ),
                      PopupMenuItem(
                        value: "fresh",
                        child: Text("FRESH HOTEL START"),
                      ),
                      PopupMenuItem(
                        value: "settings",
                        child: Text("HOTEL SETTINGS"),
                      ),
                      PopupMenuItem(
                        value: "delete",
                        child: Text("DELETE ROOM"),
                      ),
                    ];
                  },
                ),
              ]
            : [
                const HotelCloudStatusChip(),
                IconButton(
                  tooltip: "ADD ROOM",
                  onPressed: () => handleMenuAction("add"),
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  tooltip: "EDIT ROOM",
                  onPressed: () => handleMenuAction("edit"),
                  icon: const Icon(Icons.edit),
                ),
                IconButton(
                  tooltip: "CUSTOMERS",
                  onPressed: () {
                    handleMenuAction("customers");
                  },
                  icon: const Icon(Icons.people),
                ),
                IconButton(
                  tooltip: "REPORTS",
                  onPressed: () {
                    handleMenuAction("reports");
                  },
                  icon: const Icon(Icons.bar_chart),
                ),
                IconButton(
                  tooltip: "HOTEL EXPENSES",
                  onPressed: () {
                    handleMenuAction("expenses");
                  },
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                ),
                IconButton(
                  tooltip: "BACKUP / RESTORE DATA",
                  onPressed: () => handleMenuAction("backup"),
                  icon: const Icon(Icons.backup_outlined),
                ),
                IconButton(
                  tooltip: "FRESH HOTEL START",
                  onPressed: () => handleMenuAction("fresh"),
                  icon: const Icon(Icons.restart_alt),
                ),
                IconButton(
                  tooltip: "HOTEL SETTINGS",
                  onPressed: () => handleMenuAction("settings"),
                  icon: const Icon(Icons.settings),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    tooltip: "DELETE ROOM",
                    onPressed: () => handleMenuAction("delete"),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ],
      ),
      body: Column(
        children: [
          TrialBanner(onActivated: _reloadAfterCloudApply),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 12 : 20,
                isCompact ? 8 : 20,
                isCompact ? 12 : 20,
                isCompact ? 12 : 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Room Dashboard",
                    style: TextStyle(
                      fontSize: isCompact ? 18 : 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: isCompact ? 6 : 10),
                  Wrap(
                    spacing: 3,
                    runSpacing: 3,
                    children: [
                      summaryBox("TOTAL", rooms.length, Colors.blueGrey),
                      summaryBox("EMPTY", countStatus("EMPTY"), Colors.green),
                      summaryBox("BOOKED", countStatus("BOOKED"), Colors.red),
                      summaryBox(
                        "CLEANING",
                        countStatus("CLEANING"),
                        Colors.amber,
                      ),
                      summaryBox(
                        "CLOSED",
                        countStatus("CLOSED"),
                        const Color(0xFF800000),
                      ),
                    ],
                  ),
                  SizedBox(height: isCompact ? 6 : 12),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: isCompact ? 140 : 180,
                        crossAxisSpacing: isCompact ? 10 : 15,
                        mainAxisSpacing: isCompact ? 10 : 15,
                        childAspectRatio: isCompact ? 0.78 : 0.86,
                      ),
                      itemCount: rooms.length,
                      itemBuilder: (BuildContext context, int index) {
                        Room room = rooms[index];

                        return InkWell(
                          onTap: () {
                            openRoom(room);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: getRoomColor(room.status),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.hotel,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  const SizedBox(height: 5),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      room.cardTitle,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 19,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    room.status,
                                    style: const TextStyle(color: Colors.white),
                                  ),

                                  if (room.status == "BOOKED" &&
                                      room.bookingTime != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      "STAY : ${room.stayDurationLabel()}",
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      "TIME : ${formatTimeRange(room.bookingTime!, room.bookingEndTime)}",
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],

                                  if (room.futureBooking &&
                                      room.futureBookingDate != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      "FUTURE • ${formatDate(room.futureBookingDate!)} ${formatTimeRange(room.futureBookingDate!, room.futureBookingEnd)}",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

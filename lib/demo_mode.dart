import 'dart:convert';

import 'package:flutter/material.dart';
import 'services/hotel_data_buffer.dart';

import 'models/bill_record.dart';
import 'models/customer.dart';
import 'models/room.dart';
import 'services/cloud_sync_service.dart';
import 'stores/bill_store.dart';
import 'stores/customer_store.dart';
import 'stores/expense_store.dart';
import 'stores/hotel_settings_store.dart';

/// Sales / showcase build — fake data only, no cloud.
const bool kSalesDemoMode = bool.fromEnvironment(
  'DEMO_MODE',
  defaultValue: false,
);

Widget wrapSalesDemoBanner(BuildContext context, Widget? child) {
  if (!kSalesDemoMode || child == null) return child ?? const SizedBox.shrink();
  return Banner(
    message: 'SALES DEMO',
    location: BannerLocation.topEnd,
    color: const Color(0xFFB71C1C),
    child: Column(
      children: [
        Material(
          color: const Color(0xFFB71C1C),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 12,
                ),
                child: Text(
                  'DEMO / SALES SAMPLE — fake data only · cloud OFF',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

/// Seeds sample hotel data once (separate app id → empty prefs on install).
Future<void> seedHotelSalesDemoIfNeeded() async {
  if (!kSalesDemoMode) return;
  final prefs = await HotelDataBuffer.getInstance();
  if (prefs.getBool('sales_demo_seeded_v1') == true) return;

  CloudSyncService.autoSyncPaused = true;
  try {
    await HotelSettingsStore.saveSettings(
      hotelNameValue: 'Silver Cloud Hotel (DEMO)',
      hotelAddressValue: 'Sample Road, Demo City — Sales Showcase',
      hotelMobileValue: '9000000001',
      registrationNumberValue: 'DEMO-REG-001',
      gstNumberValue: '22AAAAA0000A1Z5',
      adminPasswordValue: 'DEMO1234',
    );

    final now = DateTime.now();
    final checkIn = now.subtract(const Duration(days: 1));
    final rooms = <Room>[
      Room(roomNumber: 101, roomType: 'Deluxe', normalRent: 1500)
        ..status = 'BOOKED'
        ..guestName = 'Rahul Sharma'
        ..mobile = '9811111101'
        ..idNumber = 'DEMO-AADHAAR-101'
        ..bookingRate = 1500
        ..bookingDate = checkIn
        ..bookingTime = checkIn
        ..days = 2
        ..advance = 500
        ..paymentMode = 'UPI',
      Room(roomNumber: 102, roomType: 'Luxury', normalRent: 2000)
        ..status = 'BOOKED'
        ..guestName = 'Priya Verma'
        ..mobile = '9811111102'
        ..idNumber = 'DEMO-AADHAAR-102'
        ..bookingRate = 2000
        ..bookingDate = now
        ..bookingTime = now
        ..days = 1
        ..advance = 1000
        ..paymentMode = 'Cash',
      Room(roomNumber: 103, roomType: 'Deluxe', normalRent: 1500),
      Room(roomNumber: 104, roomType: 'Luxury', normalRent: 2000),
      Room(roomNumber: 105, roomType: 'Deluxe', normalRent: 1500),
      Room(roomNumber: 106, roomType: 'Luxury', normalRent: 2000),
      Room(roomNumber: 107, roomType: 'Deluxe', normalRent: 1500),
      Room(roomNumber: 108, roomType: 'Suite', normalRent: 2500),
      Room(roomNumber: 109, roomType: 'Deluxe', normalRent: 1500),
      Room(roomNumber: 110, roomType: 'Luxury', normalRent: 2000),
      Room(roomNumber: 111, roomType: 'Deluxe', normalRent: 1500),
      Room(roomNumber: 112, roomType: 'Suite', normalRent: 2500),
    ];
    await prefs.setString(
      CloudSyncService.roomKey,
      jsonEncode(rooms.map((r) => r.toJson()).toList()),
    );

    CustomerStore.customers
      ..clear()
      ..addAll([
        Customer(
          customerId: 'CUST-0001',
          mobile: '9811111101',
          guestName: 'Rahul Sharma',
          idType: 'Aadhaar',
          idNumber: 'DEMO-AADHAAR-101',
        ),
        Customer(
          customerId: 'CUST-0002',
          mobile: '9811111102',
          guestName: 'Priya Verma',
          idType: 'Aadhaar',
          idNumber: 'DEMO-AADHAAR-102',
        ),
        Customer(
          customerId: 'CUST-0003',
          mobile: '9811111103',
          guestName: 'Amit Patel',
          idType: 'PAN',
          idNumber: 'DEMOP1234A',
        ),
      ]);
    await prefs.setString(
      CloudSyncService.customerKey,
      jsonEncode(
        CustomerStore.customers
            .map(
              (c) => {
                'customerId': c.customerId,
                'mobile': c.mobile,
                'guestName': c.guestName,
                'address': c.address,
                'idType': c.idType,
                'idNumber': c.idNumber,
                'idFrontPhotoPath': c.idFrontPhotoPath,
                'idBackPhotoPath': c.idBackPhotoPath,
                'stayHistory': c.stayHistory,
              },
            )
            .toList(),
      ),
    );

    final checkout = now.subtract(const Duration(days: 3));
    final booking = checkout.subtract(const Duration(days: 2));
    BillStore.bills
      ..clear()
      ..add(
        BillRecord(
          billNumber: 'BILL-000001',
          customerId: 'CUST-0003',
          guestName: 'Amit Patel',
          mobile: '9811111103',
          roomNumber: 108,
          roomType: 'Suite',
          bookingDate: booking,
          bookingTime: booking,
          checkoutTime: checkout,
          roomRate: 2500,
          bookedDays: 2,
          roomBill: 5000,
          charges: const [],
          partPayments: const [],
          extraCharges: 0,
          totalBill: 5000,
          discount: 0,
          advance: 2000,
          advancePaymentMode: 'Cash',
          balance: 0,
          paymentMode: 'UPI',
        ),
      );
    await prefs.setString(
      CloudSyncService.billKey,
      jsonEncode(BillStore.bills.map((b) => b.toJson()).toList()),
    );

    ExpenseStore.expenses
      ..clear()
      ..addAll([
        {
          'dateTime': now.toIso8601String(),
          'category': 'Cleaning',
          'description': 'Housekeeping supplies (demo)',
          'amount': 1200,
          'paymentMode': 'Cash',
        },
        {
          'dateTime': now.subtract(const Duration(days: 2)).toIso8601String(),
          'category': 'Electricity',
          'description': 'Monthly electricity (demo)',
          'amount': 4500,
          'paymentMode': 'UPI',
        },
      ]);
    await prefs.setString(
      CloudSyncService.expenseKey,
      jsonEncode(ExpenseStore.expenses),
    );

    await prefs.setBool('sales_demo_seeded_v1', true);
  } finally {
    CloudSyncService.autoSyncPaused = false;
  }
}

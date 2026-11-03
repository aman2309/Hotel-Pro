import 'package:get/get.dart';

import '../../../../models/bill_record.dart';
import '../../../../services/hotel_record_ids.dart';
import 'hotel_controller.dart';

class BillsController extends GetxController {
  static BillsController get instance {
    if (Get.isRegistered<BillsController>()) {
      return Get.find<BillsController>();
    }
    return Get.put(BillsController(), permanent: true);
  }

  final RxList<BillRecord> bills = <BillRecord>[].obs;

  List<BillRecord> get value => bills;

  void apply(List<BillRecord> incoming) {
    bills.assignAll(incoming);
  }

  Future<void> saveBill(BillRecord bill) async {
    final bool exists = bills.any(
      (BillRecord existing) => existing.billNumber == bill.billNumber,
    );
    if (exists) {
      final BillRecord current = bills.firstWhere(
        (BillRecord existing) => existing.billNumber == bill.billNumber,
      );
      if (current.toJson().toString() != bill.toJson().toString()) {
        throw StateError('Bill ID already exists with different details.');
      }
    } else {
      bills.add(bill);
      bills.refresh();
    }
    await HotelController.instance.saveBill(bill);
  }

  static String nextBillNumber() => HotelRecordIds.create('BILL');
}

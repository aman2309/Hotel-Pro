import 'package:get/get.dart';

import '../../../../services/hotel_record_ids.dart';
import 'hotel_controller.dart';

class ExpensesController extends GetxController {
  static ExpensesController get instance {
    if (Get.isRegistered<ExpensesController>()) {
      return Get.find<ExpensesController>();
    }
    return Get.put(ExpensesController(), permanent: true);
  }

  final RxList<Map<String, dynamic>> expenses = <Map<String, dynamic>>[].obs;

  List<Map<String, dynamic>> get value => expenses;

  void apply(List<Map<String, dynamic>> incoming) {
    expenses.assignAll(incoming);
  }

  Future<void> addExpense(Map<String, dynamic> expense) async {
    expense['expenseId'] ??= HotelRecordIds.create('exp');
    final Object? id = expense['expenseId'];
    if (expenses.any((Map<String, dynamic> item) => item['expenseId'] == id)) {
      return;
    }
    expenses.add(Map<String, dynamic>.from(expense));
    await HotelController.instance.saveExpenses(
      expenses.map(Map<String, dynamic>.from).toList(),
    );
  }

  Future<void> deleteExpense(Map<String, dynamic> expense) async {
    final Object? id = expense['expenseId'] ?? expense['id'];
    expenses.removeWhere((Map<String, dynamic> item) {
      return (item['expenseId'] ?? item['id']) == id;
    });
    await HotelController.instance.saveExpenses(
      expenses.map(Map<String, dynamic>.from).toList(),
    );
  }

  Future<void> saveAll() async {
    await HotelController.instance.saveExpenses(
      expenses.map(Map<String, dynamic>.from).toList(),
    );
  }
}

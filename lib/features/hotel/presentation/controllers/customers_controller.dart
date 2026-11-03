import 'package:get/get.dart';

import '../../../../models/customer.dart';
import '../../../../services/hotel_record_ids.dart';
import 'hotel_controller.dart';

/// Firestore-backed guest directory. Photo bytes stay in memory; only Storage
/// paths and metadata are written to the guest document.
class CustomersController extends GetxController {
  static CustomersController get instance {
    if (Get.isRegistered<CustomersController>()) {
      return Get.find<CustomersController>();
    }
    return Get.put(CustomersController(), permanent: true);
  }

  final RxList<Customer> customers = <Customer>[].obs;

  List<Customer> get value => customers;

  void apply(List<Customer> incoming) {
    customers.assignAll(incoming);
  }

  static String normalizedMobile(String mobile) {
    final String digits = mobile.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  Customer? findByMobile(String mobile) {
    final String clean = normalizedMobile(mobile);
    if (clean.isEmpty) return null;
    for (final Customer customer in customers) {
      if (normalizedMobile(customer.mobile) == clean) {
        return customer;
      }
    }
    return null;
  }

  Future<Customer> saveCustomer(Customer customer) async {
    Customer? existing = findByMobile(customer.mobile);
    if (existing == null) {
      if (customer.customerId.isEmpty) {
        customer.customerId = HotelRecordIds.guest(
          normalizedMobile(customer.mobile),
        );
      }
      existing = customer;
      customers.add(customer);
    } else {
      existing.guestName = customer.guestName;
      existing.idType = customer.idType;
      existing.idNumber = customer.idNumber;
      if (customer.address.trim().isNotEmpty) {
        existing.address = customer.address.trim();
      }
      if (customer.idFrontPhotoPath.isNotEmpty) {
        existing.idFrontPhotoPath = customer.idFrontPhotoPath;
      }
      if (customer.idBackPhotoPath.isNotEmpty) {
        existing.idBackPhotoPath = customer.idBackPhotoPath;
      }
    }
    customers.refresh();
    await HotelController.instance.saveCustomer(existing);
    return existing;
  }

  Future<bool> updateCustomer(
    Customer customer, {
    required String mobile,
    required String guestName,
    required String address,
    required String idType,
    required String idNumber,
    required String idFrontPhotoPath,
    required String idBackPhotoPath,
  }) async {
    final String cleanMobile = mobile.trim();
    for (final Customer other in customers) {
      if (other != customer && other.mobile == cleanMobile) {
        return false;
      }
    }
    customer.mobile = cleanMobile;
    customer.guestName = guestName.trim();
    customer.address = address.trim();
    customer.idType = idType.trim();
    customer.idNumber = idNumber.trim();
    customer.idFrontPhotoPath = idFrontPhotoPath;
    customer.idBackPhotoPath = idBackPhotoPath;
    customers.refresh();
    await HotelController.instance.saveCustomer(customer);
    return true;
  }

  Future<void> addStayHistory(
    String mobile,
    Map<String, dynamic> history,
  ) async {
    final Customer? customer = findByMobile(mobile);
    if (customer == null) return;
    final Object? bill = history['billNumber'];
    if (bill != null &&
        customer.stayHistory.any((Map<String, dynamic> stay) {
          return stay['billNumber'] == bill;
        })) {
      return;
    }
    customer.stayHistory.add(Map<String, dynamic>.from(history));
    customers.refresh();
    await HotelController.instance.saveCustomer(customer);
  }
}

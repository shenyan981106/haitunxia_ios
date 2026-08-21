import 'package:get/get.dart';

import '../../../data/models/address_model.dart';
import '../../../data/repositories/exam_repository.dart';
import '../../../services/snackbar_utils.dart';

/// 收货地址列表
class AddressListController extends GetxController {
  final ExamRepository _repository = ExamRepository.to;

  final RxList<AddressModel> addresses = <AddressModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isRefreshing = false.obs;
  final RxString errorMessage = ''.obs;

  @override
  void onReady() {
    super.onReady();
    loadAddresses();
  }

  /// 加载收货地址列表
  Future<void> loadAddresses({bool refresh = false}) async {
    if (refresh) {
      isRefreshing.value = true;
    } else {
      isLoading.value = true;
    }
    errorMessage.value = '';
    try {
      final response = await _repository.getAddressList();
      if (response.isSuccess) {
        addresses.assignAll(response.data ?? []);
      } else {
        errorMessage.value =
            response.message.isNotEmpty ? response.message : '加载失败，请重试';
      }
    } catch (e) {
      errorMessage.value = '加载失败，请重试';
    } finally {
      isLoading.value = false;
      isRefreshing.value = false;
    }
  }

  /// 下拉刷新
  Future<void> onRefresh() => loadAddresses(refresh: true);

  /// 删除地址(成功后从列表移除)
  Future<void> deleteAddress(int id) async {
    try {
      final response = await _repository.deleteAddress(id);
      if (response.isSuccess) {
        addresses.removeWhere((e) => e.id == id);
        SnackbarUtils.showSuccess('删除成功');
      } else {
        SnackbarUtils.showError(
            response.message.isNotEmpty ? response.message : '删除失败，请重试');
      }
    } catch (e) {
      SnackbarUtils.showError('删除失败，请重试');
    }
  }
}

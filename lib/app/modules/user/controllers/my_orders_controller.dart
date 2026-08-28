import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart' as dio;
import '../../../data/providers/api_client.dart';
import '../../../services/snackbar_utils.dart';

class MyOrdersController extends GetxController {
  // 订单列表
  final RxList<Map<String, dynamic>> orderList = <Map<String, dynamic>>[].obs;

  // 取消订单接口(待支付订单,传 order_sn,form-urlencoded)
  static const String _cancelOrderUrl = 'addons/exam/pay/cancelCourseOrder';

  // 当前 Tab 索引:0=待支付 1=已支付
  final RxInt currentTabIndex = 0.obs;

  // 加载状态
  RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    // ★课程详情支付成功后跳转携带 initialTab(1=已支付),定位到对应 Tab
    final args = Get.arguments;
    if (args is Map && args['initialTab'] is int) {
      currentTabIndex.value = args['initialTab'] as int;
    }
  }

  @override
  void onReady() {
    super.onReady();
    getMyOrderList();
  }

  /// 当前 Tab 对应的 order_status 参数(pending=待支付 paid=已支付)
  String get currentOrderStatus =>
      currentTabIndex.value == 0 ? 'pending' : 'paid';

  /// 切换顶部 Tab(切换后按状态重新拉取)
  void changeTab(int index) {
    if (currentTabIndex.value == index) return;
    currentTabIndex.value = index;
    getMyOrderList();
  }

  /// 获取我的订单列表(按 order_status 传参,后端过滤)
  Future<void> getMyOrderList() async {
    isLoading.value = true;
    try {
      var response = await ApiClient.to.get(
        'addons/exam/Coures/myList',
        queryParameters: {'order_status': currentOrderStatus},
      );

      if (response.data != null) {
        var body = response.data;
        List? list;

        if (body is Map && (body['code'] == 1 || body['code'] == 200)) {
          var data = body['data'];
          if (data is Map && data['list'] is List) {
            list = data['list'];
          } else if (data is List) {
            list = data;
          }
        }

        if (list != null && list.isNotEmpty) {
          orderList.value =
              list.map((e) => Map<String, dynamic>.from(e)).toList();
        } else {
          orderList.clear();
        }
      }
    } catch (e) {
      debugPrint("获取我的订单列表失败: $e");
      if (e is dio.DioException) {
        debugPrint("错误详情: ${e.response?.data}");
      }
      orderList.clear();
    } finally {
      isLoading.value = false;
    }
  }

  /// 下拉刷新
  Future<void> onRefresh() async {
    await getMyOrderList();
  }

  /// 取消订单(待支付订单,调用方先弹确认弹窗)
  Future<void> cancelOrder(Map<String, dynamic> order) async {
    final orderNo = order['order_no']?.toString() ?? '';
    if (orderNo.isEmpty) {
      SnackbarUtils.showWarning('订单号缺失');
      return;
    }
    try {
      final response = await ApiClient.to.post(
        _cancelOrderUrl,
        data: {'order_sn': orderNo},
        options: dio.Options(contentType: dio.Headers.formUrlEncodedContentType),
      );
      final body = response.data;
      if (body is Map && (body['code'] == 1 || body['code'] == 200)) {
        SnackbarUtils.showSuccess('订单已取消');
        getMyOrderList();
      } else {
        final msg = body is Map ? (body['msg']?.toString() ?? '') : '';
        SnackbarUtils.showError(msg.isNotEmpty ? msg : '取消订单失败');
      }
    } catch (e) {
      debugPrint('取消订单失败: $e');
      if (e is dio.DioException) {
        debugPrint('错误详情: ${e.response?.data}');
      }
      SnackbarUtils.showError('取消订单失败');
    }
  }
}

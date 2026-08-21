import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart' as dio;
import '../../../data/providers/api_client.dart';
import '../../../data/models/member_right_model.dart';

class MemberRightsController extends GetxController {
  // 我的权益列表(接口 /api/member/rights,data 为裸数组)
  final RxList<MemberRight> rightsList = <MemberRight>[].obs;

  // 当前 Tab 索引:0=生效中 1=已失效
  final RxInt currentTabIndex = 0.obs;

  // 加载状态
  RxBool isLoading = false.obs;

  // 分页状态
  RxBool isLoadingMore = false.obs;
  RxBool hasMore = true.obs;
  int _currentPage = 1;
  static const int _pageSize = 10;

  // 触底加载监听
  final ScrollController scrollController = ScrollController();

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
  }

  @override
  void onReady() {
    super.onReady();
    getMemberRightsList();
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }

  /// 滚动到底部时加载下一页
  void _onScroll() {
    if (!scrollController.hasClients) return;

    final position = scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      loadMoreRightsList();
    }
  }

  /// 当前 Tab 对应的 status 参数(active=生效中 expired=已失效)
  String get currentStatus => currentTabIndex.value == 0 ? 'active' : 'expired';

  /// 切换顶部 Tab(切换后按状态重新拉取第一页)
  void changeTab(int index) {
    if (currentTabIndex.value == index) return;
    currentTabIndex.value = index;
    getMemberRightsList();
  }

  /// 获取我的权益列表(第一页,重置分页)
  Future<void> getMemberRightsList() async {
    if (isLoading.value || isLoadingMore.value) return;

    _currentPage = 1;
    hasMore.value = true;
    isLoading.value = true;

    try {
      await _loadRightsPage(page: _currentPage, refresh: true);
    } catch (e) {
      debugPrint("获取我的权益列表失败: $e");
      if (e is dio.DioException) {
        debugPrint("错误详情: ${e.response?.data}");
      }
      rightsList.clear();
    } finally {
      isLoading.value = false;
    }
  }

  /// 上拉加载更多
  Future<void> loadMoreRightsList() async {
    if (isLoading.value || isLoadingMore.value || !hasMore.value) return;

    final nextPage = _currentPage + 1;
    isLoadingMore.value = true;

    try {
      await _loadRightsPage(page: nextPage, refresh: false);
    } catch (e) {
      debugPrint("获取我的权益列表失败: $e");
      if (e is dio.DioException) {
        debugPrint("错误详情: ${e.response?.data}");
      }
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> _loadRightsPage({
    required int page,
    required bool refresh,
  }) async {
    // ★status 只传 active/expired(其他值后端返回 code=0 "状态参数不正确")
    final requestedStatus = currentStatus;
    var response = await ApiClient.to.get(
      'api/member/rights',
      queryParameters: {
        'status': requestedStatus,
        'page': page,
        'limit': _pageSize,
      },
    );

    // 已切换 Tab,丢弃过期响应,避免新旧状态数据混入列表
    if (requestedStatus != currentStatus) return;

    var body = response.data;
    if (body is! Map || !(body['code'] == 1 || body['code'] == 200)) {
      hasMore.value = false;
      return;
    }

    var data = body['data'];
    List? list;
    if (data is Map && data['list'] is List) {
      list = data['list'];
    } else if (data is List) {
      list = data; // /api/member/rights 返回裸数组
    }

    if (list == null) {
      debugPrint("未能在返回数据中解析到列表，body: $body");
      if (refresh) {
        rightsList.clear();
      }
      hasMore.value = false;
      return;
    }

    final newList = list
        .map((e) => MemberRight.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    if (refresh) {
      rightsList.value = newList;
    } else {
      rightsList.addAll(newList);
    }

    _currentPage = page;
    // 分页判定:接口未返回 total,按一页是否拉满兜底
    hasMore.value = newList.length >= _pageSize;

    debugPrint(
        "成功解析到我的权益列表，page: $page，新增: ${newList.length}，hasMore: ${hasMore.value}");
  }

  /// 下拉刷新
  Future<void> onRefresh() async {
    await getMemberRightsList();
  }
}

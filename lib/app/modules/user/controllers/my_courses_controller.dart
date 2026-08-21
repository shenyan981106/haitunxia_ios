import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart' as dio;
import '../../../data/providers/api_client.dart';
import '../../../services/global_project_controller.dart';

class MyCoursesController extends GetxController {
  // 已购课程列表(接口 api/mycourse/index)
  final RxList<Map<String, dynamic>> courseOrderList =
      <Map<String, dynamic>>[].obs;

  // 加载状态
  RxBool isLoading = false.obs;

  // 分页状态
  RxBool isLoadingMore = false.obs;
  RxBool hasMore = true.obs;
  int _currentPage = 1;
  static const int _pageSize = 10;

  // 触底加载监听
  final ScrollController scrollController = ScrollController();

  // ★监听全局科目(二级科目)变化:切换科目后自动按新科目重拉。
  // ever() Worker 需手动释放,否则挂载在全局 Rx 上累积僵尸监听
  Worker? _projectWorker;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
  }

  @override
  void onReady() {
    super.onReady();
    // ★subject_id 以全局当前二级科目为准(首页/题库首页左上角选择,同 my_favorites/VIP memberPackages)
    _projectWorker = ever(GlobalProjectController.to.currentProject, (_) {
      getMyCourseList();
    });
    getMyCourseList();
  }

  @override
  void onClose() {
    _projectWorker?.dispose();
    scrollController.dispose();
    super.onClose();
  }

  /// 滚动到底部时加载下一页
  void _onScroll() {
    if (!scrollController.hasClients) return;

    final position = scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      loadMoreCourseList();
    }
  }

  /// 获取我的课程列表(第一页,重置分页)
  Future<void> getMyCourseList() async {
    if (isLoading.value || isLoadingMore.value) return;

    _currentPage = 1;
    hasMore.value = true;
    isLoading.value = true;

    try {
      await _loadMyCoursePage(page: _currentPage, refresh: true);
    } catch (e) {
      debugPrint("获取我的课程列表失败: $e");
      if (e is dio.DioException) {
        debugPrint("错误详情: ${e.response?.data}");
      }
      courseOrderList.clear();
    } finally {
      isLoading.value = false;
    }
  }

  /// 上拉加载更多
  Future<void> loadMoreCourseList() async {
    if (isLoading.value || isLoadingMore.value || !hasMore.value) return;

    final nextPage = _currentPage + 1;
    isLoadingMore.value = true;

    try {
      await _loadMyCoursePage(page: nextPage, refresh: false);
    } catch (e) {
      debugPrint("获取我的课程列表失败: $e");
      if (e is dio.DioException) {
        debugPrint("错误详情: ${e.response?.data}");
      }
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> _loadMyCoursePage({
    required int page,
    required bool refresh,
  }) async {
    final queryParams = <String, dynamic>{
      'page': page,
      'limit': _pageSize,
    };
    // ★科目过滤以全局当前二级科目为准(首页/题库首页左上角选择)。
    // 不依赖 Get.arguments:其为全局可变值,任何路由 push/pop 都会改写,
    // 多次切换科目后可能读到旧科目 ID → 列表显示旧科目数据(同 my_favorites)
    final currentProjectId =
        GlobalProjectController.to.currentProject.value?.id;
    final subjectId = currentProjectId ??
        (Get.arguments as Map<String, dynamic>?)?['subject_id'];
    if (subjectId != null && subjectId.toString().isNotEmpty) {
      queryParams['subject_id'] = subjectId.toString();
    }
    final requestedSubjectId = subjectId;

    var response = await ApiClient.to
        .get('api/mycourse/index', queryParameters: queryParams);

    // 科目已切换,丢弃过期响应
    final nowProjectId = GlobalProjectController.to.currentProject.value?.id;
    if (nowProjectId != requestedSubjectId) return;

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
      list = data;
    }

    if (list == null) {
      debugPrint("未能在返回数据中解析到列表，body: $body");
      if (refresh) {
        courseOrderList.clear();
      }
      hasMore.value = false;
      return;
    }

    final newList = list.map((e) => Map<String, dynamic>.from(e)).toList();

    if (refresh) {
      courseOrderList.value = newList;
    } else {
      courseOrderList.addAll(newList);
    }

    _currentPage = page;
    // 分页判定:优先用 total,缺省按一页是否拉满
    final total = data is Map
        ? int.tryParse(data['total']?.toString() ?? '')
        : null;
    hasMore.value = total != null
        ? page * _pageSize < total
        : newList.length >= _pageSize;

    debugPrint(
        "成功解析到我的课程列表，page: $page，新增: ${newList.length}，hasMore: ${hasMore.value}");
  }

  /// 下拉刷新
  Future<void> onRefresh() async {
    await getMyCourseList();
  }
}

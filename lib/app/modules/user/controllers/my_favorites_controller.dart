import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../data/providers/api_client.dart';
import '../../../services/global_project_controller.dart';

/// 收藏题目单项模型
class FavoriteItem {
  final int id;
  final int userId;
  final int questionId;
  final int createTime;
  final int updateTime;
  final int? qid;
  final String? kind;
  final String? title;
  final String? answer;
  final String? optionsJson;
  final String? difficulty;
  final String? explain;

  FavoriteItem({
    required this.id,
    required this.userId,
    required this.questionId,
    required this.createTime,
    required this.updateTime,
    this.qid,
    this.kind,
    this.title,
    this.answer,
    this.optionsJson,
    this.difficulty,
    this.explain,
  });

  factory FavoriteItem.fromJson(dynamic json) {
    if (json is! Map) {
      return FavoriteItem(
        id: 0,
        userId: 0,
        questionId: 0,
        createTime: 0,
        updateTime: 0,
      );
    }

    Map<String, dynamic>? qMap;
    final question = json['question'];
    if (question is Map) {
      qMap = <String, dynamic>{};
      for (final key in question.keys) {
        qMap[key.toString()] = question[key];
      }
    }

    return FavoriteItem(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      questionId: json['question_id'] ?? 0,
      createTime: json['createtime'] ?? 0,
      updateTime: json['updatetime'] ?? 0,
      qid: qMap?['id'],
      kind: qMap?['kind']?.toString(),
      title: qMap?['title']?.toString(),
      answer: qMap?['answer']?.toString(),
      optionsJson: qMap?['options_json']?.toString(),
      difficulty: qMap?['difficulty']?.toString(),
      explain: qMap?['explain']?.toString(),
    );
  }
}

/// 按分类分组的模型
class FavoriteGroup {
  final String cateName;
  final List<FavoriteItem> items;

  FavoriteGroup({required this.cateName, required this.items});

  int get count => items.length;
}

class MyFavoritesController extends GetxController {
  late final GlobalProjectController globalController;

  final RxList<FavoriteGroup> favoriteGroups = <FavoriteGroup>[].obs;
  final RxInt totalCount = 0.obs;
  final RxBool isLoading = true.obs;
  final RxBool isRefreshing = false.obs;
  final RxString errorMessage = ''.obs;

  // 排序选项状态
  final RxString currentSortTime = '录入时间'.obs;
  final RxString currentSortOrder = '新添加在前'.obs;

  /// 录入时间筛选选项
  static const timeOptions = ['不限', '15天', '30天'];

  /// 排序选项
  static const orderOptions = ['新添加在前', '新添加在后'];

  // ★2026-08-14 修复:ever() Worker 需手动释放,否则挂载在全局 Rx 上累积僵尸监听
  Worker? _projectWorker;

  @override
  void onReady() {
    super.onReady();
    try {
      globalController = GlobalProjectController.to;
      // ★监听全局科目(二级科目)变化:切换科目后自动按新科目重拉收藏列表,
      // 不再依赖路由参数 Get.arguments(全局可变,任何路由 push/pop 都会改写)
      _projectWorker = ever(globalController.currentProject, (_) {
        _loadFavorites();
      });
    } catch (e) {
      debugPrint('GlobalProjectController 获取失败: $e');
    }
    _loadFavorites();
  }

  @override
  void onClose() {
    _projectWorker?.dispose();
    super.onClose();
  }

  /// 加载收藏列表（调用 collectList 接口）
  Future<void> _loadFavorites({bool refresh = false}) async {
    if (refresh) {
      isRefreshing.value = true;
    } else {
      isLoading.value = true;
    }
    errorMessage.value = '';

    try {
      final params = <String, dynamic>{};
      params['order'] = currentSortOrder.value == '新添加在前' ? 'desc' : 'asc';

      // ★科目过滤以全局当前二级科目为准(collectList 按二级科目 ID 过滤)。
      // 不依赖 Get.arguments:其为全局可变值,任何路由 push/pop 都会改写,
      // 多次切换科目后可能读到旧科目 ID → 列表显示旧科目数据。
      final currentProjectId = globalController.currentProject.value?.id;
      final subjectId = currentProjectId ??
          (Get.arguments as Map<String, dynamic>?)?['subject_id'];
      if (subjectId != null) {
        params['subject_id'] = subjectId;
      }
      final requestedSubjectId = subjectId;

      final response = await ApiClient.to.getExam(
        'question/collectList',
        queryParameters: params.isEmpty ? null : params,
      );

      // 科目已切换,丢弃过期响应
      final nowProjectId = globalController.currentProject.value?.id;
      if (nowProjectId != requestedSubjectId) return;

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map && data['code'] == 1) {
          final innerData = data['data'];
          if (innerData is! Map) {
            errorMessage.value = '数据格式异常';
            return;
          }

          final listData = innerData['list'];
          final totalVal = innerData['total'];
          totalCount.value = totalVal ?? 0;

          final groups = <FavoriteGroup>[];

          if (listData is List && listData.isNotEmpty) {
            for (final group in listData) {
              if (group is! Map) continue;

              final cateName = group['cate_name']?.toString() ?? '未分组';
              final itemsRaw = group['items'];

              final items = <FavoriteItem>[];
              if (itemsRaw is List) {
                for (final item in itemsRaw) {
                  items.add(FavoriteItem.fromJson(item));
                }
              }

              if (items.isNotEmpty) {
                groups.add(FavoriteGroup(cateName: cateName, items: items));
              }
            }
          }

          favoriteGroups.assignAll(groups);
        } else {
          errorMessage.value =
              data is Map ? (data['msg']?.toString() ?? '获取收藏列表失败') : '数据异常';
        }
      } else {
        errorMessage.value = '网络请求失败';
      }
    } catch (e) {
      debugPrint('加载收藏列表失败: $e');
      errorMessage.value = '网络错误，请稍后重试';
    } finally {
      isLoading.value = false;
      isRefreshing.value = false;
    }
  }

  /// 下拉刷新
  Future<void> onRefresh() async => _loadFavorites(refresh: true);

  /// 选择录入时间筛选
  void selectTime(String time) {
    currentSortTime.value = time;
    _loadFavorites();
  }

  /// 选择排序方式
  void selectOrder(String order) {
    currentSortOrder.value = order;
    _loadFavorites();
  }

  /// 点击某个分组 - 跳转做题页面，返回后刷新列表
  Future<void> onTapGroup(FavoriteGroup group) async {
    await Get.toNamed('/question-train', arguments: {
      'pageType': 'favorite',
      'cate_name': group.cateName,
      'total': group.count,
      'items': group.items
          .map((e) => {
                'id': e.id,
                'question_id': e.questionId,
                'title': e.title ?? '',
                'kind': e.kind ?? '',
                'answer': e.answer ?? '',
                'options_json': e.optionsJson ?? '',
                'explain': e.explain ?? '',
                'difficulty': e.difficulty ?? '',
              })
          .toList(),
    });
    _loadFavorites();
  }
}

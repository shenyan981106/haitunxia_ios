import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../models/member_package_model.dart';
import '../providers/api_client.dart';
import '../../services/global_project_controller.dart';
import 'auth_service.dart';

/// 按科目 VIP 状态服务
///
/// 数据源:`addons/exam/user/memberPackages`(GET,传参 subject_id=二级科目 ID,
/// 即首页左上角所选项目 `GlobalProjectController.currentProject.id`,与会员中心同源)。
/// 返回单条会员配置 + specs 规格列表,规格 `subject_ids` 为逗号分隔的三级科目 ID 串
/// (题库顶部 tab 科目同源),`opened` 表示该规格是否已开通。
/// 题库模块据此判断"当前三级科目是否已开通 VIP",替代旧的全局 memberStatus。
class SubjectVipService extends GetxService {
  static SubjectVipService get to => Get.find();

  final GetStorage _storage = GetStorage();

  /// 存储键:三级科目 ID -> 是否已开通(Map)
  static const String _openedMapKey = 'subject_vip_opened';

  /// 内存缓存:三级科目 ID -> opened
  final Map<String, bool> _openedBySubject = {};

  /// 当前二级科目(全局当前项目)下任一规格是否已开通
  final RxBool currentProjectOpened = false.obs;

  /// 正在拉取的二级科目 ID(防并发重复请求)
  String? _loadingProjectId;

  @override
  void onInit() {
    super.onInit();
    _restoreCache();
    // 登录后刷新;登出清空
    ever(AuthService.to.isLoggedIn, (loggedIn) {
      if (loggedIn) {
        refreshCurrentProject();
      } else {
        clearCache();
      }
    });
    // 切换二级科目(首页左上角)时刷新
    ever(GlobalProjectController.to.currentProject, (_) {
      if (AuthService.to.isLoggedIn.value) {
        refreshCurrentProject();
      }
    });
    // 启动时已登录则立即刷新
    if (AuthService.to.isLoggedIn.value) {
      refreshCurrentProject();
    }
  }

  // ==================== 缓存 ====================

  void _restoreCache() {
    try {
      final stored = _storage.read<Map<String, dynamic>>(_openedMapKey);
      if (stored != null) {
        _openedBySubject
          ..clear()
          ..addAll(stored.map((key, value) => MapEntry(key, value == true)));
      }
    } catch (e) {
      debugPrint('SubjectVipService: 读取本地缓存失败: $e');
    }
  }

  void _saveCache() {
    _storage.write(_openedMapKey, _openedBySubject);
  }

  /// 清空缓存(登出时调用)
  void clearCache() {
    _openedBySubject.clear();
    currentProjectOpened.value = false;
    _storage.remove(_openedMapKey);
  }

  // ==================== 查询 ====================

  /// 指定三级科目是否已开通(同步读缓存;未知/失败一律视为未开通,失败即拦截)
  bool isSubjectOpened(String subjectId) {
    if (subjectId.isEmpty) return false;
    return _openedBySubject[subjectId] ?? false;
  }

  /// 确保拿到指定三级科目的开通状态;无缓存时拉取 memberPackages 后返回
  Future<bool> ensureSubjectOpened(String subjectId) async {
    if (subjectId.isEmpty) return false;
    if (_openedBySubject.containsKey(subjectId)) {
      return _openedBySubject[subjectId]!;
    }
    if (!AuthService.to.isLoggedIn.value) return false;
    await refreshCurrentProject();
    return _openedBySubject[subjectId] ?? false;
  }

  /// 刷新当前二级科目的规格开通状态(登录后/切换项目/支付成功后调用)
  Future<void> refreshCurrentProject() async {
    if (!AuthService.to.isLoggedIn.value) return;
    final projectId =
        GlobalProjectController.to.currentProject.value?.id ?? '5';
    if (_loadingProjectId == projectId) return;
    _loadingProjectId = projectId;
    try {
      final specs = await _fetchSpecs(projectId);
      // 项目已切换,丢弃过期结果
      final currentId =
          GlobalProjectController.to.currentProject.value?.id ?? '5';
      if (projectId != currentId) return;

      // 重建整表:仅 opened 规格覆盖的三级科目置 true,过期科目自动回落 false
      final opened = <String, bool>{};
      var anyOpened = false;
      for (final spec in specs) {
        if (spec.opened) anyOpened = true;
        for (final id in _specSubjectIds(spec)) {
          opened[id] = (opened[id] ?? false) || spec.opened;
        }
      }
      _openedBySubject
        ..clear()
        ..addAll(opened);
      currentProjectOpened.value = anyOpened;
      _saveCache();
    } catch (e) {
      // 后台预取,失败静默;保留旧缓存,判断按"未开通"处理
      debugPrint('SubjectVipService: 获取会员套餐失败: $e');
    } finally {
      _loadingProjectId = null;
    }
  }

  /// 拉取会员配置并展开全部规格(解析与会员中心一致)
  Future<List<MemberSpec>> _fetchSpecs(String projectId) async {
    final response = await ApiClient.to.exam(
      'user/memberPackages',
      queryParameters: {'subject_id': projectId},
    );
    final body = response.data;
    dynamic rawList;

    if (body is Map && body['data'] is Map) {
      // 新结构:data 为单条会员配置对象
      if (body['data']['list'] is List) {
        rawList = body['data']['list'];
      } else {
        rawList = [body['data']];
      }
    } else if (body is Map && body['data'] is List) {
      rawList = body['data'];
    } else if (body is List) {
      rawList = body;
    }

    if (rawList is List) {
      final specs = <MemberSpec>[];
      for (final pkg in rawList.whereType<Map>()) {
        specs.addAll(
            MemberPackage.fromJson(Map<String, dynamic>.from(pkg)).specs);
      }
      return specs;
    }
    return const [];
  }

  /// 规格覆盖的三级科目 ID 列表(subject_ids 逗号串 + subjectId,去重)
  List<String> _specSubjectIds(MemberSpec spec) {
    final ids = <String>[];
    if (spec.subjectIds.isNotEmpty) {
      ids.addAll(
          spec.subjectIds.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
    }
    if (spec.subjectId > 0) {
      final sid = spec.subjectId.toString();
      if (!ids.contains(sid)) ids.add(sid);
    }
    return ids;
  }
}

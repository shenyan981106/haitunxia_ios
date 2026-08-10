// home_controller.dart
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../routes/app_pages.dart';
import '../../../services/global_project_controller.dart';
import '../../../services/snackbar_utils.dart';
import '../../../data/models/api_response.dart';
import '../../../data/models/home_model.dart';
import '../../../data/models/version_model.dart';
import '../../../data/providers/api_client.dart';
import '../../../data/repositories/exam_repository.dart';

class HomeController extends GetxController {
  // 当前项目标题
  final RxString currentProjectName = ''.obs;

  // 当前选中的tab索引 默认选中精选推
  final RxInt currentTabIndex = 0.obs;

  // 版本更新检测
  String _currentVersion = '1.0.0';
  bool _versionChecked = false;
  final Rx<VersionModel?> pendingUpdate = Rx<VersionModel?>(null);

  /// 当前平台 (android/ios/ohos)
  String get currentPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.operatingSystem == 'ohos') return 'ohos';
    return 'unknown';
  }

  /// 根据当前平台获取对应的更新地址
  ///
  /// 鸿蒙平台会自动把 AppGallery https 分享链接（形如
  /// https://appgallery.huawei.com/app/C123456789）转换为
  /// store://appgallery.huawei.com/app/detail?id=C123456789，
  /// 以触发 url_launcher_harmonyos 的 launchAppGallery 分支，
  /// 直接拉起系统应用市场详情页，而不是通过浏览器中转。
  String? getUpdateUrl(VersionModel model) {
    switch (currentPlatform) {
      case 'ios':
        return model.iosUrl;
      case 'ohos':
        return _normalizeOhosUrl(model.ohosUrl);
      case 'android':
      default:
        return model.downloadUrl;
    }
  }

  /// 将 AppGallery https 分享链接转换为鸿蒙可识别的 store:// scheme
  ///
  /// 支持的输入示例（含外层反引号、空格等脏数据，downloadUpdate 内会清理）：
  /// - https://appgallery.huawei.com/app/C6917612042245117293
  /// - https://appgallery.cloud.huawei.com/ag/n/app/C6917612042245117293
  /// - https://appgallery.huawei.com/app/detail?id=C6917612042245117293
  /// - store://appgallery.huawei.com/app/detail?id=C6917612042245117293 （已正确格式，原样返回）
  String? _normalizeOhosUrl(String? rawUrl) {
    if (rawUrl == null) return null;
    // 先剥掉外层可能的反引号、引号和空白，便于后续正则匹配
    String url = rawUrl.trim();
    if (url.startsWith('`') && url.endsWith('`')) {
      url = url.substring(1, url.length - 1).trim();
    }
    if (url.startsWith("'") && url.endsWith("'")) {
      url = url.substring(1, url.length - 1).trim();
    }
    if (url.startsWith('"') && url.endsWith('"')) {
      url = url.substring(1, url.length - 1).trim();
    }
    if (url.isEmpty) return null;

    // 已经是 store:// 格式，直接返回
    if (url.startsWith('store:')) return url;

    // 尝试从 https 链接中提取 appId
    // /app/Cxxxxx  或  /app/detail?id=Cxxxxx  或  /ag/n/app/Cxxxxx
    final appGalleryMatch = RegExp(
      r'^https?://appgallery(?:\.cloud)?\.huawei\.com(?:/ag/n)?/app/(?:detail\?id=)?([A-Za-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(url);

    if (appGalleryMatch != null) {
      final appId = appGalleryMatch.group(1)!;
      return 'store://appgallery.huawei.com/app/detail?id=$appId';
    }

    // 不是 AppGallery 链接（例如普通 APK/企业分发地址），保持原样
    return url;
  }

  /// 当前平台是否可以执行更新操作
  bool canUpdate(VersionModel model) {
    final url = getUpdateUrl(model);
    return url != null && url.isNotEmpty;
  }

  /// 当前平台更新按钮文案
  String updateButtonText(VersionModel model) {
    if (!canUpdate(model)) {
      switch (currentPlatform) {
        case 'ios':
          return 'iOS版审核中';
        case 'ohos':
          return '鸿蒙版审核中';
        default:
          return '敬请期待';
      }
    }
    return '立即更新';
  }

  // ever 监听器引用，用于在 onClose 中释放
  Worker? _projectChangeWorker;

  // 切换科目
  void switchSubject() {
    Get.toNamed(Routes.PROJECT);
  }

  // 状态行点击事件
  void onStatusItemTap(String title) {
    switch (title) {
      case '模拟考试':
        Get.toNamed(Routes.QUESTIONS_EXAM);
        break;
      case '历年试卷':
        Get.toNamed(Routes.QUESTIONS_LIST);
        break;
      case '免费资料':
        Get.toNamed(Routes.STUDY);
        break;
      case '每日一练':
        final subjectId =
            GlobalProjectController.to.currentProject.value?.id ?? '5';
        Get.toNamed(
          '/question-train',
          preventDuplicates: false,
          arguments: {
            'subject': '每日一练',
            'subject_id': subjectId,
            'mode': 'prac',
            '_ts': DateTime.now().millisecondsSinceEpoch,
          },
        );
        break;
      case '企业合作':
        Get.toNamed(Routes.ENTERPRISE_AGREEMENT);
        break;
      case '我的课程':
        Get.toNamed(Routes.MY_COURSES);
        break;
      default:
        SnackbarUtils.showInfo('功能开发中: $title');
        break;
    }
  }

  // 课程点击事件
  void onCourseTap(Map<String, dynamic> course) {
    Get.toNamed(Routes.STUDY, arguments: course);
  }

  // 广告横幅点击事件
  Future<void> onBannerTap(String url) async {
    if (url.isEmpty) {
      SnackbarUtils.showInfo('该广告没有链接');
      return;
    }

    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        SnackbarUtils.showInfo('无法打开链接');
      }
    } catch (e) {
      SnackbarUtils.showInfo('链接格式错误');
    }
  }

  // 切换tab
  void switchTab(int index) {
    currentTabIndex.value = index;
  }

  // 跳转到搜索页
  void goToSearch() {
    Get.toNamed(Routes.SEARCH);
  }

  // Repository 实例
  final ExamRepository _examRepository = ExamRepository.to;

  // 加载状态
  final RxBool isLoading = false.obs;

  // 公共接口返回的数据
  Rx<ApiResponse<HomeData>?> homeApiResponse = Rx<ApiResponse<HomeData>?>(null);

  @override
  void onInit() {
    super.onInit();
    // 初始化当前项目名称
    currentProjectName.value = GlobalProjectController.to.currentProjectName;

    // 加载首页公共接口数据
    loadHomeData();

    // 监听全局项目变化，保存 Worker 引用以便释放
    _projectChangeWorker =
        ever(GlobalProjectController.to.currentProject, (project) {
      currentProjectName.value = GlobalProjectController.to.currentProjectName;
      loadHomeData();
    });
  }

  @override
  void onClose() {
    _projectChangeWorker?.dispose();
    super.onClose();
  }

  /// 检测版本更新
  Future<void> checkVersion() async {
    if (_versionChecked) return;
    _versionChecked = true;

    try {
      // 自动读取版本号
      // 注意: package_info_plus 在鸿蒙(ohos)平台无原生实现，PackageInfo.fromPlatform()
      // 会抛出 MissingPluginException，需降级从打包的 pubspec.yaml 中读取版本号
      try {
        final info = await PackageInfo.fromPlatform();
        _currentVersion = info.version;
      } catch (e) {
        debugPrint('PackageInfo.fromPlatform 失败，降级读取 pubspec.yaml: $e');
        _currentVersion = await _readVersionFromPubspec();
      }
      debugPrint('当前版本: $_currentVersion (平台: $currentPlatform)');

      final response = await ApiClient.to.initApp(
        version: _currentVersion,
      );

      debugPrint('版本检测响应: ${response.data}');

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        debugPrint('版本检测 data: $data');

        final rawData = data['data'];
        if (rawData is Map<String, dynamic>) {
          final versionData = rawData['versiondata'];
          debugPrint('版本检测 versionData: $versionData');

          VersionModel versionModel;
          if (versionData is Map<String, dynamic>) {
            versionModel = VersionModel.fromJson(versionData);
            debugPrint(
                'needUpdate: ${versionModel.needUpdate}, newVersion: ${versionModel.newVersion}');
          } else {
            versionModel = VersionModel.fromJson(null);
          }

          final hasNewerVersion = _isRemoteVersionNewer(
            versionModel.newVersion,
            _currentVersion,
          );
          debugPrint(
              '版本比较 currentVersion: $_currentVersion, newVersion: ${versionModel.newVersion}, hasNewerVersion: $hasNewerVersion');

          if (versionModel.needUpdate && hasNewerVersion) {
            pendingUpdate.value = versionModel;
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint('版本检测失败: $e');
      debugPrint('堆栈: $stackTrace');
    }
  }

  /// 从打包的 pubspec.yaml 中读取版本号（鸿蒙降级方案）
  ///
  /// package_info_plus 无 ohos 原生实现，在鸿蒙设备上调用
  /// PackageInfo.fromPlatform() 会抛出 MissingPluginException。
  /// 此方法通过 rootBundle 读取随应用打包的 pubspec.yaml，
  /// 解析其中的 version 字段作为降级版本号。
  Future<String> _readVersionFromPubspec() async {
    try {
      final pubspecContent = await rootBundle.loadString('pubspec.yaml');
      // 匹配非注释行的 "version: x.y.z"，忽略 "# version: ..." 注释行
      final match = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(pubspecContent);
      if (match != null) {
        // 去除行内注释，如 "1.0.1 #android 版本号" -> "1.0.1"
        final rawVersion = match.group(1)!;
        return rawVersion.split('#').first.trim();
      }
    } catch (e) {
      debugPrint('读取 pubspec.yaml 版本号失败: $e');
    }
    return '1.0.0';
  }

  bool _isRemoteVersionNewer(String? remoteVersion, String currentVersion) {
    final remoteParts = _parseVersionParts(remoteVersion);
    final currentParts = _parseVersionParts(currentVersion);

    if (remoteParts == null || currentParts == null) {
      return false;
    }

    final maxLength = remoteParts.length > currentParts.length
        ? remoteParts.length
        : currentParts.length;
    for (var i = 0; i < maxLength; i++) {
      final remotePart = i < remoteParts.length ? remoteParts[i] : 0;
      final currentPart = i < currentParts.length ? currentParts[i] : 0;

      if (remotePart > currentPart) return true;
      if (remotePart < currentPart) return false;
    }

    return false;
  }

  List<int>? _parseVersionParts(String? version) {
    final value = version?.trim();
    if (value == null || value.isEmpty) return null;

    final coreVersion = value
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split(RegExp(r'[-+]'))
        .first
        .trim();
    if (coreVersion.isEmpty) return null;

    final parts = <int>[];
    for (final part in coreVersion.split('.')) {
      final number = int.tryParse(part);
      if (number == null) return null;
      parts.add(number);
    }

    return parts;
  }

  /// 获取企业合作配置并打开 H5 页面
  Future<void> fetchCompanyConfigAndOpenH5() async {
    try {
      final response = await ApiClient.to.exam(
        'common/getConfig',
        queryParameters: {'id': 1},
      );
      final data = response.data as Map<String, dynamic>?;
      if (data != null && data['code'] == 1) {
        final config = data['data'] is Map
            ? Map<String, dynamic>.from(data['data'] as Map)
            : <String, dynamic>{};
        final value = config['company_report_config'];
        final url = value is String ? value.trim() : '';
        if (url.isNotEmpty) {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            Get.snackbar('提示', '无法打开链接');
          }
        } else {
          Get.snackbar('提示', '未获取到链接地址');
        }
      } else {
        Get.snackbar('提示', data?['msg'] ?? '获取企业合作配置失败');
      }
    } catch (e) {
      Get.snackbar('提示', '获取企业合作配置失败');
    }
  }

  /// 跳转下载页面
  Future<void> downloadUpdate(String? url) async {
    debugPrint('downloadUpdate called with url: $url');
    if (url == null || url.isEmpty) {
      Get.back();
      Get.snackbar('提示', '下载地址不存在');
      return;
    }
    String cleanUrl = url.trim();
    if (cleanUrl.startsWith('`') && cleanUrl.endsWith('`')) {
      cleanUrl = cleanUrl.substring(1, cleanUrl.length - 1).trim();
    }
    if (cleanUrl.startsWith("'") && cleanUrl.endsWith("'")) {
      cleanUrl = cleanUrl.substring(1, cleanUrl.length - 1).trim();
    }
    if (cleanUrl.startsWith('"') && cleanUrl.endsWith('"')) {
      cleanUrl = cleanUrl.substring(1, cleanUrl.length - 1).trim();
    }
    if (cleanUrl.isEmpty) {
      Get.back();
      Get.snackbar('提示', '下载地址不存在');
      return;
    }
    debugPrint('downloadUpdate cleaned url: $cleanUrl');
    Get.back();
    final uri = Uri.parse(cleanUrl);
    debugPrint('downloadUpdate launching uri: $uri');
    // 优先使用 externalApplication：鸿蒙上 platformDefault + https 会走
    // openUrlInWebView 路径（需要 harmony_browser_page 配置），导致失败
    bool success = await launchUrl(uri, mode: LaunchMode.externalApplication);
    debugPrint('launchUrl externalApplication result: $success');
    if (!success) {
      success = await launchUrl(uri, mode: LaunchMode.platformDefault);
      debugPrint('launchUrl platformDefault fallback result: $success');
    }
    if (!success) {
      Get.snackbar('提示', '无法打开下载链接');
    }
  }

  // 加载首页公共接口数据
  Future<void> loadHomeData() async {
    isLoading.value = true;

    try {
      // 使用 Repository 获取首页数据
      final response = await _examRepository.getHomeData(
        subjectId: GlobalProjectController.to.currentProject.value?.id ?? '5',
      );
      homeApiResponse.value = response;
    } catch (e) {
      // 错误已在 Repository 中处理
    } finally {
      isLoading.value = false;
    }
  }
}

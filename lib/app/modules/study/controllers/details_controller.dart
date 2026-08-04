import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart' as dio;
import '../services/study_video_adapter.dart';
import '../../../data/providers/api_client.dart';
import '../../../data/services/auth_service.dart';
import '../../../services/snackbar_utils.dart';
import '../../../routes/app_pages.dart';

class DetailsController extends GetxController {
  final currentTabIndex = 0.obs;

  final RxMap<String, dynamic> courseDetail = <String, dynamic>{}.obs;

  final RxList<dynamic> courseItems = <dynamic>[].obs;

  final RxBool isLoading = false.obs;

  StudyVideoAdapter? videoAdapter;
  StreamSubscription<StudyVideoEvent>? _playerEventSubscription;

  final RxString currentVideoUrl = ''.obs;
  final RxString currentVideoTitle = ''.obs;
  final RxBool isVideoPlaying = false.obs;
  final RxInt currentPlayingLessonId = 0.obs;
  final RxBool isFullScreen = false.obs;

  int? _currentLessonId;
  DateTime? _playStartTime;
  bool _isHandlingCompletion = false;
  bool _isPlayerInitialized = false;
  bool _isVideoActuallyPlayed = false;
  bool _isLoadingVideo = false;
  Timer? _videoLoadingTimer;

  @override
  void onInit() {
    super.onInit();
    if (Get.arguments != null) {
      final dynamic args = Get.arguments;
      int? courseId;
      if (args is Map) {
        courseId = int.tryParse(args['id']?.toString() ?? '');
      } else if (args is int) {
        courseId = args;
      } else if (args is String) {
        courseId = int.tryParse(args);
      }

      if (courseId != null) {
        getCourseDetail(courseId);
      } else {
        SnackbarUtils.showError("无效的课程ID");
      }
    }
  }

  void initPlayer(BuildContext context) {
    if (_isPlayerInitialized && videoAdapter != null) {
      return;
    }

    if (videoAdapter != null) {
      _playerEventSubscription?.cancel();
      videoAdapter!.dispose();
    }

    videoAdapter = StudyVideoAdapter.create();
    videoAdapter!.init(context);

    _playerEventSubscription = videoAdapter!.events.listen((event) {
      if (event is EnterFullscreenEvent) {
        enterFullscreen();
      } else if (event is ExitFullscreenEvent) {
        exitFullscreen();
      } else if (event is StartEvent) {
        _isVideoActuallyPlayed = true;
        isVideoPlaying.value = true;
        _dismissVideoLoading();
      } else if (event is ProgressEvent) {
        _isVideoActuallyPlayed = true;
        _dismissVideoLoading();
      } else if (event is ErrorEvent) {
        _dismissVideoLoading();
        SnackbarUtils.showError(event.message);
        _isVideoActuallyPlayed = false;
      } else if (event is CompleteEvent) {
        if (_isHandlingCompletion) return;
        isVideoPlaying.value = false;
        if (_isVideoActuallyPlayed ||
            (videoAdapter?.currentPosition ?? 0) > 2) {
          _handleVideoCompleted();
        }
        _isVideoActuallyPlayed = false;
      }
    });

    _isPlayerInitialized = true;
  }

  /// 进入全屏：横屏 + 隐藏系统 UI。
  void enterFullscreen() {
    isFullScreen.value = true;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// 退出全屏：恢复竖屏与系统 UI。
  void exitFullscreen() {
    isFullScreen.value = false;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  /// 全屏切换（供播放器视图内的全屏按钮回调）。
  void toggleFullscreen() {
    if (isFullScreen.value) {
      exitFullscreen();
    } else {
      enterFullscreen();
    }
  }

  /// 返回平台对应的播放器视图（供 details_view 调用）。
  /// 内部会幂等地初始化播放器。
  Widget buildPlayerView(BuildContext context) {
    initPlayer(context);
    final adapter = videoAdapter;
    if (adapter == null) return const SizedBox.shrink();
    return adapter.buildView(
      context,
      fullscreen: isFullScreen.value,
      onToggleFullscreen: toggleFullscreen,
    );
  }

  Future<void> getCourseDetail(int id) async {
    isLoading.value = true;
    try {
      final response = await ApiClient.to.get(
        'addons/exam/coures/detail',
        queryParameters: {'id': id},
        options: dio.Options(
          headers: {
            'token': Get.isRegistered<AuthService>()
                ? AuthService.to.token.value ?? ''
                : '',
          },
        ),
      );

      if (response.data != null && response.data['code'] == 1) {
        final data = response.data['data'];
        if (data is Map<String, dynamic>) {
          courseDetail.value = data;

          if (data['items'] is List) {
            courseItems.value = data['items'];
          }

          print("Success: Course details loaded - ${courseDetail['title']}");
        }
      } else {
        SnackbarUtils.showError(response.data['msg'] ?? "获取详情失败");
      }
    } catch (e) {
      print("Error: Failed to load course details - $e");
      if (e is dio.DioException) {
        SnackbarUtils.showError("服务器错误 ${e.response?.statusCode}");
      } else {
        SnackbarUtils.showError("获取课程详情失败");
      }
    } finally {
      isLoading.value = false;
    }
  }

  void switchTab(int index) {
    currentTabIndex.value = index;
  }

  void playCourseItem(dynamic item) {
    // 视频加载中时忽略重复点击，避免大视频重复触发加载导致无法播放
    if (_isLoadingVideo) return;

    final bool isPay = courseDetail['is_pay']?.toString() == '1' ||
        courseDetail['is_pay'] == true;
    final bool isFree = courseDetail['is_free']?.toString() == '1';
    if (!isPay && !isFree && !AuthService.to.isMember) {
      SnackbarUtils.showError('请先购买或订阅课程');
      return;
    }

    final String? videoUrl =
        item['url']?.toString() ?? item['video_url']?.toString();
    final String title = item['title']?.toString() ?? '课程视频';
    final lessonId = int.tryParse(item['id']?.toString() ?? '');

    final progress = item['progress'];
    final lastPosition =
        int.tryParse(progress?['last_position']?.toString() ?? '0') ?? 0;
    final duration =
        int.tryParse(progress?['duration']?.toString() ?? '0') ?? 0;
    final initialPosition =
        duration > 0 && lastPosition >= duration - 3 ? 0 : lastPosition;

    if (videoAdapter != null) {
      _saveCurrentProgress();
    }

    _currentLessonId = lessonId;
    currentPlayingLessonId.value = lessonId ?? 0;
    _playStartTime = DateTime.now();

    if (videoUrl != null && videoUrl.isNotEmpty) {
      _showVideoLoading();
      playVideo(videoUrl, title, initialPosition);
    } else {
      SnackbarUtils.showInfo('该课程暂无视频 $title');
    }
  }

  void playVideo(String url, String title, [int initialPosition = 0]) {
    final adapter = videoAdapter;
    if (adapter == null) {
      _dismissVideoLoading();
      return;
    }

    _isVideoActuallyPlayed = false;
    currentVideoUrl.value = url;
    currentVideoTitle.value = title;
    isVideoPlaying.value = true;

    adapter.play(
      ApiClient.replaceUri(url),
      title,
      startPos: initialPosition.toDouble(),
    );
  }

  /// 显示视频加载弹窗，并启动超时兜底，避免大视频卡在加载态。
  /// 时长设为 18s，比 OhosVideoAdapter 的 15s initialize 超时略晚，
  /// 让适配器先发出带具体原因的 ErrorEvent，本定时器仅作最终兜底。
  void _showVideoLoading() {
    _isLoadingVideo = true;
    SnackbarUtils.showLoading(msg: '视频加载中..');
    _videoLoadingTimer?.cancel();
    _videoLoadingTimer = Timer(const Duration(seconds: 18), () {
      if (_isLoadingVideo) {
        _isLoadingVideo = false;
        SnackbarUtils.dismissLoading();
        SnackbarUtils.showError('视频加载超时，请稍后重试');
      }
    });
  }

  /// 关闭视频加载弹窗（已关闭则忽略，可安全多次调用）
  void _dismissVideoLoading() {
    if (!_isLoadingVideo) return;
    _isLoadingVideo = false;
    _videoLoadingTimer?.cancel();
    _videoLoadingTimer = null;
    SnackbarUtils.dismissLoading();
  }

  Future<void> _handleVideoCompleted() async {
    if (_isHandlingCompletion) return;

    _isHandlingCompletion = true;
    await _saveCurrentProgress();

    final nextItem = _getNextPlayableItem();
    if (nextItem != null) {
      playCourseItem(nextItem);
    } else {
      isVideoPlaying.value = false;
      SnackbarUtils.showInfo('已播放到最后一节');
    }

    _isHandlingCompletion = false;
  }

  dynamic _getNextPlayableItem() {
    final items = _flattenPlayableItems(courseItems);
    if (items.isEmpty) return null;

    final currentIndex = items.indexWhere((item) {
      final itemId = int.tryParse(item['id']?.toString() ?? '');
      final itemUrl = item['url']?.toString() ?? item['video_url']?.toString();
      final processedItemUrl =
          itemUrl != null ? ApiClient.replaceUri(itemUrl) : '';
      return (_currentLessonId != null && itemId == _currentLessonId) ||
          (currentVideoUrl.value.isNotEmpty &&
              processedItemUrl == currentVideoUrl.value);
    });

    if (currentIndex >= 0 && currentIndex < items.length - 1) {
      return items[currentIndex + 1];
    }
    return null;
  }

  List<dynamic> _flattenPlayableItems(List<dynamic> items) {
    final result = <dynamic>[];

    for (final item in items) {
      if (item is! Map) continue;

      final videoUrl = item['url']?.toString() ?? item['video_url']?.toString();
      if (videoUrl != null && videoUrl.isNotEmpty) {
        result.add(item);
      }

      final children = item['childlist'] ?? item['children'];
      if (children is List) {
        result.addAll(_flattenPlayableItems(children));
      }
    }

    return result;
  }

  Future<void> _saveCurrentProgress() async {
    if (_currentLessonId == null || videoAdapter == null) return;

    final courseId = courseDetail['id'];
    if (courseId == null) return;

    try {
      int position = videoAdapter!.currentPosition;
      int duration = videoAdapter!.duration;

      int watchDuration = 0;
      if (_playStartTime != null) {
        watchDuration = DateTime.now().difference(_playStartTime!).inSeconds;
      }

      await ApiClient.to.exam(
        'coures/saveProgress',
        method: 'POST',
        data: {
          'course_id': courseId.toString(),
          'lesson_id': _currentLessonId.toString(),
          'last_position': position,
          if (duration > 0) 'duration': duration,
          if (watchDuration > 0) 'watch_duration': watchDuration,
        },
      );

      print("Progress saved: lesson=$_currentLessonId, pos=$position");
    } catch (e) {
      print("Error: Failed to save progress - $e");
    }
  }

  void startLearning(dynamic item) {
    playCourseItem(item);
  }

  @override
  void onClose() {
    _videoLoadingTimer?.cancel();
    _videoLoadingTimer = null;
    if (_isLoadingVideo) {
      _isLoadingVideo = false;
      SnackbarUtils.dismissLoading();
    }
    _saveCurrentProgress();
    _playerEventSubscription?.cancel();
    videoAdapter?.dispose();
    // 页面退出时强制恢复竖屏与系统 UI，避免影响其他页面
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.onClose();
  }
}

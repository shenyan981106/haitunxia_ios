import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart' as dio;
import 'package:superplayer_widget/demo_superplayer_lib.dart';
import '../../../data/providers/api_client.dart';
import '../../../data/services/auth_service.dart';
import '../../../services/snackbar_utils.dart';
import '../../../routes/app_pages.dart';

class DetailsController extends GetxController {
  final currentTabIndex = 0.obs;

  final RxMap<String, dynamic> courseDetail = <String, dynamic>{}.obs;

  final RxList<dynamic> courseItems = <dynamic>[].obs;

  final RxBool isLoading = false.obs;

  SuperPlayerController? superPlayerController;
  StreamSubscription? _playerEventSubscription;

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
    if (_isPlayerInitialized && superPlayerController != null) {
      return;
    }

    if (superPlayerController != null) {
      superPlayerController!.releasePlayer();
      _playerEventSubscription?.cancel();
    }

    superPlayerController = SuperPlayerController(context);

    _playerEventSubscription =
        superPlayerController!.onSimplePlayerEventBroadcast.listen((event) {
      String evtName = event["event"];
      if (evtName == SuperPlayerViewEvent.onStartFullScreenPlay) {
        isFullScreen.value = true;
        // 切换到横屏并隐藏系统 UI，让播放器铺满整个物理屏幕
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else if (evtName == SuperPlayerViewEvent.onStopFullScreenPlay) {
        isFullScreen.value = false;
        // 恢复竖屏与系统 UI
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
      } else if (evtName == SuperPlayerViewEvent.onSuperPlayerDidStart) {
        _isVideoActuallyPlayed = true;
        isVideoPlaying.value = true;
      } else if (evtName == SuperPlayerViewEvent.onSuperPlayerProgress) {
        _isVideoActuallyPlayed = true;
      } else if (evtName == SuperPlayerViewEvent.onSuperPlayerError) {
        SnackbarUtils.showError('视频播放出错');
        _isVideoActuallyPlayed = false;
      } else if (evtName == SuperPlayerViewEvent.onSuperPlayerDidEnd) {
        if (_isHandlingCompletion) return;
        isVideoPlaying.value = false;
        if (_isVideoActuallyPlayed ||
            (superPlayerController?.currentDuration ?? 0) > 2) {
          _handleVideoCompleted();
        }
        _isVideoActuallyPlayed = false;
      }
    });

    _isPlayerInitialized = true;
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

    if (superPlayerController != null) {
      _saveCurrentProgress();
    }

    _currentLessonId = lessonId;
    currentPlayingLessonId.value = lessonId ?? 0;
    _playStartTime = DateTime.now();

    if (videoUrl != null && videoUrl.isNotEmpty) {
      playVideoWithSuperPlayer(videoUrl, title, initialPosition);
    } else {
      SnackbarUtils.showInfo('该课程暂无视频 $title');
    }
  }

  void playVideoWithSuperPlayer(String url, String title,
      [int initialPosition = 0]) {
    if (superPlayerController == null) return;

    _isVideoActuallyPlayed = false;
    currentVideoUrl.value = url;
    currentVideoTitle.value = title;
    isVideoPlaying.value = true;

    superPlayerController!.startPos = initialPosition.toDouble();

    SuperPlayerModel model = SuperPlayerModel();
    model.videoURL = ApiClient.replaceUri(url);
    model.title = title;
    model.coverUrl = '';
    model.playAction = SuperPlayerModel.PLAY_ACTION_AUTO_PLAY;
    model.isEnableDownload = false;

    superPlayerController!.playWithModelNeedLicence(model);
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
      return (_currentLessonId != null && itemId == _currentLessonId) ||
          (currentVideoUrl.value.isNotEmpty &&
              itemUrl == currentVideoUrl.value);
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
    if (_currentLessonId == null || superPlayerController == null) return;

    final courseId = courseDetail['id'];
    if (courseId == null) return;

    try {
      int position = (superPlayerController!.currentDuration).round();
      int duration = (superPlayerController!.videoDuration).round();

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
    _saveCurrentProgress();
    _playerEventSubscription?.cancel();
    superPlayerController?.releasePlayer();
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

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:super_player/super_player.dart';
import '../../../data/providers/api_client.dart';
import '../../../services/snackbar_utils.dart';

class StudyVideoPlayerController extends GetxController {
  TXVodPlayerController? txVodPlayerController;

  int? _viewId;

  final RxString currentVideoUrl = ''.obs;

  final RxString currentVideoTitle = ''.obs;

  final RxBool isVideoInitialized = false.obs;

  final RxBool isFullScreen = false.obs;

  @override
  void onInit() {
    super.onInit();
    if (Get.arguments != null) {
      final dynamic args = Get.arguments;
      String? videoUrl;
      String title = '课程视频';

      if (args is Map) {
        videoUrl = args['url']?.toString() ?? args['video_url']?.toString();
        title = args['title']?.toString() ?? '课程视频';
      } else if (args is String) {
        videoUrl = args;
      }

      if (videoUrl != null && videoUrl.isNotEmpty) {
        initVideoPlayer(videoUrl, title);
      } else {
        SnackbarUtils.showError('该课程暂无视频');
      }
    }
  }

  void setPlayerView(int viewId) {
    _viewId = viewId;
    txVodPlayerController?.setPlayerView(viewId);
  }

  Future<void> initVideoPlayer(String videoUrl, String title) async {
    currentVideoUrl.value = videoUrl;
    currentVideoTitle.value = title;
    isVideoInitialized.value = false;

    try {
      final String fullUrl = ApiClient.getFullImageUrl(videoUrl);

      txVodPlayerController = TXVodPlayerController();

      txVodPlayerController!.onPlayerEventBroadcast.listen((event) {
        int? eventCode = event[TXVodPlayEvent.EVT_PARAM1];
        if (eventCode == TXVodPlayEvent.PLAY_EVT_PLAY_BEGIN) {
          isVideoInitialized.value = true;
        } else if (eventCode == TXVodPlayEvent.PLAY_EVT_PLAY_END) {
          isVideoInitialized.value = false;
        } else if (eventCode == TXVodPlayEvent.PLAY_ERR_NET_DISCONNECT) {
          SnackbarUtils.showError('网络断开连接');
        } else if (eventCode == TXVodPlayEvent.PLAY_EVT_ERROR_INVALID_LICENSE) {
          SnackbarUtils.showError('播放器 License 无效');
        }
      });

      if (_viewId != null) {
        txVodPlayerController!.setPlayerView(_viewId!);
      }

      await txVodPlayerController!.startVodPlay(fullUrl);

      isVideoInitialized.value = true;
    } catch (e) {
      print("Error: Failed to initialize video player - $e");
      SnackbarUtils.showError("视频加载失败");
    }
  }

  Future<void> switchVideo(String videoUrl, String title) async {
    disposeVideoPlayer();
    await initVideoPlayer(videoUrl, title);
  }

  void disposeVideoPlayer() {
    txVodPlayerController?.pause();
    txVodPlayerController?.dispose();
    txVodPlayerController = null;
    isVideoInitialized.value = false;
  }

  @override
  void onClose() {
    disposeVideoPlayer();
    super.onClose();
  }
}

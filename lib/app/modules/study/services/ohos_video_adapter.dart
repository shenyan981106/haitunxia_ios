import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../views/ohos_video_player_widget.dart';
import 'study_video_adapter.dart';

/// 鸿蒙端实现：包装社区 `video_player` 鸿蒙适配分支的 `VideoPlayerController`。
///
/// 鸿蒙端 `super_player` 无原生实现，改用基于 `@ohos.multimedia.media` AVPlayer
/// 的 `video_player` 插件。仅当 `Platform.operatingSystem == 'ohos'` 时由工厂创建。
class OhosVideoAdapter implements StudyVideoAdapter {
  VideoPlayerController? _vc;
  final StreamController<StudyVideoEvent> _events =
      StreamController<StudyVideoEvent>.broadcast();
  bool _completionFired = false;
  bool _errorFired = false;

  /// 供视图监听 controller 实例变化（play 时会创建新实例）。
  final ValueNotifier<VideoPlayerController?> _controllerNotifier =
      ValueNotifier<VideoPlayerController?>(null);

  /// 供视图读取以构造 [VideoPlayer] widget。
  VideoPlayerController? get controller => _vc;

  /// 视图通过它响应 controller 实例切换。
  ValueListenable<VideoPlayerController?> get controllerListenable =>
      _controllerNotifier;

  @override
  Future<void> init(BuildContext context) async {
    // 鸿蒙端在 play() 时按需创建 controller，无需前置初始化。
  }

  @override
  Future<void> play(String fullUrl, String title, {double startPos = 0}) async {
    debugPrint('[OhosVideoAdapter] play url=$fullUrl startPos=$startPos');
    try {
      final old = _vc;
      if (old != null) {
        old.removeListener(_onVcChanged);
        // 先置空通知视图解除对旧 controller 的监听，再 dispose 旧 controller，
        // 避免视图持有已 dispose 的 controller。
        _controllerNotifier.value = null;
        _vc = null;
        await old.dispose();
      }
      _completionFired = false;
      _errorFired = false;
      _vc = VideoPlayerController.networkUrl(Uri.parse(fullUrl));
      _controllerNotifier.value = _vc;
      // 在 initialize 之前挂监听，确保初始化期间的错误也能被捕获。
      _vc!.addListener(_onVcChanged);

      // initialize 加超时兜底：video_player_ohos 的原生 create() 在某些情况下
      // 不会回复（Promise rejection 被消息处理器吞掉），避免上层永久卡死。
      await _vc!.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('视频初始化超时（15s）');
        },
      );
      if (startPos > 0) {
        await _vc!.seekTo(Duration(milliseconds: (startPos * 1000).round()));
      }
      await _vc!.play();
      _events.add(StartEvent());
      _events.add(ProgressEvent());
    } catch (e, st) {
      debugPrint('[OhosVideoAdapter] play failed: $e');
      debugPrint('[OhosVideoAdapter] stack: $st');
      if (!_errorFired) {
        _errorFired = true;
        _events.add(ErrorEvent(_formatError(e)));
      }
    }
  }

  /// 把底层异常转换为对用户友好的错误文案，同时保留诊断信息。
  String _formatError(Object e) {
    if (e is TimeoutException) {
      return '视频加载超时，请检查网络后重试';
    }
    if (e is PlatformException) {
      final msg = e.message ?? e.code;
      debugPrint('[OhosVideoAdapter] PlatformException code=${e.code} '
          'message=${e.message} details=${e.details}');
      return '视频加载失败: $msg';
    }
    return '视频加载失败: $e';
  }

  void _onVcChanged() {
    final v = _vc?.value;
    if (v == null) return;
    if (v.errorDescription != null) {
      debugPrint('[OhosVideoAdapter] controller error: ${v.errorDescription}');
      if (!_errorFired) {
        _errorFired = true;
        _events.add(ErrorEvent('视频播放出错: ${v.errorDescription}'));
      }
      return;
    }
    if (v.isCompleted && !_completionFired) {
      _completionFired = true;
      _events.add(CompleteEvent());
    } else if (!v.isCompleted) {
      _completionFired = false;
    }
    if (v.isInitialized && v.duration.inMilliseconds > 0) {
      _events.add(ProgressEvent());
    }
  }

  @override
  int get currentPosition => _vc?.value.position.inSeconds ?? 0;

  @override
  int get duration => _vc?.value.duration.inSeconds ?? 0;

  @override
  Widget buildView(
    BuildContext context, {
    required bool fullscreen,
    required VoidCallback onToggleFullscreen,
  }) {
    return OhosVideoPlayerWidget(
      adapter: this,
      fullscreen: fullscreen,
      onToggleFullscreen: onToggleFullscreen,
    );
  }

  @override
  Stream<StudyVideoEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    _vc?.removeListener(_onVcChanged);
    await _vc?.dispose();
    _controllerNotifier.value = null;
    _controllerNotifier.dispose();
    await _events.close();
  }
}

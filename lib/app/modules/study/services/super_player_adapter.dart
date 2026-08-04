import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:superplayer_widget/demo_superplayer_lib.dart';

import 'study_video_adapter.dart';

/// Android / iOS 端实现：包装腾讯 `SuperPlayerController` + `SuperPlayerView`。
///
/// 这是对原 DetailsController 中 SuperPlayer 逻辑的等价搬迁，行为保持不变：
/// 全屏事件由 SuperPlayerView 自带全屏按钮触发，经事件流上抛给控制器。
class SuperPlayerAdapter implements StudyVideoAdapter {
  SuperPlayerController? _controller;
  StreamSubscription<dynamic>? _sub;
  final StreamController<StudyVideoEvent> _events =
      StreamController<StudyVideoEvent>.broadcast();
  final GlobalKey _playerViewKey = GlobalKey();
  bool _inited = false;

  @override
  Future<void> init(BuildContext context) async {
    if (_inited && _controller != null) return;
    // 先用 context 创建新 controller，避免跨 async gap 使用 BuildContext。
    final newController = SuperPlayerController(context);
    if (_controller != null) {
      _controller!.releasePlayer();
      await _sub?.cancel();
    }
    _controller = newController;
    _sub = _controller!.onSimplePlayerEventBroadcast.listen((event) {
      final String evtName = event['event'];
      if (evtName == SuperPlayerViewEvent.onStartFullScreenPlay) {
        _events.add(EnterFullscreenEvent());
      } else if (evtName == SuperPlayerViewEvent.onStopFullScreenPlay) {
        _events.add(ExitFullscreenEvent());
      } else if (evtName == SuperPlayerViewEvent.onSuperPlayerDidStart) {
        _events.add(StartEvent());
      } else if (evtName == SuperPlayerViewEvent.onSuperPlayerProgress) {
        _events.add(ProgressEvent());
      } else if (evtName == SuperPlayerViewEvent.onSuperPlayerError) {
        _events.add(ErrorEvent('视频播放出错'));
      } else if (evtName == SuperPlayerViewEvent.onSuperPlayerDidEnd) {
        _events.add(CompleteEvent());
      }
    });
    _inited = true;
  }

  @override
  Future<void> play(String fullUrl, String title, {double startPos = 0}) async {
    final c = _controller;
    if (c == null) return;
    c.startPos = startPos;
    final SuperPlayerModel model = SuperPlayerModel();
    model.videoURL = fullUrl;
    model.title = title;
    model.coverUrl = '';
    model.playAction = SuperPlayerModel.PLAY_ACTION_AUTO_PLAY;
    model.isEnableDownload = false;
    c.playWithModelNeedLicence(model);
  }

  @override
  int get currentPosition => ((_controller?.currentDuration ?? 0)).round();

  @override
  int get duration => ((_controller?.videoDuration ?? 0)).round();

  @override
  Widget buildView(
    BuildContext context, {
    required bool fullscreen,
    required VoidCallback onToggleFullscreen,
  }) {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();
    // 严格保持原 details_view 的两处构造：全屏带 FILL_VIEW，内联无 renderMode。
    if (fullscreen) {
      return SuperPlayerView(c,
          viewKey: _playerViewKey, renderMode: SuperPlayerRenderMode.FILL_VIEW);
    }
    return SuperPlayerView(c, viewKey: _playerViewKey);
  }

  @override
  Stream<StudyVideoEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _controller?.releasePlayer();
    await _events.close();
  }
}

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../services/screenAdapter.dart';
import '../services/ohos_video_adapter.dart';

/// 鸿蒙端课程视频播放器视图（最小可用控制条）。
///
/// `superplayer_widget` 的带控制条 UI 在鸿蒙不可用，这里基于 `video_player`
/// 的 `VideoPlayer` 自绘一套简易控制条：播放/暂停、进度拖拽、全屏切换、
/// 加载态、错误态。仅鸿蒙端使用。
class OhosVideoPlayerWidget extends StatefulWidget {
  final OhosVideoAdapter adapter;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;

  const OhosVideoPlayerWidget({
    super.key,
    required this.adapter,
    required this.fullscreen,
    required this.onToggleFullscreen,
  });

  @override
  State<OhosVideoPlayerWidget> createState() => _OhosVideoPlayerWidgetState();
}

class _OhosVideoPlayerWidgetState extends State<OhosVideoPlayerWidget> {
  VideoPlayerController? _vc;
  VoidCallback? _vcListener;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    widget.adapter.controllerListenable.addListener(_onControllerChanged);
    _attach(widget.adapter.controllerListenable.value);
  }

  void _onControllerChanged() {
    _detach();
    _attach(widget.adapter.controllerListenable.value);
    if (mounted) setState(() {});
  }

  void _attach(VideoPlayerController? vc) {
    _vc = vc;
    if (vc != null) {
      _vcListener = () {
        if (mounted) setState(() {});
      };
      vc.addListener(_vcListener!);
    }
  }

  void _detach() {
    if (_vc != null && _vcListener != null) {
      _vc!.removeListener(_vcListener!);
    }
    _vcListener = null;
  }

  @override
  void dispose() {
    _detach();
    widget.adapter.controllerListenable.removeListener(_onControllerChanged);
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final vc = _vc;
    // 先判错误：errorDescription 非空时 isInitialized 也为 false，
    // 必须在加载态之前返回，否则错误会被永久遮盖成"加载中"。
    if (vc != null && vc.value.errorDescription != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: ScreenAdapter.width(40)),
        child: Text('视频加载失败\n${vc.value.errorDescription}',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white70,
                fontSize: ScreenAdapter.fontSize(28))),
      );
    }
    if (vc == null || !vc.value.isInitialized) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: SizedBox(
          width: ScreenAdapter.width(60),
          height: ScreenAdapter.width(60),
          child: const CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
          ),
        ),
      );
    }
    final size = vc.value.size;
    final aspect =
        size.width > 0 && size.height > 0 ? size.width / size.height : 16 / 9;
    final double durMs = vc.value.duration.inMilliseconds.toDouble();
    final double posMs = vc.value.position.inMilliseconds.toDouble();
    final double max = durMs <= 0 ? 1.0 : durMs;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
              child: AspectRatio(aspectRatio: aspect, child: VideoPlayer(vc))),
          // 点击切换控制条显隐
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _controlsVisible = !_controlsVisible),
            child: Container(color: Colors.transparent),
          ),
          if (_controlsVisible) ...[
            // 中心播放/暂停
            Center(
              child: IconButton(
                icon: Icon(
                  vc.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white70,
                  size: ScreenAdapter.width(80),
                ),
                onPressed: () {
                  setState(() {
                    vc.value.isPlaying ? vc.pause() : vc.play();
                  });
                },
              ),
            ),
            // 顶部：返回（全屏时） + 全屏切换
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Row(
                  children: [
                    if (widget.fullscreen)
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: widget.onToggleFullscreen,
                      ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        widget.fullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        color: Colors.white,
                      ),
                      onPressed: widget.onToggleFullscreen,
                    ),
                  ],
                ),
              ),
            ),
            // 底部进度条
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Row(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: ScreenAdapter.width(16)),
                      child: Text(_fmt(vc.value.position),
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: ScreenAdapter.fontSize(22))),
                    ),
                    Expanded(
                      child: Slider(
                        value: posMs.clamp(0.0, max),
                        min: 0,
                        max: max,
                        onChanged: (v) {
                          vc.seekTo(Duration(milliseconds: v.round()));
                        },
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(right: ScreenAdapter.width(16)),
                      child: Text(_fmt(vc.value.duration),
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: ScreenAdapter.fontSize(22))),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

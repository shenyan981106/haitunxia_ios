import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'ohos_video_adapter.dart';
import 'super_player_adapter.dart';

/// 课程视频播放器统一抽象。
///
/// 背景：`super_player`（腾讯 LiteAVSDK）只有 android/ios 平台实现，鸿蒙端无原生
/// handler 导致视频无法播放。这里把 DetailsController 用到的播放能力抽象出来，
/// 由 [SuperPlayerAdapter]（android/ios）和 [OhosVideoAdapter]（鸿蒙）分别实现，
/// 让上层播放/进度/全屏/自动下一节逻辑对两套播放器复用。
abstract class StudyVideoAdapter {
  /// 初始化播放器（事件订阅等）。幂等，重复调用安全。
  Future<void> init(BuildContext context);

  /// 播放指定 URL（已替换为绝对地址），可带起始位置（秒）。
  Future<void> play(String fullUrl, String title, {double startPos = 0});

  /// 播放器事件流（开始/进度/完成/错误/全屏进出）。
  Stream<StudyVideoEvent> get events;

  /// 当前播放位置（秒）。
  int get currentPosition;

  /// 视频总时长（秒）。
  int get duration;

  /// 返回平台对应的播放器视图。
  /// [fullscreen] 当前是否全屏；[onToggleFullscreen] 由视图内的全屏按钮回调
  /// （SuperPlayerView 自带全屏按钮，可不使用此回调）。
  Widget buildView(
    BuildContext context, {
    required bool fullscreen,
    required VoidCallback onToggleFullscreen,
  });

  /// 释放资源。
  Future<void> dispose();

  /// 按当前平台创建适配器。
  /// 用 `Platform.operatingSystem == 'ohos'` 判断，标准 Flutter 与 ohos fork 均可编译。
  factory StudyVideoAdapter.create() {
    if (Platform.operatingSystem == 'ohos') {
      return OhosVideoAdapter();
    }
    return SuperPlayerAdapter();
  }
}

/// 播放器统一事件。
sealed class StudyVideoEvent {}

/// 开始播放。
class StartEvent extends StudyVideoEvent {}

/// 进度更新（视频正在播放）。
class ProgressEvent extends StudyVideoEvent {}

/// 播放完成。
class CompleteEvent extends StudyVideoEvent {}

/// 播放出错。
class ErrorEvent extends StudyVideoEvent {
  final String message;
  ErrorEvent(this.message);
}

/// 进入全屏。
class EnterFullscreenEvent extends StudyVideoEvent {}

/// 退出全屏。
class ExitFullscreenEvent extends StudyVideoEvent {}

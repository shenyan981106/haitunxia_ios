import 'package:flutter/foundation.dart';

/// 统一日志工具:业务调试日志一律走这里(替代裸 print/debugPrint)
/// - debug 构建:debugPrint 输出(带节流,长日志不丢帧)
/// - release 构建:完全静默,零输出零开销
/// 说明:main.dart 中另有全局兜底 —— release 下将 debugPrint 整体静默,
/// 此处再按 kDebugMode 判断一次,双保险且不依赖全局覆写。
class AppLog {
  static void d(Object? message) {
    if (kDebugMode) {
      debugPrint(message?.toString());
    }
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class SnackbarUtils {
  // loading 超时兜底计时器：防止 showLoading 因异常路径未关闭，
  // 导致遮罩永久残留、挡住全局点击（偶发“点了没反应”的根因）
  static Timer? _loadingTimeoutTimer;
  static const Duration _loadingTimeout = Duration(seconds: 30);

  // 成功提示
  static void showSuccess(String message) {
    dismissLoading();
    SmartDialog.showToast(
      message,
      displayType: SmartToastType.onlyRefresh,
      alignment: Alignment.center,
      maskColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xE6000000),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        );
      },
    );
  }

  // 错误提示
  static void showError(String message) {
    dismissLoading();
    SmartDialog.showToast(
      message,
      displayType: SmartToastType.onlyRefresh,
      alignment: Alignment.center,
      maskColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xE6FF4B4B),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        );
      },
    );
  }

  // 警告提示
  static void showWarning(String message) {
    SmartDialog.showToast(
      message,
      displayType: SmartToastType.onlyRefresh,
      alignment: Alignment.center,
      maskColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFE6A800),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        );
      },
    );
  }

  // 信息提示
  static void showInfo(String message) {
    // 先清除之前的提示，避免重复
    dismissLoading();
    SmartDialog.showToast(
      message,
      displayType: SmartToastType.onlyRefresh,
      alignment: Alignment.center,
      maskColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xE6000000),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        );
      },
    );
  }

  // 显示加载
  // 增加超时兜底：即使调用方因异常路径忘记 dismissLoading，
  // 也会在 [timeout] 后自动关闭，避免遮罩永久残留导致全局点击失效
  static void showLoading({String? msg, Duration? timeout}) {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = Timer(timeout ?? _loadingTimeout, () {
      _loadingTimeoutTimer = null;
      // 超时强制关闭 loading，防止永久卡死
      SmartDialog.dismiss(status: SmartStatus.loading);
    });
    SmartDialog.showLoading(
      msg: msg ?? '加载中..',
      maskColor: Colors.black.withValues(alpha: 0.3),
    );
  }

  // 关闭加载
  // 只关闭 loading，不影响 toast/custom，避免误关成功/失败提示
  static void dismissLoading() {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = null;
    SmartDialog.dismiss(status: SmartStatus.loading);
  }
}

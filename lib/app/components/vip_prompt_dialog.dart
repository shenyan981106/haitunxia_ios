import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

/// VIP 开通提示弹窗(★2026-08-26 新增,合并 questions_home/questions_list 两处同构弹窗)
///
/// 统一「提示」标题 +「该功能需要开通VIP会员才能使用」文案 + 单按钮;
/// onConfirm 默认仅关闭弹窗;需要跳转开通页时传回调
/// (如 questions_list 传 `Get.back(); Get.toNamed('/vip-center')`),
/// 按钮文案用 buttonText 定制(「我知道了」/「立即开通」)
class VipPromptDialog {
  static Future<void> show({
    String buttonText = '我知道了',
    VoidCallback? onConfirm,
  }) {
    return Get.dialog(
      AlertDialog(
        backgroundColor: Colors.white,
        titlePadding: EdgeInsets.only(top: 56.h),
        contentPadding: EdgeInsets.symmetric(horizontal: 48.w, vertical: 28.h),
        actionsPadding: EdgeInsets.only(bottom: 48.h, top: 36.h),
        title: Text(
          '提示',
          style: TextStyle(
            fontSize: 50.sp,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF333333),
          ),
          textAlign: TextAlign.center,
        ),
        content: Text(
          '该功能需要开通VIP会员才能使用',
          style: TextStyle(
            fontSize: 38.sp,
            color: const Color(0xFF666666),
          ),
          textAlign: TextAlign.center,
        ),
        actions: [
          Center(
            child: SizedBox(
              width: 360.w,
              height: 92.h,
              child: ElevatedButton(
                onPressed: onConfirm ?? () => Get.back(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1890FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                child: Text(
                  buttonText,
                  style: TextStyle(
                    fontSize: 32.sp,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
      ),
    );
  }
}

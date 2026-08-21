import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

/// 通用返回按钮
///
/// 统一全工程页面顶部返回按钮样式：
/// 图标 arrow_back_ios + 默认 48.sp，颜色默认 #333333（深色头部可传白色）。
/// 内置 padding 扩大点击热区，默认点击行为 Get.back()。
class CommonBackButton extends StatelessWidget {
  /// 点击回调（默认 Get.back()）
  final VoidCallback? onTap;

  /// 图标颜色（默认 #333333）
  final Color? color;

  /// 图标大小（默认 48.sp）
  final double? size;

  const CommonBackButton({
    super.key,
    this.onTap,
    this.color,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap ?? () => Get.back(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
        child: Icon(
          Icons.arrow_back_ios,
          size: size ?? 48.sp,
          color: color ?? const Color(0xFF333333),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 通用标签/角标组件
///
/// 圆角底色 + 文字的轻量标签,统一各页面「类型/状态/课程标签」等小标签样式。
/// 默认浅蓝底蓝字(课程标签风格),可自定义背景/文字颜色、圆角、字号、内边距。
class AppTag extends StatelessWidget {
  /// 标签文字
  final String text;

  /// 背景色(默认 #F0F7FF)
  final Color? bgColor;

  /// 文字颜色(默认 #3D7CFF)
  final Color? textColor;

  /// 圆角(默认 8)
  final double? radius;

  /// 字号(默认 26.sp)
  final double? fontSize;

  /// 字重(默认正常,订单「职场」标等大标签用 w500)
  final FontWeight? fontWeight;

  /// 内边距(默认 水平 12.w 垂直 6.h)
  final EdgeInsetsGeometry? padding;

  const AppTag(
    this.text, {
    super.key,
    this.bgColor,
    this.textColor,
    this.radius,
    this.fontSize,
    this.fontWeight,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          padding ?? EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: bgColor ?? const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(radius ?? 8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize ?? 26.sp,
          color: textColor ?? const Color(0xFF3D7CFF),
          fontWeight: fontWeight,
        ),
      ),
    );
  }
}

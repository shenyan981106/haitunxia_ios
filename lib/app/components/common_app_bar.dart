import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'common_back_button.dart';

/// 通用页面顶部导航栏(AppBar)
///
/// 统一全工程页面标题栏样式:白底、无阴影、标题居中、默认带返回按钮。
/// 内置 scrolledUnderElevation/surfaceTintColor 处理,避免各页面重复书写;
/// 无 actions 时自动补一个与左侧等宽的对称占位,保证标题绝对居中
/// (兼容题库列表页原 Stack/Row 手写头部的居中效果)。
class CommonAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// 标题文字(与 titleWidget 二选一)
  final String title;

  /// 自定义标题组件(需要响应式标题时传 Obx(() => Text(...)))
  final Widget? titleWidget;

  /// 标题样式(默认 44.sp w500 #333333,特殊页面再传入)
  final TextStyle? titleStyle;

  /// 左侧组件(默认 CommonBackButton)
  final Widget? leading;

  /// 右侧组件列表
  final List<Widget>? actions;

  /// AppBar bottom(如 questionsList 底部 Tab 栏)
  final PreferredSizeWidget? bottom;

  /// 工具栏高度(题库列表页原 110.h 大标题头部用)
  final double? toolbarHeight;

  /// 是否显示返回按钮(无返回键的页面传 false)
  final bool showBack;

  /// 背景色(默认白色)
  final Color backgroundColor;

  /// 标题是否居中(默认 true)
  final bool centerTitle;

  /// 阴影高度(默认 0;PDF 预览页等特殊页可传 0.5)
  final double? elevation;

  /// 标题与左侧组件间距(默认 AppBar 内置值;协议页左对齐标题传 0)
  final double? titleSpacing;

  /// 底部 1px 边框颜色(收藏/错题等原手写头部带 #EEEEEE 分割线时传入)
  final Color? bottomBorderColor;

  const CommonAppBar({
    super.key,
    this.title = '',
    this.titleWidget,
    this.titleStyle,
    this.leading,
    this.actions,
    this.bottom,
    this.toolbarHeight,
    this.showBack = true,
    this.backgroundColor = Colors.white,
    this.centerTitle = true,
    this.elevation,
    this.titleSpacing,
    this.bottomBorderColor,
  });

  @override
  Size get preferredSize => Size.fromHeight(
      (toolbarHeight ?? kToolbarHeight) + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final Widget effectiveLeading = showBack
        ? (leading ?? const CommonBackButton())
        : (leading ?? const SizedBox.shrink());
    // 无右侧组件时补一个与 leading 等宽的占位,保证标题绝对居中
    final List<Widget>? effectiveActions =
        actions ?? (centerTitle ? [SizedBox(width: kToolbarHeight)] : null);
    return AppBar(
      elevation: elevation ?? 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: backgroundColor,
      foregroundColor: const Color(0xFF333333),
      centerTitle: centerTitle,
      toolbarHeight: toolbarHeight,
      titleSpacing: titleSpacing,
      leadingWidth: kToolbarHeight,
      leading: effectiveLeading,
      actions: effectiveActions,
      bottom: bottom,
      shape: bottomBorderColor != null
          ? Border(bottom: BorderSide(color: bottomBorderColor!, width: 1))
          : null,
      title: titleWidget ??
          Text(
            title,
            style: titleStyle ??
                TextStyle(
                  fontSize: 44.sp,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF333333),
                ),
          ),
    );
  }
}

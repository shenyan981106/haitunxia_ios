import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 在 iPad 等大屏设备上将内容居中显示，两侧填充黑色背景
/// 通过 ScreenUtil.configure 手动注入约束尺寸，确保 .w/.h/.sp 基于手机比例计算
class CenterTheWidgets extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final Color backgroundColor;
  final double aspectRatio;

  const CenterTheWidgets({
    super.key,
    required this.child,
    this.maxWidth = 414,
    this.backgroundColor = Colors.black,
    this.aspectRatio = 1080 / 2400,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;

    final isLargeScreen = size.shortestSide >= 600;

    if (!isLargeScreen) {
      return child;
    }

    double contentWidth;
    double contentHeight;

    if (size.width > size.height) {
      contentHeight = size.height;
      contentWidth = contentHeight * aspectRatio;

      if (contentWidth > maxWidth) {
        contentWidth = maxWidth;
        contentHeight = contentWidth / aspectRatio;
      }
    } else {
      contentWidth = maxWidth;
      contentHeight = size.height;
    }

    final constrainedSize = Size(contentWidth, contentHeight);
    final constrainedData = mediaQuery.copyWith(
      size: constrainedSize,
      padding: EdgeInsets.zero,
      viewPadding: EdgeInsets.zero,
      viewInsets: EdgeInsets.zero,
    );

    ScreenUtil.configure(
      data: constrainedData,
      designSize: const Size(1080, 2400),
      splitScreenMode: true,
      minTextAdapt: true,
    );

    return Container(
      color: backgroundColor,
      child: Center(
        child: SizedBox(
          width: contentWidth,
          height: contentHeight,
          child: MediaQuery(
            data: constrainedData,
            child: ClipRect(
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

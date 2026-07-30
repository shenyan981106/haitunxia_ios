import 'package:flutter/material.dart';

/// 在 iPad 等大屏设备上将内容居中显示，两侧填充黑色背景
/// 保持手机端的宽高比（默认 9:20），等比例缩放内容
class CenterTheWidgets extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final Color backgroundColor;
  final double aspectRatio;

  const CenterTheWidgets({
    super.key,
    required this.child,
    this.maxWidth = 600,
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
      contentHeight = contentWidth / aspectRatio;

      if (contentHeight > size.height) {
        contentHeight = size.height;
        contentWidth = contentHeight * aspectRatio;
      }
    }

    final constrainedSize = Size(contentWidth, contentHeight);

    return Container(
      color: backgroundColor,
      child: Center(
        child: SizedBox(
          width: contentWidth,
          height: contentHeight,
          child: MediaQuery(
            data: mediaQuery.copyWith(
              size: constrainedSize,
            ),
            child: ClipRect(
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

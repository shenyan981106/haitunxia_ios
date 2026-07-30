import 'package:flutter/material.dart';

/// 在 iPad 等大屏设备上将内容居中显示，两侧填充黑色背景
class CenterTheWidgets extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final Color backgroundColor;

  const CenterTheWidgets({
    super.key,
    required this.child,
    this.maxWidth = 600,
    this.backgroundColor = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLargeScreen = mediaQuery.size.shortestSide >= maxWidth;

    if (!isLargeScreen) {
      return child;
    }

    final constrainedSize = Size(maxWidth, mediaQuery.size.height);

    return Container(
      color: backgroundColor,
      child: Center(
        child: SizedBox(
          width: maxWidth,
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

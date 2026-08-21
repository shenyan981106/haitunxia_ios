import 'package:flutter/material.dart';

import '../services/screenAdapter.dart';

/// 自定义胶囊滑动开关(iOS 风格,替代原生 Switch 的默认样式)
///
/// 用法:
/// ```dart
/// CustomSwitch(
///   value: controller.isDefault.value,
///   onChanged: (v) => controller.isDefault.value = v,
/// )
/// ```
class CustomSwitch extends StatelessWidget {
  /// 当前值
  final bool value;

  /// 切换回调
  final ValueChanged<bool> onChanged;

  /// 开启态轨道颜色(默认品牌蓝 #3D7CFF)
  final Color activeColor;

  /// 关闭态轨道颜色(默认 #E5E6EC)
  final Color inactiveColor;

  const CustomSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor = const Color(0xFF3D7CFF),
    this.inactiveColor = const Color(0xFFE5E6EC),
  });

  @override
  Widget build(BuildContext context) {
    const animation = Duration(milliseconds: 200);
    final trackWidth = ScreenAdapter.width(100);
    final trackHeight = ScreenAdapter.height(56);
    final thumbSize = ScreenAdapter.width(48);
    final padding = ScreenAdapter.width(4);

    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: animation,
        curve: Curves.easeOut,
        width: trackWidth,
        height: trackHeight,
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: value ? activeColor : inactiveColor,
          borderRadius: BorderRadius.circular(trackHeight / 2),
        ),
        child: AnimatedAlign(
          duration: animation,
          curve: Curves.easeOut,
          alignment:
              value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: thumbSize,
            height: thumbSize,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: ScreenAdapter.width(6),
                  offset: Offset(0, ScreenAdapter.height(2)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

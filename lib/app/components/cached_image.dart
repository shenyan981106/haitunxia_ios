import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 统一网络图片组件:磁盘缓存 + 加载/失败占位
///
/// 使用规则(见 docs/kb/09-components-utils.md):
/// - 列表/轮播/头像等网络图片一律用它,禁止 Image.network(无缓存,滚动往返重复下载)
/// - URL 预处理(如 ApiClient.replaceUri / getFullImageUrl)由调用方完成后再传入,
///   与 questions_exam_view 既有 CachedNetworkImage 用法保持一致
/// - 尺寸由调用方传入(各自适配体系换算后),组件内部不做适配
class CachedImage extends StatelessWidget {
  const CachedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// 非空时自动包一层 ClipRRect 圆角裁剪(封面图常用)
  final BorderRadius? borderRadius;

  /// 加载中占位,默认灰底 Container(与 questions_exam_view 既有用法一致)
  final Widget? placeholder;

  /// 加载失败占位,默认灰底 + broken_image 图标
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    final Widget image = CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) =>
          placeholder ?? _defaultPlaceholder(context),
      errorWidget: (context, url, error) =>
          errorWidget ?? _defaultError(context),
    );

    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }

  Widget _defaultPlaceholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
    );
  }

  Widget _defaultError(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Icon(Icons.broken_image, color: Colors.grey),
    );
  }
}

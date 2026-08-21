import 'package:flutter/foundation.dart';

/// 环境配置
class EnvConfig {
  /// API基础地址
  static const String baseUrl = 'https://appdev.haitunxia.com/';

  /// 静态资源CDN地址（图片、视频、附件等?
  static const String cdnUrl = 'https://cdn.haitunxia.com/';

  /// 是否启用日志
  /// ★2026-08-14 修复:改为 kDebugMode,release 构建不再输出任何网络日志
  /// (此前恒为 true,LogInterceptor 会把完整请求/响应 body 打进生产包)
  static const bool enableLog = kDebugMode;
}

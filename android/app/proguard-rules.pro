# Flutter核心
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# SuperPlayer/腾讯云播放器
-keep class com.tencent.** { *; }
-keep class com.superplayer.** { *; }
-keep class com.liteav.** { *; }
-dontwarn com.tencent.**

# 支付宝支付
-keep class com.alipay.** { *; }
-keep class tobias.** { *; }

# WebView
-keep class android.webkit.** { *; }

# 项目类
-keep class com.zgjan.haitunxia.** { *; }

# 注解
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions

# 禁用日志输出（Release模式）
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:super_player/super_player.dart';
import 'package:superplayer_widget/demo_superplayer_lib.dart';
import 'package:fluwx/fluwx.dart';

import 'app/config/env_config.dart';
import 'app/data/providers/api_client.dart';
import 'app/data/services/auth_service.dart';
import 'app/data/services/subject_vip_service.dart';
import 'app/data/services/iap_service.dart';
import 'app/data/repositories/repository_provider.dart';
import 'app/services/global_project_controller.dart';
import 'app/services/center_the_widgets.dart';
import 'app/routes/app_pages.dart';

/// 微信AppID，请替换为实际值
const String kWechatAppId = 'wxec2cc33383f6cc8e';

/// iOS Universal Link，替换为实际值
const String kWechatUniversalLink = 'https://app.haitunxia.com/';

void main() async {
  // 确保Flutter绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // ★2026-08-14 修复:release 构建全局静默 debugPrint(全项目 100+ 处 debugPrint
  // 直接输出到生产控制台,含登录时打印手机号等个人信息;此处统一兜底静默)
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // ==================== 微信SDK初始化 ====================
  final fluwx = Fluwx();
  await fluwx.registerApi(
    appId: kWechatAppId,
    doOnAndroid: true,
    doOnIOS: true,
    universalLink: kWechatUniversalLink,
  );

  // 设置状态栏样式
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // 初始化本地存储
  await GetStorage.init();

  // ==================== 注册核心服务 ====================

  // 1. 注册API客户端（被其他服务依赖）
  Get.put(ApiClient(), permanent: true);

  // 2. 注册认证服务（依赖API客户端）
  final authService = Get.put(AuthService(), permanent: true);
  // 等待安全存储登录态恢复完成（splash 页登录态判断依赖,避免未恢复时误判未登录）
  await authService.ready;

  // 3. 注册所有Repository（依赖API客户端）
  RepositoryProvider.init();

  // 4. 注册全局项目控制器（依赖Repository）
  Get.put(GlobalProjectController(), permanent: true);

  // 5. 注册按科目VIP状态服务（依赖AuthService + GlobalProjectController）
  Get.put(SubjectVipService(), permanent: true);

  // 6. 注册苹果IAP内购服务（★仅iOS生效，安卓/鸿蒙内部自动降级；
  //    onInit 内处理 StoreKit 注册、purchaseStream 订阅与启动补单）
  Get.put(IapService(), permanent: true);

  // ==================== 腾讯云播放器 License 初始化 ====================
  // 需要在腾讯云控制台申请 License
  // 参考文档：https://cloud.tencent.com/document/product/881/79169
  String licenceURL =
      "https://1258752030.trtcube-license.cn/license/v2/1258752030_1/v_cube.license";
  String licenceKey = "361963c5ee298b2b82a6d2b19bfddca3";
  SuperPlayerPlugin.setGlobalLicense(licenceURL, licenceKey);

  // ==================== 确定初始路由 ====================

  // 始终从启动页开始，由启动页判断是否显示协议弹窗和后续跳转
  final String initialRoute = AppPages.INITIAL;

  // ==================== 启动应用 ====================

  runApp(
    ScreenUtilInit(
      designSize: const Size(1080, 2400),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return GetMaterialApp(
          debugShowCheckedModeBanner: false,
          title: '海豚侠',
          initialRoute: initialRoute,
          getPages: AppPages.routes,
          builder: (context, child) {
            final smartDialogBuilder = FlutterSmartDialog.init();
            return smartDialogBuilder(
              context,
              CenterTheWidgets(child: child ?? const SizedBox.shrink()),
            );
          },
          enableLog: EnvConfig.enableLog,
          logWriterCallback: (text, {bool isError = false}) {
            debugPrint('[GetX] $text');
          },
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            SuperPlayerWidgetLocals.delegate,
          ],
          supportedLocales: [
            const Locale('zh', 'CN'),
            const Locale('en', 'US'),
          ],
        );
      },
    ),
  );
}

import 'package:get/get.dart';

import '../controllers/login_controller.dart';

class LoginBinding extends Bindings {
  @override
  void dependencies() {
    // fenix: true —— 控制器被释放后再次进入页面时自动重建，
    // 避免拿到旧实例（其 TextEditingController 可能已被 dispose）。
    Get.lazyPut<LoginController>(
      () => LoginController(),
      fenix: true,
    );
  }
}

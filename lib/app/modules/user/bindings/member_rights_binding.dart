import 'package:get/get.dart';

import '../controllers/member_rights_controller.dart';

class MemberRightsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MemberRightsController>(
      () => MemberRightsController(),
    );
  }
}

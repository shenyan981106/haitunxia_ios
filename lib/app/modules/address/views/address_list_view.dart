import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../components/app_tag.dart';
import '../../../components/common_app_bar.dart';
import '../../../components/common_dialog.dart';
import '../../../components/common_empty_state.dart';
import '../../../components/common_error_state.dart';
import '../../../data/models/address_model.dart';
import '../../../routes/app_pages.dart';
import '../../../services/screenAdapter.dart';
import '../controllers/address_list_controller.dart';

/// 收货地址列表(可新增/编辑/删除)
/// 选择模式:Get.toNamed 传 arguments: {'selectMode': true},
/// 隐藏编辑/删除,点击地址卡片 Get.back(result: AddressModel) 返回选中项
class AddressListView extends GetView<AddressListController> {
  const AddressListView({Key? key}) : super(key: key);

  /// 是否选择模式(下单页等场景选地址用)
  bool get _isSelectMode {
    final args = Get.arguments;
    return args is Map && args['selectMode'] == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: CommonAppBar(title: _isSelectMode ? '选择收货地址' : '收货地址'),
      body: Column(
        children: [
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }
              if (controller.errorMessage.value.isNotEmpty &&
                  controller.addresses.isEmpty) {
                return CommonErrorState(
                  message: controller.errorMessage.value,
                  onRetry: () => controller.loadAddresses(),
                );
              }
              if (controller.addresses.isEmpty) {
                return const CommonEmptyState(
                  icon: Icons.location_off_outlined,
                  title: '暂无收货地址',
                  subtitle: '点击下方按钮添加收货地址',
                );
              }
              return RefreshIndicator(
                onRefresh: () => controller.onRefresh(),
                color: const Color(0xFF1890FF),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: ScreenAdapter.width(30),
                    vertical: ScreenAdapter.height(20),
                  ),
                  itemCount: controller.addresses.length,
                  separatorBuilder: (_, __) =>
                      SizedBox(height: ScreenAdapter.height(20)),
                  itemBuilder: (context, index) =>
                      _buildAddressCard(controller.addresses[index]),
                ),
              );
            }),
          ),
          SafeArea(child: _buildAddButton()),
        ],
      ),
    );
  }

  /// 地址卡片
  Widget _buildAddressCard(AddressModel item) {
    return GestureDetector(
      // 选择模式:点击卡片直接返回选中项
      onTap: _isSelectMode ? () => Get.back(result: item) : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.all(ScreenAdapter.width(32)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ScreenAdapter.radius(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  item.consignee,
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(36),
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF333333),
                  ),
                ),
                SizedBox(width: ScreenAdapter.width(20)),
                Text(
                  item.phone,
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(32),
                    color: const Color(0xFF666666),
                  ),
                ),
                if (item.isDefaultAddress) ...[
                  SizedBox(width: ScreenAdapter.width(16)),
                  const AppTag('默认'),
                ],
              ],
            ),
            SizedBox(height: ScreenAdapter.height(16)),
            Text(
              item.fullAddress,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(30),
                color: const Color(0xFF666666),
                height: 1.5,
              ),
            ),
            // 非选择模式才显示编辑/删除操作
            if (!_isSelectMode) ...[
              SizedBox(height: ScreenAdapter.height(16)),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildAction('编辑', Icons.edit_outlined,
                      const Color(0xFF3D7CFF), () => _goEdit(item)),
                  SizedBox(width: ScreenAdapter.width(32)),
                  _buildAction('删除', Icons.delete_outline,
                      const Color(0xFFFF4D4F), () => _confirmDelete(item)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAction(
      String text, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ScreenAdapter.width(12),
          vertical: ScreenAdapter.height(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: ScreenAdapter.width(36), color: color),
            SizedBox(width: ScreenAdapter.width(8)),
            Text(
              text,
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(30),
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 编辑(返回后刷新列表)
  Future<void> _goEdit(AddressModel item) async {
    await Get.toNamed(Routes.ADDRESS_EDIT, arguments: item);
    controller.loadAddresses();
  }

  /// 删除确认弹窗
  Future<void> _confirmDelete(AddressModel item) async {
    final confirmed = await CommonDialog.show(
      title: '删除地址',
      content: '确定要删除该收货地址吗？',
      confirmText: '删除',
    );
    if (confirmed) {
      await controller.deleteAddress(item.id);
    }
  }

  /// 底部新增按钮
  Widget _buildAddButton() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ScreenAdapter.width(30),
        ScreenAdapter.height(16),
        ScreenAdapter.width(30),
        ScreenAdapter.height(24),
      ),
      child: SizedBox(
        width: double.infinity,
        height: ScreenAdapter.height(120),
        child: ElevatedButton(
          onPressed: () async {
            await Get.toNamed(Routes.ADDRESS_EDIT);
            controller.loadAddresses();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3D7CFF),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ScreenAdapter.radius(20)),
            ),
          ),
          child: Text(
            '新增收货地址',
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(40),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

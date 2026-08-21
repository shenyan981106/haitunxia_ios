import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../components/common_app_bar.dart';
import '../../../components/custom_switch.dart';
import '../../../services/screenAdapter.dart';
import '../controllers/address_edit_controller.dart';

/// 新增/编辑收货地址(新增与编辑共用一页,Controller 按 Get.arguments 区分)
class AddressEditView extends GetView<AddressEditController> {
  const AddressEditView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: CommonAppBar(
          title: controller.isEditMode ? '编辑收货地址' : '新增收货地址'),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: ScreenAdapter.width(30),
                vertical: ScreenAdapter.height(24),
              ),
              children: [
                _buildInfoCard(),
                SizedBox(height: ScreenAdapter.height(24)),
                _buildDefaultCard(),
              ],
            ),
          ),
          SafeArea(child: _buildSubmitButton()),
        ],
      ),
    );
  }

  /// 收货信息卡片
  Widget _buildInfoCard() {
    return Container(
      padding: EdgeInsets.all(ScreenAdapter.width(30)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ScreenAdapter.width(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 卡片标题
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: ScreenAdapter.fontSize(42),
                color: const Color(0xFF3D7CFF),
              ),
              SizedBox(width: ScreenAdapter.width(10)),
              Text(
                '收货信息',
                style: TextStyle(
                  fontSize: ScreenAdapter.fontSize(46),
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF333333),
                ),
              ),
            ],
          ),
          SizedBox(height: ScreenAdapter.height(30)),
          _buildInputRow(
            '收货人',
            TextField(
              controller: controller.consigneeController,
              maxLength: 50,
              decoration: _inputDecoration('请填写收货人姓名'),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(20)),
          _buildInputRow(
            '手机号',
            TextField(
              controller: controller.phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 20,
              decoration: _inputDecoration('请填写手机号'),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(20)),
          _buildInputRow('所在地区', _buildAreaRow()),
          SizedBox(height: ScreenAdapter.height(20)),
          _buildInputRow(
            '详细地址',
            TextField(
              controller: controller.detailController,
              maxLines: 3,
              maxLength: 200,
              decoration: _inputDecoration('请填写街道、门牌号等详细地址', multiline: true),
            ),
            alignTop: true,
          ),
        ],
      ),
    );
  }

  /// 输入行:左侧 label + 右侧填充式输入框(多行时 label 顶部对齐)
  Widget _buildInputRow(String label, Widget child, {bool alignTop = false}) {
    return Row(
      crossAxisAlignment:
          alignTop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: ScreenAdapter.width(160),
          child: Padding(
            padding: EdgeInsets.only(
              top: alignTop ? ScreenAdapter.height(22) : 0,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(32),
                fontWeight: FontWeight.w500,
                color: const Color(0xFF333333),
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  /// 省市区选择行(与输入框同款填充容器)
  Widget _buildAreaRow() {
    return GestureDetector(
      onTap: () => controller.pickArea(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ScreenAdapter.width(24),
          vertical: ScreenAdapter.height(22),
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(ScreenAdapter.width(16)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Obx(() {
                final names = [
                  controller.provinceName.value,
                  controller.cityName.value,
                  controller.districtName.value,
                ].where((e) => e.isNotEmpty).toList();
                final hasSelected = controller.provinceId.value > 0;
                return Text(
                  hasSelected ? names.join(' ') : '请选择省市区',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(32),
                    color: hasSelected
                        ? const Color(0xFF333333)
                        : const Color(0xFFB1B8CA),
                  ),
                );
              }),
            ),
            Icon(
              Icons.chevron_right,
              color: const Color(0xFFB1B8CA),
              size: ScreenAdapter.width(44),
            ),
          ],
        ),
      ),
    );
  }

  /// 设为默认地址卡片
  Widget _buildDefaultCard() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ScreenAdapter.width(30),
        vertical: ScreenAdapter.height(20),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ScreenAdapter.width(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '设为默认地址',
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(32),
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF333333),
                  ),
                ),
                SizedBox(height: ScreenAdapter.height(8)),
                Text(
                  '下单时默认使用该地址',
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(26),
                    color: const Color(0xFF999999),
                  ),
                ),
              ],
            ),
          ),
          Obx(() => CustomSwitch(
                value: controller.isDefault.value,
                onChanged: (v) => controller.isDefault.value = v,
              )),
        ],
      ),
    );
  }

  /// 底部保存按钮(提交中禁用并显示转圈)
  Widget _buildSubmitButton() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ScreenAdapter.width(30),
        ScreenAdapter.height(16),
        ScreenAdapter.width(30),
        ScreenAdapter.height(24),
      ),
      child: Obx(() => SizedBox(
            width: double.infinity,
            height: ScreenAdapter.height(130),
            child: ElevatedButton(
              onPressed:
                  controller.isSubmitting.value ? null : controller.submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3D7CFF),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFCCCCCC),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ScreenAdapter.radius(20)),
                ),
              ),
              child: controller.isSubmitting.value
                  ? SizedBox(
                      width: ScreenAdapter.width(44),
                      height: ScreenAdapter.width(44),
                      child: const CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      '保存',
                      style: TextStyle(
                        fontSize: ScreenAdapter.fontSize(44),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          )),
    );
  }

  /// 填充式输入框装饰(灰底圆角,聚焦描蓝边)
  InputDecoration _inputDecoration(String hint, {bool multiline = false}) {
    return InputDecoration(
      isDense: true,
      counterText: '',
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: ScreenAdapter.fontSize(30),
        color: const Color(0xFFB1B8CA),
      ),
      filled: true,
      fillColor: const Color(0xFFF8F9FA),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ScreenAdapter.width(16)),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ScreenAdapter.width(16)),
        borderSide: const BorderSide(color: Color(0xFF3D7CFF), width: 1),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: ScreenAdapter.width(24),
        vertical: multiline
            ? ScreenAdapter.height(20)
            : ScreenAdapter.height(22),
      ),
    );
  }
}

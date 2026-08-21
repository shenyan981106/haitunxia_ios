import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../components/area_picker.dart';
import '../../../data/models/address_model.dart';
import '../../../data/repositories/exam_repository.dart';
import '../../../services/snackbar_utils.dart';

/// 新增/编辑收货地址(Get.arguments 传 AddressModel = 编辑,不传 = 新增)
class AddressEditController extends GetxController {
  final ExamRepository _repository = ExamRepository.to;

  /// 编辑中的地址(null = 新增模式)
  AddressModel? _editAddress;

  /// 是否编辑模式
  bool get isEditMode => _editAddress != null;

  late final TextEditingController consigneeController;
  late final TextEditingController phoneController;
  late final TextEditingController detailController;

  final RxInt provinceId = 0.obs;
  final RxString provinceName = ''.obs;
  final RxInt cityId = 0.obs;
  final RxString cityName = ''.obs;
  final RxInt districtId = 0.obs; // 0 = 未选择(区县可空)
  final RxString districtName = ''.obs;

  final RxBool isDefault = false.obs;
  final RxBool isSubmitting = false.obs;

  /// 后端手机号校验规则:5-20 位数字、-、+、空格(支持区号/分机)
  static final RegExp _phoneRegExp = RegExp(r'^[0-9+\- ]{5,20}$');

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is AddressModel) {
      _editAddress = args;
      consigneeController = TextEditingController(text: args.consignee);
      phoneController = TextEditingController(text: args.phone);
      detailController = TextEditingController(text: args.detail);
      provinceId.value = args.province;
      provinceName.value = args.provinceName;
      cityId.value = args.city;
      cityName.value = args.cityName;
      districtId.value = args.district ?? 0;
      districtName.value = args.districtName;
      isDefault.value = args.isDefaultAddress;
    } else {
      consigneeController = TextEditingController();
      phoneController = TextEditingController();
      detailController = TextEditingController();
    }
  }

  @override
  void onClose() {
    consigneeController.dispose();
    phoneController.dispose();
    detailController.dispose();
    super.onClose();
  }

  /// 供 AreaPicker 回填的当前选择
  AreaSelection? get initialSelection {
    if (provinceId.value == 0) return null;
    return AreaSelection(
      provinceId: provinceId.value,
      provinceName: provinceName.value,
      cityId: cityId.value,
      cityName: cityName.value,
      districtId: districtId.value == 0 ? null : districtId.value,
      districtName: districtName.value,
    );
  }

  /// 弹出省市区三级联动选择器
  Future<void> pickArea() async {
    final result = await AreaPicker.show(initial: initialSelection);
    if (result == null) return;
    provinceId.value = result.provinceId;
    provinceName.value = result.provinceName;
    cityId.value = result.cityId;
    cityName.value = result.cityName;
    districtId.value = result.districtId ?? 0;
    districtName.value = result.districtName;
  }

  /// 校验并保存
  Future<void> submit() async {
    final consignee = consigneeController.text.trim();
    if (consignee.isEmpty) {
      SnackbarUtils.showWarning('请填写收货人姓名');
      return;
    }
    final phone = phoneController.text.trim();
    if (phone.isEmpty) {
      SnackbarUtils.showWarning('请填写手机号');
      return;
    }
    if (!_phoneRegExp.hasMatch(phone)) {
      SnackbarUtils.showWarning('手机号格式不正确');
      return;
    }
    if (provinceId.value == 0) {
      SnackbarUtils.showWarning('请选择省份');
      return;
    }
    if (cityId.value == 0) {
      SnackbarUtils.showWarning('请选择城市');
      return;
    }
    final detail = detailController.text.trim();
    if (detail.isEmpty) {
      SnackbarUtils.showWarning('请填写详细地址');
      return;
    }

    isSubmitting.value = true;
    try {
      final data = <String, dynamic>{
        'consignee': consignee,
        'phone': phone,
        'province': provinceId.value,
        'city': cityId.value,
        if (districtId.value != 0) 'district': districtId.value,
        'detail': detail,
        'is_default': isDefault.value ? 1 : 0,
      };
      final response = isEditMode
          ? await _repository.editAddress({...data, 'id': _editAddress!.id})
          : await _repository.addAddress(data);
      if (response.isSuccess) {
        SnackbarUtils.showSuccess(response.message.isNotEmpty
            ? response.message
            : (isEditMode ? '修改成功' : '添加成功'));
        Get.back(result: true);
      } else {
        SnackbarUtils.showError(
            response.message.isNotEmpty ? response.message : '保存失败，请重试');
      }
    } finally {
      isSubmitting.value = false;
    }
  }
}

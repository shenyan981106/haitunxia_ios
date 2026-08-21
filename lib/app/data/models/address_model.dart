/// 收货地址模型
/// 对应接口:api/address/lists(返回 data.list 数组)
class AddressModel {
  final int id;
  final int userId;
  final String consignee;
  final String phone;
  final int province;
  final String provinceName;
  final int city;
  final String cityName;
  final int? district;
  final String districtName;
  final String detail;
  final int isDefault;

  const AddressModel({
    required this.id,
    required this.userId,
    required this.consignee,
    required this.phone,
    required this.province,
    required this.provinceName,
    required this.city,
    required this.cityName,
    this.district,
    required this.districtName,
    required this.detail,
    required this.isDefault,
  });

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    return AddressModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      consignee: json['consignee']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      province: (json['province'] as num?)?.toInt() ?? 0,
      provinceName: json['province_name']?.toString() ?? '',
      city: (json['city'] as num?)?.toInt() ?? 0,
      cityName: json['city_name']?.toString() ?? '',
      district: (json['district'] as num?)?.toInt(),
      districtName: json['district_name']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      isDefault: (json['is_default'] as num?)?.toInt() ?? 0,
    );
  }

  /// 是否默认地址
  bool get isDefaultAddress => isDefault == 1;

  /// 省市区 + 详细地址拼接的完整地址
  String get fullAddress {
    final region = [
      provinceName,
      cityName,
      if (districtName.isNotEmpty) districtName,
    ].join('');
    return '$region$detail';
  }
}

/// 省市区选项(api/area/province|city|district 返回 data: [{value, name}])
class AreaOption {
  final int value;
  final String name;

  const AreaOption({required this.value, required this.name});

  factory AreaOption.fromJson(Map<String, dynamic> json) {
    return AreaOption(
      value: (json['value'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
    );
  }
}

/// 省市区三级联动选择结果(AreaPicker 返回)
class AreaSelection {
  final int provinceId;
  final String provinceName;
  final int cityId;
  final String cityName;
  final int? districtId;
  final String districtName;

  const AreaSelection({
    required this.provinceId,
    required this.provinceName,
    required this.cityId,
    required this.cityName,
    this.districtId,
    required this.districtName,
  });
}

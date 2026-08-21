/// 会员套餐与规格数据模型
///
/// 对应接口 `/addons/exam/user/memberPackages`(GET,传参 subject_id)返回结构:
/// `data` 为单条会员配置(exam_member_config),不区分年卡/季卡/月卡,
/// 下挂 `specs` 单科规格列表(spec_type=1),科目多选。
/// 订单金额完全由所选规格的 price 决定,时长取套餐的 days。

/// 会员套餐合计价格信息(售价/原价/立省)
class PackagePriceInfo {
  final double price;
  final double original;
  final double save;

  const PackagePriceInfo({
    required this.price,
    required this.original,
    required this.save,
  });
}

/// 会员规格(exam_member_spec)
class MemberSpec {
  final int id;
  final int memberConfigId;
  final int subjectId;
  final int specType;
  final String name;

  /// 逗号分隔的科目 ID 串,如 "28,9"
  final String subjectIds;
  final String price;
  final String originalPrice;
  final String saveAmount;

  /// 是否已开通此科目
  final bool opened;

  MemberSpec({
    required this.id,
    required this.memberConfigId,
    required this.subjectId,
    required this.specType,
    required this.name,
    this.subjectIds = '',
    this.price = '0',
    this.originalPrice = '0',
    this.saveAmount = '0',
    this.opened = false,
  });

  factory MemberSpec.fromJson(Map<String, dynamic> json) {
    return MemberSpec(
      id: _parseInt(json['id']),
      memberConfigId: _parseInt(json['member_config_id']),
      subjectId: _parseInt(json['subject_id']),
      specType: _parseInt(json['spec_type']),
      name: json['name']?.toString() ?? '',
      subjectIds: json['subject_ids']?.toString() ?? '',
      price: json['price']?.toString() ?? '0',
      originalPrice: json['original_price']?.toString() ?? '0',
      saveAmount: json['save_amount']?.toString() ?? '0',
      opened: json['opened'] == true || json['opened'] == 1,
    );
  }
}

/// 会员套餐(exam_member_config)
class MemberPackage {
  final int id;
  final String name;
  final String price;
  final int days;
  final String tag;
  final String desc;

  /// 单科规格列表(接口字段 `specs`,兼容旧字段 single_specs)
  final List<MemberSpec> specs;

  MemberPackage({
    required this.id,
    required this.name,
    this.price = '0',
    this.days = 0,
    this.tag = '',
    this.desc = '',
    List<MemberSpec>? specs,
  }) : specs = specs ?? const [];

  factory MemberPackage.fromJson(Map<String, dynamic> json) {
    List<MemberSpec> parseSpecs(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => MemberSpec.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return MemberPackage(
      id: _parseInt(json['id']),
      name: json['name']?.toString() ?? '',
      price: json['price']?.toString() ?? '0',
      days: _parseInt(json['days']),
      tag: json['tag']?.toString() ?? '',
      desc: json['desc']?.toString() ?? '',
      specs: parseSpecs(json['specs'] ?? json['single_specs']),
    );
  }
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// 我的权益记录数据模型
///
/// 对应接口 `/api/member/rights`(GET,传参 status=active|expired、page、limit)返回结构:
/// `data` 为裸数组,每条为一条会员权益记录。
/// 日期文案直接使用后端返回的 `open_time_text`/`expire_time_text`,不自行格式化。

/// 会员权益记录
class MemberRight {
  final int id;
  final int subjectId;
  final String subjectName;

  /// 科目路径(父级科目链),仅展示用,保留原始 Map
  final Map<String, dynamic> subjectPath;

  final int memberConfigId;
  final String memberConfigName;

  /// 权益时长(天)
  final int days;
  final String tag;
  final String desc;
  final String orderNo;
  final String amount;
  final String payMoney;
  final int openTime;
  final String openTimeText;

  /// 是否永久有效
  final bool isPermanent;
  final int expireTime;
  final String expireTimeText;

  /// 剩余天数(已失效时为 0/负数)
  final int remainDays;

  /// active=生效中 expired=已失效
  final String status;
  final String statusText;

  MemberRight({
    required this.id,
    this.subjectId = 0,
    this.subjectName = '',
    Map<String, dynamic>? subjectPath,
    this.memberConfigId = 0,
    this.memberConfigName = '',
    this.days = 0,
    this.tag = '',
    this.desc = '',
    this.orderNo = '',
    this.amount = '0',
    this.payMoney = '0',
    this.openTime = 0,
    this.openTimeText = '',
    this.isPermanent = false,
    this.expireTime = 0,
    this.expireTimeText = '',
    this.remainDays = 0,
    this.status = '',
    this.statusText = '',
  }) : subjectPath = subjectPath ?? const {};

  factory MemberRight.fromJson(Map<String, dynamic> json) {
    return MemberRight(
      id: _parseInt(json['id']),
      subjectId: _parseInt(json['subject_id']),
      subjectName: json['subject_name']?.toString() ?? '',
      subjectPath: json['subject_path'] is Map
          ? Map<String, dynamic>.from(json['subject_path'] as Map)
          : const {},
      memberConfigId: _parseInt(json['member_config_id']),
      memberConfigName: json['member_config_name']?.toString() ?? '',
      days: _parseInt(json['days']),
      tag: json['tag']?.toString() ?? '',
      desc: json['desc']?.toString() ?? '',
      orderNo: json['order_no']?.toString() ?? '',
      amount: json['amount']?.toString() ?? '0',
      payMoney: json['pay_money']?.toString() ?? '0',
      openTime: _parseInt(json['open_time']),
      openTimeText: json['open_time_text']?.toString() ?? '',
      isPermanent: json['is_permanent'] == true || json['is_permanent'] == 1,
      expireTime: _parseInt(json['expire_time']),
      expireTimeText: json['expire_time_text']?.toString() ?? '',
      remainDays: _parseInt(json['remain_days']),
      status: json['status']?.toString() ?? '',
      statusText: json['status_text']?.toString() ?? '',
    );
  }
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

import 'dart:convert';

/// iOS 会员可选科目与价格档位数据模型
///
/// 对应接口 `/addons/exam/pay/iosMemberProducts`(POST form-urlencoded,
/// 传参 member_config_id + subject_id=二级科目 ID,★仅 iOS 调用,见 07 §3.4):返回**科目列表**
/// (subjects,id/name/opened——★opened 为后端 2026-08-21 新增字段,已开通科目
/// 页面置灰不可选)与**价格档位列表**
/// (tiers,按所选科目数量定价,如 1科 68 / 2科 128 ...)。
/// ★客户端不硬编码档位:页面展示价与下单 product_id 均以接口返回为准。

/// 价格档位(按所选科目数量定价)
class IosMemberTier {
  /// 科目数量(档位)
  final int subjectCount;

  /// 档位名,如 "1科会员"
  final String name;

  /// 内购商品 ID(下单接口按科目数量反查返回的即此值)
  final String productId;

  /// 档位价格(元,字符串)
  final String price;

  IosMemberTier({
    required this.subjectCount,
    required this.name,
    required this.productId,
    required this.price,
  });

  factory IosMemberTier.fromJson(Map<String, dynamic> json) {
    return IosMemberTier(
      subjectCount: int.tryParse(json['subject_count']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      price: json['price']?.toString() ?? '0',
    );
  }
}

/// 可选科目(三级科目;opened 为后端 2026-08-21 新增字段,已开通科目页面置灰不可选)
class IosMemberSubject {
  final int id;
  final String name;

  /// 是否已开通此科目(true/1;缺失默认 false,兼容接口未加字段前的过渡状态)
  final bool opened;

  IosMemberSubject({required this.id, required this.name, this.opened = false});

  factory IosMemberSubject.fromJson(Map<String, dynamic> json) {
    return IosMemberSubject(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      opened: json['opened'] == true || json['opened'] == 1,
    );
  }
}

/// iOS 会员产品配置(会员配置 id + 可选科目 + 价格档位)
class IosMemberProducts {
  final int memberConfigId;
  final String name;
  final int days;
  final List<IosMemberSubject> subjects;
  final List<IosMemberTier> tiers;

  IosMemberProducts({
    required this.memberConfigId,
    required this.name,
    required this.days,
    required this.subjects,
    required this.tiers,
  });

  factory IosMemberProducts.fromJson(Map<String, dynamic> json) {
    List<T> parseList<T>(dynamic raw, T Function(Map<String, dynamic>) fromJson) {
      // 兼容双重编码:subjects/tiers 为 JSON 字符串时先解码
      if (raw is String && raw.isNotEmpty) {
        try {
          raw = jsonDecode(raw);
        } catch (_) {
          return const [];
        }
      }
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return IosMemberProducts(
      memberConfigId:
          int.tryParse(json['member_config_id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      days: int.tryParse(json['days']?.toString() ?? '') ?? 0,
      subjects: parseList(json['subjects'], IosMemberSubject.fromJson),
      tiers: parseList(json['tiers'], IosMemberTier.fromJson),
    );
  }

  /// 指定科目数量对应的价格档位(无对应档位返回 null)
  IosMemberTier? tierByCount(int count) {
    for (final tier in tiers) {
      if (tier.subjectCount == count) return tier;
    }
    return null;
  }
}

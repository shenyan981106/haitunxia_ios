import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:tobias/tobias.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluwx/fluwx.dart';

import '../../../data/models/ios_member_product_model.dart';
import '../../../data/models/member_package_model.dart';
import '../../../data/providers/api_client.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/iap_service.dart';
import '../../../data/services/subject_vip_service.dart';
import '../../../services/global_project_controller.dart';
import '../../../services/snackbar_utils.dart';
import '../../../utils/api_error_handler.dart';

/// 会员中心控制器
///
/// 数据源:`addons/exam/user/memberPackages`(GET,传参 subject_id=全局当前项目 ID,
/// 与首页精选推荐/历年真题同源)。返回单条会员配置(不区分年/季/月卡),
/// 下挂 specs 单科规格列表(spec_type=1),科目多选。
/// 支付:先 `pay/createMemberOrder` 下单(spec_ids 传所选规格多个),
/// 再 `pay/memberPay` 发起支付。两个接口均为 form-urlencoded 提交。
/// 订单金额完全由所选规格 price 决定,时长取套餐 days。
class VipCenterController extends GetxController with WidgetsBindingObserver {
  /// 选中的单科规格名集合(多选)
  final RxSet<String> selectedSingleSpecNames = <String>{}.obs;

  final RxnString selectedPayCode = RxnString();
  final RxList<Map<String, dynamic>> payMethods = <Map<String, dynamic>>[].obs;
  final RxList<MemberPackage> packages = <MemberPackage>[].obs;
  final RxBool isLoadingPackages = true.obs;

  final bool enablePayment = true; //屏蔽支付
  bool _isPaying = false;

  final Fluwx _fluwx = Fluwx();
  FluwxCancelable? _wechatPaySubscription;

  // ==================== iOS 苹果内购(可选科目 + 价格档位) ====================

  /// iOS 专用:可选科目与价格档位接口返回(★仅 iOS 拉取,见 _fetchIosMemberProducts)
  final RxList<IosMemberSubject> iosSubjects = <IosMemberSubject>[].obs;
  final RxList<IosMemberTier> iosTiers = <IosMemberTier>[].obs;
  final Rxn<IosMemberProducts> iosProducts = Rxn<IosMemberProducts>();

  /// iOS 选中的三级科目 ID 集合(多选,展示价按选中数量取档位)
  final RxSet<int> selectedIosSubjectIds = <int>{}.obs;

  /// 是否 iOS(苹果内购链路)
  bool get isIos => Platform.isIOS;

  // ==================== 派生状态 ====================

  /// 当前会员配置(接口返回单条,不区分年/季/月卡)
  MemberPackage? get package =>
      packages.isEmpty ? null : packages.first;

  /// 可选科目(合并各配置的 specs,以 name 去重)
  List<MemberSpec> get currentTabSpecs {
    final seen = <String>{};
    final result = <MemberSpec>[];
    for (final p in packages) {
      for (final s in p.specs) {
        if (seen.add(s.name)) {
          result.add(s);
        }
      }
    }
    return result;
  }

  /// 指定科目名是否选中
  bool isSpecSelected(String name) => selectedSingleSpecNames.contains(name);

  /// 页面主体是否有数据可渲染:
  /// iOS 以 memberPackages 配置就绪为准(科目/档位走 iosMemberProducts,随后到);
  /// 安卓/鸿蒙以 specs 非空为准(原逻辑)
  bool get hasContent {
    if (isIos) {
      return packages.isNotEmpty;
    }
    return currentTabSpecs.isNotEmpty;
  }

  /// 是否还有可购买的科目(加载中/无数据时视为有,避免支付栏闪烁;全部已开通则无)
  bool get hasSelectableSpec {
    // iOS:列表为空(加载中/无数据)视为有;全部已开通则隐藏支付栏
    if (isIos) {
      return iosSubjects.isEmpty || iosSubjects.any((s) => !s.opened);
    }
    final specs = currentTabSpecs;
    return specs.isEmpty || specs.any((s) => !s.opened);
  }

  /// 指定套餐中已选中的规格对象
  List<MemberSpec> selectedSpecsInPackage(MemberPackage pkg) {
    return pkg.specs.where((s) => isSpecSelected(s.name)).toList();
  }

  /// iOS 当前选中数量对应的价格档位(数量无对应档位时 null)
  IosMemberTier? get selectedIosTier {
    final products = iosProducts.value;
    if (products == null) return null;
    return products.tierByCount(selectedIosSubjectIds.length);
  }

  /// 支付栏展示价:iOS 按选中科目数量取档位价(与苹果弹窗实扣一致),
  /// 安卓/鸿蒙按所选规格 price 求和
  double get payPrice {
    if (isIos) {
      final tier = selectedIosTier;
      if (tier != null) return _toDouble(tier.price);
      return 0;
    }
    final pkg = package;
    if (pkg == null) return 0;
    return packagePriceInfo(pkg).price;
  }

  /// 套餐合计价格信息(售价/原价/立省),由选中规格 price 汇总
  PackagePriceInfo packagePriceInfo(MemberPackage pkg) {
    final list = selectedSpecsInPackage(pkg);
    if (list.isEmpty) {
      return PackagePriceInfo(price: _toDouble(pkg.price), original: 0, save: 0);
    }
    var price = 0.0;
    var original = 0.0;
    var save = 0.0;
    for (final s in list) {
      price += _toDouble(s.price);
      original += _toDouble(s.originalPrice);
      save += _toDouble(s.saveAmount);
    }
    if (save <= 0) {
      save = original - price;
    }
    if (save < 0) {
      save = 0;
    }
    return PackagePriceInfo(price: price, original: original, save: save);
  }

  double _toDouble(dynamic value) =>
      double.tryParse(value?.toString() ?? '') ?? 0;

  // ==================== 生命周期 ====================

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _fetchMemberPackages();
    _fetchPayMethods();
  }

  @override
  void onClose() {
    _wechatPaySubscription?.cancel();
    _fluwx.clearSubscribers();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 支付结果确认兜底:微信回调丢失或 H5 支付时,返回 App 后静默走完整刷新链
    // (重拉套餐=服务端权威状态,已开通则会员/题库判断自动更新)
    if (state == AppLifecycleState.resumed && _isPaying) {
      _isPaying = false;
      Future.delayed(const Duration(seconds: 2), () {
        _onPaySuccess();
      });
    }
  }

  /// 刷新用户会员信息
  Future<void> _refreshUserInfo() async {
    await AuthService.to.fetchUserInfo();
  }

  /// 科目 ID:与首页精选推荐/历年真题同源,取全局当前项目 ID(首页左上角选择科目),兜底 '5'
  String _resolveSubjectId() {
    return GlobalProjectController.to.currentProject.value?.id ?? '5';
  }

  /// 获取会员套餐列表(含全科/单科规格)
  Future<void> _fetchMemberPackages() async {
    try {
      final response = await ApiClient.to.exam(
        'user/memberPackages',
        queryParameters: {'subject_id': _resolveSubjectId()},
      );
      final body = response.data;
      dynamic rawList;

      if (body is Map && body['data'] is Map) {
        // 新结构:data 为单条会员配置对象
        if (body['data']['list'] is List) {
          rawList = body['data']['list'];
        } else {
          rawList = [body['data']];
        }
      } else if (body is Map && body['data'] is List) {
        rawList = body['data'];
      } else if (body is List) {
        rawList = body;
      }

      if (rawList is List) {
        packages.value = rawList
            .whereType<Map>()
            .map((e) => MemberPackage.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } else {
        packages.clear();
      }
    } on DioException catch (e) {
      ApiErrorHandler.handleDioError(e, fallbackMessage: '获取会员套餐失败');
    } catch (e) {
      ApiErrorHandler.handleError(e, fallbackMessage: '获取会员套餐失败');
    } finally {
      isLoadingPackages.value = false;
      _resetSelections();
      // ★iOS 追加拉取可选科目与价格档位(依赖 memberPackages 返回的配置 id)
      if (Platform.isIOS) {
        _fetchIosMemberProducts();
      }
    }
  }

  /// 拉取 iOS 可选科目与价格档位(★仅 iOS;member_config_id 取自 memberPackages 配置 id)
  Future<void> _fetchIosMemberProducts() async {
    final pkgId = package?.id;
    if (pkgId == null || pkgId <= 0) {
      iosProducts.value = null;
      iosSubjects.clear();
      iosTiers.clear();
      return;
    }
    try {
      // ★后端为 POST 接口,GET 传参收不到 member_config_id 会返回「会员配置ID必须为正整数」
      final response = await ApiClient.to.post(
        'addons/exam/pay/iosMemberProducts',
        data: {
          'member_config_id': pkgId,
          'subject_id': _resolveSubjectId(),
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final body = response.data;
      if (kDebugMode) {
        debugPrint('vip_center: iosMemberProducts 原始响应: $body');
      }
      dynamic raw;
      if (body is Map && body['data'] != null) {
        raw = body['data'];
        // 兼容双重编码:data 为 JSON 字符串时先解码
        if (raw is String && raw.isNotEmpty) {
          try {
            raw = jsonDecode(raw);
          } catch (_) {
            raw = null;
          }
        }
      } else if (body is Map) {
        raw = body;
      }

      // 兼容 data.list 包裹(部分后端返回 {data: {list: {...}}})
      if (raw is Map &&
          raw['subjects'] == null &&
          raw['tiers'] == null &&
          raw['list'] is Map) {
        raw = raw['list'];
      }

      if (raw is Map) {
        final products =
            IosMemberProducts.fromJson(Map<String, dynamic>.from(raw));
        iosProducts.value = products;
        iosSubjects.value = products.subjects;
        iosTiers.value = products.tiers;
        if (kDebugMode) {
          debugPrint('vip_center: iosMemberProducts 解析结果: '
              'subjects=${products.subjects.length}, tiers=${products.tiers.length}');
        }
        // 接口成功但 subjects 为空:无可用科目时提示
        if (products.subjects.isEmpty) {
          SnackbarUtils.showError('当前无可开通科目');
        }
      } else {
        iosProducts.value = null;
        iosSubjects.clear();
        iosTiers.clear();
        if (kDebugMode) {
          debugPrint('vip_center: iosMemberProducts 响应无 data/结构不符');
        }
        SnackbarUtils.showError('获取会员价格档位数据异常');
      }
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('vip_center: iosMemberProducts 请求失败: ${e.message}');
      }
      ApiErrorHandler.handleDioError(e, fallbackMessage: '获取会员价格档位失败');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('vip_center: iosMemberProducts 解析异常: $e');
      }
      ApiErrorHandler.handleError(e, fallbackMessage: '获取会员价格档位失败');
    } finally {
      _resetIosSelection();
    }
  }

  /// iOS 默认勾选第一个未开通科目(已开通的不可再选)
  void _resetIosSelection() {
    selectedIosSubjectIds.clear();
    for (final subject in iosSubjects) {
      if (!subject.opened) {
        selectedIosSubjectIds.add(subject.id);
        return;
      }
    }
  }

  /// 重置默认选中:默认勾选第一个未开通的规格(已开通的科目不可再选)
  void _resetSelections() {
    final specs = currentTabSpecs;
    selectedSingleSpecNames.clear();
    for (final spec in specs) {
      if (!spec.opened) {
        selectedSingleSpecNames.add(spec.name);
        return;
      }
    }
  }

  /// 获取支付方式列表
  Future<void> _fetchPayMethods() async {
    if (Platform.isIOS) {
      // iOS 会员开通走苹果 IAP(独立下单/凭证校验接口),不请求后端支付方式;
      // 注入本地虚拟方式仅用于支付栏展示,支付分支按平台判断(见 doPay)
      payMethods.value = [
        {'code': 'apple', 'name': 'Apple Pay', 'status': 1},
      ];
      selectPayMethod('apple');
      return;
    }

    try {
      final response = await ApiClient.to.get('addons/exam/pay/payMethod');
      final body = response.data;
      dynamic rawList;

      if (body is Map && body['data'] is List) {
        rawList = body['data'];
      } else if (body is Map &&
          body['data'] is Map &&
          (body['data']['list'] is List)) {
        rawList = body['data']['list'];
      } else if (body is List) {
        rawList = body;
      }

      if (rawList is List) {
        payMethods.value = rawList
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        final enabledMethods =
            payMethods.where((m) => m['status'] == 1).toList();
        if (enabledMethods.isNotEmpty) {
          selectPayMethod(enabledMethods.first['code']?.toString() ?? '');
        }
      }
    } on DioException catch (e) {
      ApiErrorHandler.handleDioError(e, fallbackMessage: '获取支付方式失败');
    } catch (e) {
      ApiErrorHandler.handleError(e, fallbackMessage: '获取支付方式失败');
    }
  }

  // ==================== 选择动作 ====================

  /// 科目勾选切换(多选);已开通的科目不可再选
  void toggleSingleSpec(String name) {
    MemberSpec? spec;
    for (final s in currentTabSpecs) {
      if (s.name == name) {
        spec = s;
        break;
      }
    }
    if (spec == null || spec.opened) return;
    if (selectedSingleSpecNames.contains(name)) {
      selectedSingleSpecNames.remove(name);
    } else {
      selectedSingleSpecNames.add(name);
    }
  }

  /// iOS 科目勾选切换(多选,按选中数量联动档位价);已开通科目不可再选
  void toggleIosSubject(int id) {
    IosMemberSubject? subject;
    for (final s in iosSubjects) {
      if (s.id == id) {
        subject = s;
        break;
      }
    }
    if (subject == null || subject.opened) return;
    if (selectedIosSubjectIds.contains(id)) {
      selectedIosSubjectIds.remove(id);
    } else {
      selectedIosSubjectIds.add(id);
    }
  }

  /// 选择支付方式
  void selectPayMethod(String code) {
    selectedPayCode.value = code;
  }

  // ==================== 支付 ====================

  /// 从下单接口返回中提取订单号 order_sn
  String? _extractOrderSn(dynamic body) {
    if (body is Map) {
      final data = body['data'];
      if (data is Map) {
        return data['order_sn']?.toString() ?? data['orderSn']?.toString();
      }
      if (data is String && data.isNotEmpty) {
        return data;
      }
      return body['order_sn']?.toString() ?? body['orderSn']?.toString();
    }
    if (body is String && body.isNotEmpty) {
      return body;
    }
    return null;
  }

  /// partner="xxx"&seller_id="xxx"&out_trade_no="xxx"&subject="xxx"...
  String? _extractAlipayOrderString(dynamic body) {
    if (body is String && body.isNotEmpty) {
      return body;
    }

    if (body is Map) {
      final orderKeys = [
        'orderString',
        'order_info',
        'orderInfo',
        'pay_order_info',
      ];
      for (final key in orderKeys) {
        final val = body[key];
        if (val is String && val.isNotEmpty && val.contains('=')) {
          return val;
        }
      }

      final dataVal = body['data'];
      if (dataVal is String && dataVal.isNotEmpty && dataVal.contains('=')) {
        return dataVal;
      }
      if (dataVal is Map) {
        for (final key in orderKeys) {
          final val = dataVal[key];
          if (val is String && val.isNotEmpty && val.contains('=')) {
            return val;
          }
        }
      }
    }

    return null;
  }

  /// 提取微信App支付参数(兼容大小写键名)
  Map<String, dynamic>? _extractWechatPayParams(dynamic body) {
    Map<String, dynamic>? params;

    if (body is Map) {
      params = Map<String, dynamic>.from(body);
      final dataVal = body['data'];
      if (dataVal is Map) {
        params = Map<String, dynamic>.from(dataVal);
      }
    }

    if (params == null) return null;

    final appId = params['appId']?.toString() ?? params['appid']?.toString();
    final partnerId =
        params['partnerId']?.toString() ?? params['partnerid']?.toString();
    final prepayId =
        params['prepayId']?.toString() ?? params['prepayid']?.toString();
    final packageValue = params['package']?.toString();
    final nonceStr =
        params['nonceStr']?.toString() ?? params['noncestr']?.toString();
    final timestamp =
        params['timestamp']?.toString() ?? params['timeStamp']?.toString();
    final sign = params['sign']?.toString();

    if (appId != null &&
        partnerId != null &&
        prepayId != null &&
        nonceStr != null &&
        timestamp != null &&
        sign != null) {
      return {
        'appId': appId,
        'partnerId': partnerId,
        'prepayId': prepayId,
        'packageValue': packageValue ?? 'Sign=WXPay',
        'nonceStr': nonceStr,
        'timeStamp': int.tryParse(timestamp) ?? 0,
        'sign': sign,
      };
    }

    return null;
  }

  /// 发起微信App支付
  Future<void> _doWechatAppPay(Map<String, dynamic> params) async {
    final isInstalled = await _fluwx.isWeChatInstalled;
    if (!isInstalled) {
      _isPaying = false;
      SnackbarUtils.showError('请先安装微信');
      return;
    }

    _wechatPaySubscription?.cancel();
    _wechatPaySubscription = _fluwx.addSubscriber((response) {
      if (response is WeChatPaymentResponse) {
        _wechatPaySubscription?.cancel();
        _isPaying = false;

        if (response.isSuccessful) {
          SnackbarUtils.showSuccess('支付成功');
          _onPaySuccess();
        } else if (response.errCode == -2) {
          SnackbarUtils.showInfo('支付已取消');
        } else {
          SnackbarUtils.showError(
            '支付失败：${response.errStr ?? '未知错误'}(${response.errCode})',
          );
        }
      }
    });

    try {
      final result = await _fluwx.pay(
        which: Payment(
          appId: params['appId']!,
          partnerId: params['partnerId']!,
          prepayId: params['prepayId']!,
          packageValue: params['packageValue']!,
          nonceStr: params['nonceStr']!,
          timestamp: params['timeStamp']! as int,
          sign: params['sign']!,
        ),
      );

      if (kDebugMode) {
        debugPrint('微信支付调起结果: $result');
      }
    } catch (e) {
      _isPaying = false;
      _wechatPaySubscription?.cancel();
      if (kDebugMode) {
        debugPrint('调起微信支付失败: $e');
      }
      SnackbarUtils.showError('调起微信失败：${e.toString()}');
    }
  }

  /// 支付成功后的公共处理
  void _onPaySuccess() {
    _fetchMemberPackages();
    _refreshUserInfo();
    // 刷新按科目 VIP 状态(题库等模块的按科目判断立即生效)
    SubjectVipService.to.refreshCurrentProject();
  }

  /// 发起支付(安卓/鸿蒙:支付宝/微信 App 支付;iOS:苹果 IAP 内购)
  ///
  /// 流程:createMemberOrder 下单(取 order_sn)→ memberPay 发起支付(取网关参数)。
  /// iOS 走独立链路:createIosMemberOrder → StoreKit 购买 → iosVerifyReceipt(见 _doIosIapPay)。
  Future<void> doPay() async {
    if (!enablePayment) {
      SnackbarUtils.showInfo('请联系客服');
      return;
    }

    // ★iOS 会员开通走苹果 IAP(独立下单/凭证校验接口),安卓/鸿蒙维持原微信/支付宝链路
    if (Platform.isIOS) {
      await _doIosIapPay();
      return;
    }

    final type = selectedPayCode.value ?? 'wechat';

    final pkg = package;
    if (pkg == null || pkg.specs.isEmpty) {
      SnackbarUtils.showError('暂无会员套餐');
      return;
    }
    final specs = selectedSpecsInPackage(pkg);
    if (specs.isEmpty) {
      SnackbarUtils.showError('请选择科目');
      return;
    }
    // 所选科目必须全部在该套餐下有对应规格,否则下单金额与展示不一致
    final expectedCount = selectedSingleSpecNames.length;
    if (specs.length != expectedCount) {
      SnackbarUtils.showError('所选科目暂不支持该套餐');
      return;
    }

    _isPaying = true;

    try {
      SnackbarUtils.showInfo('正在发起支付...');

      // 1. 下单:spec_ids 传所选单科规格 id 列表(多选传多个,form-urlencoded)
      // ★必须用 ListFormat.multiCompatible 编码为 spec_ids[]=156&spec_ids[]=157,
      // 否则默认 multi 编码(PHP 只取最后一个值)会导致价格不叠加、只存一个规格
      final orderResponse = await ApiClient.to.post(
        'addons/exam/pay/createMemberOrder',
        data: {
          'member_config_id': pkg.id,
          'spec_ids': specs.map((s) => s.id).toList(),
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          listFormat: ListFormat.multiCompatible,
        ),
      );

      final orderSn = _extractOrderSn(orderResponse.data);
      if (orderSn == null || orderSn.isEmpty) {
        _isPaying = false;
        SnackbarUtils.showError('创建订单失败');
        return;
      }

      // 2. 支付
      final response = await ApiClient.to.post(
        'addons/exam/pay/memberPay',
        data: {
          'order_sn': orderSn,
          'pay_type': type,
          'method': 'app',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      if (response.data != null) {
        var body = response.data;

        if (type == 'alipay') {
          final orderString = _extractAlipayOrderString(body);
          if (kDebugMode) {
            debugPrint('支付宝支付响应: $body');
            debugPrint('解析后的订单字符串: $orderString');
          }

          if (orderString != null && orderString.isNotEmpty) {
            final Tobias tobias = Tobias();
            try {
              final payResult = await tobias.pay(orderString);
              _isPaying = false;
              if (kDebugMode) {
                debugPrint('支付宝支付结果: $payResult');
              }
              final resultStatus = payResult['resultStatus']?.toString();
              if (resultStatus == '9000') {
                SnackbarUtils.showSuccess('支付成功');
                _onPaySuccess();
              } else if (resultStatus == '6001') {
                SnackbarUtils.showInfo('支付已取消');
              } else if (resultStatus == '4000') {
                SnackbarUtils.showError('支付失败');
              } else {
                SnackbarUtils.showError('支付结果：${payResult['memo'] ?? '未知状态'}');
              }
            } catch (e) {
              _isPaying = false;
              if (kDebugMode) {
                debugPrint('调起支付宝失败: $e');
              }
              SnackbarUtils.showError('调起支付宝失败：${e.toString()}');
            }
          } else {
            // H5 支付:保持 _isPaying=true,返回 App 时由 didChangeAppLifecycleState 兜底刷新
            final payUrl = body is Map
                ? body['payUrl']?.toString() ?? body['url']?.toString()
                : null;
            if (payUrl != null && payUrl.isNotEmpty) {
              final uri = Uri.parse(payUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
              } else {
                _isPaying = false;
                SnackbarUtils.showError('无法打开支付页面');
              }
            } else {
              _isPaying = false;
              SnackbarUtils.showError('获取支付参数失败');
            }
          }
        }

        if (type == 'wechat') {
          final wechatParams = _extractWechatPayParams(body);

          if (kDebugMode) {
            debugPrint('微信支付响应: $body');
            debugPrint('解析后的支付参数: $wechatParams');
          }

          if (wechatParams != null) {
            await _doWechatAppPay(wechatParams);
          } else {
            // H5 支付:保持 _isPaying=true,返回 App 时由 didChangeAppLifecycleState 兜底刷新
            final payUrl = body is String
                ? body
                : (body is Map
                    ? body['payUrl']?.toString() ?? body['url']?.toString()
                    : null);

            if (payUrl != null && payUrl.isNotEmpty) {
              final uri = Uri.parse(payUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
              } else {
                _isPaying = false;
                SnackbarUtils.showError('无法打开支付页面');
              }
            } else {
              _isPaying = false;
              SnackbarUtils.showError('获取微信支付参数失败');
            }
          }
        }
      } else {
        _isPaying = false;
        SnackbarUtils.showError('获取支付参数失败');
      }
    } on DioException catch (e) {
      _isPaying = false;
      ApiErrorHandler.handleDioError(e, fallbackMessage: '支付请求失败');
    } catch (e) {
      _isPaying = false;
      ApiErrorHandler.handleError(e, fallbackMessage: '支付失败');
    }
  }

  // ==================== iOS 苹果 IAP 内购 ====================

  /// iOS 会员开通:苹果 IAP 内购链路(仅 iOS,doPay 平台分支调用)
  ///
  /// 流程:createIosMemberOrder 下单(member_config_id + subject_ids,取
  /// order_sn/product_id)→ 落盘待校验订单 → StoreKit 购买 → 读凭证 →
  /// iosVerifyReceipt 服务端校验 → 成功走 _onPaySuccess 刷新链。
  /// 购买中断/校验失败由 IapService 启动补单兜底。
  /// 可选科目与价格档位来自 pay/iosMemberProducts(展示价与苹果实扣一致)。
  Future<void> _doIosIapPay() async {
    final products = iosProducts.value;
    final pkg = package;
    if (products == null || pkg == null) {
      SnackbarUtils.showError('暂无会员套餐');
      return;
    }
    if (selectedIosSubjectIds.isEmpty) {
      SnackbarUtils.showError('请选择科目');
      return;
    }
    // 选中数量必须在档位表内(如 1-6 科),否则服务端无法定价
    if (selectedIosTier == null) {
      SnackbarUtils.showError('所选科目数量超出可购档位');
      return;
    }

    _isPaying = true;

    try {
      SnackbarUtils.showInfo('正在发起支付...');

      // 1. iOS 下单:subject_ids 传所选三级科目 ID(逗号分隔,排序保证稳定),
      //    服务端按数量反查档位返回 product_id
      final subjectIds = (selectedIosSubjectIds.toList()..sort()).join(',');
      final orderResponse = await ApiClient.to.post(
        'addons/exam/pay/createIosMemberOrder',
        data: {
          'member_config_id':
              products.memberConfigId > 0 ? products.memberConfigId : pkg.id,
          'subject_ids': subjectIds,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final data = orderResponse.data is Map
          ? (orderResponse.data['data'] is Map
              ? orderResponse.data['data']
              : orderResponse.data)
          : null;
      final orderSn = data is Map ? data['order_sn']?.toString() : null;
      final productId = data is Map ? data['product_id']?.toString() : null;
      if (orderSn == null ||
          orderSn.isEmpty ||
          productId == null ||
          productId.isEmpty) {
        _isPaying = false;
        SnackbarUtils.showError('创建订单失败');
        return;
      }
      if (kDebugMode) {
        // ★诊断日志:比对后端 product_id 与 ASC 内购商品 ID 是否一致
        debugPrint('vip_center: createIosMemberOrder 返回 '
            'order_sn=$orderSn product_id=$productId');
      }

      // 2. 落盘待校验订单(购买中断/校验失败由 IapService 启动补单兜底)
      IapService.to.savePendingOrder(
        orderSn: orderSn,
        productId: productId,
        subjectId: _resolveSubjectId(),
      );

      // 3. StoreKit 购买 + 凭证校验(成功时 IapService 已刷新会员态)
      final result = await IapService.to.buy(
        productId: productId,
        orderSn: orderSn,
      );
      switch (result.status) {
        case IapPayStatus.success:
          _isPaying = false;
          SnackbarUtils.showSuccess('支付成功');
          _onPaySuccess();
          break;
        case IapPayStatus.cancelled:
          _isPaying = false;
          SnackbarUtils.showInfo('支付已取消');
          break;
        case IapPayStatus.failed:
          _isPaying = false;
          // ★仍有待补单订单(可能已扣款但凭证校验未完成)时提示自动到账,
          // 避免用户「钱扣了却报错」恐慌;IapService 启动补单/刷新会员态兜底
          var message = result.message;
          if (IapService.to.readPendingOrder() != null) {
            message = '$message,若已扣款将自动到账';
          }
          SnackbarUtils.showError(message);
          break;
      }
    } on DioException catch (e) {
      _isPaying = false;
      ApiErrorHandler.handleDioError(e, fallbackMessage: '支付请求失败');
    } catch (e) {
      _isPaying = false;
      ApiErrorHandler.handleError(e, fallbackMessage: '支付失败');
    }
  }
}

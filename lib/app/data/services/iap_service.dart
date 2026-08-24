import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import '../providers/api_client.dart';
import 'auth_service.dart';
import 'subject_vip_service.dart';

/// 苹果 IAP 内购支付结果状态
enum IapPayStatus {
  /// 购买成功且凭证校验通过(会员已生效)
  success,

  /// 用户取消
  cancelled,

  /// 失败(含校验失败/超时)
  failed,
}

/// 苹果 IAP 内购支付结果
class IapPayResult {
  final IapPayStatus status;

  /// 失败原因/提示文案
  final String message;

  const IapPayResult(this.status, this.message);
}

/// 苹果 IAP 凭证校验结果
class IapVerifyResult {
  final bool ok;
  final String message;

  const IapVerifyResult(this.ok, this.message);
}

/// 苹果 IAP 内购服务(★仅 iOS 生效,安卓/鸿蒙调用直接返回失败)
///
/// 会员开通专属流程:先 `pay/createIosMemberOrder` 下单(取 order_sn + product_id,
/// 见 VipCenterController),再经本服务完成 StoreKit 购买 → 读 appStoreReceipt →
/// `pay/iosVerifyReceipt` 服务端校验 → 校验成功才 completePurchase。
///
/// 掉单兜底:购买前把订单信息落盘(GetStorage 键 `iap_pending_member_order`),
/// 校验成功后清除;启动时发现残留订单且凭证存在则静默重试校验并刷新会员态。
/// 校验失败**不** completePurchase,苹果下次启动会重新推送交易,配合残留订单补单。
class IapService extends GetxService {
  static IapService get to => Get.find();

  /// 读取 appStoreReceipt 的原生通道(iOS AppDelegate 实现)
  static const MethodChannel _receiptChannel =
      MethodChannel('app.haitunxia.com/iap');

  final GetStorage _storage = GetStorage();

  /// 待校验订单存储键
  static const String pendingOrderKey = 'iap_pending_member_order';

  /// 购买等待超时(StoreKit 弹窗停留上限)
  static const int _buyTimeoutSeconds = 300;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  Completer<IapPayResult>? _buyCompleter;
  bool _isBusy = false;

  /// 当前平台是否支持苹果内购(仅 iOS)
  bool get isSupported => Platform.isIOS;

  @override
  void onInit() {
    super.onInit();
    if (!isSupported) return;

    // 项目未依赖 in_app_purchase umbrella 包,直接使用 storekit 实现需手动注册
    InAppPurchaseStoreKitPlatform.registerPlatform();
    _purchaseSub = InAppPurchasePlatform.instance.purchaseStream
        .listen(_handlePurchases, onError: (e) {
      debugPrint('IapService: purchaseStream 异常: $e');
    });

    // 启动补单:上次购买中断/校验失败的残留订单(含苹果重推的未完成交易)
    Future(() => retryPendingOrder());
  }

  @override
  void onClose() {
    _purchaseSub?.cancel();
    super.onClose();
  }

  // ==================== 购买入口 ====================

  /// 发起内购购买(仅 iOS;购买前请先下单并 [savePendingOrder])
  ///
  /// [productId] 下单接口返回的内购商品 ID(com.haitunxia.tiku.*)
  /// [orderSn] 下单接口返回的订单号(凭证校验必传)
  Future<IapPayResult> buy({
    required String productId,
    required String orderSn,
  }) async {
    if (!isSupported) {
      return const IapPayResult(IapPayStatus.failed, '当前平台不支持苹果内购');
    }
    if (_isBusy) {
      return const IapPayResult(IapPayStatus.failed, '支付进行中,请稍后');
    }

    _isBusy = true;
    _buyCompleter = Completer<IapPayResult>();
    try {
      // 1. 查询商品(校验 product_id 存在,StoreKit 弹窗展示真实价格)
      final details = await _queryProduct(orderSn, productId);
      if (details == null) {
        _buyCompleter = null;
        _isBusy = false;
        // ★诊断期带出商品 ID,便于比对 ASC 配置;定位后恢复简洁文案
        return IapPayResult(
            IapPayStatus.failed, '商品信息获取失败($productId),请稍后重试');
      }

      // 2. 发起购买,结果经 purchaseStream 回调
      await InAppPurchasePlatform.instance
          .buyNonConsumable(purchaseParam: PurchaseParam(productDetails: details));

      // 3. 等待回调或超时(超时保留落盘订单,由启动补单兜底)
      return await _buyCompleter!.future.timeout(
        const Duration(seconds: _buyTimeoutSeconds),
        onTimeout: () {
          _buyCompleter = null;
          _isBusy = false;
          return const IapPayResult(
              IapPayStatus.failed, '支付确认超时,结果稍后自动同步');
        },
      );
    } catch (e) {
      _buyCompleter = null;
      _isBusy = false;
      debugPrint('IapService: 发起购买失败: $e');
      return IapPayResult(IapPayStatus.failed, '发起购买失败:${e.toString()}');
    }
  }

  /// 查询内购商品(不存在/查询失败返回 null)
  Future<ProductDetails?> _queryProduct(String orderSn, String productId) async {
    try {
      final response = await InAppPurchasePlatform.instance
          .queryProductDetails({productId});
      if (response.error != null) {
        debugPrint('IapService: 查询商品 $productId 失败: '
            '${response.error!.code} ${response.error!.message}');
        return null;
      }
      if (response.productDetails.isEmpty) {
        // ★商品查不到:ID 会落在 notFoundIDs(常见原因:ASC 未创建该商品/
        // 商品未关联到当前 App/状态未达 Ready to Submit/后端返回的 ID 与 ASC 不一致)
        debugPrint('IapService: 商品 $productId 不存在(order_sn=$orderSn),'
            'notFoundIDs=${response.notFoundIDs}');
        return null;
      }
      return response.productDetails.first;
    } catch (e) {
      debugPrint('IapService: 查询商品异常: $e');
      return null;
    }
  }

  // ==================== 交易处理 ====================

  void _handlePurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      _handlePurchase(purchase);
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    // Ask to Buy:等待家长批准,不处理
    if (purchase.status == PurchaseStatus.pending) return;

    if (purchase.status == PurchaseStatus.error) {
      // ★失败交易必须 completePurchase 出队,否则同一商品再次购买会报
      // storekit_duplicate_product_object(存在未完成的 pending transaction)
      await _completePurchase(purchase);
      _completeBuy(IapPayResult(
          IapPayStatus.failed, purchase.error?.message ?? '购买失败'));
      return;
    }
    if (purchase.status == PurchaseStatus.canceled) {
      // ★取消交易同样要 completePurchase 出队(同商品重复购买依赖出队)
      await _completePurchase(purchase);
      _completeBuy(const IapPayResult(IapPayStatus.cancelled, '支付已取消'));
      return;
    }

    // purchased / restored:校验凭证后再完成交易
    await _verifyAndComplete(purchase);
  }

  /// 凭证校验 → 完成交易;校验失败保留落盘订单,启动补单兜底
  Future<void> _verifyAndComplete(PurchaseDetails purchase) async {
    final pending = readPendingOrder();
    if (pending == null) {
      // 无待校验订单(恢复购买/历史交易):直接完成,避免反复推送。
      // 会员开通暂不支持"恢复购买"(需后端无单凭证校验),此处仅清掉交易。
      if (kDebugMode) {
        debugPrint('IapService: 收到无待校验订单的交易 ${purchase.productID},直接完成');
      }
      await _completePurchase(purchase);
      return;
    }

    final orderSn = pending['order_sn']?.toString() ?? '';
    final productId = pending['product_id']?.toString() ?? '';

    // 商品与下单返回不一致:非本订单的交易,不完成(保留待对应订单处理)
    if (purchase.productID != productId) {
      debugPrint('IapService: 交易商品 ${purchase.productID} '
          '与待校验订单商品 $productId 不一致,暂不处理');
      return;
    }

    // ★2026-08-24 改为**先完成交易再校验**:appStoreReceipt 只有交易出队后
    // 才可能包含该笔购买记录(此前先校验后出队:凭证陈旧读不到交易→校验失败
    // →不出队→凭证永不更新,死锁报「支付凭证中没有该商品的有效交易」)。
    // 校验失败仍保留落盘订单,凭证已含交易,启动补单重试即可闭环。
    await _completePurchase(purchase);

    try {
      final receipt = await getReceiptData();
      if (receipt == null) {
        _completeBuy(const IapPayResult(IapPayStatus.failed, '读取内购凭证失败'));
        return;
      }
      final verify = await verifyReceipt(
        orderSn: orderSn,
        receiptData: receipt,
        productId: productId,
        subjectId: pending['subject_id']?.toString() ?? '',
      );
      if (verify.ok) {
        clearPendingOrder();
        _completeBuy(const IapPayResult(IapPayStatus.success, '支付成功'));
        // 刷新会员态(会员中心/题库按科目判断立即生效)
        SubjectVipService.to.refreshCurrentProject();
        AuthService.to.fetchUserInfo();
      } else {
        // ★凭证已被其他订单使用(同商品重复购买:沙盒/重复下单返回同一交易):
        // 该商品实际已支付开通,按成功收尾——清落盘订单防每次启动死循环重试
        if (_isReceiptAlreadyUsed(verify.message)) {
          clearPendingOrder();
          _completeBuy(const IapPayResult(IapPayStatus.success, '该科目已开通'));
          SubjectVipService.to.refreshCurrentProject();
          AuthService.to.fetchUserInfo();
          return;
        }
        // 其他校验失败(如"内购商品与订单不匹配"):保留落盘订单,启动补单重试
        _completeBuy(IapPayResult(IapPayStatus.failed, verify.message));
      }
    } catch (e) {
      debugPrint('IapService: 凭证校验异常: $e');
      _completeBuy(
          const IapPayResult(IapPayStatus.failed, '凭证校验异常,请稍后重试'));
    }
  }

  Future<void> _completePurchase(PurchaseDetails purchase) async {
    try {
      await InAppPurchasePlatform.instance.completePurchase(purchase);
    } catch (e) {
      debugPrint('IapService: completePurchase 失败: $e');
    }
  }

  /// 完成一次购买等待(购买等待为空时静默,即启动补单场景)
  void _completeBuy(IapPayResult result) {
    final completer = _buyCompleter;
    _buyCompleter = null;
    _isBusy = false;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  // ==================== 凭证与校验接口 ====================

  /// 读取内购凭证 appStoreReceipt 的 base64(不存在则先刷新凭证)
  Future<String?> getReceiptData() async {
    try {
      final data = await _receiptChannel.invokeMethod<String>('getReceiptData');
      return (data != null && data.isNotEmpty) ? data : null;
    } on PlatformException catch (e) {
      debugPrint('IapService: 读取内购凭证失败: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('IapService: 读取内购凭证异常: $e');
      return null;
    }
  }

  /// 服务端凭证校验:`addons/exam/pay/iosVerifyReceipt`
  Future<IapVerifyResult> verifyReceipt({
    required String orderSn,
    required String receiptData,
    required String productId,
    String subjectId = '',
  }) async {
    try {
      final response = await ApiClient.to.post(
        'addons/exam/pay/iosVerifyReceipt',
        data: {
          'order_sn': orderSn,
          'receipt_data': receiptData,
          'product_id': productId,
          'subject_id': subjectId,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final body = response.data;
      if (body is Map) {
        final code = body['code'];
        final ok = code == 0 || code == 1 || code == 200 ||
            code == '0' || code == '1' || code == '200';
        if (ok) return const IapVerifyResult(true, '');
        return IapVerifyResult(
            false, body['msg']?.toString() ?? '凭证校验失败');
      }
      return const IapVerifyResult(false, '凭证校验失败');
    } on DioException catch (e) {
      return IapVerifyResult(false, _extractDioErrorMessage(e) ?? '凭证校验失败');
    } catch (e) {
      return const IapVerifyResult(false, '凭证校验异常,请稍后重试');
    }
  }

  String? _extractDioErrorMessage(DioException e) {
    if (e.response?.data is Map) {
      final data = e.response!.data as Map;
      if (data['msg'] != null) return data['msg'].toString();
      if (data['message'] != null) return data['message'].toString();
    }
    return e.message;
  }

  // ==================== 掉单持久化 ====================

  /// 读取待校验订单
  Map<String, dynamic>? readPendingOrder() {
    try {
      final raw = _storage.read(pendingOrderKey);
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('IapService: 读取待校验订单失败: $e');
    }
    return null;
  }

  /// 落盘待校验订单(购买前调用)
  void savePendingOrder({
    required String orderSn,
    required String productId,
    String subjectId = '',
  }) {
    _storage.write(pendingOrderKey, {
      'order_sn': orderSn,
      'product_id': productId,
      'subject_id': subjectId,
    });
  }

  /// 清除待校验订单(校验成功后调用)
  void clearPendingOrder() {
    _storage.remove(pendingOrderKey);
  }

  /// 启动补单:残留订单 + 已有凭证 → 重试服务端校验,成功静默刷新会员态
  Future<void> retryPendingOrder() async {
    if (!isSupported) return;
    final pending = readPendingOrder();
    if (pending == null) return;

    final orderSn = pending['order_sn']?.toString() ?? '';
    final productId = pending['product_id']?.toString() ?? '';
    if (orderSn.isEmpty || productId.isEmpty) {
      // 数据损坏,清除避免死循环
      clearPendingOrder();
      return;
    }

    final receipt = await getReceiptData();
    if (receipt == null) return; // 尚无凭证,保留订单等待下次

    final verify = await verifyReceipt(
      orderSn: orderSn,
      receiptData: receipt,
      productId: productId,
      subjectId: pending['subject_id']?.toString() ?? '',
    );
    if (verify.ok) {
      clearPendingOrder();
      // 静默刷新(登录态/按科目 VIP 状态)
      AuthService.to.fetchUserInfo();
      SubjectVipService.to.refreshCurrentProject();
    } else if (_isReceiptAlreadyUsed(verify.message)) {
      // 凭证已被其他订单使用:商品已开通,清残留订单避免每次启动重复重试
      clearPendingOrder();
      SubjectVipService.to.refreshCurrentProject();
      AuthService.to.fetchUserInfo();
    }
  }

  /// 判断校验失败是否为「凭证已被其他订单使用」(同商品重复购买场景:
  /// 苹果返回同一交易,凭证已被之前订单消费,商品实际已开通;
  /// 按成功收尾避免死循环;★后端可返回稳定错误码后替换此文案匹配)
  bool _isReceiptAlreadyUsed(String message) {
    return message.contains('已被') && message.contains('使用');
  }
}

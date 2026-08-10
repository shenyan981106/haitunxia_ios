import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:tobias/tobias.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluwx/fluwx.dart';
import '../../../data/providers/api_client.dart';
import '../../../data/services/auth_service.dart';
import '../../../services/snackbar_utils.dart';
import '../../../utils/api_error_handler.dart';

class VipCenterController extends GetxController with WidgetsBindingObserver {
  final RxInt selectedIndex = 0.obs;
  final RxnString selectedPayCode = RxnString();
  final RxList<Map<String, dynamic>> payMethods = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> memberConfigs =
      <Map<String, dynamic>>[].obs;
  final RxBool isLoadingConfigs = true.obs;

  final bool enablePayment = true; //屏蔽支付
  bool _isPaying = false;

  final Fluwx _fluwx = Fluwx();
  FluwxCancelable? _wechatPaySubscription;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _fetchMemberConfigs();
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
    if (state == AppLifecycleState.resumed && _isPaying) {
      _isPaying = false;
      Future.delayed(const Duration(seconds: 2), () {
        _refreshUserInfo();
      });
    }
  }

  /// 刷新用户会员信息
  Future<void> _refreshUserInfo() async {
    await AuthService.to.fetchUserInfo();
  }

  /// 获取会员配置列表
  Future<void> _fetchMemberConfigs() async {
    try {
      final response =
          await ApiClient.to.get('addons/exam/user/memberOpenConfig');
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
        memberConfigs.value = rawList
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } on DioException catch (e) {
      ApiErrorHandler.handleDioError(e, fallbackMessage: '获取VIP配置失败');
    } catch (e) {
      ApiErrorHandler.handleError(e, fallbackMessage: '获取VIP配置失败');
    } finally {
      isLoadingConfigs.value = false;
    }
  }

  /// 获取支付方式列表
  Future<void> _fetchPayMethods() async {
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

  /// 选择套餐
  void selectPlan(int index) {
    selectedIndex.value = index;
  }

  /// 选择支付方式
  void selectPayMethod(String code) {
    selectedPayCode.value = code;
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

  /// 提取微信App支付参数
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
          _fetchMemberConfigs();
          _refreshUserInfo();
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

  /// 发起支付（支付宝使用App支付，微信使用App支付）
  Future<void> doPay() async {
    if (!enablePayment) {
      SnackbarUtils.showInfo('请联系客服');
      return;
    }
    final type = selectedPayCode.value ?? 'wechat';

    if (memberConfigs.isEmpty || selectedIndex.value >= memberConfigs.length) {
      SnackbarUtils.showError('请选择会员类型');
      return;
    }
    final memberConfigId = memberConfigs[selectedIndex.value]['id']?.toString();
    if (memberConfigId == null || memberConfigId.isEmpty) {
      SnackbarUtils.showError('会员配置信息异常');
      return;
    }

    _isPaying = true;

    try {
      SnackbarUtils.showInfo('正在发起支付...');

      var response = await ApiClient.to.post(
        'addons/exam/pay/pay',
        data: {
          'order_type': 'member',
          'order_id': memberConfigId,
          'pay_type': type,
          'method': 'app',
        },
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
                _fetchMemberConfigs();
                _refreshUserInfo();
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
            _isPaying = false;
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
                SnackbarUtils.showError('无法打开支付页面');
              }
            } else {
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
            _isPaying = false;

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
                SnackbarUtils.showError('无法打开支付页面');
              }
            } else {
              SnackbarUtils.showError('获取微信支付参数失败');
            }
          }
        }
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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dio/dio.dart';
import 'package:fluwx/fluwx.dart';
import 'package:tobias/tobias.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/screenAdapter.dart';
import '../../../data/providers/api_client.dart';
import '../../../services/snackbar_utils.dart';
import '../../../utils/api_error_handler.dart';

class OrderConfirmView extends StatefulWidget {
  final Map<String, dynamic> courseData;

  const OrderConfirmView({Key? key, required this.courseData})
      : super(key: key);

  @override
  State<OrderConfirmView> createState() => _OrderConfirmViewState();
}

class _OrderConfirmViewState extends State<OrderConfirmView> {
  String selectedPayment = '';
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  final List<Map<String, dynamic>> _payMethods = [];
  bool _isLoadingPayMethods = true;
  bool _isPaying = false;

  final Fluwx _fluwx = Fluwx();
  FluwxCancelable? _wechatPaySubscription;

  @override
  void initState() {
    super.initState();
    _fetchPayMethods();
  }

  @override
  void dispose() {
    _wechatPaySubscription?.cancel();
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    super.dispose();
  }

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
        final methods = rawList
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        final enabledMethods = methods.where((m) => m['status'] == 1).toList();
        setState(() {
          _payMethods.addAll(enabledMethods);
          if (enabledMethods.isNotEmpty) {
            selectedPayment = enabledMethods.first['code']?.toString() ?? '';
          }
        });
      }
    } on DioException catch (e) {
      ApiErrorHandler.handleDioError(e, fallbackMessage: '获取支付方式失败');
    } catch (e) {
      ApiErrorHandler.handleError(e, fallbackMessage: '获取支付方式失败');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPayMethods = false;
        });
      }
    }
  }

  String _getSvgForCode(String code) {
    switch (code) {
      case 'wechat':
        return 'assets/fonts/wechat.svg';
      case 'alipay':
        return 'assets/fonts/zhifubao.svg';
      default:
        return 'assets/fonts/wechat.svg';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          '确认下单',
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(50),
            fontWeight: FontWeight.w500,
            color: Color(0xFF333333),
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Get.back(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: ScreenAdapter.width(32),
                vertical: ScreenAdapter.height(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 课程信息卡片
                  _buildCourseInfoCard(),
                  SizedBox(height: ScreenAdapter.height(24)),

                  // 收货信息卡片
                  _buildShippingInfoCard(),
                  SizedBox(height: ScreenAdapter.height(24)),

                  // 支付方式卡片
                  _buildPaymentCard(),
                ],
              ),
            ),
          ),

          // 底部提交按钮
          _buildBottomButton(),
        ],
      ),
    );
  }

  /// 课程信息展示（上下结构：图片 + 标题/价格）
  Widget _buildCourseInfoCard() {
    final data = widget.courseData;
    final title = data['title']?.toString() ?? '未知课程';
    final price = data['price']?.toString() ?? '0';
    final originalPrice = data['original_price']?.toString() ?? '';
    final image = data['cover_image_url']?.toString() ??
        data['cover_image']?.toString() ??
        data['image']?.toString() ??
        '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ScreenAdapter.width(16)),
      ),
      padding: EdgeInsets.all(ScreenAdapter.width(32)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 课程封面图（顶部全宽显示）
          ClipRRect(
            borderRadius: BorderRadius.circular(ScreenAdapter.width(12)),
            child: image.isNotEmpty
                ? Image.network(
                    ApiClient.replaceUri(image),
                    width: double.infinity,
                    height: ScreenAdapter.height(360),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildPlaceholderImage(),
                  )
                : _buildPlaceholderImage(),
          ),
          SizedBox(height: ScreenAdapter.height(28)),

          // 课程标题
          Text(
            title,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(40),
              fontWeight: FontWeight.w500,
              color: Color(0xFF333333),
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: ScreenAdapter.height(20)),

          // 价格
          Row(
            children: [
              Text(
                '\u00A5$price',
                style: TextStyle(
                  fontSize: ScreenAdapter.fontSize(42),
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF4D4F),
                ),
              ),
              if (originalPrice.isNotEmpty && originalPrice != price) ...[
                SizedBox(width: ScreenAdapter.width(12)),
                Text(
                  '\u00A5$originalPrice',
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(32),
                    color: Color(0xFF999999),
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: double.infinity,
      height: ScreenAdapter.height(360),
      color: Color(0xFFEEEEEE),
      child: Icon(Icons.image,
          color: Color(0xFFCCCCCC), size: ScreenAdapter.fontSize(52)),
    );
  }

  /// 收货信息卡片（收货人 + 手机号）
  Widget _buildShippingInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ScreenAdapter.width(16)),
      ),
      padding: EdgeInsets.all(ScreenAdapter.width(32)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '收货信息',
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(38),
              fontWeight: FontWeight.w500,
              color: Color(0xFF333333),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(40)),

          // 收货人输入
          _buildInputField('收货人', nameController, hint: '请输入收货人姓名'),
          SizedBox(height: ScreenAdapter.height(48)),

          // 手机号码输入
          _buildInputField('手机号码', phoneController,
              keyboardType: TextInputType.phone, hint: '请输入手机号码'),
          SizedBox(height: ScreenAdapter.height(48)),

          // 收货地址输入
          _buildInputField('收货地址', addressController, hint: '请输入收货地址'),
        ],
      ),
    );
  }

  /// 输入框组件
  Widget _buildInputField(String label, TextEditingController controller,
      {TextInputType keyboardType = TextInputType.text, required String hint}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: ScreenAdapter.width(160),
          child: Text(
            label,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(36),
              color: Color(0xFF333333),
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(34),
              color: Color(0xFF333333),
            ),
            inputFormatters: label == '手机号码'
                ? [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11)
                  ]
                : null,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: TextStyle(
                  fontSize: ScreenAdapter.fontSize(32),
                  color: Color(0xFFCCCCCC)),
              contentPadding: EdgeInsets.symmetric(
                horizontal: ScreenAdapter.width(16),
                vertical: ScreenAdapter.height(12),
              ),
              border: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFF5F5F5), width: 1),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFF5F5F5), width: 1),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF3D7CFF), width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 支付方式选择卡片（动态渲染）
  Widget _buildPaymentCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ScreenAdapter.width(16)),
      ),
      padding: EdgeInsets.all(ScreenAdapter.width(32)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '支付方式',
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(38),
              fontWeight: FontWeight.w500,
              color: Color(0xFF333333),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(36)),
          if (_isLoadingPayMethods)
            Center(
              child: Padding(
                padding:
                    EdgeInsets.symmetric(vertical: ScreenAdapter.height(20)),
                child: CircularProgressIndicator(color: Color(0xFF3D7CFF)),
              ),
            )
          else if (_payMethods.isEmpty)
            Center(
              child: Padding(
                padding:
                    EdgeInsets.symmetric(vertical: ScreenAdapter.height(20)),
                child: Text(
                  '暂无可用支付方式',
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(32),
                    color: Color(0xFF999999),
                  ),
                ),
              ),
            )
          else ...[
            Row(
              children: _payMethods.asMap().entries.map((entry) {
                final index = entry.key;
                final method = entry.value;
                final code = method['code']?.toString() ?? '';
                final name = method['name']?.toString() ?? '';
                final svg = _getSvgForCode(code);
                final isSelected = selectedPayment == code;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index == _payMethods.length - 1
                          ? 0
                          : ScreenAdapter.width(24),
                    ),
                    child: _buildPaymentOption(
                      svgPath: svg,
                      label: name,
                      isSelected: isSelected,
                      onTap: () => setState(() => selectedPayment = code),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// 单个支付选项
  Widget _buildPaymentOption({
    required String svgPath,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ScreenAdapter.width(24),
          vertical: ScreenAdapter.height(28),
        ),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFFEBF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(ScreenAdapter.width(12)),
          border: Border.all(
            color: isSelected ? Color(0xFF3D7CFF) : Color(0xFFE5E5E5),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              svgPath,
              width: ScreenAdapter.width(44),
              height: ScreenAdapter.height(44),
            ),
            SizedBox(width: ScreenAdapter.width(12)),
            Text(
              label,
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(34),
                color: isSelected ? Color(0xFF3D7CFF) : Color(0xFF333333),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (isSelected)
              Padding(
                padding: EdgeInsets.only(left: ScreenAdapter.width(6)),
                child: Icon(
                  Icons.check_circle,
                  size: ScreenAdapter.fontSize(32),
                  color: Color(0xFF3D7CFF),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 底部确认购买按钮
  Widget _buildBottomButton() {
    final data = widget.courseData;
    final price = data['price']?.toString() ?? '0';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: ScreenAdapter.width(32),
        vertical: ScreenAdapter.height(20),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: ScreenAdapter.width(10),
            offset: Offset(0, -ScreenAdapter.height(4)),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ElevatedButton(
          onPressed: _isPaying ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isPaying ? Color(0xFFCCCCCC) : Color(0xFF3D7CFF),
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: ScreenAdapter.height(28)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ScreenAdapter.width(16)),
            ),
            elevation: 0,
          ),
          child: _isPaying
              ? SizedBox(
                  height: ScreenAdapter.fontSize(36),
                  width: ScreenAdapter.fontSize(36),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  '确认购买 \u00A5$price',
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(38),
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }

  void _handleSubmit() {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    final address = addressController.text.trim();

    if (name.isEmpty) {
      SnackbarUtils.showError('请输入收货人姓名');
      return;
    }
    if (phone.isEmpty) {
      SnackbarUtils.showError('请输入手机号码');
      return;
    }
    if (phone.length != 11) {
      SnackbarUtils.showError('请输入正确的11位手机号码');
      return;
    }
    if (address.isEmpty) {
      SnackbarUtils.showError('请输入收货地址');
      return;
    }
    if (selectedPayment.isEmpty) {
      SnackbarUtils.showError('请选择支付方式');
      return;
    }

    _submitPay(name, phone, address);
  }

  Future<void> _submitPay(String name, String phone, String address) async {
    if (_isPaying) return;

    final courseId = widget.courseData['id']?.toString();
    if (courseId == null || courseId.isEmpty) {
      SnackbarUtils.showError('课程信息异常');
      return;
    }

    setState(() {
      _isPaying = true;
    });

    try {
      SnackbarUtils.showInfo('正在发起支付...');

      final response = await ApiClient.to.post(
        'addons/exam/pay/pay',
        data: {
          'order_type': 'course',
          'order_id': courseId,
          'pay_type': selectedPayment,
          'method': 'app',
          'extra_params': {
            'name': name,
            'phone': phone,
            'address': address,
          },
        },
      );

      if (response.data != null) {
        final body = response.data;
        final type = selectedPayment;

        if (type == 'alipay') {
          await _doAlipayPay(body);
        } else if (type == 'wechat') {
          await _doWechatPay(body);
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _isPaying = false;
        });
      }
      ApiErrorHandler.handleDioError(e, fallbackMessage: '支付请求失败');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPaying = false;
        });
      }
      ApiErrorHandler.handleError(e, fallbackMessage: '支付失败');
    }
  }

  /// 支付宝支付
  Future<void> _doAlipayPay(dynamic body) async {
    final orderString = _extractAlipayOrderString(body);
    if (kDebugMode) {
      debugPrint('支付宝支付响应: $body');
      debugPrint('解析后的订单字符串: $orderString');
    }

    if (orderString != null && orderString.isNotEmpty) {
      final Tobias tobias = Tobias();
      try {
        final payResult = await tobias.pay(orderString);
        if (mounted) {
          setState(() {
            _isPaying = false;
          });
        }
        if (kDebugMode) {
          debugPrint('支付宝支付结果: $payResult');
        }
        final resultStatus = payResult['resultStatus']?.toString();
        if (resultStatus == '9000') {
          SnackbarUtils.showSuccess('支付成功');
          Get.back(result: true);
        } else if (resultStatus == '6001') {
          SnackbarUtils.showInfo('支付已取消');
        } else if (resultStatus == '4000') {
          SnackbarUtils.showError('支付失败');
        } else {
          SnackbarUtils.showError('支付结果：${payResult['memo'] ?? '未知状态'}');
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isPaying = false;
          });
        }
        if (kDebugMode) {
          debugPrint('调起支付宝失败: $e');
        }
        SnackbarUtils.showError('调起支付宝失败：${e.toString()}');
      }
    } else {
      if (mounted) {
        setState(() {
          _isPaying = false;
        });
      }
      final payUrl = body is Map
          ? body['payUrl']?.toString() ?? body['url']?.toString()
          : null;
      if (payUrl != null && payUrl.isNotEmpty) {
        final uri = Uri.parse(payUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          SnackbarUtils.showError('无法打开支付页面');
        }
      } else {
        SnackbarUtils.showError('获取支付参数失败');
      }
    }
  }

  /// 微信支付
  Future<void> _doWechatPay(dynamic body) async {
    final wechatParams = _extractWechatPayParams(body);

    if (kDebugMode) {
      debugPrint('微信支付响应: $body');
      debugPrint('解析后的支付参数: $wechatParams');
    }

    if (wechatParams != null) {
      await _doWechatAppPay(wechatParams);
    } else {
      if (mounted) {
        setState(() {
          _isPaying = false;
        });
      }
      final payUrl = body is String
          ? body
          : (body is Map
              ? body['payUrl']?.toString() ?? body['url']?.toString()
              : null);

      if (payUrl != null && payUrl.isNotEmpty) {
        final uri = Uri.parse(payUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          SnackbarUtils.showError('无法打开支付页面');
        }
      } else {
        SnackbarUtils.showError('获取微信支付参数失败');
      }
    }
  }

  /// 提取支付宝订单字符串
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
      if (mounted) {
        setState(() {
          _isPaying = false;
        });
      }
      SnackbarUtils.showError('请先安装微信');
      return;
    }

    _wechatPaySubscription?.cancel();
    _wechatPaySubscription = _fluwx.addSubscriber((response) {
      if (response is WeChatPaymentResponse) {
        _wechatPaySubscription?.cancel();
        if (mounted) {
          setState(() {
            _isPaying = false;
          });
        }

        if (response.isSuccessful) {
          SnackbarUtils.showSuccess('支付成功');
          Get.back(result: true);
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
      if (mounted) {
        setState(() {
          _isPaying = false;
        });
      }
      _wechatPaySubscription?.cancel();
      if (kDebugMode) {
        debugPrint('调起微信支付失败: $e');
      }
      SnackbarUtils.showError('调起微信支付失败：${e.toString()}');
    }
  }
}

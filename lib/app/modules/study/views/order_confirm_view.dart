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
import '../../../data/models/address_model.dart';
import '../../../data/repositories/exam_repository.dart';
import '../../../services/snackbar_utils.dart';
import '../../../utils/api_error_handler.dart';
import '../../../components/app_tag.dart';
import '../../../components/common_app_bar.dart';
import '../../../routes/app_pages.dart';

class OrderConfirmView extends StatefulWidget {
  final Map<String, dynamic> courseData;

  const OrderConfirmView({Key? key, required this.courseData})
      : super(key: key);

  @override
  State<OrderConfirmView> createState() => _OrderConfirmViewState();
}

class _OrderConfirmViewState extends State<OrderConfirmView>
    with WidgetsBindingObserver {
  String selectedPayment = '';
  final List<Map<String, dynamic>> _payMethods = [];
  bool _isLoadingPayMethods = true;
  bool _isPaying = false;

  /// 已选收货地址(必填,未选时提交被拦截并跳转选择页)
  AddressModel? _selectedAddress;

  /// 已有订单模式:按 spec_ids 拉课程详情解析出的规格名(如「系统班 + 精讲班」,加载失败为空)
  String _existingSpecNames = '';

  /// 已有订单模式(我的订单-待支付「去结算」进入):直接支付已有订单,
  /// 跳过 createCourseOrder 下单与收货地址选择(地址已随订单存储)
  bool get _isExistingOrder => widget.courseData['existing_order'] == true;

  final Fluwx _fluwx = Fluwx();
  FluwxCancelable? _wechatPaySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchPayMethods();
    if (_isExistingOrder) {
      // 优先用列表接口透传的 spec_names(逗号分隔);为空(旧数据/未传)时拉课程详情兜底
      final specNames = widget.courseData['spec_names']?.toString().trim() ?? '';
      if (specNames.isNotEmpty) {
        _existingSpecNames = specNames.split(',').map((e) => e.trim()).join(' + ');
      } else {
        _loadOrderSpecs();
      }
    } else {
      _loadDefaultAddress();
    }
  }

  /// 兜底逻辑:courseData['spec_names'] 为空时,按 class_id 拉课程详情,
  /// 用 spec_ids 匹配出规格名(仅展示,失败静默)
  Future<void> _loadOrderSpecs() async {
    final classId = widget.courseData['class_id']?.toString() ?? '';
    final specIdsStr = widget.courseData['spec_ids']?.toString() ?? '';
    if (classId.isEmpty || specIdsStr.isEmpty) return;
    try {
      final response = await ApiClient.to.get(
        'addons/exam/coures/detail',
        queryParameters: {'id': classId},
      );
      final body = response.data;
      List? specs;
      if (body is Map) {
        final data = body['data'];
        // 新旧结构兼容:specs 均在 data 根(新结构 data.course 下无 specs)
        if (data is Map) {
          specs = data['specs'] is List ? data['specs'] : null;
        }
      }
      if (specs is List) {
        final ids = specIdsStr
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final names = specs
            .whereType<Map>()
            .where((s) => ids.contains(s['id']?.toString()))
            .map((s) => s['name']?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
        if (names.isNotEmpty && mounted) {
          setState(() => _existingSpecNames = names.join(' + '));
        }
      }
    } catch (e) {
      // 静默:规格名拉取失败不影响支付
    }
  }

  /// 进入页面时自动选中默认收货地址(失败静默,不阻塞下单)
  Future<void> _loadDefaultAddress() async {
    try {
      final response = await ExamRepository.to.getAddressList();
      if (response.isSuccess) {
        final list = response.data ?? [];
        final defaultItems = list.where((e) => e.isDefaultAddress).toList();
        if (defaultItems.isNotEmpty && mounted) {
          setState(() => _selectedAddress = defaultItems.first);
        }
      }
    } catch (e) {
      // 静默:地址加载失败不阻塞下单页,用户可手动点击选择
    }
  }

  /// 跳转地址列表选择页,选中后回填
  Future<void> _pickAddress() async {
    final result = await Get.toNamed(
      Routes.ADDRESS_LIST,
      arguments: {'selectMode': true},
    );
    if (result is AddressModel && mounted) {
      setState(() => _selectedAddress = result);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wechatPaySubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 支付结果确认兜底:微信/支付宝回调丢失或 H5 支付时,从外部返回后
    // 静默返回 true,由课程详情页重拉详情确认支付结果(未支付时详情不变)
    if (state == AppLifecycleState.resumed && _isPaying) {
      _isPaying = false;
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Get.back(result: true);
        }
      });
    }
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
      appBar: CommonAppBar(
        title: '确认下单',
        titleStyle: TextStyle(
          fontSize: ScreenAdapter.fontSize(50),
          fontWeight: FontWeight.w500,
          color: Color(0xFF333333),
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

                  // 收货地址卡片(必选;★已有订单模式隐藏,地址已随订单存储)
                  if (!_isExistingOrder) ...[
                    _buildAddressCard(),
                    SizedBox(height: ScreenAdapter.height(24)),
                  ],

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
    final originalPrice = data['original_price']?.toString() ?? '';
    final image = data['cover_image_url']?.toString() ??
        data['cover_image']?.toString() ??
        data['image']?.toString() ??
        '';

    // ★2026-08-17 规格下单:selected_specs 存在时展示所选规格名称,金额 = Σ 规格价格
    final List selectedSpecs =
        (data['selected_specs'] as List?)?.whereType<Map>().toList() ??
            const [];
    final bool hasSpecs = selectedSpecs.isNotEmpty;
    final String price = hasSpecs
        ? selectedSpecs
            .map((s) => double.tryParse(s['price']?.toString() ?? '') ?? 0)
            .fold(0.0, (a, b) => a + b)
            .toStringAsFixed(2)
        : (data['price']?.toString() ?? '0');
    final String specNames = hasSpecs
        ? selectedSpecs.map((s) => s['name']?.toString() ?? '').join(' + ')
        : '';

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

          // 所选班型规格名称
          if (hasSpecs) ...[
            SizedBox(height: ScreenAdapter.height(12)),
            Text(
              '班型：$specNames',
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(32),
                color: Color(0xFF666666),
              ),
            ),
          ],

          // 已有订单模式:规格名按 spec_ids 拉课程详情得出(仅展示,拉取失败/无规格则隐藏)
          if (!hasSpecs && _isExistingOrder && _existingSpecNames.isNotEmpty) ...[
            SizedBox(height: ScreenAdapter.height(12)),
            Text(
              '班型：$_existingSpecNames',
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(32),
                color: Color(0xFF666666),
              ),
            ),
          ],
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
              if (!hasSpecs &&
                  originalPrice.isNotEmpty &&
                  originalPrice != price) ...[
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

  /// 收货地址选择卡片(点击进入地址列表选择页)
  Widget _buildAddressCard() {
    final addr = _selectedAddress;
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
            '收货地址',
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(38),
              fontWeight: FontWeight.w500,
              color: Color(0xFF333333),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(36)),
          GestureDetector(
            onTap: _pickAddress,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  color: Color(0xFF3D7CFF),
                  size: ScreenAdapter.fontSize(44),
                ),
                SizedBox(width: ScreenAdapter.width(20)),
                Expanded(
                  child: addr == null
                      ? Text(
                          '请选择收货地址',
                          style: TextStyle(
                            fontSize: ScreenAdapter.fontSize(34),
                            color: Color(0xFF999999),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  addr.consignee,
                                  style: TextStyle(
                                    fontSize: ScreenAdapter.fontSize(36),
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF333333),
                                  ),
                                ),
                                SizedBox(width: ScreenAdapter.width(20)),
                                Text(
                                  addr.phone,
                                  style: TextStyle(
                                    fontSize: ScreenAdapter.fontSize(32),
                                    color: Color(0xFF666666),
                                  ),
                                ),
                                if (addr.isDefaultAddress) ...[
                                  SizedBox(width: ScreenAdapter.width(16)),
                                  const AppTag('默认'),
                                ],
                              ],
                            ),
                            SizedBox(height: ScreenAdapter.height(12)),
                            Text(
                              addr.fullAddress,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: ScreenAdapter.fontSize(30),
                                color: Color(0xFF666666),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Color(0xFF999999),
                  size: ScreenAdapter.fontSize(44),
                ),
              ],
            ),
          ),
        ],
      ),
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
                  _isExistingOrder
                      ? '确认支付 \u00A5$price'
                      : '确认购买 \u00A5$price',
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
    if (selectedPayment.isEmpty) {
      SnackbarUtils.showError('请选择支付方式');
      return;
    }

    // ★已有订单模式:收货地址已随订单存储,无需再次选择
    if (!_isExistingOrder) {
      // ★2026-08-18 收货地址必填:未选择时提示并跳转地址选择页
      if (_selectedAddress == null) {
        SnackbarUtils.showWarning('请选择收货地址');
        _pickAddress();
        return;
      }
    }

    _submitPay();
  }

  Future<void> _submitPay() async {
    if (_isPaying) return;

    // ★已有订单模式:直接用订单号支付,跳过 createCourseOrder 下单
    final String? existingOrderSn = _isExistingOrder
        ? (widget.courseData['order_no']?.toString() ?? '')
        : null;
    if (_isExistingOrder &&
        (existingOrderSn == null || existingOrderSn.isEmpty)) {
      SnackbarUtils.showError('订单信息异常');
      return;
    }

    final courseId = widget.courseData['id']?.toString();
    if (!_isExistingOrder && (courseId == null || courseId.isEmpty)) {
      SnackbarUtils.showError('课程信息异常');
      return;
    }

    // ★2026-08-17 规格下单:spec_ids 取所选班型规格(createCourseOrder 必传)
    final List selectedSpecs =
        (widget.courseData['selected_specs'] as List?)?.whereType<Map>().toList() ??
            const [];
    final specIds = selectedSpecs
        .map((s) => s['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (!_isExistingOrder && specIds.isEmpty) {
      SnackbarUtils.showError('请选择班型科目');
      return;
    }

    setState(() {
      _isPaying = true;
    });

    try {
      SnackbarUtils.showInfo('正在发起支付...');

      // 1. 取订单号:已有订单直接用 order_no;否则 createCourseOrder 下单
      String orderSn;
      if (_isExistingOrder) {
        orderSn = existingOrderSn!;
      } else {
        // ★后端文档(2026-08-18):spec_ids 为逗号分隔字符串(非数组,无需 listFormat),
        //   address_id 为顶层参数(收货地址 id,必选)
        final orderResponse = await ApiClient.to.post(
          'addons/exam/pay/createCourseOrder',
          data: {
            'course_id': courseId,
            'spec_ids': specIds.join(','),
            'address_id': _selectedAddress!.id,
          },
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );

        orderSn = _extractOrderSn(orderResponse.data) ?? '';
        if (orderSn.isEmpty) {
          if (mounted) {
            setState(() {
              _isPaying = false;
            });
          }
          final msg = orderResponse.data is Map
              ? (orderResponse.data['msg']?.toString() ?? '')
              : '';
          SnackbarUtils.showError(msg.isNotEmpty ? msg : '创建订单失败');
          return;
        }
      }

      // 2. 支付
      final response = await ApiClient.to.post(
        'addons/exam/pay/coursePay',
        data: {
          'order_sn': orderSn,
          'pay_type': selectedPayment,
          'method': 'app',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      if (response.data != null) {
        final body = response.data;
        final type = selectedPayment;

        if (type == 'alipay') {
          await _doAlipayPay(body);
        } else if (type == 'wechat') {
          await _doWechatPay(body);
        }
      } else {
        if (mounted) {
          setState(() {
            _isPaying = false;
          });
        }
        SnackbarUtils.showError('获取支付参数失败');
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

  /// 提取下单接口返回的订单号(兼容 data.order_sn / 顶层 order_sn / 纯字符串)
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
      // H5 支付:保持 _isPaying=true,返回 App 时由 didChangeAppLifecycleState 兜底确认
      final payUrl = body is Map
          ? body['payUrl']?.toString() ?? body['url']?.toString()
          : null;
      if (payUrl != null && payUrl.isNotEmpty) {
        final uri = Uri.parse(payUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            setState(() {
              _isPaying = false;
            });
          }
          SnackbarUtils.showError('无法打开支付页面');
        }
      } else {
        if (mounted) {
          setState(() {
            _isPaying = false;
          });
        }
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
      // H5 支付:保持 _isPaying=true,返回 App 时由 didChangeAppLifecycleState 兜底确认
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
          if (mounted) {
            setState(() {
              _isPaying = false;
            });
          }
          SnackbarUtils.showError('无法打开支付页面');
        }
      } else {
        if (mounted) {
          setState(() {
            _isPaying = false;
          });
        }
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

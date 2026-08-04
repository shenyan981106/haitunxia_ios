import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dio/dio.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchPayMethods();
  }

  @override
  void dispose() {
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
          onPressed: _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF3D7CFF),
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: ScreenAdapter.height(28)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ScreenAdapter.width(16)),
            ),
            elevation: 0,
          ),
          child: Text(
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
    if (selectedPayment.isEmpty) {
      SnackbarUtils.showError('请选择支付方式');
      return;
    }

    final payMethod = _payMethods.firstWhere(
      (m) => m['code']?.toString() == selectedPayment,
      orElse: () => <String, dynamic>{'name': '默认'},
    );
    final payName = payMethod['name']?.toString() ?? '默认支付';
    SnackbarUtils.showInfo('已选择$payName支付，订单已提交');
  }
}

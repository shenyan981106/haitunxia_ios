import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../services/screenAdapter.dart';
import '../../../components/common_app_bar.dart';
import '../../../components/common_empty_state.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/providers/api_client.dart';
import '../../../data/models/member_package_model.dart';
import '../../../services/snackbar_utils.dart';
import '../controllers/vip_center_controller.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

/// 价格格式化:去掉多余小数位(29.90 → 29.9,19.00 → 19)
String _formatPrice(double value) {
  var text = value.toStringAsFixed(2);
  if (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.0')) {
    text = text.substring(0, text.length - 2);
  }
  return text;
}

class VipCenterView extends GetView<VipCenterController> {
  const VipCenterView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF4FF),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: Obx(() {
                    if (controller.isLoadingPackages.value) {
                      return Padding(
                        padding:
                            EdgeInsets.only(top: ScreenAdapter.height(120)),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF3D7CFF),
                          ),
                        ),
                      );
                    }
                    if (controller.currentTabSpecs.isEmpty) {
                      return Padding(
                        padding:
                            EdgeInsets.only(top: ScreenAdapter.height(120)),
                        child: CommonEmptyState(
                          icon: Icons.card_membership_outlined,
                          title: '暂无会员套餐',
                          titleFontSize: ScreenAdapter.fontSize(30),
                          iconSize: 120,
                        ),
                      );
                    }
                    return ListView(
                      padding: EdgeInsets.symmetric(
                        horizontal: ScreenAdapter.width(30),
                        vertical: ScreenAdapter.height(20),
                      ),
                      children: [
                        _buildDurationPriceSection(),
                        _buildSubjectSection(),
                        SizedBox(height: ScreenAdapter.height(40)),
                        _buildBenefitsTitle(),
                        SizedBox(height: ScreenAdapter.height(30)),
                        _buildBenefitsGrid(),
                        SizedBox(height: ScreenAdapter.height(200)),
                      ],
                    );
                  }),
                ),
              ],
            ),
            _buildBottomPayBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final titleBarHeight = ScreenAdapter.height(112);
    final gapHeight = ScreenAdapter.height(26);
    final backgroundHeight =
        ScreenAdapter.height(520) - titleBarHeight - gapHeight;

    return Column(
      children: [
        CommonAppBar(
          title: '会员中心',
          toolbarHeight: titleBarHeight,
          actions: [SizedBox(width: ScreenAdapter.width(96))],
        ),
        SizedBox(height: gapHeight),
        Container(
          width: double.infinity,
          height: backgroundHeight,
          padding: EdgeInsets.fromLTRB(
            ScreenAdapter.width(20),
            ScreenAdapter.height(20),
            ScreenAdapter.width(20),
            ScreenAdapter.height(20),
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF3D7CFF), Color(0xFF1E5AE0)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(40),
              bottomRight: Radius.circular(40),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildVipInfoCard(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVipInfoCard() {
    return Obx(() {
      final info = AuthService.to.user.value?.toJson();
      final isLoggedIn = AuthService.to.isLoggedIn.value;
      final displayName = isLoggedIn
          ? (info?['nickname']?.toString() ??
              info?['username']?.toString() ??
              '未登录用户')
          : '未登录用户';
      final avatar = info?['avatar']?.toString() ?? '';
      final hasAvatar = avatar.isNotEmpty;
      final relativePath = hasAvatar
          ? avatar
          : 'uploads/20260221/d058aab5aa43767fd921131ae4a9a88e.png';
      final url = ApiClient.getFullImageUrl(relativePath);
      final radius = ScreenAdapter.width(70);
      // 状态:全部科目均已开通才显示"已开通";
      final specs = controller.currentTabSpecs;
      final allOpened = specs.isNotEmpty && specs.every((s) => s.opened);
      final statusText = allOpened ? '已开通科目会员' : '未开通科目会员';

      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: ScreenAdapter.width(30),
          vertical: ScreenAdapter.height(20),
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ScreenAdapter.width(34)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(ScreenAdapter.width(3)),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: CircleAvatar(
                radius: radius,
                backgroundColor: Colors.white,
                backgroundImage: NetworkImage(url),
              ),
            ),
            SizedBox(width: ScreenAdapter.width(28)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: ScreenAdapter.fontSize(50),
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: ScreenAdapter.height(10)),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: ScreenAdapter.fontSize(30),
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  /// 时长价格区域:标题「开通时长」+ 卡片(有效期截止/有效期天数/日均价)
  Widget _buildDurationPriceSection() {
    return Obx(() {
      final pkg = controller.package;
      if (pkg == null) {
        return const SizedBox.shrink();
      }
      final info = controller.packagePriceInfo(pkg);
      final days = pkg.days;
      final expireDate = DateTime.now().add(Duration(days: days));
      final expireText =
          '${expireDate.year}-${expireDate.month.toString().padLeft(2, '0')}-${expireDate.day.toString().padLeft(2, '0')}';
      final perDay = days > 0 ? info.price / days : 0.0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: ScreenAdapter.height(30)),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: ScreenAdapter.width(30),
              vertical: ScreenAdapter.height(30),
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(
                ScreenAdapter.width(24),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: ScreenAdapter.width(60),
                  height: ScreenAdapter.width(60),
                  decoration: const BoxDecoration(
                    color: Color(0xFF3D7CFF),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    color: Colors.white,
                    size: ScreenAdapter.fontSize(36),
                  ),
                ),
                SizedBox(width: ScreenAdapter.width(20)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '开通时长',
                        style: TextStyle(
                          fontSize: ScreenAdapter.fontSize(40),
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF333333),
                        ),
                      ),
                      SizedBox(height: ScreenAdapter.height(16)),
                      Text(
                        '有效期截止：$expireText',
                        style: TextStyle(
                          fontSize: ScreenAdapter.fontSize(30),
                          color: const Color(0xFF666666),
                        ),
                      ),
                      SizedBox(height: ScreenAdapter.height(12)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '有效期时长：$days 日',
                              style: TextStyle(
                                fontSize: ScreenAdapter.fontSize(30),
                                color: const Color(0xFF666666),
                              ),
                            ),
                          ),
                          Text(
                            '${perDay.toStringAsFixed(2)} 元/天',
                            style: TextStyle(
                              fontSize: ScreenAdapter.fontSize(32),
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF3D7CFF),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  /// 选择科目(单科规格,多选):按钮选中态联动
  Widget _buildSubjectSection() {
    return Obx(() {
      final specs = controller.currentTabSpecs;
      if (specs.isEmpty) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: ScreenAdapter.height(40)),
          Text(
            '科目列表',
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(44),
              fontWeight: FontWeight.w500,
              color: const Color(0xFF333333),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(30)),
          Wrap(
            spacing: ScreenAdapter.width(20),
            runSpacing: ScreenAdapter.height(20),
            children: specs.map((s) => _buildSubjectButton(s)).toList(),
          ),
        ],
      );
    });
  }

  Widget _buildSubjectButton(MemberSpec spec) {
    final isSelected = controller.isSpecSelected(spec.name);

    // 已开通的科目:置灰不可选
    if (spec.opened) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: ScreenAdapter.width(36),
          vertical: ScreenAdapter.height(16),
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ScreenAdapter.width(12)),
          border: Border.all(color: const Color(0xFFE0E3E8), width: 1),
        ),
        child: Text(
          spec.name,
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(32),
            color: const Color(0xFFB0B3BA),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => controller.toggleSingleSpec(spec.name),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ScreenAdapter.width(36),
          vertical: ScreenAdapter.height(16),
        ),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3D7CFF) : Colors.white,
          borderRadius: BorderRadius.circular(ScreenAdapter.width(12)),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF3D7CFF) : const Color(0xFFD0D5DD),
            width: 1,
          ),
        ),
        child: Text(
          spec.name,
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(32),
            color: isSelected ? Colors.white : const Color(0xFF3D7CFF),
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// 会员权益标题
  Widget _buildBenefitsTitle() {
    return Text(
      '会员权益',
      style: TextStyle(
        fontSize: ScreenAdapter.fontSize(44),
        fontWeight: FontWeight.w500,
        color: const Color(0xFF333333),
      ),
    );
  }

  /// 会员权益网格(固定死,3列2行)
  Widget _buildBenefitsGrid() {
    final items = [
      _BenefitItem(
        icon: Icons.menu_book,
        iconColor: const Color(0xFF3D7CFF),
        title: '章节练习：',
        subtitle: '享100%题量',
      ),
      _BenefitItem(
        icon: Icons.assignment,
        iconColor: const Color(0xFF3D7CFF),
        title: '模拟题：',
        subtitle: '全真模拟演练',
      ),
      _BenefitItem(
        icon: Icons.auto_stories,
        iconColor: const Color(0xFF3D7CFF),
        title: '历年真题：',
        subtitle: '真题演练',
      ),
      _BenefitItem(
        icon: Icons.verified,
        iconColor: const Color(0xFF3D7CFF),
        title: '每日一练：',
        subtitle: '每天5-10题',
      ),
      _BenefitItem(
        icon: Icons.fact_check,
        iconColor: const Color(0xFF3D7CFF),
        title: '考前点题：',
        subtitle: '考前10天开放',
      ),
      _BenefitItem(
        icon: Icons.dashboard,
        iconColor: const Color(0xFF3D7CFF),
        title: '章节真题：',
        subtitle: '全节真题',
      ),
    ];

    return Container(
      padding: EdgeInsets.all(ScreenAdapter.width(24)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ScreenAdapter.width(24)),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: ScreenAdapter.width(16),
          mainAxisSpacing: ScreenAdapter.height(20),
          childAspectRatio: 1.0,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => items[index],
      ),
    );
  }

  Widget _buildBottomPayBar() {
    return Obx(() {
      if (!controller.hasSelectableSpec) {
        return const SizedBox.shrink();
      }
      return _BottomPayBarWidget(controller: controller);
    });
  }
}

/// 会员权益单项
class _BenefitItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _BenefitItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FF),
        borderRadius: BorderRadius.circular(ScreenAdapter.width(16)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(ScreenAdapter.width(10)),
            decoration: const BoxDecoration(
              color: Color(0xFFE8F0FF),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: ScreenAdapter.fontSize(44),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(12)),
          Text(
            title,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(28),
              fontWeight: FontWeight.w600,
              color: const Color(0xFF333333),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(4)),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(26),
              color: const Color(0xFF666666),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomPayBarWidget extends StatefulWidget {
  final VipCenterController controller;

  const _BottomPayBarWidget({required this.controller});

  @override
  State<_BottomPayBarWidget> createState() => _BottomPayBarWidgetState();
}

class _BottomPayBarWidgetState extends State<_BottomPayBarWidget> {
  bool isExpanded = false;
  bool _agreed = false;

  Widget _buildPayOption({
    required String svgPath,
    required String label,
    required String code,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final double circleSize = ScreenAdapter.width(52);
    final double checkSize = ScreenAdapter.fontSize(30);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: ScreenAdapter.height(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                SvgPicture.asset(
                  svgPath,
                  width: ScreenAdapter.width(44),
                  height: ScreenAdapter.height(44),
                ),
                SizedBox(width: ScreenAdapter.width(20)),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(38),
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF333333),
                  ),
                ),
              ],
            ),
            Container(
              width: circleSize,
              height: circleSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF3D7CFF)
                      : const Color(0xFFCCCCCC),
                  width: 2,
                ),
                color: isSelected ? const Color(0xFF3D7CFF) : Colors.white,
              ),
              child: isSelected
                  ? Icon(Icons.check, size: checkSize, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaySelector() {
    return Obx(() {
      final payMethods =
          widget.controller.payMethods.where((m) => m['status'] == 1).toList();
      final selectedCode = widget.controller.selectedPayCode.value;

      if (payMethods.isEmpty) {
        return const SizedBox.shrink();
      }

      final currentMethod = payMethods.firstWhere(
        (m) => m['code']?.toString() == selectedCode,
        orElse: () => payMethods.first,
      );

      final currentCode = currentMethod['code']?.toString() ?? '';
      final currentName = currentMethod['name']?.toString() ?? '';
      final currentSvg = _getSvgForCode(currentCode);
      final isWechat = currentCode == 'wechat';
      // 仅一种支付方式时(如 iOS 苹果内购)不显示展开箭头与列表
      final singleMethod = payMethods.length == 1;

      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: ScreenAdapter.width(24),
          vertical: ScreenAdapter.height(26),
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(ScreenAdapter.width(20)),
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: () {
                if (singleMethod) return;
                setState(() => isExpanded = !isExpanded);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      SvgPicture.asset(
                        currentSvg,
                        width: ScreenAdapter.width(44),
                        height: ScreenAdapter.height(44),
                      ),
                      SizedBox(width: ScreenAdapter.width(16)),
                      Text(
                        currentName,
                        style: TextStyle(
                          fontSize: ScreenAdapter.fontSize(38),
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF333333),
                        ),
                      ),
                      if (isWechat) ...[
                        SizedBox(width: ScreenAdapter.width(12)),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ScreenAdapter.width(14),
                            vertical: ScreenAdapter.height(6),
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF07C160).withOpacity(0.1),
                            borderRadius:
                                BorderRadius.circular(ScreenAdapter.width(8)),
                          ),
                          child: Text(
                            '推荐',
                            style: TextStyle(
                              fontSize: ScreenAdapter.fontSize(24),
                              color: const Color(0xFF07C160),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (!singleMethod)
                    Row(
                      children: [
                        Text(
                          isExpanded ? '收起' : '更多支付方式',
                          style: TextStyle(
                              fontSize: ScreenAdapter.fontSize(32),
                              color: const Color(0xFF999999)),
                        ),
                        SizedBox(width: ScreenAdapter.width(10)),
                        Icon(
                          isExpanded
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                          size: ScreenAdapter.fontSize(32),
                          color: const Color(0xFF999999),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (isExpanded && !singleMethod) ...[
              SizedBox(height: ScreenAdapter.height(24)),
              Divider(
                  height: 1,
                  color: const Color(0xFFE5E5E5),
                  indent: ScreenAdapter.width(60)),
              SizedBox(height: ScreenAdapter.height(24)),
              ...payMethods.asMap().entries.map((entry) {
                final index = entry.key;
                final method = entry.value;
                final code = method['code']?.toString() ?? '';
                final name = method['name']?.toString() ?? '';
                final svg = _getSvgForCode(code);
                final isSelected = selectedCode == code;
                final isLast = index == payMethods.length - 1;
                return Column(
                  children: [
                    if (index > 0) ...[
                      Divider(
                          height: 1,
                          color: const Color(0xFFE5E5E5),
                          indent: ScreenAdapter.width(60)),
                      SizedBox(height: ScreenAdapter.height(24)),
                    ],
                    _buildPayOption(
                      svgPath: svg,
                      label: name,
                      code: code,
                      isSelected: isSelected,
                      onTap: () {
                        widget.controller.selectPayMethod(code);
                        setState(() => isExpanded = false);
                      },
                    ),
                    if (isLast) SizedBox(height: ScreenAdapter.height(16)),
                  ],
                );
              }),
            ],
          ],
        ),
      );
    });
  }

  String _getSvgForCode(String code) {
    switch (code) {
      case 'wechat':
        return 'assets/fonts/wechat.svg';
      case 'alipay':
        return 'assets/fonts/zhifubao.svg';
      case 'apple':
        return 'assets/fonts/apple.svg';
      default:
        return 'assets/fonts/wechat.svg';
    }
  }

  Widget _buildPriceSection() {
    return Obx(() {
      final pkg = widget.controller.package;
      if (pkg == null) {
        return const SizedBox.shrink();
      }
      final info = widget.controller.packagePriceInfo(pkg);
      final displayPrice = '¥${_formatPrice(info.price)}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: ScreenAdapter.width(20)),
            child: Text(
              displayPrice,
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(64),
                fontWeight: FontWeight.w600,
                color: const Color(0xFF3D7CFF),
              ),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(12)),
          Padding(
            padding: EdgeInsets.only(left: ScreenAdapter.width(20)),
            child: GestureDetector(
              onTap: () => setState(() => _agreed = !_agreed),
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: ScreenAdapter.width(32),
                    height: ScreenAdapter.width(32),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _agreed
                          ? const Color(0xFF3D7CFF)
                          : Colors.transparent,
                      border: Border.all(
                        color: _agreed
                            ? const Color(0xFF3D7CFF)
                            : const Color(0xFFCCCCCC),
                        width: 1.5,
                      ),
                    ),
                    child: _agreed
                        ? Icon(Icons.check,
                            size: ScreenAdapter.fontSize(22),
                            color: Colors.white)
                        : null,
                  ),
                  SizedBox(width: ScreenAdapter.width(12)),
                  Text(
                    '我已阅读并同意',
                    style: TextStyle(
                      fontSize: ScreenAdapter.fontSize(28),
                      color: const Color(0xFF999999),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showServiceAgreementDialog(),
                    child: Text(
                      '《服务协议》',
                      style: TextStyle(
                        fontSize: ScreenAdapter.fontSize(26),
                        color: const Color(0xFF3D7CFF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  /// 服务协议富文本弹窗 - 调用富文本接口，传参 id=8
  void _showServiceAgreementDialog() {
    Get.dialog(
      const _ServiceAgreementDialog(),
      barrierDismissible: true,
    );
  }

  Widget _buildPayButton() {
    return Obx(() {
      final pkg = widget.controller.package;
      var priceText = '';
      if (pkg != null) {
        priceText = _formatPrice(widget.controller.packagePriceInfo(pkg).price);
      }
      return SizedBox(
        width: ScreenAdapter.width(360),
        height: ScreenAdapter.height(110),
        child: ElevatedButton(
          onPressed: () {
            if (!_agreed) {
              SnackbarUtils.showInfo('请先阅读并同意《服务协议》');
              return;
            }
            widget.controller.doPay();
          },
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ScreenAdapter.width(55))),
          ).copyWith(
            backgroundColor: MaterialStateProperty.all(Colors.transparent),
            shadowColor: MaterialStateProperty.all(
                const Color(0xFF3D7CFF).withOpacity(0.4)),
          ),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ScreenAdapter.width(55)),
              gradient: const LinearGradient(
                  colors: [Color(0xFF5B9BFF), Color(0xFF3D7CFF)]),
            ),
            child: Center(
              child: Text(
                priceText.isEmpty ? '立即开通' : '¥$priceText 立即开通',
                style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(36),
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          ScreenAdapter.width(30),
          ScreenAdapter.height(30),
          ScreenAdapter.width(30),
          ScreenAdapter.height(40),
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(ScreenAdapter.width(30))),
          boxShadow: [
            BoxShadow(
                color: Colors.grey.withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: 5,
                offset: const Offset(0, -5))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPaySelector(),
            SizedBox(height: ScreenAdapter.height(28)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _buildPriceSection()),
                SizedBox(width: ScreenAdapter.width(24)),
                _buildPayButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 服务协议富文本弹窗（全屏）
///
/// 调用富文本接口 `common/richtextContent`（id=8）获取 HTML 内容并展示。
class _ServiceAgreementDialog extends StatefulWidget {
  const _ServiceAgreementDialog();

  @override
  State<_ServiceAgreementDialog> createState() =>
      _ServiceAgreementDialogState();
}

class _ServiceAgreementDialogState extends State<_ServiceAgreementDialog> {
  String _content = '';
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fetchContent();
  }

  String? _extractText(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is Map) {
      return _extractText(
        value['content'] ?? value['text'] ?? value['value'],
      );
    }
    return null;
  }

  Future<void> _fetchContent() async {
    try {
      final response = await ApiClient.to.get(
        'addons/exam/common/richtextContent',
        queryParameters: {'id': 8},
      );
      final data = response.data;

      String content = '';
      if (data is String) {
        content = data;
      } else if (data is Map) {
        final candidate =
            data['data'] ?? data['content'] ?? data['text'] ?? data;
        final extracted = _extractText(candidate);
        content = extracted ?? data.toString();
      } else {
        content = data?.toString() ?? '';
      }

      if (!mounted) return;
      setState(() {
        _content = content;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ScreenAdapter.width(30),
                vertical: ScreenAdapter.height(20),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '服务协议',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: ScreenAdapter.fontSize(40),
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF333333),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Get.back(),
                    child: Padding(
                      padding: EdgeInsets.all(ScreenAdapter.width(10)),
                      child: Icon(
                        Icons.close,
                        color: const Color(0xFF999999),
                        size: ScreenAdapter.fontSize(48),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF3D7CFF),
        ),
      );
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Text(
          _error,
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(30),
            color: const Color(0xFF999999),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: ScreenAdapter.width(30),
        vertical: ScreenAdapter.height(30),
      ),
      child: HtmlWidget(
        _content,
        textStyle: TextStyle(
          fontSize: ScreenAdapter.fontSize(30),
          height: 1.6,
          color: const Color(0xFF333333),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../services/screenAdapter.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/providers/api_client.dart';
import '../../../components/common_dialog.dart';
import '../controllers/vip_center_controller.dart';

class VipCenterView extends GetView<VipCenterController> {
  const VipCenterView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: ScreenAdapter.width(30),
                      vertical: ScreenAdapter.height(20),
                    ),
                    children: [
                      _buildPlansSection(),
                      SizedBox(height: ScreenAdapter.height(40)),
                      SizedBox(height: ScreenAdapter.height(180)),
                    ],
                  ),
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
    final backgroundHeight = ScreenAdapter.height(400);
    final cardHeight = ScreenAdapter.height(400);
    final cardWidth = ScreenAdapter.width(1000);
    final headerHeight = backgroundHeight + cardHeight * 0.5;

    return SizedBox(
      height: headerHeight,
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: backgroundHeight,
            padding: EdgeInsets.fromLTRB(
              ScreenAdapter.width(20),
              ScreenAdapter.height(10),
              ScreenAdapter.width(20),
              ScreenAdapter.height(20),
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF151A2F), Color(0xFF11121F)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(ScreenAdapter.width(40)),
                bottomRight: Radius.circular(ScreenAdapter.width(40)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () {
                        Get.back();
                      },
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          '会员中心',
                          style: TextStyle(
                            fontSize: ScreenAdapter.fontSize(46),
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: ScreenAdapter.width(80),
                    ),
                  ],
                ),
                SizedBox(height: ScreenAdapter.height(26)),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: _buildVipInfoCard(),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildVipInfoCard() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF27324A), Color(0xFF1F2638)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(
          ScreenAdapter.width(34),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.35),
            blurRadius: 50,
            spreadRadius: 2,
            offset: Offset(0, ScreenAdapter.height(30)),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: ScreenAdapter.width(36),
            bottom: ScreenAdapter.height(26),
            child: Icon(
              Icons.emoji_events,
              size: ScreenAdapter.width(360),
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ScreenAdapter.width(40),
              vertical: ScreenAdapter.height(36),
            ),
            child: _buildVipInfoContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildVipInfoContent() {
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

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(ScreenAdapter.width(3)),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1B2140),
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
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: ScreenAdapter.height(10)),
              Text(
                '升级会员享额外特权',
                style: TextStyle(
                  fontSize: ScreenAdapter.fontSize(30),
                  color: Colors.white.withOpacity(0.82),
                ),
              ),
              if (_isMember())
                Padding(
                  padding: EdgeInsets.only(top: ScreenAdapter.height(8)),
                  child: Text(
                    '有效期至 ${_getExpireTimeText()}',
                    style: TextStyle(
                      fontSize: ScreenAdapter.fontSize(26),
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isMember() {
    final info = AuthService.to.user.value?.info;
    return info?.status == 1;
  }

  String _getExpireTimeText() {
    final info = AuthService.to.user.value?.info;
    return info?.expireTimeText ?? '';
  }

  Widget _buildPlansSection() {
    return Obx(() {
      final configs = controller.memberConfigs;
      final List<Widget> cards = [];
      final int count = configs.length < 3 ? configs.length : 3;
      for (int i = 0; i < count; i++) {
        if (i > 0) {
          cards.add(SizedBox(width: ScreenAdapter.width(10)));
        }
        cards.add(
          Expanded(
            child: GestureDetector(
              onTap: () => controller.selectPlan(i),
              child: _buildPlanItemFromConfig(
                configs[i],
                isSelected: controller.selectedIndex.value == i,
              ),
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: ScreenAdapter.height(20)),
          Text(
            '会员开通',
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(43),
              fontWeight: FontWeight.w500,
              color: const Color(0xFF333333),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(40)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ScreenAdapter.width(20),
              vertical: ScreenAdapter.height(26),
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(
                ScreenAdapter.width(24),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: cards,
            ),
          ),
        ],
      );
    });
  }

  Widget _buildPlanItemFromConfig(Map<String, dynamic> config,
      {bool isSelected = false}) {
    final tag = config['tag']?.toString() ?? '会员套餐';
    final title = config['title']?.toString() ?? '会员';
    final price = config['price']?.toString() ?? '';
    final desc = config['desc']?.toString() ?? '';
    return _buildPlanItem(
      tag: tag,
      title: title,
      price: price,
      desc: desc,
      isSelected: isSelected,
    );
  }

  Widget _buildPlanItem({
    required String tag,
    required String title,
    required String price,
    required String desc,
    bool isSelected = false,
  }) {
    return Container(
      width: ScreenAdapter.width(280),
      height: ScreenAdapter.height(430),
      padding: EdgeInsets.all(ScreenAdapter.width(16)),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFFBF1E5) : const Color(0xFFF9FAFF),
        borderRadius: BorderRadius.circular(
          ScreenAdapter.width(20),
        ),
        border: Border.all(
          color: isSelected ? const Color(0xFFE89A3C) : const Color(0xFFE5E6EC),
          width: isSelected ? 1.2 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              height: ScreenAdapter.height(60),
              padding: EdgeInsets.symmetric(
                horizontal: ScreenAdapter.width(32),
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF323758), Color(0xFF141621)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(ScreenAdapter.width(20)),
                  bottomRight: Radius.circular(ScreenAdapter.width(20)),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                tag,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ScreenAdapter.fontSize(24),
                  color: Colors.white,
                ),
              ),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(20)),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(40),
              fontWeight: FontWeight.w500,
              color: const Color(0xFF333333),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(8)),
          Text(
            price,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(60),
              fontWeight: FontWeight.w500,
              color: const Color(0xFFE89A3C),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(4)),
          Text(
            desc,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(30),
              color: const Color(0xFF999999),
            ),
          ),
          SizedBox(height: ScreenAdapter.height(4)),
          Text(
            '更多权益',
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(26),
              color: const Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPayBar() {
    return _BottomPayBarWidget(controller: controller);
  }

  /// 确认支付弹窗 - 使用公共弹窗组件
  void _showConfirmDialog() async {
    final configs = controller.memberConfigs;
    String priceInfo = '';
    if (configs.isNotEmpty && controller.selectedIndex.value < configs.length) {
      final selected = configs[controller.selectedIndex.value];
      priceInfo = '${selected["title"] ?? ""} - ${selected["price"] ?? ""}';
    }

    final content =
        '即将使用${controller.selectedPayMethod.value == 0 ? "微信" : "支付宝"}支付\n$priceInfo';

    final confirmed = await CommonDialog.show(
      title: '确认开通',
      content: content,
      confirmText: '立即支付',
      cancelText: '取消',
      barrierDismissible: false,
      confirmColor: const Color(0xFFE89A3C),
    );

    if (confirmed) {
      controller.doPay();
    }
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

  @override
  void initState() {
    super.initState();
    if (widget.controller.selectedPayMethod.value == null) {
      widget.controller.selectPayMethod(0);
    }
  }

  Widget _buildPayOption({
    required String svgPath,
    required String label,
    required int value,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
            width: ScreenAdapter.width(44),
            height: ScreenAdapter.width(44),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF07C160)
                    : const Color(0xFFCCCCCC),
                width: 2,
              ),
              color: isSelected ? const Color(0xFF07C160) : Colors.white,
            ),
            child: isSelected
                ? Icon(Icons.check,
                    size: ScreenAdapter.fontSize(26), color: Colors.white)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPaySelector() {
    return Obx(() {
      final selectedPayMethod = widget.controller.selectedPayMethod.value;
      final isWechat = selectedPayMethod == 0;
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
              onTap: () => setState(() => isExpanded = !isExpanded),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      SvgPicture.asset(
                        isWechat
                            ? 'assets/fonts/wechat.svg'
                            : 'assets/fonts/zhifubao.svg',
                        width: ScreenAdapter.width(44),
                        height: ScreenAdapter.height(44),
                      ),
                      SizedBox(width: ScreenAdapter.width(16)),
                      Text(
                        isWechat ? '微信' : '支付宝',
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
                        isExpanded ? Icons.arrow_downward : Icons.arrow_upward,
                        size: ScreenAdapter.fontSize(32),
                        color: const Color(0xFF999999),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isExpanded) ...[
              SizedBox(height: ScreenAdapter.height(24)),
              Divider(
                  height: 1,
                  color: const Color(0xFFE5E5E5),
                  indent: ScreenAdapter.width(60)),
              SizedBox(height: ScreenAdapter.height(24)),
              _buildPayOption(
                svgPath: 'assets/fonts/wechat.svg',
                label: '微信',
                value: 0,
                isSelected: widget.controller.selectedPayMethod.value == 0,
                onTap: () {
                  widget.controller.selectPayMethod(0);
                  setState(() => isExpanded = false);
                },
              ),
              SizedBox(height: ScreenAdapter.height(24)),
              Divider(
                  height: 1,
                  color: const Color(0xFFE5E5E5),
                  indent: ScreenAdapter.width(60)),
              SizedBox(height: ScreenAdapter.height(24)),
              _buildPayOption(
                svgPath: 'assets/fonts/zhifubao.svg',
                label: '支付宝',
                value: 1,
                isSelected: widget.controller.selectedPayMethod.value == 1,
                onTap: () {
                  widget.controller.selectPayMethod(1);
                  setState(() => isExpanded = false);
                },
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildPriceSection() {
    return Obx(() {
      final configs = widget.controller.memberConfigs;
      final selectedIndex = widget.controller.selectedIndex.value;
      if (configs.isEmpty || selectedIndex >= configs.length) {
        return const SizedBox.shrink();
      }
      final selected = configs[selectedIndex];
      final price = selected['price']?.toString() ?? '';
      final displayPrice = price.startsWith('￥') ? price : '￥$price';
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
                color: const Color(0xFFE89A3C),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildPayButton() {
    return SizedBox(
      width: ScreenAdapter.width(360),
      height: ScreenAdapter.height(110),
      child: ElevatedButton(
        onPressed: () => widget.controller.doPay(),
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ScreenAdapter.width(55))),
        ).copyWith(
          backgroundColor: MaterialStateProperty.all(Colors.transparent),
          shadowColor: MaterialStateProperty.all(
              const Color(0xFFE5C07B).withOpacity(0.4)),
        ),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ScreenAdapter.width(55)),
            gradient: const LinearGradient(
                colors: [Color(0xFFF4D18C), Color(0xFFE6B870)]),
          ),
          child: Center(
            child: Text(
              '立即开通',
              style: TextStyle(
                  fontSize: ScreenAdapter.fontSize(36),
                  fontWeight: FontWeight.w600,
                  color: const Color.fromARGB(255, 255, 255, 255)),
            ),
          ),
        ),
      ),
    );
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

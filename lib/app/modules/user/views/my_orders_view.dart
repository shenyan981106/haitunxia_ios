import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../services/screenAdapter.dart';
import '../../../components/common_empty_state.dart';
import '../../../components/common_app_bar.dart';
import '../../../components/app_tag.dart';
import '../../../components/common_dialog.dart';
import '../../../routes/app_pages.dart';
import '../controllers/my_orders_controller.dart';

class MyOrdersView extends GetView<MyOrdersController> {
  const MyOrdersView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: CommonAppBar(
        title: '我的订单',
        titleStyle: TextStyle(
          fontSize: ScreenAdapter.fontSize(44),
          fontWeight: FontWeight.w500,
          color: const Color(0xFF333333),
        ),
        bottomBorderColor: const Color(0xFFEEEEEE),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(ScreenAdapter.height(90)),
          child: _buildTabBar(),
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.orderList.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final orders = controller.orderList;
        if (orders.isEmpty) {
          return CommonEmptyState(
            icon: Icons.receipt_long_outlined,
            title: controller.currentTabIndex.value == 0
                ? '暂无待支付订单'
                : '暂无已支付订单',
          );
        }

        return RefreshIndicator(
          onRefresh: controller.onRefresh,
          child: ListView.builder(
            padding: EdgeInsets.symmetric(
              horizontal: ScreenAdapter.width(24),
              vertical: ScreenAdapter.height(24),
            ),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return _OrderCard(
                order: order,
                // 仅待支付 Tab 展示操作按钮
                showActions: controller.currentTabIndex.value == 0,
                onPaySuccess: () => controller.getMyOrderList(),
                onCancelOrder: () => controller.cancelOrder(order),
              );
            },
          ),
        );
      }),
    );
  }

  /// 顶部 Tab 栏(待支付 / 已支付)
  Widget _buildTabBar() {
    const titles = ['待支付', '已支付'];
    return Container(
      height: ScreenAdapter.height(90),
      color: Colors.white,
      child: Obx(() => Row(
            children: List.generate(titles.length, (index) {
              final isSelected = controller.currentTabIndex.value == index;
              return Expanded(
                child: GestureDetector(
                  onTap: () => controller.changeTab(index),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: ScreenAdapter.height(4),
                          color: isSelected
                              ? const Color(0xFF3D7CFF)
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Text(
                      titles[index],
                      style: TextStyle(
                        fontSize: ScreenAdapter.fontSize(44),
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? const Color(0xFF3D7CFF)
                            : const Color(0xFF999999),
                      ),
                    ),
                  ),
                ),
              );
            }),
          )),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;

  /// 是否展示操作按钮(仅待支付 Tab)
  final bool showActions;

  /// 支付成功返回后的刷新回调(待支付列表移除该订单)
  final VoidCallback onPaySuccess;

  /// 取消订单回调(弹窗确认后调用)
  final VoidCallback onCancelOrder;

  const _OrderCard({
    required this.order,
    required this.showActions,
    required this.onPaySuccess,
    required this.onCancelOrder,
  });

  @override
  Widget build(BuildContext context) {
    // 从订单中提取课程信息
    final course = order['coures'] as Map<String, dynamic>? ?? {};
    final String title = course['title']?.toString() ?? '';

    // 从 teacher_list 拼接老师名称
    final teacherList = course['teacher_list'] as List? ?? [];
    String teacherName = '知知学堂';
    if (teacherList.isNotEmpty) {
      final names = teacherList
          .map((t) => t['name']?.toString())
          .whereType<String>()
          .toList();
      if (names.isNotEmpty) {
        teacherName = names.join('、');
      }
    }

    // 价格处理:订单金额优先取实付金额(非 0),否则订单 price,再兜底课程价(与 _goPay 一致)
    final double price = _getOrderAmount(order, course);
    final bool isFree = course['is_free'] == 1 || price == 0;

    return GestureDetector(
      onTap: () => Get.toNamed('/order-detail', arguments: order),
      child: Container(
        margin: EdgeInsets.only(bottom: ScreenAdapter.height(24)),
        padding: EdgeInsets.all(ScreenAdapter.width(30)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ScreenAdapter.width(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 职场标签 + 标题
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTag(
                  '职场',
                  bgColor: const Color(0xFFE8F0FF),
                  fontSize: ScreenAdapter.fontSize(42),
                  fontWeight: FontWeight.w500,
                  padding: EdgeInsets.symmetric(
                    horizontal: ScreenAdapter.width(12),
                    vertical: ScreenAdapter.height(4),
                  ),
                ),
                SizedBox(width: ScreenAdapter.width(16)),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: ScreenAdapter.fontSize(46),
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF333333),
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            SizedBox(height: ScreenAdapter.height(24)),

            // 生效时间
            _buildInfoRow(
                '生效时间：',
                order['start_time'] != null
                    ? _formatTimestamp(order['start_time'])
                    : '-'),

            SizedBox(height: ScreenAdapter.height(12)),

            // 授课老师
            _buildInfoRow('授课老师：', teacherName),

            SizedBox(height: ScreenAdapter.height(12)),

            // 课程价格
            _buildInfoRow('课程价格：', '${price.toStringAsFixed(2)} 元'),

            SizedBox(height: ScreenAdapter.height(24)),

            // 分割线
            Divider(height: 1, color: const Color(0xFFF0F0F0)),

            SizedBox(height: ScreenAdapter.height(20)),

            // 底部总计
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '共 1 项，总计：',
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(36),
                    color: const Color(0xFF666666),
                  ),
                ),
                Text(
                  '${price.toStringAsFixed(2)} 元',
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(38),
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFF6B00),
                  ),
                ),
              ],
            ),

            // 待支付操作按钮:去结算 / 取消订单
            if (showActions) ...[
              SizedBox(height: ScreenAdapter.height(20)),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildActionButton(
                    '取消订单',
                    filled: false,
                    onTap: _confirmCancelOrder,
                  ),
                  SizedBox(width: ScreenAdapter.width(20)),
                  _buildActionButton(
                    '去结算',
                    filled: true,
                    onTap: _goPay,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 订单金额取值链:actual_amount(实付)非 0 优先 → 订单 price → 课程价兜底
  double _getOrderAmount(Map<String, dynamic> order, Map<String, dynamic> course) {
    final double actualAmount =
        double.tryParse(order['actual_amount']?.toString() ?? '') ?? 0;
    if (actualAmount != 0) return actualAmount;
    final double orderPrice =
        double.tryParse(order['price']?.toString() ?? '') ?? 0;
    if (orderPrice != 0) return orderPrice;
    return double.tryParse(course['price']?.toString() ?? '0') ?? 0;
  }

  /// 去结算:跳转确认订单页(已有订单模式,直接用 order_no 支付)
  Future<void> _goPay() async {
    final course = order['coures'] as Map<String, dynamic>? ?? {};
    // 订单金额优先取实际支付金额(非 0),否则订单金额,再兜底课程价
    String orderAmount = '';
    final actualAmount = order['actual_amount']?.toString() ?? '';
    final orderPrice = order['price']?.toString() ?? '';
    if (actualAmount.isNotEmpty && (double.tryParse(actualAmount) ?? 0) != 0) {
      orderAmount = actualAmount;
    } else if (orderPrice.isNotEmpty) {
      orderAmount = orderPrice;
    } else {
      orderAmount = course['price']?.toString() ?? '0';
    }
    final args = <String, dynamic>{
      'existing_order': true,
      'order_no': order['order_no']?.toString() ?? '',
      // 课程 id 与购买规格 id 串(逗号分隔),下单页按 spec_ids 拉课程详情展示规格名
      'class_id': course['id']?.toString() ?? order['class_id']?.toString() ?? '',
      'spec_ids': order['spec_ids']?.toString() ?? '',
      // ★规格名(后端 Coures/myList 返回,逗号分隔,如「系统班,精讲班」;无则确认页拉详情兜底)
      'spec_names': order['spec_names']?.toString() ?? '',
      'title': course['title']?.toString() ?? '',
      'price': orderAmount,
      'cover_image_url': course['cover_image_url']?.toString() ??
          course['cover_image']?.toString() ??
          course['image']?.toString() ??
          '',
    };
    // ★Get.toNamed 不带泛型(见 05 坑 10);支付成功返回 true 后刷新列表
    final payResult = await Get.toNamed(Routes.ORDER_CONFIRM, arguments: args);
    if (payResult == true) {
      onPaySuccess();
    }
  }

  /// 取消订单:弹窗确认后调接口
  Future<void> _confirmCancelOrder() async {
    final confirmed = await CommonDialog.show(
      title: '取消订单',
      content: '确定要取消该订单吗?',
      confirmText: '确定',
    );
    if (confirmed) {
      onCancelOrder();
    }
  }

  /// 操作按钮(圆角胶囊:取消订单描边灰底,去结算蓝色实底)
  Widget _buildActionButton(
    String text, {
    required bool filled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ScreenAdapter.width(40),
          vertical: ScreenAdapter.height(16),
        ),
        decoration: BoxDecoration(
          color: filled ? const Color(0xFF3D7CFF) : Colors.white,
          borderRadius: BorderRadius.circular(ScreenAdapter.width(44)),
          border: filled
              ? null
              : Border.all(color: const Color(0xFFCCCCCC), width: 1),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(38),
            fontWeight: FontWeight.w500,
            color: filled ? Colors.white : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: label,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(36),
              color: const Color(0xFF999999),
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(36),
              color: const Color(0xFF666666),
            ),
          ),
        ],
      ),
    );
  }

  /// 将时间戳格式化为 yyyy 年 MM 月 dd 日
  String _formatTimestamp(dynamic timestamp) {
    final int ts = int.tryParse(timestamp.toString()) ?? 0;
    if (ts == 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${dt.year}年${dt.month.toString().padLeft(2, '0')}月${dt.day.toString().padLeft(2, '0')}日';
  }
}

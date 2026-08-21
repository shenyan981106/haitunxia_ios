import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../services/screenAdapter.dart';
import '../../../components/common_empty_state.dart';
import '../../../components/common_app_bar.dart';
import '../../../components/app_tag.dart';
import '../../../data/models/member_right_model.dart';
import '../controllers/member_rights_controller.dart';

class MemberRightsView extends GetView<MemberRightsController> {
  const MemberRightsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: CommonAppBar(
        title: '我的权益',
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
        if (controller.isLoading.value && controller.rightsList.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final rights = controller.rightsList;
        if (rights.isEmpty) {
          return CommonEmptyState(
            icon: Icons.workspace_premium_outlined,
            title: controller.currentTabIndex.value == 0
                ? '暂无生效中的权益'
                : '暂无已失效的权益',
          );
        }

        return RefreshIndicator(
          onRefresh: controller.onRefresh,
          child: ListView.builder(
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(), // 确保即使内容不足也能触发下拉刷新
            padding: EdgeInsets.symmetric(
              horizontal: ScreenAdapter.width(24),
              vertical: ScreenAdapter.height(24),
            ),
            itemCount: rights.length + 1,
            itemBuilder: (context, index) {
              if (index == rights.length) {
                return _buildLoadMoreFooter();
              }
              return _RightCard(right: rights[index]);
            },
          ),
        );
      }),
    );
  }

  /// 顶部 Tab 栏(生效中 / 已失效)
  Widget _buildTabBar() {
    const titles = ['生效中', '已失效'];
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

  Widget _buildLoadMoreFooter() {
    return Obx(() {
      if (controller.isLoadingMore.value) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: ScreenAdapter.height(24)),
          child: Center(
            child: SizedBox(
              width: ScreenAdapter.width(36),
              height: ScreenAdapter.width(36),
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }

      if (!controller.hasMore.value) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: ScreenAdapter.height(24)),
          child: Center(
            child: Text(
              '没有更多了',
              style: TextStyle(
                color: Colors.grey,
                fontSize: ScreenAdapter.fontSize(28),
              ),
            ),
          ),
        );
      }

      return SizedBox(height: ScreenAdapter.height(12));
    });
  }
}

/// 权益记录卡片
class _RightCard extends StatelessWidget {
  final MemberRight right;

  const _RightCard({required this.right});

  @override
  Widget build(BuildContext context) {
    final bool active = right.status == 'active';

    return Container(
      margin: EdgeInsets.only(bottom: ScreenAdapter.height(24)),
      padding: EdgeInsets.all(ScreenAdapter.width(30)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ScreenAdapter.width(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 科目名 + 状态角标
          Row(
            children: [
              Expanded(
                child: Text(
                  right.subjectName.isEmpty ? '全部科目' : right.subjectName,
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(46),
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF333333),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppTag(
                right.statusText.isEmpty
                    ? (active ? '生效中' : '已失效')
                    : right.statusText,
                bgColor:
                    active ? const Color(0xFFE8F0FF) : const Color(0xFFF0F0F0),
                textColor:
                    active ? const Color(0xFF3D7CFF) : const Color(0xFF999999),
                fontSize: ScreenAdapter.fontSize(34),
                fontWeight: FontWeight.w500,
                padding: EdgeInsets.symmetric(
                  horizontal: ScreenAdapter.width(16),
                  vertical: ScreenAdapter.height(6),
                ),
              ),
            ],
          ),

          SizedBox(height: ScreenAdapter.height(20)),

          // 会员配置名 + tag
          Row(
            children: [
              if (right.memberConfigName.isNotEmpty)
                Text(
                  right.memberConfigName,
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(38),
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF666666),
                  ),
                ),
              if (right.tag.isNotEmpty) ...[
                SizedBox(width: ScreenAdapter.width(12)),
                AppTag(
                  right.tag,
                  fontSize: ScreenAdapter.fontSize(28),
                  padding: EdgeInsets.symmetric(
                    horizontal: ScreenAdapter.width(12),
                    vertical: ScreenAdapter.height(4),
                  ),
                ),
              ],
            ],
          ),

          SizedBox(height: ScreenAdapter.height(24)),

          // 有效期 / 开通时间
          _buildInfoRow(
            '有效期：',
            right.isPermanent
                ? '永久有效'
                : (right.expireTimeText.isEmpty ? '-' : right.expireTimeText),
          ),
          SizedBox(height: ScreenAdapter.height(12)),
          _buildInfoRow(
            '开通时间：',
            right.openTimeText.isEmpty ? '-' : right.openTimeText,
          ),
          if (active && right.remainDays > 0) ...[
            SizedBox(height: ScreenAdapter.height(12)),
            _buildInfoRow('剩余天数：', '${right.remainDays} 天'),
          ],
        ],
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
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../services/screenAdapter.dart';
import '../../../components/common_error_state.dart';
import '../../../components/common_empty_state.dart';
import '../../../components/common_app_bar.dart';
import '../../../components/filter_dropdown_button.dart';
import '../controllers/my_favorites_controller.dart';

class MyFavoritesView extends GetView<MyFavoritesController> {
  const MyFavoritesView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CommonAppBar(
        title: '我的收藏',
        toolbarHeight: ScreenAdapter.height(112),
        actions: [SizedBox(width: ScreenAdapter.width(96))],
        bottomBorderColor: const Color(0xFFEEEEEE),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFilterBar(context),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  /// 构建筛选栏
  Widget _buildFilterBar(BuildContext context) {
    return Container(
      height: ScreenAdapter.height(140),
      padding: EdgeInsets.symmetric(
        horizontal: ScreenAdapter.width(40),
        vertical: ScreenAdapter.height(20),
      ),
      decoration: const BoxDecoration(color: Colors.white),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Obx(() => FilterDropdownButton(
                label: controller.currentSortTime.value,
                onTap: () => _showTimeFilterPicker(context),
              )),
          Obx(() => FilterDropdownButton(
                label: controller.currentSortOrder.value,
                onTap: () => _showOrderPicker(context),
              )),
        ],
      ),
    );
  }

  /// 构建主体内容区域
  Widget _buildBody() {
    return Obx(() {
      if (controller.isLoading.value) {
        return Center(
          child: CircularProgressIndicator(
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1890FF)),
          ),
        );
      }

      if (controller.errorMessage.value.isNotEmpty &&
          controller.favoriteGroups.isEmpty) {
        return _buildErrorState();
      }

      if (controller.favoriteGroups.isEmpty) {
        return _buildEmptyState();
      }

      return RefreshIndicator(
        onRefresh: () => controller.onRefresh(),
        color: const Color(0xFF1890FF),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: controller.favoriteGroups.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: Color(0xFFF5F5F5)),
          itemBuilder: (context, index) {
            final group = controller.favoriteGroups[index];
            return _buildListItem(group);
          },
        ),
      );
    });
  }

  /// 构建列表项
  Widget _buildListItem(FavoriteGroup group) {
    return GestureDetector(
      onTap: () => controller.onTapGroup(group),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: ScreenAdapter.height(140),
        padding: EdgeInsets.symmetric(horizontal: ScreenAdapter.width(40)),
        child: Row(
          children: [
            // 左侧蓝色勾选图标
            Container(
              width: ScreenAdapter.width(42),
              height: ScreenAdapter.width(42),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF1890FF),
              ),
              child: Icon(
                Icons.check_rounded,
                size: ScreenAdapter.fontSize(28),
                color: Colors.white,
              ),
            ),
            SizedBox(width: ScreenAdapter.width(24)),

            // 中间分类名称
            Expanded(
              child: Text(
                group.cateName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ScreenAdapter.fontSize(40),
                  color: const Color(0xFF333333),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            // 右侧数量和箭头
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '${group.count}题',
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(30),
                    color: const Color(0xFF999999),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: ScreenAdapter.fontSize(38),
                  color: const Color(0xFFCCCCCC),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return CommonEmptyState(
      icon: Icons.bookmark_border_outlined,
      title: '暂无收藏题目',
      subtitle: '去练习页面收藏你感兴趣的题目',
    );
  }

  /// 错误状态
  Widget _buildErrorState() {
    return CommonErrorState(
      message: controller.errorMessage.value,
      onRetry: () => controller.onRefresh(),
    );
  }

  /// 显示录入时间筛选弹窗
  void _showTimeFilterPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ScreenAdapter.radius(20)),
        ),
        title: const Text('录入时间'),
        content: _buildFilterOptions(
          options: MyFavoritesController.timeOptions,
          currentValue: controller.currentSortTime.value,
          onSelect: (value) {
            controller.selectTime(value);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  /// 显示排序方式筛选弹窗
  void _showOrderPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ScreenAdapter.radius(20)),
        ),
        title: const Text('排序方式'),
        content: _buildFilterOptions(
          options: MyFavoritesController.orderOptions,
          currentValue: controller.currentSortOrder.value,
          onSelect: (value) {
            controller.selectOrder(value);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  /// 构建筛选选项列表
  Widget _buildFilterOptions({
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onSelect,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: options
          .map((option) => _buildOption(
                label: option,
                isSelected: option == currentValue,
                onTap: () => onSelect(option),
              ))
          .toList(),
    );
  }

  /// 构建单个选项
  Widget _buildOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          vertical: ScreenAdapter.height(24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(32),
                color: isSelected
                    ? const Color(0xFF1890FF)
                    : const Color(0xFF333333),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (isSelected) ...[
              SizedBox(width: ScreenAdapter.width(8)),
              const Icon(
                Icons.check,
                color: Color(0xFF1890FF),
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

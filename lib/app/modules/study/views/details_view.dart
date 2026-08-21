import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:dio/dio.dart' as dio_package;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf_render/pdf_render_widgets.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import '../../../services/screenAdapter.dart';
import '../../../data/providers/api_client.dart';
// TODO: 支付对接完成后恢复导入
import '../../../routes/app_pages.dart';
import '../../../components/common_dialog.dart';
import '../controllers/details_controller.dart';
import '../../../services/snackbar_utils.dart';
import '../../../components/customer_service_dialog.dart';
import '../../../components/common_app_bar.dart';

// 单个目录项组件
class CatalogItemWidget extends StatefulWidget {
  final dynamic item;
  final int index;
  final int level;
  final Function(dynamic) onTap;
  final bool isExpanded;
  final int selectedLessonId;
  final VoidCallback? onExpandToggle;

  const CatalogItemWidget({
    Key? key,
    required this.item,
    required this.index,
    required this.level,
    required this.onTap,
    required this.isExpanded,
    required this.selectedLessonId,
    this.onExpandToggle,
  }) : super(key: key);

  @override
  _CatalogItemWidgetState createState() => _CatalogItemWidgetState();
}

class _CatalogItemWidgetState extends State<CatalogItemWidget> {
  @override
  Widget build(BuildContext context) {
    final title = widget.item['title']?.toString() ?? '未知课程';

    final dynamic childrenList =
        widget.item['childlist'] ?? widget.item['children'];
    final bool hasChildren = childrenList is List && childrenList.isNotEmpty;

    // 父级章节：标题 + 右箭头，可展开收起
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 章节标题行
        GestureDetector(
          onTap: () {
            if (hasChildren && widget.onExpandToggle != null) {
              widget.onExpandToggle!();
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            color: Colors.white,
            padding: EdgeInsets.only(
              left: ScreenAdapter.width(32),
              right: ScreenAdapter.width(32),
              top: ScreenAdapter.height(36),
              bottom: ScreenAdapter.height(36),
            ),
            child: Row(
              children: [
                // 标题
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: ScreenAdapter.fontSize(40),
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF333333),
                    ),
                  ),
                ),
                // 右侧箭头
                Icon(Icons.chevron_right,
                    color: Color(0xFFCCCCCC), size: ScreenAdapter.fontSize(34)),
              ],
            ),
          ),
        ),

        // 标题下方浅灰色分割线
        if (widget.isExpanded && hasChildren)
          Container(
            height: 1,
            margin: EdgeInsets.symmetric(
              horizontal: ScreenAdapter.width(20),
            ),
            color: Color(0xFFEEEEEE),
          ),

        // 子级课程列表
        if (widget.isExpanded && hasChildren)
          ..._buildLessonRows(childrenList as List),
      ],
    );
  }

  /// 构建子级课程行列
  List<Widget> _buildLessonRows(List childrenList) {
    return childrenList.asMap().entries.map((entry) {
      return _buildLessonRow(entry.value, entry.key);
    }).toList();
  }

  /// 构建子级课程行：标题 + 上次学习标签 | 视频信息 | 播放按钮
  Widget _buildLessonRow(dynamic item, int index) {
    final lessonTitle = item['title']?.toString() ?? '未知课时';
    final lessonId = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    final isSelected =
        widget.selectedLessonId > 0 && lessonId == widget.selectedLessonId;

    // 类型标签
    final typeStr = item['type_name']?.toString() ??
        item['type']?.toString()?.replaceAll('video', '视频') ??
        '视频';
    final displayType = typeStr == 'video' ? '视频' : typeStr;

    // 学习次数
    final studyCount = item['student_num']?.toString() ?? '0';

    // 上次播放进度（从 progress 对象中读取）
    final progress = item['progress'];
    final lastPlaySeconds =
        int.tryParse(progress?['last_position']?.toString() ?? '0') ?? 0;
    final duration =
        int.tryParse(progress?['duration']?.toString() ?? '0') ?? 0;
    // 学习进度百分比
    final progressPercent = (duration > 0 && lastPlaySeconds > 0)
        ? ((lastPlaySeconds / duration) * 100).toInt()
        : 0;
    final hasProgress = lastPlaySeconds > 0;

    // 是否显示"上次学习"标签（有进度时显示）
    final showLastStudyBadge = hasProgress;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          widget.onTap(item);
        },
        child: Container(
          padding: EdgeInsets.only(
            left: ScreenAdapter.width(32),
            right: ScreenAdapter.width(24),
            top: ScreenAdapter.height(42),
            bottom: ScreenAdapter.height(36),
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFF0F0F0), width: 1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 左侧：标题和信息
              Expanded(
                flex: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 第一行：标题
                    Text(
                      lessonTitle,
                      style: TextStyle(
                        fontSize: ScreenAdapter.fontSize(34),
                        color:
                            isSelected ? Color(0xFF3D7CFF) : Color(0xFF333333),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: ScreenAdapter.height(20)),
                    // 第二行：视频 + 次数 + 进度
                    Row(
                      children: [
                        Text(
                          displayType,
                          style: TextStyle(
                            fontSize: ScreenAdapter.fontSize(26),
                            color: Color(0xFF999999),
                          ),
                        ),
                        SizedBox(width: ScreenAdapter.width(16)),
                        Text(
                          '$studyCount次学习',
                          style: TextStyle(
                            fontSize: ScreenAdapter.fontSize(26),
                            color: Color(0xFF999999),
                          ),
                        ),
                        if (hasProgress && progressPercent > 0) ...[
                          SizedBox(width: ScreenAdapter.width(16)),
                          Text(
                            '已学$progressPercent%',
                            style: TextStyle(
                              fontSize: ScreenAdapter.fontSize(28),
                              color: Color(0xFF999999),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // 右侧：上次学习标签 + 播放按钮
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (showLastStudyBadge)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ScreenAdapter.width(12),
                          vertical: ScreenAdapter.height(4),
                        ),
                        decoration: BoxDecoration(
                          color: Color(0xFF3D7CFF),
                          borderRadius:
                              BorderRadius.circular(ScreenAdapter.width(6)),
                        ),
                        child: Text(
                          '上次学习',
                          style: TextStyle(
                            fontSize: ScreenAdapter.fontSize(20),
                            color: Colors.white,
                          ),
                        ),
                      ),
                    if (showLastStudyBadge)
                      SizedBox(height: ScreenAdapter.height(8)),
                    GestureDetector(
                      onTap: () {
                        widget.onTap(item);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: ScreenAdapter.width(72),
                        height: ScreenAdapter.width(72),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? Color(0xFF3D7CFF)
                                : Color(0xFFCCCCCC),
                            width: ScreenAdapter.width(2),
                          ),
                        ),
                        child: Icon(
                          Icons.play_arrow,
                          size: ScreenAdapter.fontSize(36),
                          color: isSelected
                              ? Color(0xFF3D7CFF)
                              : Color(0xFF999999),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 目录列表容器，管理展开/折叠状态
class _CatalogListContent extends StatefulWidget {
  final List<dynamic> items;
  final Function(dynamic) onItemTap;
  final int selectedLessonId;

  const _CatalogListContent({
    required this.items,
    required this.onItemTap,
    required this.selectedLessonId,
  });

  @override
  State<_CatalogListContent> createState() => _CatalogListContentState();
}

class _CatalogListContentState extends State<_CatalogListContent> {
  int expandedIndex = 0; // 默认第一个展开

  @override
  void didUpdateWidget(covariant _CatalogListContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedLessonId != widget.selectedLessonId) {
      _expandSelectedChapter();
    }
  }

  void _expandSelectedChapter() {
    if (widget.selectedLessonId <= 0) return;

    final selectedChapterIndex =
        widget.items.indexWhere((item) => _containsLesson(item));
    if (selectedChapterIndex >= 0 && selectedChapterIndex != expandedIndex) {
      setState(() => expandedIndex = selectedChapterIndex);
    }
  }

  bool _containsLesson(dynamic item) {
    if (item is! Map) return false;

    final lessonId = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    if (lessonId == widget.selectedLessonId) return true;

    final children = item['childlist'] ?? item['children'];
    if (children is List) {
      return children.any(_containsLesson);
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Center(
        child: Text(
          '暂无相关目录',
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(36),
            color: Color(0xFF999999),
          ),
        ),
      );
    }

    return Container(
      color: Color(0xFFF5F5F5),
      child: ListView.builder(
        padding: EdgeInsets.symmetric(
          horizontal: ScreenAdapter.width(32),
          vertical: ScreenAdapter.height(16),
        ),
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          final isExpanded = index == expandedIndex;
          return Container(
            margin: EdgeInsets.only(bottom: ScreenAdapter.height(16)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ScreenAdapter.width(12)),
            ),
            child: CatalogItemWidget(
              item: widget.items[index],
              index: index,
              level: 0,
              onTap: widget.onItemTap,
              isExpanded: isExpanded,
              selectedLessonId: widget.selectedLessonId,
              onExpandToggle: () {
                setState(() {
                  if (isExpanded) {
                    expandedIndex = -1;
                  } else {
                    expandedIndex = index;
                  }
                });
              },
            ),
          );
        },
      ),
    );
  }
}

class DetailsView extends GetView<DetailsController> {
  DetailsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 强制注册控制器，以防路由跳转时丢控制器
    if (!Get.isRegistered<DetailsController>()) {
      Get.put(DetailsController());
    }

    return Obx(() {
      return Scaffold(
        backgroundColor:
            controller.isFullScreen.value ? Colors.black : Colors.white,
        appBar: controller.isFullScreen.value
            ? null
            : CommonAppBar(
                title: '学习目录',
                titleStyle: TextStyle(
                  fontSize: ScreenAdapter.fontSize(46),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF333333),
                ),
              ),
        body: Obx(() {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }

          if (controller.courseDetail.isEmpty) {
            return const Center(child: Text("加载失败或数据为空"));
          }

          if (controller.isFullScreen.value) {
            return _buildFullScreenPlayer(context);
          }

          return Column(
            children: [
              _buildVideoHeader(),
              Expanded(
                child: Container(
                  color: Colors.white,
                  child: Column(
                    children: [
                      // ★2026-08-17 改版:Tab 栏(介绍/目录/资料)注释隐藏,后续如需恢复取消注释即可
                      // _buildTabs(),
                      Expanded(
                        child: Obx(() {
                          // ★改版:Tab 内容区替换为新的课程信息页(标题/价格/有效期/总课时/教研团队/课程说明)
                          // 旧 Tab 内容(介绍/目录/资料)方法保留在文件中,恢复 Tab 后改回即可
                          return _buildCourseInfoPage();
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              _buildBottomButton(context),
            ],
          );
        }),
      );
    });
  }

  Widget _buildTabs() {
    final selectedIndex = controller.currentTabIndex.value;
    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
        ),
      ),
      child: Row(
        children: [
          _buildTabOption('介绍', 0, selectedIndex == 0),
          _buildTabOption('目录', 1, selectedIndex == 1),
          _buildTabOption('资料', 2, selectedIndex == 2),
        ],
      ),
    );
  }

  Widget _buildTabOption(String text, int index, bool selected,
      {String? suffix}) {
    final label = suffix != null && suffix.isNotEmpty ? '$text $suffix' : text;
    final textStyle = TextStyle(
      fontSize: ScreenAdapter.fontSize(40),
      fontWeight: selected ? FontWeight.w500 : FontWeight.w500,
      color: selected ? Color(0xFF333333) : Color(0xFF999999),
    );

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => controller.switchTab(index),
        child: SizedBox(
          height: ScreenAdapter.height(120),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textSpan = TextSpan(text: label, style: textStyle);
              final painter =
                  TextPainter(text: textSpan, textDirection: TextDirection.ltr)
                    ..layout();
              final textWidth = painter.width;
              painter.dispose();
              final lineLeft = (constraints.maxWidth - textWidth) / 2;

              return Stack(
                children: [
                  Center(child: Text(label, style: textStyle)),
                  if (selected)
                    Positioned(
                      left: lineLeft,
                      bottom: 0,
                      width: textWidth,
                      height: ScreenAdapter.height(3),
                      child: Container(color: Color(0xFF3D7CFF)),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 2026-08-17 改版:课程信息页(替代原 Tab 内容区)
  /// 顺序:标题 → 价格 → 课程有效期/总课时 → 教研团队(横向滚动) → 课程说明(富文本)
  Widget _buildCourseInfoPage() {
    final detail = controller.courseDetail;
    final String title = detail['title']?.toString() ?? '';
    final String description = detail['description']?.toString() ??
        detail['intro']?.toString() ??
        detail['content']?.toString() ??
        '';
    final bool isFree = detail['is_free']?.toString() == '1';
    final String price = isFree ? '免费' : '${detail['price']}';
    final String originalPrice = detail['original_price']?.toString() ?? '';

    // 课程有效期:优先 study_period_text,其次 service_end_date,兜底 study_period 天数换算
    final String studyPeriodText =
        (detail['study_period_text']?.toString() ?? '').trim();
    final String serviceEndDate =
        (detail['service_end_date']?.toString() ?? '').trim();
    final String studyPeriod = studyPeriodText.isNotEmpty
        ? studyPeriodText
        : (serviceEndDate.isNotEmpty
            ? serviceEndDate
            : _formatStudyPeriod(detail['study_period']));
    // 总课时
    final String totalLessons =
        (detail['total_lessons']?.toString() ?? '').trim();
    // 教研团队
    final List teacherList = (detail['teacher_list'] as List?) ?? const [];

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: ScreenAdapter.width(32),
        vertical: ScreenAdapter.height(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 课程标题
          if (title.isNotEmpty) ...[
            Text(
              title,
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(44),
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
            ),
            SizedBox(height: ScreenAdapter.height(16)),
          ],

          // 价格展示(红色字体)
          if (isFree)
            Text(
              price,
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(36),
                fontWeight: FontWeight.w500,
                color: Color(0xFFFF4D4F),
              ),
            )
          else
            Row(
              children: [
                Text(
                  '¥$price',
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(48),
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFF4D4F),
                  ),
                ),
                if (originalPrice.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(left: ScreenAdapter.width(16)),
                    child: Text(
                      '¥$originalPrice',
                      style: TextStyle(
                        fontSize: ScreenAdapter.fontSize(28),
                        color: Color(0xFF999999),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ),
              ],
            ),

          // 课程有效期 + 总课时(接口动态取值)
          if (studyPeriod.isNotEmpty || totalLessons.isNotEmpty) ...[
            SizedBox(height: ScreenAdapter.height(24)),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: ScreenAdapter.width(32),
                vertical: ScreenAdapter.height(28),
              ),
              decoration: BoxDecoration(
                color: Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(ScreenAdapter.width(16)),
              ),
              child: Column(
                children: [
                  if (studyPeriod.isNotEmpty) ...[
                    _buildInfoLine('课程有效期', studyPeriod),
                    if (totalLessons.isNotEmpty)
                      SizedBox(height: ScreenAdapter.height(20)),
                  ],
                  if (totalLessons.isNotEmpty)
                    _buildInfoLine('总课时', '$totalLessons课时'),
                ],
              ),
            ),
          ],

          // 分隔横线
          if (teacherList.isNotEmpty || description.isNotEmpty)
            Container(
              height: 1,
              color: Color(0xFFEEEEEE),
              margin: EdgeInsets.symmetric(vertical: ScreenAdapter.height(32)),
            ),

          // 教研团队(横向滚动列表:头像 + 姓名)
          if (teacherList.isNotEmpty) ...[
            _buildCourseSectionTitle('教研团队'),
            SizedBox(height: ScreenAdapter.height(28)),
            SizedBox(
              height: ScreenAdapter.height(230),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: teacherList.length,
                separatorBuilder: (_, __) =>
                    SizedBox(width: ScreenAdapter.width(48)),
                itemBuilder: (context, index) {
                  final teacher = teacherList[index];
                  if (teacher is! Map) return const SizedBox.shrink();
                  return Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Color(0xFFE8E8E8), width: 1.5),
                        ),
                        child: CircleAvatar(
                          radius: ScreenAdapter.width(64),
                          backgroundImage: NetworkImage(
                              ApiClient.replaceUri(
                                  teacher['avatar']?.toString() ?? '')),
                          onBackgroundImageError: (e, s) {},
                          backgroundColor: Color(0xFFF0F0F0),
                        ),
                      ),
                      SizedBox(height: ScreenAdapter.height(12)),
                      Text(
                        teacher['name']?.toString() ?? '',
                        style: TextStyle(
                          fontSize: ScreenAdapter.fontSize(28),
                          color: Color(0xFF333333),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (description.isNotEmpty) SizedBox(height: ScreenAdapter.height(32)),
          ],

          // 课程说明(富文本)
          if (description.isNotEmpty) ...[
            _buildCourseSectionTitle('课程说明'),
            SizedBox(height: ScreenAdapter.height(20)),
            HtmlWidget(
              description,
              textStyle: TextStyle(
                fontSize: ScreenAdapter.fontSize(30),
                color: Color(0xFF666666),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 课程有效期天数换算(study_period 单位为天;0=永久;整除 365 显示"X年")
  String _formatStudyPeriod(dynamic days) {
    final v = int.tryParse(days?.toString() ?? '');
    if (v == null || v <= 0) return '';
    if (v % 365 == 0) return '${v ~/ 365}年';
    return '$v天';
  }

  /// 区块标题(左侧蓝竖线装饰,与"课程说明"样式一致)
  Widget _buildCourseSectionTitle(String text) {
    return Container(
      margin: EdgeInsets.only(bottom: ScreenAdapter.height(16)),
      child: Row(
        children: [
          Container(
            width: ScreenAdapter.width(6),
            height: ScreenAdapter.height(40),
            decoration: BoxDecoration(
              color: Color(0xFF3D7CFF),
              borderRadius: BorderRadius.circular(ScreenAdapter.width(3)),
            ),
          ),
          SizedBox(width: ScreenAdapter.width(16)),
          Text(
            text,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(44),
              color: Color(0xFF333333),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 信息行:左侧灰色标签 + 右侧黑色值
  Widget _buildInfoLine(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(32),
            color: Color(0xFF999999),
          ),
        ),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(32),
                color: Color(0xFF333333),
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  /// 底部按钮：免费显示"立即订阅"，付费显示"立即购买"
  /// 已购买/已订阅时不显示底部区域
  Widget _buildBottomButton(BuildContext context) {
    final detail = controller.courseDetail;
    final bool isPay =
        detail['is_pay']?.toString() == '1' || detail['is_pay'] == true;

    if (isPay) {
      return SizedBox.shrink();
    }

    final bool isFree = detail['is_free']?.toString() == '1';
    // 课程无 VIP 免购逻辑:免费课订阅,付费课购买
    final String buttonText = isFree ? '立即订阅' : '立即购买';
    final String disabledText = isFree ? '已订阅' : '已购买';
    final String price = isFree ? '免费' : '${detail['price']}';
    final String originalPrice = detail['original_price']?.toString() ?? '';

    return SafeArea(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          left: ScreenAdapter.width(32),
          right: ScreenAdapter.width(32),
          top: ScreenAdapter.height(20),
          bottom: ScreenAdapter.height(40),
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: ScreenAdapter.width(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isFree)
                      Text(
                        price,
                        style: TextStyle(
                          fontSize: ScreenAdapter.fontSize(36),
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF333333),
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '¥$price',
                            style: TextStyle(
                              fontSize: ScreenAdapter.fontSize(60),
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFE6B870),
                            ),
                          ),
                          if (originalPrice.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(
                                  left: ScreenAdapter.width(20)),
                              child: Text(
                                '¥$originalPrice',
                                style: TextStyle(
                                  fontSize: ScreenAdapter.fontSize(34),
                                  color: Color(0xFF999999),
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(width: ScreenAdapter.width(24)),
            GestureDetector(
              onTap: isPay
                  ? null
                  : () async {
                      if (isFree) {
                        final confirmed = await CommonDialog.show(
                          title: '提示',
                          content: '确定要订阅该课程吗？',
                          confirmText: '确认',
                          cancelText: '取消',
                        );
                        if (!confirmed) return;

                        final courseId = detail['id']?.toString();
                        if (courseId != null && courseId.isNotEmpty) {
                          try {
                            final response = await ApiClient.to.exam(
                              'pay/redeem',
                              method: 'POST',
                              data: {'course_id': courseId},
                            );
                            if (response.statusCode == 200) {
                              final data = response.data;
                              if (data is Map &&
                                  (data['code'] == 1 || data['code'] == 200)) {
                                SnackbarUtils.showSuccess('订阅成功');
                                controller.getCourseDetail(
                                  int.tryParse(courseId) ?? 0,
                                );
                              } else {
                                SnackbarUtils.showError(
                                    data['msg']?.toString() ?? '订阅失败');
                              }
                            } else {
                              SnackbarUtils.showError('订阅失败');
                            }
                          } catch (e) {
                            SnackbarUtils.showError('订阅失败：$e');
                          }
                        }
                        return;
                      }
                      // 付费课程先弹出规格选择弹窗
                      _showCourseSpecSheet(context);
                    },
              child: Transform.translate(
                offset:
                    Offset(-ScreenAdapter.width(6), ScreenAdapter.height(0)),
                child: Container(
                  width: ScreenAdapter.width(320),
                  height: ScreenAdapter.height(108),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isPay ? Color(0xFFCCCCCC) : Color(0xFFFFB366),
                    borderRadius:
                        BorderRadius.circular(ScreenAdapter.width(64)),
                  ),
                  child: Text(
                    isPay ? disabledText : buttonText,
                    style: TextStyle(
                      fontSize: ScreenAdapter.fontSize(38),
                      fontWeight: FontWeight.w500,
                      color: isPay ? Color(0xFF999999) : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示课程规格选择弹窗（班级种类 / 选择科目）
  void _showCourseSpecSheet(BuildContext context) {
    final detail = controller.courseDetail;
    final String coverImage = detail['cover_image_url']?.toString() ??
        detail['cover_image']?.toString() ??
        '';
    final String title = detail['title']?.toString() ?? '课程名称';
    final String originalPrice = detail['original_price']?.toString() ?? '';

    // ★2026-08-17 改版:班级种类/科目选项全部取接口活数据。
    // 兼容两种返回结构:
    //  ①新结构:class_types=[{key,name,spec_count}] + specs={班型key:[规格...]} + default_spec_id
    //  ②当前 app 端结构:specs 为扁平数组(规格含 type/type_text),无 class_types/default_spec_id
    //    → 班型列表由 specs 按 type 去重推导
    final List classTypes = (detail['class_types'] as List?) ?? const [];
    final List flatSpecs = detail['specs'] is List
        ? (detail['specs'] as List).whereType<Map>().toList()
        : const [];
    final Map<String, dynamic> specsByType = detail['specs'] is Map
        ? Map<String, dynamic>.from(detail['specs'] as Map)
        : <String, dynamic>{};
    // 无 class_types 时按规格 type 去重推导班型列表
    final List effectiveClassTypes = classTypes.isNotEmpty
        ? classTypes
        : () {
            final seen = <String>{};
            final result = <Map<String, dynamic>>[];
            for (final s in flatSpecs) {
              final type = s['type']?.toString() ?? '';
              if (type.isEmpty || seen.contains(type)) continue;
              seen.add(type);
              result.add({
                'key': type,
                'name': s['type_text']?.toString() ?? type,
                'spec_count': flatSpecs
                    .where((x) => x['type']?.toString() == type)
                    .length,
              });
            }
            return result;
          }();
    final int defaultSpecId =
        int.tryParse(detail['default_spec_id']?.toString() ?? '') ?? 0;

    // 预选:default_spec_id(新结构)定位科目与所属班级种类;无则默认选第一个科目
    // ★科目选中集:单科班(course_count=1)可多选,全科班(course_count>1)单选
    int selectedClassIndex = 0;
    final Set<int> selectedSubjectIndexes = <int>{};
    if (defaultSpecId > 0) {
      for (var i = 0; i < effectiveClassTypes.length; i++) {
        final ct = effectiveClassTypes[i];
        final key = ct is Map ? ct['key']?.toString() : '';
        if (key == null || key.isEmpty) continue;
        List list = specsByType[key] is List
            ? (specsByType[key] as List)
            : const [];
        if (list.isEmpty) {
          list = flatSpecs
              .where((s) => s['type']?.toString() == key)
              .toList();
        }
        final idx = list.indexWhere((s) =>
            s is Map &&
            (int.tryParse(s['id']?.toString() ?? '') ?? 0) == defaultSpecId);
        if (idx >= 0) {
          selectedClassIndex = i;
          selectedSubjectIndexes.add(idx);
          break;
        }
      }
    }
    if (selectedSubjectIndexes.isEmpty) {
      // 默认选中第一个班型的第一个科目
      selectedSubjectIndexes.add(0);
    }

    Get.bottomSheet(
      StatefulBuilder(
        builder: (context, setState) {
          // 当前班级种类(选中项)与对应的科目规格列表
          final currentClassType = effectiveClassTypes.isNotEmpty &&
                  selectedClassIndex < effectiveClassTypes.length
              ? effectiveClassTypes[selectedClassIndex]
              : null;
          final String currentClassKey = currentClassType is Map
              ? (currentClassType['key']?.toString() ?? '')
              : '';
          final List currentSpecs = specsByType[currentClassKey] is List
              ? (specsByType[currentClassKey] as List)
              : flatSpecs
                  .where((s) => s['type']?.toString() == currentClassKey)
                  .toList();
          // 单科班(course_count==1)科目可多选;全科班(course_count>1)单选
          final bool isSingleSubjectMulti = currentSpecs.isNotEmpty &&
              (int.tryParse(currentSpecs.first['course_count']?.toString() ?? '') ??
                      1) ==
                  1;
          // ★选中科目总价 = Σ 所选规格 price(多选自动累加,随选中联动刷新)
          final String selectedTotalPrice = currentSpecs
              .asMap()
              .entries
              .where((e) => selectedSubjectIndexes.contains(e.key))
              .map((e) => e.value)
              .whereType<Map>()
              .map((s) => double.tryParse(s['price']?.toString() ?? '') ?? 0)
              .fold(0.0, (a, b) => a + b)
              .toStringAsFixed(2);

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(ScreenAdapter.width(32)),
                topRight: Radius.circular(ScreenAdapter.width(32)),
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ScreenAdapter.width(44),
                    vertical: ScreenAdapter.height(44),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 头部：封面 + 价格 + 关闭
                      Stack(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                    ScreenAdapter.width(16)),
                                child: Container(
                                  width: ScreenAdapter.width(300),
                                  height: ScreenAdapter.width(225),
                                  color: Color(0xFFF5F5F5),
                                  child: coverImage.isNotEmpty
                                      ? Image.network(
                                          ApiClient.replaceUri(coverImage),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _buildDefaultCover(),
                                        )
                                      : _buildDefaultCover(),
                                ),
                              ),
                              SizedBox(width: ScreenAdapter.width(32)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(height: ScreenAdapter.height(12)),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          '¥$selectedTotalPrice',
                                          style: TextStyle(
                                            fontSize:
                                                ScreenAdapter.fontSize(64),
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFFF4D4F),
                                          ),
                                        ),
                                        if (originalPrice.isNotEmpty) ...[
                                          SizedBox(
                                              width: ScreenAdapter.width(16)),
                                          Text(
                                            '¥$originalPrice',
                                            style: TextStyle(
                                              fontSize:
                                                  ScreenAdapter.fontSize(32),
                                              color: Color(0xFF999999),
                                              decoration:
                                                  TextDecoration.lineThrough,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    SizedBox(height: ScreenAdapter.height(16)),
                                    Text(
                                      title,
                                      style: TextStyle(
                                        fontSize: ScreenAdapter.fontSize(38),
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF333333),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: GestureDetector(
                              onTap: () => Get.back(),
                              behavior: HitTestBehavior.opaque,
                              child: Icon(
                                Icons.close,
                                color: Color(0xFF999999),
                                size: ScreenAdapter.fontSize(52),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: ScreenAdapter.height(56)),

                      // 班级种类(接口 class_types / specs 推导,动态渲染,单选)
                      if (effectiveClassTypes.isNotEmpty) ...[
                        _buildSpecSectionTitle('班级种类', '（任选单一科目，包含多种班级）'),
                        SizedBox(height: ScreenAdapter.height(28)),
                        Wrap(
                          spacing: ScreenAdapter.width(24),
                          runSpacing: ScreenAdapter.height(24),
                          children: effectiveClassTypes.asMap().entries.map((entry) {
                            final index = entry.key;
                            final ct = entry.value;
                            final label =
                                ct is Map ? (ct['name']?.toString() ?? '') : '';
                            final selected = index == selectedClassIndex;
                            return _buildSpecOption(
                              label: label,
                              selected: selected,
                              onTap: () => setState(() {
                                selectedClassIndex = index;
                                // 切换班级种类后科目选中重置(默认选第一个)
                                selectedSubjectIndexes
                                  ..clear()
                                  ..add(0);
                              }),
                            );
                          }).toList(),
                        ),
                        SizedBox(height: ScreenAdapter.height(48)),
                      ],

                      // 选择科目(接口 specs[当前班级种类] 动态渲染;单科班可多选,全科班单选)
                      if (currentSpecs.isNotEmpty) ...[
                        _buildSpecSectionTitle(
                          '选择科目',
                          isSingleSubjectMulti ? '（可多选）' : '（单选）',
                        ),
                        SizedBox(height: ScreenAdapter.height(28)),
                        Wrap(
                          spacing: ScreenAdapter.width(24),
                          runSpacing: ScreenAdapter.height(24),
                          children: currentSpecs.asMap().entries.map((entry) {
                            final index = entry.key;
                            final spec = entry.value;
                            final label = spec is Map
                                ? (spec['name']?.toString() ?? '')
                                : '';
                            final selected =
                                selectedSubjectIndexes.contains(index);
                            return _buildSpecOption(
                              label: label,
                              selected: selected,
                              onTap: () => setState(() {
                                if (isSingleSubjectMulti) {
                                  // 单科班:多选,点击切换选中/取消
                                  if (!selectedSubjectIndexes.add(index)) {
                                    selectedSubjectIndexes.remove(index);
                                  }
                                } else {
                                  // 全科班:单选
                                  selectedSubjectIndexes
                                    ..clear()
                                    ..add(index);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                        SizedBox(height: ScreenAdapter.height(56)),
                      ],

                      // 确定按钮
                      GestureDetector(
                        onTap: () async {
                          // 收集选中的科目规格(单科班可多选,全科班单选;当前班型有科目数据时必须至少选一个)
                          final List selectedSpecs = currentSpecs
                              .asMap()
                              .entries
                              .where((e) =>
                                  selectedSubjectIndexes.contains(e.key))
                              .map((e) => e.value)
                              .toList();
                          if (currentSpecs.isNotEmpty &&
                              selectedSpecs.isEmpty) {
                            SnackbarUtils.showError('请选择科目');
                            return;
                          }
                          Get.back();
                          // 携带所选规格信息给下单页(名称/价格/spec_id 由下单接口 createCourseOrder 使用)
                          final args = Map<String, dynamic>.from(detail);
                          if (selectedSpecs.isNotEmpty) {
                            args['selected_specs'] = selectedSpecs;
                          }
                          // 支付结果确认:下单页成功返回 true 后重拉课程详情,刷新已购状态
                          // ★Get.toNamed 不带泛型:带泛型(bool)时 Flutter 内部
                          // `as Route<T?>` 会把 GetPageRoute<dynamic> cast 失败抛 TypeError,路由不跳转
                          final payResult = await Get.toNamed(
                            Routes.ORDER_CONFIRM,
                            arguments: args,
                          );
                          if (payResult == true) {
                            final courseId = args['id']?.toString();
                            if (courseId != null && courseId.isNotEmpty) {
                              controller.getCourseDetail(
                                int.tryParse(courseId) ?? 0,
                              );
                            }
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          height: ScreenAdapter.height(108),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFFFF7A45),
                                Color(0xFFFF4D4F),
                              ],
                            ),
                            borderRadius:
                                BorderRadius.circular(ScreenAdapter.width(64)),
                          ),
                          child: Text(
                            '确定',
                            style: TextStyle(
                              fontSize: ScreenAdapter.fontSize(40),
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  Widget _buildSpecSectionTitle(String title, [String? subtitle]) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(40),
            fontWeight: FontWeight.w500,
            color: Color(0xFF333333),
          ),
        ),
        if (subtitle != null && subtitle.isNotEmpty)
          Text(
            subtitle,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(28),
              color: Color(0xFF999999),
            ),
          ),
      ],
    );
  }

  Widget _buildSpecOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ScreenAdapter.width(28),
          vertical: ScreenAdapter.height(20),
        ),
        decoration: BoxDecoration(
          color: selected ? Color(0xFFFFF2F0) : Colors.white,
          border: Border.all(
            color: selected ? Color(0xFFFF4D4F) : Color(0xFFEEEEEE),
            width: ScreenAdapter.width(2),
          ),
          borderRadius: BorderRadius.circular(ScreenAdapter.width(10)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(32),
            color: selected ? Color(0xFFFF4D4F) : Color(0xFF333333),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecTag(String text, {required bool filled}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ScreenAdapter.width(8),
        vertical: ScreenAdapter.height(4),
      ),
      decoration: BoxDecoration(
        color: filled ? Color(0xFFFF4D4F) : Colors.transparent,
        border: Border.all(
          color: Color(0xFFFF4D4F),
          width: ScreenAdapter.width(1.5),
        ),
        borderRadius: BorderRadius.circular(ScreenAdapter.width(4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: ScreenAdapter.fontSize(22),
          color: filled ? Colors.white : Color(0xFFFF4D4F),
        ),
      ),
    );
  }

  /// 显示购买弹窗（含收货信息 + 支付方式选择）
  void _showPurchaseDialog(BuildContext context) {
    String selectedPayment = 'wechat'; // 默认微信支付
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ScreenAdapter.width(28)),
              ),
              child: Container(
                width: ScreenAdapter.width(1100),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(ScreenAdapter.width(28)),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: ScreenAdapter.width(40),
                  vertical: ScreenAdapter.height(40),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题
                    Text(
                      '兑换收货信息',
                      style: TextStyle(
                        fontSize: ScreenAdapter.fontSize(40),
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF333333),
                      ),
                    ),
                    SizedBox(height: ScreenAdapter.height(40)),

                    // 收货人
                    _buildInfoInputRow('收货人', nameController),
                    SizedBox(height: ScreenAdapter.height(48)),

                    // 手机号码
                    _buildInfoInputRow('手机号码', phoneController,
                        keyboardType: TextInputType.phone),
                    SizedBox(height: ScreenAdapter.height(48)),

                    // 收货地址
                    _buildInfoInputRow('收货地址', addressController),
                    SizedBox(height: ScreenAdapter.height(48)),

                    // 支付方式选择
                    _buildPaymentSelector(selectedPayment, (value) {
                      setState(() => selectedPayment = value);
                    }),
                    SizedBox(height: ScreenAdapter.height(40)),

                    // 按钮行
                    Row(
                      children: [
                        // 取消按钮
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Color(0xFF3D7CFF),
                              side: BorderSide(
                                  color: Color(0xFF3D7CFF), width: 1),
                              padding: EdgeInsets.symmetric(
                                vertical: ScreenAdapter.height(24),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    ScreenAdapter.width(8)),
                              ),
                            ),
                            child: Text(
                              '取消',
                              style: TextStyle(
                                fontSize: ScreenAdapter.fontSize(30),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: ScreenAdapter.width(24)),
                        // 确认购买按钮
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              String paymentName =
                                  selectedPayment == 'wechat' ? '微信' : '支付宝';
                              SnackbarUtils.showInfo('已选择$paymentName支付');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF3D7CFF),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                vertical: ScreenAdapter.height(24),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    ScreenAdapter.width(8)),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              '确认购买',
                              style: TextStyle(
                                fontSize: ScreenAdapter.fontSize(30),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 信息行组件
  Widget _buildInfoRowItem(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: ScreenAdapter.width(160),
          child: Text(
            label,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(34),
              color: Color(0xFF666666),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(34),
              color: Color(0xFF333333),
            ),
          ),
        ),
      ],
    );
  }

  /// 可输入信息行组件
  Widget _buildInfoInputRow(String label, TextEditingController controller,
      {TextInputType keyboardType = TextInputType.text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: ScreenAdapter.width(160),
          child: Text(
            label,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(34),
              color: Color(0xFF333333),
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(32),
              color: Color(0xFF333333),
            ),
            decoration: InputDecoration(
              isDense: true,
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

  /// 支付方式选择组件
  Widget _buildPaymentSelector(
      String selectedValue, ValueChanged<String> onChanged) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '支付方式',
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(34),
            color: Color(0xFF333333),
          ),
        ),
        SizedBox(width: ScreenAdapter.width(80)),
        // 微信支付
        _buildPaymentOption(
          svgPath: 'assets/fonts/wechat.svg',
          label: '微信',
          isSelected: selectedValue == 'wechat',
          onTap: () => onChanged('wechat'),
        ),
        SizedBox(width: ScreenAdapter.width(24)),
        // 支付宝支付
        _buildPaymentOption(
          svgPath: 'assets/fonts/zhifubao.svg',
          label: '支付宝',
          isSelected: selectedValue == 'alipay',
          onTap: () => onChanged('alipay'),
        ),
      ],
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
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ScreenAdapter.width(28),
          vertical: ScreenAdapter.height(20),
        ),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFFEBF2FF) : Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(ScreenAdapter.width(12)),
          border: Border.all(
            color: isSelected ? Color(0xFF3D7CFF) : Color(0xFFE0E0E0),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              svgPath,
              width: ScreenAdapter.width(40),
              height: ScreenAdapter.height(40),
            ),
            SizedBox(width: ScreenAdapter.width(12)),
            Text(
              label,
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(34),
                color: isSelected ? Color(0xFF3D7CFF) : Color(0xFF333333),
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
            if (isSelected) ...[
              SizedBox(width: ScreenAdapter.width(8)),
              Icon(
                Icons.check_circle,
                size: ScreenAdapter.fontSize(30),
                color: Color(0xFF3D7CFF),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 介绍页面
  Widget _buildIntroPage() {
    final detail = controller.courseDetail;
    final String title = detail['title']?.toString() ?? '';
    final String description = detail['description']?.toString() ??
        detail['intro']?.toString() ??
        detail['content']?.toString() ??
        '';
    final bool isFree = detail['is_free']?.toString() == '1';
    final String price = isFree ? '免费' : '${detail['price']}';
    final String originalPrice = detail['original_price']?.toString() ?? '';

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: ScreenAdapter.width(32),
        vertical: ScreenAdapter.height(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 课程标题
          if (title.isNotEmpty)
            Text(
              title,
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(44),
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
            ),

          SizedBox(height: ScreenAdapter.height(16)),

          // 价格展示（红色字体）
          if (isFree)
            Text(
              price,
              style: TextStyle(
                fontSize: ScreenAdapter.fontSize(36),
                fontWeight: FontWeight.w500,
                color: Color(0xFFFF4D4F),
              ),
            )
          else
            Row(
              children: [
                Text(
                  '¥$price',
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(48),
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFF4D4F),
                  ),
                ),
                if (originalPrice.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(left: ScreenAdapter.width(16)),
                    child: Text(
                      '¥$originalPrice',
                      style: TextStyle(
                        fontSize: ScreenAdapter.fontSize(28),
                        color: Color(0xFF999999),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ),
              ],
            ),

          // 分隔横线
          if (description.isNotEmpty)
            Container(
              height: 1,
              color: Color(0xFFEEEEEE),
              margin: EdgeInsets.symmetric(vertical: ScreenAdapter.height(24)),
            ),

          // 课程说明标题（左侧竖线装饰）
          if (description.isNotEmpty)
            Container(
              margin: EdgeInsets.only(bottom: ScreenAdapter.height(16)),
              child: Row(
                children: [
                  Container(
                    width: ScreenAdapter.width(6),
                    height: ScreenAdapter.height(40),
                    decoration: BoxDecoration(
                      color: Color(0xFF3D7CFF),
                      borderRadius:
                          BorderRadius.circular(ScreenAdapter.width(3)),
                    ),
                  ),
                  SizedBox(width: ScreenAdapter.width(16)),
                  Text(
                    '课程说明',
                    style: TextStyle(
                      fontSize: ScreenAdapter.fontSize(44),
                      color: Color(0xFF333333),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // 描述（富文本展示）
          if (description.isNotEmpty)
            HtmlWidget(
              description,
              textStyle: TextStyle(
                fontSize: ScreenAdapter.fontSize(30),
                color: Color(0xFF666666),
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }

  /// 信息行（带分隔线）
  Widget _infoRow(String label, String value,
      {bool highlightPrice = false, bool showDivider = true}) {
    return Container(
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: Color(0xFFF5F5F5), width: 1)),
            )
          : null,
      padding: EdgeInsets.symmetric(
        vertical: ScreenAdapter.height(36),
        horizontal: ScreenAdapter.width(32),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: ScreenAdapter.fontSize(40),
              color: Color(0xFF666666),
            ),
          ),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: RichText(
                text: TextSpan(
                  children: _parsePriceText(value, highlightPrice),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _parsePriceText(String value, bool highlightPrice) {
    if (!highlightPrice || !value.contains('¥')) {
      return [
        TextSpan(
            text: value,
            style: TextStyle(
                fontSize: ScreenAdapter.fontSize(40), color: Color(0xFF333333)))
      ];
    }
    // 解析 "¥价格   ¥原价" 格式
    final parts = value.split(RegExp(r'\s+'));
    final spans = <TextSpan>[];
    for (var part in parts) {
      if (part.startsWith('¥')) {
        final isFirst = spans.isEmpty;
        spans.add(TextSpan(
          text: '$part ',
          style: TextStyle(
            fontSize: isFirst
                ? ScreenAdapter.fontSize(42)
                : ScreenAdapter.fontSize(34),
            color: isFirst ? Color(0xFFFF4D4F) : Color(0xFF999999),
            fontWeight: isFirst ? FontWeight.w500 : FontWeight.normal,
            decoration: !isFirst ? TextDecoration.lineThrough : null,
            decorationColor: !isFirst ? Color(0xFF999999) : null,
          ),
        ));
      } else {
        spans.add(TextSpan(
            text: '$part ',
            style: TextStyle(
                fontSize: ScreenAdapter.fontSize(36),
                color: Color(0xFF333333))));
      }
    }
    return spans;
  }

  /// 目录页面：课程列表
  Widget _buildCatalogList() {
    return _buildCatalogContent();
  }

  /// 目录列表内容
  Widget _buildCatalogContent() {
    return _CatalogListContent(
      items: controller.courseItems,
      onItemTap: (item) => controller.playCourseItem(item),
      selectedLessonId: controller.currentPlayingLessonId.value,
    );
  }

  List<dynamic> _getMaterialsList() {
    final detail = controller.courseDetail;
    final dynamic v = detail['materials'] ??
        detail['material'] ??
        detail['files'] ??
        detail['file_list'] ??
        detail['attachments'] ??
        detail['resources'];
    return v is List ? v : const [];
  }

  Widget _buildMaterialsList() {
    final materials = _getMaterialsList();
    if (materials.isEmpty) {
      return Center(
        child: Text(
          '暂无相关资料',
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(40),
            color: Color(0xFF999999),
          ),
        ),
      );
    }

    return Container(
      color: Color(0xFFF5F5F5),
      padding: EdgeInsets.symmetric(vertical: ScreenAdapter.height(20)),
      child: ListView.builder(
        padding: EdgeInsets.symmetric(
          horizontal: ScreenAdapter.width(40),
        ),
        itemCount: materials.length,
        itemBuilder: (context, index) {
          final item = materials[index];
          final name = (item is Map
                  ? (item['name'] ??
                      item['title'] ??
                      item['filename'] ??
                      item['file_name'])
                  : null)
              ?.toString();
          final urlRaw = (item is Map
                  ? (item['url'] ??
                      item['file_url'] ??
                      item['fileurl'] ??
                      item['path'] ??
                      item['download_url'] ??
                      item['downloadurl'] ??
                      item['src'] ??
                      item['href'] ??
                      item['link'] ??
                      item['file_path'])
                  : null)
              ?.toString();
          final size = (item is Map
                  ? (item['size'] ??
                      item['file_size'] ??
                      item['filesize'] ??
                      item['fileSize'])
                  : null)
              ?.toString();

          final safeName = (name == null || name.isEmpty) ? '未知文件' : name;
          final safeUrl = urlRaw == null ? '' : ApiClient.replaceUri(urlRaw);
          final safeSize = (size == null || size.isEmpty) ? '' : size;

          // 解析文件扩展名
          String ext = '';
          if (safeName.contains('.')) {
            ext = safeName.split('.').last.toLowerCase();
          } else if (safeUrl.isNotEmpty) {
            final withoutQuery = safeUrl.split('?').first;
            final withoutHash = withoutQuery.split('#').first;
            if (withoutHash.contains('.')) {
              ext = withoutHash.split('.').last.toLowerCase();
            }
          }
          final extLabel = ext.isNotEmpty ? ext.toUpperCase() : 'FILE';

          return Container(
            margin: EdgeInsets.only(bottom: ScreenAdapter.height(16)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ScreenAdapter.width(12)),
              border: Border.all(color: Color(0xFFEEEEEE), width: 1),
            ),
            child: InkWell(
              onTap: () => _showMaterialActionSheet(
                name: safeName,
                url: safeUrl,
                size: safeSize,
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  left: ScreenAdapter.width(32),
                  right: ScreenAdapter.width(32),
                  top: ScreenAdapter.height(38),
                  bottom: ScreenAdapter.height(38),
                ),
                child: Row(
                  children: [
                    // 左侧文档图标（蓝色圆角方形）
                    Container(
                      width: ScreenAdapter.width(64),
                      height: ScreenAdapter.width(64),
                      decoration: BoxDecoration(
                        color: Color(0xFFE8F0FF),
                        borderRadius:
                            BorderRadius.circular(ScreenAdapter.width(14)),
                      ),
                      child: Center(
                        child: SvgPicture.asset(
                          'assets/fonts/text.svg',
                          width: ScreenAdapter.width(36),
                          height: ScreenAdapter.width(36),
                          colorFilter: ColorFilter.mode(
                              Color(0xFF3D7CFF), BlendMode.srcIn),
                        ),
                      ),
                    ),
                    SizedBox(width: ScreenAdapter.width(24)),
                    // 标题
                    Expanded(
                      child: Text(
                        safeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ScreenAdapter.fontSize(40),
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ),
                    // 右侧更多按钮
                    GestureDetector(
                      onTap: () => _showMaterialActionSheet(
                        name: safeName,
                        url: safeUrl,
                        size: safeSize,
                      ),
                      behavior: HitTestBehavior.opaque,
                      child: Icon(
                        Icons.more_horiz,
                        color: Color(0xFFCCCCCC),
                        size: ScreenAdapter.fontSize(34),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showMaterialActionSheet({
    required String name,
    required String url,
    required String size,
  }) {
    Get.bottomSheet(
      Container(
        color: Colors.white,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _actionItem('预览', () {
                Get.back();
                _openPdfPreview(url, name);
              }),
              Divider(height: 1, color: Color(0xFFEEEEEE)),
              _actionItem(size.isEmpty || size == '0' ? '下载' : '下载 ($size)',
                  () {
                Get.back();
                _downloadAndOpen(url, name);
              }),
              Divider(height: 1, color: Color(0xFFEEEEEE)),
              _actionItem('复制下载链接', () async {
                Get.back();
                final detail = controller.courseDetail;
                final bool isPay = detail['is_pay']?.toString() == '1' ||
                    detail['is_pay'] == true;
                final bool isFree = detail['is_free']?.toString() == '1';
                if (!isPay && !isFree) {
                  SnackbarUtils.showError('请先购买或订阅课程');
                  return;
                }
                await Clipboard.setData(ClipboardData(text: url));
                SnackbarUtils.showSuccess('链接已复制');
              }),
              Container(
                height: ScreenAdapter.height(34),
                color: Color(0xFFF5F5F5),
              ),
              _actionItem('取消', () => Get.back()),
            ],
          ),
        ),
      ),
      isScrollControlled: false,
    );
  }

  /// 应用内预览PDF
  Future<void> _openPdfPreview(String url, String name) async {
    if (url.isEmpty) {
      SnackbarUtils.showError('文件地址无效');
      return;
    }

    final detail = controller.courseDetail;
    final bool isPay =
        detail['is_pay']?.toString() == '1' || detail['is_pay'] == true;
    final bool isFree = detail['is_free']?.toString() == '1';
    if (!isPay && !isFree) {
      SnackbarUtils.showError('请先购买或订阅课程');
      return;
    }

    Get.dialog(
      Center(
        child: Container(
          padding: EdgeInsets.all(ScreenAdapter.width(40)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ScreenAdapter.width(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: ScreenAdapter.height(20)),
              Text('正在加载文档...'),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );

    try {
      final localPath = await _downloadToLocal(url, name);
      Get.back();
      if (localPath == null) return;
      Get.to(() => _PdfPreviewPage(filePath: localPath, title: name));
    } catch (e) {
      Get.back();
      SnackbarUtils.showError('预览失败: ${e.toString()}');
    }
  }

  /// 跳转浏览器下载
  Future<void> _downloadAndOpen(String url, String name) async {
    if (url.isEmpty) {
      SnackbarUtils.showError('文件地址无效');
      return;
    }

    final detail = controller.courseDetail;
    final bool isPay =
        detail['is_pay']?.toString() == '1' || detail['is_pay'] == true;
    final bool isFree = detail['is_free']?.toString() == '1';
    if (!isPay && !isFree) {
      SnackbarUtils.showError('请先购买或订阅课程');
      return;
    }

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      SnackbarUtils.showError('无法打开下载链接');
    }
  }

  /// 下载文件到本地（供预览使用）
  Future<String?> _downloadToLocal(String url, String name) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/$name';

      if (await File(savePath).exists()) return savePath;

      final dio = dio_package.Dio();
      await dio.download(url, savePath);

      return savePath;
    } catch (e) {
      debugPrint('下载失败: $e');
      return null;
    }
  }

  Widget _actionItem(String title, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(vertical: ScreenAdapter.height(42)),
        color: Colors.white,
        child: Text(
          title,
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(44),
            color: Color(0xFF333333),
          ),
        ),
      ),
    );
  }

  /// 构建全屏播放器，占满整个物理屏幕
  Widget _buildFullScreenPlayer(BuildContext context) {
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Builder(
              builder: (context) {
                controller.initPlayer(context);
                return controller.buildPlayerView(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 构建顶部视频区域（支持在封面图内播放视频）
  Widget _buildVideoHeader() {
    final detail = controller.courseDetail;
    final String coverImage = detail['cover_image_url']?.toString() ??
        detail['cover_image']?.toString() ??
        '';
    final String title = detail['title']?.toString() ?? '课程名称';

    return Container(
      width: double.infinity,
      height: ScreenAdapter.height(600),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Builder(
            builder: (context) {
              controller.initPlayer(context);
              return controller.buildPlayerView(context);
            },
          ),
          Obx(() {
            if (!controller.isVideoPlaying.value) {
              return coverImage.isNotEmpty
                  ? Image.network(
                      ApiClient.replaceUri(coverImage),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildDefaultCover(),
                    )
                  : _buildDefaultCover();
            }
            return const SizedBox.shrink();
          }),
          Obx(() {
            if (!controller.isVideoPlaying.value) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.2),
                      Colors.black.withOpacity(0.5),
                    ],
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }),
          Obx(() {
            if (!controller.isVideoPlaying.value) {
              return Positioned(
                left: ScreenAdapter.width(32),
                bottom: ScreenAdapter.height(32),
                right: ScreenAdapter.width(100),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: ScreenAdapter.fontSize(52),
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: Colors.black45, blurRadius: 8),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }
            return const SizedBox.shrink();
          }),
        ],
      ),
    );
  }

  /// 默认红色渐变封面
  Widget _buildDefaultCover() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD4363C), Color(0xFFB01F24)],
        ),
      ),
    );
  }
}

/// 应用内PDF预览页面（WebView + PDF.js 渲染）
class _PdfPreviewPage extends StatefulWidget {
  final String filePath;
  final String title;

  const _PdfPreviewPage({
    required this.filePath,
    required this.title,
  });

  @override
  State<_PdfPreviewPage> createState() => _PdfPreviewPageState();
}

class _PdfPreviewPageState extends State<_PdfPreviewPage> {
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      setState(() => isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonAppBar(
        title: widget.title,
        titleStyle: const TextStyle(fontSize: 18),
        elevation: 0.5,
      ),
      body: Stack(
        children: [
          PdfViewer.openFile(widget.filePath),
          if (isLoading) Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

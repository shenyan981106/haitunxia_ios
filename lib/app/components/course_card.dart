import 'package:flutter/material.dart';
import '../data/providers/api_client.dart';
import '../services/screenAdapter.dart';
import 'app_tag.dart';

/// 通用课程卡片
///
/// 合并课程列表页(CourseItemWidget)与我的课程页(MyCourseItemWidget)的重复实现,
/// 统一字段解析与卡片样式(白底圆角 30 + 阴影 + 老师头像 + 价格行)。
/// 通过开关参数适配两种形态:
/// - 课程列表页:显示教师标签区 + 底部左侧「x课时」
/// - 我的课程页:价格右对齐 + 右上角「会员免费」角标(未免费时)
class CourseCard extends StatelessWidget {
  /// 课程数据(统一字段解析:title/cover_image_url/cover_image/teacher_list/
  /// is_free/price/original_price/total_lessons/teacher_tags/total_students)
  final Map<String, dynamic> course;

  /// 点击回调
  final VoidCallback onTap;

  /// 是否显示教师标签区(课程列表页 true,我的课程页 false)
  final bool showTags;

  /// 是否显示底部左侧「x课时」(课程列表页 true,我的课程页 false)
  final bool showLessonCount;

  /// 价格是否右对齐(我的课程页 true)
  final bool priceAlignRight;

  /// 是否显示右上角「会员免费」角标(我的课程页 is_free=0 时 true)
  final bool showVipBadge;

  /// 标题字号(课程列表页原 44,默认 46)
  final double? titleFontSize;

  /// 是否使用横向封面布局(封面+hot角标+标题+价格+「了解更多」按钮;
  /// 课程列表页「为您精选课程」样式 true,默认旧布局 false)
  final bool coverLayout;

  /// 右下角按钮文字(默认「了解更多」;我的课程页传「开始学习」)
  final String buttonText;

  const CourseCard({
    super.key,
    required this.course,
    required this.onTap,
    this.showTags = true,
    this.showLessonCount = true,
    this.priceAlignRight = false,
    this.showVipBadge = false,
    this.titleFontSize,
    this.coverLayout = false,
    this.buttonText = '了解更多',
  });

  @override
  Widget build(BuildContext context) {
    // 横向封面布局(为您精选课程样式)
    if (coverLayout) {
      return _buildCoverLayout();
    }

    final String title = course['title']?.toString() ?? '';
    final String teacherTags = course['teacher_tags']?.toString() ?? '';

    final bool isFree = course['is_free']?.toString() == '1';

    int totalLessons =
        int.tryParse(course['total_lessons']?.toString() ?? '0') ?? 0;

    // 标签处理
    List tags = [];
    if (teacherTags.isNotEmpty) {
      tags = teacherTags.split(',');
    }

    final List teacherList = (course['teacher_list'] as List?) ?? const [];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: ScreenAdapter.height(24)),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(ScreenAdapter.width(30)),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(ScreenAdapter.width(30)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 标题
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleFontSize ?? ScreenAdapter.fontSize(46),
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF333333),
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: ScreenAdapter.height(20)),

                  // 2. 老师列表
                  if (teacherList.isNotEmpty)
                    Padding(
                      padding:
                          EdgeInsets.only(bottom: ScreenAdapter.height(16)),
                      child: Row(
                        children: teacherList.map<Widget>((teacher) {
                          final t = teacher as Map<String, dynamic>;
                          return Padding(
                            padding:
                                EdgeInsets.only(right: ScreenAdapter.width(32)),
                            child: Column(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: const Color(0xFFE8E8E8),
                                        width: 1.5),
                                  ),
                                  child: CircleAvatar(
                                    radius: ScreenAdapter.width(40),
                                    backgroundImage: NetworkImage(
                                        ApiClient.replaceUri(
                                            t['avatar']?.toString() ?? '')),
                                    onBackgroundImageError: (e, s) {},
                                    backgroundColor: const Color(0xFFF0F0F0),
                                  ),
                                ),
                                SizedBox(height: ScreenAdapter.height(8)),
                                Text(
                                  t['name']?.toString() ?? '',
                                  style: TextStyle(
                                    fontSize: ScreenAdapter.fontSize(26),
                                    color: const Color(0xFF666666),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  // 3. 标签列表(课程列表页)
                  if (showTags && tags.isNotEmpty)
                    Padding(
                      padding:
                          EdgeInsets.only(bottom: ScreenAdapter.height(20)),
                      child: Wrap(
                        spacing: ScreenAdapter.width(16),
                        runSpacing: ScreenAdapter.height(10),
                        children: tags
                            .take(3)
                            .map((tag) => AppTag(tag.toString()))
                            .toList(),
                      ),
                    ),

                  SizedBox(height: ScreenAdapter.height(20)),
                  const Divider(height: 1, color: Color(0xFFF5F5F5)),
                  SizedBox(height: ScreenAdapter.height(20)),

                  // 4. 底部 课时和价格
                  Row(
                    mainAxisAlignment: priceAlignRight
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.spaceBetween,
                    children: [
                      if (showLessonCount)
                        Text(
                          '$totalLessons课时',
                          style: TextStyle(
                            fontSize: ScreenAdapter.fontSize(30),
                            color: const Color(0xFF999999),
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '¥',
                            style: TextStyle(
                              fontSize: ScreenAdapter.fontSize(32),
                              color: const Color(0xFFFF4D4F),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            isFree ? '0' : course['price']?.toString() ?? '0',
                            style: TextStyle(
                              fontSize: ScreenAdapter.fontSize(52),
                              color: const Color(0xFFFF4D4F),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 右上角「会员免费」角标(我的课程页,未免费时)
            if (showVipBadge && !isFree)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ScreenAdapter.width(22),
                    vertical: ScreenAdapter.height(12),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4E5),
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(ScreenAdapter.width(30)),
                      bottomLeft: Radius.circular(ScreenAdapter.width(30)),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.workspace_premium,
                        color: const Color(0xFFFF9900),
                        size: ScreenAdapter.fontSize(30),
                      ),
                      SizedBox(width: ScreenAdapter.width(8)),
                      Text(
                        '会员免费',
                        style: TextStyle(
                          fontSize: ScreenAdapter.fontSize(30),
                          color: const Color(0xFFFF9900),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 横向封面布局:左侧封面(左上角 hot 角标)+ 右侧标题 + 科目名 + 价格 + 「了解更多」按钮
  Widget _buildCoverLayout() {
    final String title = course['title']?.toString() ?? '';
    final String coverUrl = ApiClient.replaceUri(
        (course['cover_image_url'] ?? course['cover_image'])?.toString() ?? '');
    final bool isFree = course['is_free']?.toString() == '1';
    // 价格为空的场景(如我的课程接口无价格字段)隐藏价格区,避免显示 ¥0
    final String price = isFree ? '0' : course['price']?.toString() ?? '';
    // 科目名副标题(我的课程接口 subject_name;无此字段的调用方不显示)
    final String subjectName = course['subject_name']?.toString() ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: ScreenAdapter.height(24)),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(ScreenAdapter.width(30)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ScreenAdapter.width(30)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          // IntrinsicHeight + stretch:封面固定高度、右侧内容填满,价格行与按钮沉底
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左侧封面(固定宽高 + cover 裁剪,不随右侧文字高度拉伸)
                ClipRRect(
                  borderRadius: BorderRadius.circular(ScreenAdapter.width(16)),
                  child: SizedBox(
                    width: ScreenAdapter.width(230),
                    height: ScreenAdapter.height(210),
                    child: coverUrl.isEmpty
                        ? _buildCoverPlaceholder()
                        : Image.network(
                            coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildCoverPlaceholder(),
                          ),
                  ),
                ),
                SizedBox(width: ScreenAdapter.width(26)),
                // 右侧:标题 + 价格 + 了解更多按钮
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ScreenAdapter.fontSize(44),
                          color: const Color(0xFF1B2F5C),
                          height: 1.3,
                        ),
                      ),
                      if (subjectName.isNotEmpty) ...[
                        SizedBox(height: ScreenAdapter.height(10)),
                        Text(
                          subjectName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: ScreenAdapter.fontSize(30),
                            color: const Color(0xFF999999),
                          ),
                        ),
                      ],
                      SizedBox(height: ScreenAdapter.height(14)),
                      const Spacer(),
                      // 底部一行:左价格(为空隐藏)+ 右了解更多按钮
                      Row(
                        children: [
                          if (price.isNotEmpty)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '¥',
                                  style: TextStyle(
                                    fontSize: ScreenAdapter.fontSize(30),
                                    color: const Color(0xFFFF4D4F),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  price,
                                  style: TextStyle(
                                    fontSize: ScreenAdapter.fontSize(48),
                                    color: const Color(0xFFFF4D4F),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          const Spacer(),
                          // 了解更多按钮(蓝边框白底蓝字,同首页历年真题「立即参加」)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ScreenAdapter.width(28),
                              vertical: ScreenAdapter.height(12),
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                                  BorderRadius.circular(ScreenAdapter.width(40)),
                              border: Border.all(
                                color: const Color(0xFF3D7CFF),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              buttonText,
                              style: TextStyle(
                                fontSize: ScreenAdapter.fontSize(28),
                                color: const Color(0xFF3D7CFF),
                              ),
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
          ),
        ),
      );
  }

  /// 封面加载失败/缺省时的灰色占位
  Widget _buildCoverPlaceholder() {
    return Container(
      color: const Color(0xFFF0F0F0),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        size: ScreenAdapter.fontSize(48),
        color: const Color(0xFFCCCCCC),
      ),
    );
  }
}

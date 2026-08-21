import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:dio/dio.dart' as dio_package;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf_render/pdf_render_widgets.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../services/screenAdapter.dart';
import '../../../data/providers/api_client.dart';
import '../../../components/common_app_bar.dart';
import '../controllers/my_course_detail_controller.dart';
import '../../../services/snackbar_utils.dart';

/// 单个目录项组件（与 details_view.dart 的 CatalogItemWidget 同源拷贝）
class _MyCourseCatalogItem extends StatefulWidget {
  final dynamic item;
  final int index;
  final int level;
  final Function(dynamic) onTap;
  final bool isExpanded;
  final int selectedLessonId;
  final VoidCallback? onExpandToggle;

  const _MyCourseCatalogItem({
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
  _MyCourseCatalogItemState createState() => _MyCourseCatalogItemState();
}

class _MyCourseCatalogItemState extends State<_MyCourseCatalogItem> {
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

/// 目录列表容器，管理展开/折叠状态（与 details_view.dart 的 _CatalogListContent 同源拷贝）
class _MyCourseCatalogList extends StatefulWidget {
  final List<dynamic> items;
  final Function(dynamic) onItemTap;
  final int selectedLessonId;

  const _MyCourseCatalogList({
    required this.items,
    required this.onItemTap,
    required this.selectedLessonId,
  });

  @override
  State<_MyCourseCatalogList> createState() => _MyCourseCatalogListState();
}

class _MyCourseCatalogListState extends State<_MyCourseCatalogList> {
  int expandedIndex = 0; // 默认第一个展开

  @override
  void didUpdateWidget(covariant _MyCourseCatalogList oldWidget) {
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
            child: _MyCourseCatalogItem(
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

/// 我的课程详情页：顶部课程图片+名称，下方 目录/资料 tab，点击课时页内直接播放
class MyCourseDetailView extends GetView<MyCourseDetailController> {
  MyCourseDetailView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 强制注册控制器，以防路由跳转时丢控制器
    if (!Get.isRegistered<MyCourseDetailController>()) {
      Get.put(MyCourseDetailController());
    }

    return Obx(() {
      return Scaffold(
        backgroundColor:
            controller.isFullScreen.value ? Colors.black : Colors.white,
        appBar: controller.isFullScreen.value
            ? null
            : CommonAppBar(
                title: '我的课程详情',
                titleStyle: TextStyle(
                  fontSize: ScreenAdapter.fontSize(46),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF333333),
                ),
              ),
        body: Obx(() {
          // 进入时已用列表页参数预填图片/名称，此处仅全空时显示加载/失败态
          if (controller.isLoading.value && controller.courseDetail.isEmpty) {
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
                      _buildTabs(),
                      Expanded(
                        child: Obx(() {
                          switch (controller.currentTabIndex.value) {
                            case 0:
                              return _buildCatalogContent();
                            case 1:
                              return _buildMaterialsList();
                            default:
                              return const SizedBox.shrink();
                          }
                        }),
                      ),
                    ],
                  ),
                ),
              ),
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
          _buildTabOption('目录', 0, selectedIndex == 0),
          _buildTabOption('资料', 1, selectedIndex == 1),
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

  /// 目录页面：课程列表
  Widget _buildCatalogContent() {
    return _MyCourseCatalogList(
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
                // ★2026-08-19 权限判断统一走 canWatchCourse(order.can_watch,兼容旧 is_pay/is_free)
                if (!controller.canWatchCourse) {
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

    // ★2026-08-19 权限判断统一走 canWatchCourse(order.can_watch,兼容旧 is_pay/is_free)
    if (!controller.canWatchCourse) {
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

  /// 构建顶部课程信息区（封面图+课程名称，播放时切换为播放器视图）
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

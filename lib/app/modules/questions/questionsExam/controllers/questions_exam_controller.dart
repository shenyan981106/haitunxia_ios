import 'package:get/get.dart';
import 'package:flutter/material.dart';
import '../../../../services/global_project_controller.dart';
import '../../../../data/providers/api_client.dart';
import '../../../../data/models/category_model.dart';
import '../../../../data/models/project_model.dart';
import 'package:xmshop/app/utils/app_log.dart';

class QuestionsExamController extends GetxController {
  // 全局项目控制器 - 延迟初始化
  late final GlobalProjectController globalController;

  // 页面类型：must_brush, past_exams, mock_exams
  final String pageType;

  QuestionsExamController({required this.pageType});

  // 科目列表
  RxList<Category> categories = <Category>[].obs;
  RxList<CategoryChild> subjects = <CategoryChild>[].obs;
  final RxInt currentSubjectIndex = 0.obs;

  // ★2026-08-14 修复:ever() Worker 需手动释放,否则挂载在全局 Rx 上累积僵尸监听
  Worker? _projectWorker;
  Worker? _subjectWorker;

  // 加载状态
  bool isLoading = false;
  String errorMessage = '';

  List<String> get tabTitles {
    if (subjects.isEmpty) return [];
    return subjects.map((e) => e.name).toList();
  }

  // ★2026-08-26 优化:科目过滤结果缓存(courses 为静态硬编码列表,按科目名缓存,
  // 避免每次 build 全量 where+toList 过滤)
  final Map<String, List<Map<String, dynamic>>> _filteredCoursesCache = {};

  List<Map<String, dynamic>> getFilteredCourses(String subject) {
    return _filteredCoursesCache.putIfAbsent(subject, () {
      return subject == '全部科目'
          ? courses
          : courses
              .where((element) => (element['title'] as String).contains(subject))
              .toList();
    });
  }

  // 课程数据
  final List<Map<String, dynamic>> courses = [
    {
      'image':
          'https://neeko-copilot.bytedance.net/api/text2image?prompt=online%20course%20cover%20math&size=512x512',
      'type': '直播',
      'title': '高等数学必刷母题精讲',
      'teacher': '张老师',
      'progress': '已更新2/20课时',
      'watched': '已观看课时'
    },
    {
      'image':
          'https://neeko-copilot.bytedance.net/api/text2image?prompt=online%20course%20cover%20english&size=512x512',
      'type': '录播',
      'title': '英语历年真题解析',
      'teacher': '李老师',
      'progress': '已更新5/15课时',
      'watched': '已观看课时'
    },
    {
      'image':
          'https://neeko-copilot.bytedance.net/api/text2image?prompt=online%20course%20cover%20computer&size=512x512',
      'type': '直播',
      'title': '计算机基础模拟考试',
      'teacher': '王老师',
      'progress': '已更新0/12课时',
      'watched': '已观看课时'
    },
  ];

  // 页面控制器
  late PageController pageController;

  // 试卷列表缓存 Map<subjectId, List<ExamPaper>>
  RxMap<int, List<Map<String, dynamic>>> examPapersMap =
      <int, List<Map<String, dynamic>>>{}.obs;

  // 试卷加载状态 Map<subjectId, bool>
  RxMap<int, bool> isExamLoadingMap = <int, bool>{}.obs;

  // === 分页状态（按 subjectId 隔离）===
  RxMap<int, int> examPageMap = <int, int>{}.obs; // 当前页码
  RxMap<int, bool> examHasMoreMap = <int, bool>{}.obs; // 是否还有更多
  RxMap<int, bool> examIsLoadingMoreMap = <int, bool>{}.obs; // 上拉加载中
  RxMap<int, String> examLoadErrorMap = <int, String>{}.obs; // 加载失败信息
  final Map<int, ScrollController> _scrollControllers = {}; // 每科目一个
  static const int _pageSize = 15;

  @override
  void onInit() {
    super.onInit();
    // 在 onInit 中获取 GlobalProjectController，确保服务已注册
    globalController = GlobalProjectController.to;
    pageController = PageController(initialPage: currentSubjectIndex.value);

    if (pageType == 'chapter_detail') {
      final args = Get.arguments;
      if (args != null && args is Map) {
        if (args['sections'] != null && args['sections'] is List) {
          final sectionsList = args['sections'] as List;
          final newSubjects = sectionsList.map<CategoryChild>((section) {
            final raw = section['raw'] ?? {};
            int id = 0;
            if (raw['id'] != null) {
              id = int.tryParse(raw['id'].toString()) ?? 0;
            }
            return CategoryChild(
              id: id,
              name: section['title'] ?? '',
              parentId: 0,
              weigh: 0,
              children: [],
            );
          }).toList();
          subjects.assignAll(newSubjects);

          if (subjects.isNotEmpty) {
            currentSubjectIndex.value = 0;
            fetchExamPapers(subjects[0].id);
          }
        }
      }
    } else {
      fetchSubjects();

      // 监听全局项目变化
      _projectWorker = ever<Project?>(globalController.currentProject, (project) {
        if (project != null) {
          fetchSubjects();
        }
      });
    }

    // 监听科目切换，获取对应试卷列表
    _subjectWorker = ever(currentSubjectIndex, (index) {
      if (subjects.isNotEmpty && index >= 0 && index < subjects.length) {
        final subjectId = subjects[index].id;
        // 如果该科目没有数据且未在加载中，则请求数据
        if (!examPapersMap.containsKey(subjectId)) {
          fetchExamPapers(subjectId);
        }
      }
    });
  }

  // 获取试卷列表（首次加载 / 刷新入口；保持原签名兼容现有调用点）
  Future<void> fetchExamPapers(int subjectId) async {
    // 如果正在加载，则忽略
    if (isExamLoadingMap[subjectId] == true) return;
    return refreshExamPapers(subjectId);
  }

  // 下拉刷新 / 首次加载：拉取第 1 页
  Future<void> refreshExamPapers(int subjectId) async {
    if (isExamLoadingMap[subjectId] == true) return;

    isExamLoadingMap[subjectId] = true;
    examLoadErrorMap[subjectId] = '';

    try {
      // 调用 paper/index 接口，传递 subject_id + 分页参数
      final response =
          await ApiClient.to.getExam('paper/index', queryParameters: {
        'subject_id': subjectId,
        'page': 1,
        'limit': _pageSize,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['code'] == 1) {
          final dataBlock = data['data'];
          final listObj = dataBlock is Map ? dataBlock['list'] : null;
          final total = dataBlock is Map ? dataBlock['total'] : null;

          List<dynamic> listData;
          bool hasMore;
          if (listObj is List) {
            // 后端分页结构：data.list 是本页数组，data.total 是总数
            listData = listObj;
            final loaded = listData.length;
            if (total is num) {
              hasMore = loaded < total;
            } else {
              hasMore = false; // 无 total 则当作全量
            }
          } else if (listObj is Map) {
            // FastAdmin 分页结构：list.data 为本页数据
            listData = listObj['data'] ?? [];
            hasMore = _computeHasMore(listObj, subjectId);
          } else {
            listData = [];
            hasMore = false;
          }
          examPapersMap[subjectId] =
              listData.map((e) => Map<String, dynamic>.from(e)).toList();
          examPageMap[subjectId] = 1;
          examHasMoreMap[subjectId] = hasMore;
        }
      }
    } catch (e) {
      AppLog.d('Fetch exam papers error: $e');
      // 出错时也设为空列表，避免无限重试
      if (!examPapersMap.containsKey(subjectId)) {
        examPapersMap[subjectId] = [];
      }
      examHasMoreMap[subjectId] = false;
    } finally {
      isExamLoadingMap[subjectId] = false;
    }
  }

  // 上拉加载更多：拉取下一页并追加
  Future<void> loadMoreExamPapers(int subjectId) async {
    if (isExamLoadingMap[subjectId] == true) return;
    if (examIsLoadingMoreMap[subjectId] == true) return;
    if (examHasMoreMap[subjectId] == false) return;

    examIsLoadingMoreMap[subjectId] = true;
    examLoadErrorMap[subjectId] = '';

    final nextPage = (examPageMap[subjectId] ?? 1) + 1;

    try {
      final response =
          await ApiClient.to.getExam('paper/index', queryParameters: {
        'subject_id': subjectId,
        'page': nextPage,
        'limit': _pageSize,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['code'] == 1) {
          final dataBlock = data['data'];
          final listObj = dataBlock is Map ? dataBlock['list'] : null;
          final total = dataBlock is Map ? dataBlock['total'] : null;

          List<dynamic> listData;
          bool hasMore;
          if (listObj is List) {
            // 后端分页结构：data.list 是本页新增数据
            listData = listObj;
            final existingCount = (examPapersMap[subjectId]?.length) ?? 0;
            final newCount = listData.length;
            if (total is num) {
              hasMore = (existingCount + newCount) < total;
            } else {
              hasMore = false;
            }
          } else if (listObj is Map) {
            listData = listObj['data'] ?? [];
            hasMore = _computeHasMore(listObj, subjectId);
          } else {
            listData = const [];
            hasMore = false;
          }
          final newItems =
              listData.map((e) => Map<String, dynamic>.from(e)).toList();

          final existing = examPapersMap[subjectId] ?? [];
          examPapersMap[subjectId] = [...existing, ...newItems];
          examPageMap[subjectId] = nextPage;
          examHasMoreMap[subjectId] = hasMore;
        }
      }
    } catch (e) {
      AppLog.d('Load more exam papers error: $e');
      examLoadErrorMap[subjectId] = '加载失败，点击重试';
    } finally {
      examIsLoadingMoreMap[subjectId] = false;
    }
  }

  // 根据分页元数据判断是否还有更多
  bool _computeHasMore(dynamic listObj, int subjectId) {
    if (listObj is! Map) return false;
    final currentPage = listObj['current_page'];
    final lastPage = listObj['last_page'];
    if (currentPage is num && lastPage is num) {
      return currentPage < lastPage;
    }
    // 兜底：用 total 判断
    final total = listObj['total'];
    final loaded = (examPapersMap[subjectId]?.length) ?? 0;
    if (total is num) {
      return loaded < total;
    }
    return false;
  }

  // 获取（懒创建）某科目的 ScrollController
  ScrollController getScrollController(int subjectId) {
    if (!_scrollControllers.containsKey(subjectId)) {
      final sc = ScrollController();
      sc.addListener(() => _onScroll(subjectId));
      _scrollControllers[subjectId] = sc;
    }
    return _scrollControllers[subjectId]!;
  }

  // 滚动接近底部时触发加载更多
  void _onScroll(int subjectId) {
    final sc = _scrollControllers[subjectId];
    if (sc == null || !sc.hasClients) return;
    if (sc.position.pixels >= sc.position.maxScrollExtent - 200) {
      loadMoreExamPapers(subjectId);
    }
  }

  Future<void> fetchSubjects() async {
    isLoading = true;
    errorMessage = '';
    update();

    try {
      final response = await ApiClient.to.getExam('subject/index');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['code'] == 1) {
          final List<dynamic> categoryData = data['data'] ?? [];
          categories.assignAll(
              categoryData.map((item) => Category.fromJson(item)).toList());

          subjects.clear();

          if (categories.isNotEmpty) {
            final currentName = globalController.currentProjectName;
            CategoryChild? target;

            for (final category in categories) {
              for (final child in category.children) {
                if (child.name == currentName) {
                  target = child;
                  break;
                }
              }
              if (target != null) {
                break;
              }
            }

            if (target == null) {
              for (final category in categories) {
                if (category.children.isNotEmpty) {
                  target = category.children.first;
                  break;
                }
              }
            }

            if (target != null && target.children.isNotEmpty) {
              subjects.assignAll(target.children);
              currentSubjectIndex.value = 0;
              // 初始加载第一个科目的试卷
              fetchExamPapers(target.children[0].id);
            } else {
              errorMessage = '暂无子分类数据';
            }
          } else {
            errorMessage = '暂无科目数据';
          }
        } else {
          errorMessage = data['msg']?.toString() ?? '获取科目数据失败';
        }
      } else {
        errorMessage = '网络请求失败，请稍后重试';
      }
    } catch (_) {
      errorMessage = '网络错误，请检查网络连接';
    } finally {
      isLoading = false;
      update();
    }
  }

  @override
  void onClose() {
    _projectWorker?.dispose();
    _subjectWorker?.dispose();
    pageController.dispose();
    for (final sc in _scrollControllers.values) {
      sc.dispose();
    }
    _scrollControllers.clear();
    super.onClose();
  }

  // 设置当前科目索引（点击Tab调用）
  void setCurrentSubjectIndex(int index) {
    if (currentSubjectIndex.value == index) return;
    currentSubjectIndex.value = index;
    pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // 页面滑动回调
  void onPageChanged(int index) {
    if (currentSubjectIndex.value == index) return;
    currentSubjectIndex.value = index;
  }

  // 每个Tab的颜色主题（使用MaterialColor或Color）
  List<MaterialColor> get tabThemeColors {
    switch (pageType) {
      case 'must_brush':
        return [
          Colors.blue, // 历史 - 蓝色
          Colors.blue, // 英语 - 蓝色
          Colors.blue, // 马原 - 蓝色
          Colors.blue, // 高数 - 蓝色
          Colors.blue, // 语文 - 蓝色
        ];
      case 'past_exams':
        return [
          Colors.teal, // 2025 - 青色
          Colors.teal, // 2024 - 青色
          Colors.teal, // 2023 - 青色
          Colors.teal, // 2022 - 青色
          Colors.teal, // 2021 - 青色
        ];
      case 'mock_exams':
        return [
          Colors.purple, // 模拟一 - 紫色
          Colors.purple, // 模拟二 - 紫色
          Colors.purple, // 模拟三 - 紫色
          Colors.purple, // 模拟四 - 紫色
          Colors.purple, // 模拟五 - 紫色
        ];
      default:
        return [
          Colors.blue, // 默认 - 蓝色
          Colors.blue, // 默认 - 蓝色
          Colors.blue, // 默认 - 蓝色
          Colors.blue, // 默认 - 蓝色
          Colors.blue, // 默认 - 蓝色
        ];
    }
  }

  // 获取主题颜色
  Color getThemeColor(int index) {
    if (index < 0 || index >= tabThemeColors.length) {
      return Colors.blue; // 默认颜色
    }
    return tabThemeColors[index];
  }

  // 获取默认主题颜色
  Color get defaultThemeColor {
    switch (pageType) {
      case 'must_brush':
        return Colors.blue;
      case 'past_exams':
        return Colors.teal;
      case 'mock_exams':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }
}

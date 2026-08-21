import 'package:get/get.dart';
import 'package:flutter/material.dart';
import '../../../data/repositories/exam_repository.dart';
import '../../../services/global_project_controller.dart';
import 'package:xmshop/app/utils/app_log.dart';

class SearchQuestion {
  final String id;
  final String content;
  final String type;
  final List<String> options;
  final List<int> correctAnswers;
  final String? explanation;
  final String? difficulty;
  final String? categoryName;
  // 保留接口返回的原始数据，用于跳转答题页时直接展示
  final Map<String, dynamic> rawJson;

  SearchQuestion({
    required this.id,
    required this.content,
    required this.type,
    required this.options,
    required this.correctAnswers,
    this.explanation,
    this.difficulty,
    this.categoryName,
    this.rawJson = const {},
  });

  factory SearchQuestion.fromJson(Map<String, dynamic> json) {
    // 解析选项，从 options_json 中获取
    List<String> options = [];
    if (json['options_json'] != null && json['options_json'] is List) {
      final optionsJson = json['options_json'] as List;
      for (var option in optionsJson) {
        if (option is Map && option['value'] != null) {
          options.add(option['value'].toString());
        }
      }
    }

    // 解析正确答案
    List<int> correctAnswers = [];
    final answer = json['answer'];
    if (answer != null) {
      if (answer is String) {
        // 比如 "C"，转换为索引
        final answerIndex = answer.codeUnitAt(0) - 'A'.codeUnitAt(0);
        if (answerIndex >= 0) {
          correctAnswers.add(answerIndex);
        }
      } else if (answer is int) {
        correctAnswers.add(answer);
      } else if (answer is List) {
        correctAnswers = List<int>.from(answer);
      }
    }

    // 解析难度
    String? difficultyText;
    if (json['difficulty'] != null) {
      final diff = json['difficulty'].toString();
      if (diff == 'GENERAL') {
        difficultyText = '一般';
      } else if (diff == 'EASY') {
        difficultyText = '简单';
      } else if (diff == 'HARD') {
        difficultyText = '困难';
      } else {
        difficultyText = diff;
      }
    }

    // 解析分类名称
    String? categoryName;
    if (json['cates'] != null && json['cates'] is Map) {
      categoryName = json['cates']['name']?.toString();
    }
    if (categoryName == null && json['cate_name'] != null) {
      categoryName = json['cate_name'].toString();
    }
    if (categoryName == null && json['category_name'] != null) {
      categoryName = json['category_name'].toString();
    }

    return SearchQuestion(
      id: json['id']?.toString() ?? '',
      content: json['title']?.toString() ?? json['content']?.toString() ?? '',
      type:
          json['kind_text']?.toString() ?? json['kind']?.toString() ?? 'single',
      options: options,
      correctAnswers: correctAnswers,
      explanation:
          json['explain']?.toString() ?? json['explanation']?.toString(),
      difficulty: difficultyText,
      categoryName: categoryName,
      rawJson: json,
    );
  }
}

class QuestionSearchController extends GetxController {
  final ExamRepository _examRepository = ExamRepository.to;

  final TextEditingController searchController = TextEditingController();

  final RxBool isSearching = false.obs;
  final RxBool hasSearched = false.obs;
  final RxString searchError = ''.obs;
  final RxList<SearchQuestion> searchResults = <SearchQuestion>[].obs;
  final RxList<String> searchHistory = <String>[].obs;
  final RxString searchText = ''.obs;

  @override
  void onInit() {
    super.onInit();
    searchController.addListener(() {
      searchText.value = searchController.text;
    });
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  Future<void> search() async {
    final keyword = searchController.text.trim();
    if (keyword.isEmpty) {
      return;
    }

    hasSearched.value = true;
    isSearching.value = true;
    searchError.value = '';

    try {
      final subjectId =
          GlobalProjectController.to.currentProject.value?.id?.toString() ??
              '5';

      final response =
          await _examRepository.searchQuestions(keyword, subjectId: subjectId);

      if (response.isSuccess && response.data != null) {
        final listData = response.data!['list'];
        // 题目实际在 list.data 中
        List<dynamic>? items;
        if (listData is Map) {
          items = listData['data'] as List?;
        } else if (listData is List) {
          items = listData;
        }

        if (items != null && items.isNotEmpty) {
          searchResults.value =
              items.whereType<Map>().map<SearchQuestion>((item) {
            final map = item.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value));
            return SearchQuestion.fromJson(map);
          }).toList();
        } else {
          searchResults.value = [];
        }
      } else {
        searchError.value = response.message ?? '搜索失败';
        searchResults.value = [];
      }
    } catch (e) {
      searchError.value = '网络错误，请检查网络连接';
      searchResults.value = [];
    } finally {
      isSearching.value = false;
    }
  }

  void clearSearch() {
    searchController.clear();
    searchResults.clear();
    hasSearched.value = false;
    searchError.value = '';
  }

  /// 点击搜索结果，跳转到答题页面
  /// 直接把搜索接口返回的题目原始数据带给答题页（与收藏模式思路一致），
  /// 避免依赖 cate_id/paper_id，复用已有答题流程。
  void goToQuestionDetail(SearchQuestion question) {
    final String title =
        (question.categoryName != null && question.categoryName!.isNotEmpty)
            ? question.categoryName!
            : '题目搜索';

    AppLog.d('🔍 搜索跳转: question.id=${question.id}, title=$title');
    AppLog.d('🔍 rawJson keys: ${question.rawJson.keys.toList()}');

    Get.toNamed(
      '/question-train',
      preventDuplicates: false,
      arguments: {
        'pageType': 'search',
        'title': title,
        'items': <Map<String, dynamic>>[question.rawJson],
        '_ts': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }
}

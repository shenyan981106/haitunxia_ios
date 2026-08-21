import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:xmshop/app/services/global_project_controller.dart';
import 'package:xmshop/app/data/models/question_model.dart';
import 'package:xmshop/app/data/providers/api_client.dart';
import 'package:xmshop/app/routes/app_pages.dart';
import 'package:xmshop/app/services/snackbar_utils.dart';
import 'package:xmshop/app/services/screenAdapter.dart';
import 'package:xmshop/app/data/services/auth_service.dart';
import 'package:xmshop/app/data/repositories/exam_repository.dart';
import 'package:xmshop/app/components/common_dialog.dart';
import 'package:xmshop/app/utils/app_log.dart';

class QuestionTrainController extends GetxController {
  final GetStorage _box = GetStorage();
  final ExamRepository _examRepository = ExamRepository();

  // 记录每道题的开始时间（用于计算答题用时）
  DateTime? _questionStartTime;

  // 计时器上一次 tick 的墙钟时间(退后台/卡顿后按真实流逝时间补扣,防切后台"暂停"考试刷时间)
  DateTime _lastTickTime = DateTime.now();

  // 当前题目列表
  final RxList<Question> questions = <Question>[].obs;

  // 加载状态
  final RxBool isLoading = true.obs;
  final RxString errorMessage = ''.obs;

  // 当前题目索引
  final RxInt currentQuestionIndex = 0.obs;

  // 用户答案记录：Map<题目索引, 用户选择的答案索引列表>
  final RxMap<int, List<int>> userAnswers = <int, List<int>>{}.obs;

  // 简答题答案记录：Map<题目索引, 用户输入的答案>
  final RxMap<int, String> shortAnswers = <int, String>{}.obs;

  // 答题结果记录：Map<题目索引, 是否正确>
  final RxMap<int, bool> answerResults = <int, bool>{}.obs;

  // 收藏的题目：Map<题目索引, 是否收藏>
  final RxMap<int, bool> favoriteQuestions = <int, bool>{}.obs;

  // 收藏操作加载状态
  final RxBool isCollecting = false.obs;

  // 是否显示答案解释
  final RxBool showExplanation = false.obs;

  // 控制是否允许返回
  final RxBool canPopNow = false.obs;

  // 新增设置项状态
  final RxDouble fontSizeScale = 1.0.obs; // 字体大小缩放
  final RxDouble lineHeight = 1.5.obs; // 行距 (默认1.5)
  final RxBool isAutoNext = true.obs; // 自动跳转 (默认开启)
  final RxBool isAutoShowExplanation = false.obs; // 自动显示解析 (默认关闭)
  final RxBool isDarkMode = false.obs; // 夜间模式 (默认关闭)

  // 是否已看滑动提示
  final RxBool hasSeenSwipePrompt = false.obs;

  // 卡片显示控制
  final RxBool showFontSizeCard = false.obs; // 字体大小卡片
  final RxBool showSettingsCard = false.obs; // 设置卡片

  // 切换字体大小卡片
  void toggleFontSizeCard() {
    showFontSizeCard.toggle();
    if (showFontSizeCard.value) {
      showSettingsCard.value = false;
    }
  }

  // 切换设置卡片
  void toggleSettingsCard() {
    showSettingsCard.toggle();
    if (showSettingsCard.value) {
      showFontSizeCard.value = false;
    }
  }

  // 关闭所有卡片
  void closeAllCards() {
    showFontSizeCard.value = false;
    showSettingsCard.value = false;
  }

  // 是否详情模式 (用于看题模式切换列表/详情)
  final RxBool isDetailView = true.obs;

  // 是否已提交 (用于练习模式)
  final RxBool isSubmitted = false.obs;

  /// ★2026-08-14 修复:是否已成功交卷。交卷成功退出后再进入**不弹**继续考试弹窗
  /// (onClose 不再回写进度);返回退出(未交卷)才保存进度、再进入弹恢复弹窗
  bool _isExamSubmitted = false;

  // 计时器（秒）
  final RxInt elapsedSeconds = 0.obs;
  final RxInt remainingSeconds = 0.obs; // 倒计时秒数
  Timer? _timer; // 使用可空类型，避免late 初始化问题
  int examInitialSeconds = 0; // 考试初始时间（秒）

  // ★2026-08-14 修复:倒计时改用墙钟绝对截止时刻(毫秒精度),机制见 _startTimer 注释
  DateTime? _countdownEndTime;
  // 正计时毫秒累计(显示时向下取整,不丢余数)
  int _elapsedMs = 0;

  // 格式化倒计时/正计时
  bool get isCountdownMode {
    // 有 paperId 说明是试卷/真题模式，使用倒计时
    if (paperId != null) return true;
    // 无 paperId 但 EXAM 模式也用倒计时
    if (pageMode.value == 'EXAM') return true;
    // 章节练习（无 paperId）用正计时
    return false;
  }

  // 是否需要批量提交答题日志:
  // 仅章节练习/试卷答题/真题答题三类;收藏/错题/搜索/每日一练等本地场景不记录
  bool get _shouldTrackLog {
    if (paperId != null) return true; // 试卷/真题
    if (pageType.isNotEmpty) return false; // 收藏/错题/搜索/页面配置等
    if (_entryMode == 'prac') return false; // 每日一练
    return true; // 章节练习
  }

  String get timerText {
    if (isCountdownMode) {
      int minutes = remainingSeconds.value ~/ 60;
      int seconds = remainingSeconds.value % 60;
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      int minutes = elapsedSeconds.value ~/ 60;
      int seconds = elapsedSeconds.value % 60;
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  // 兼容旧代码引用
  String get remainingTimeText => timerText;

  // 页面控制
  final PageController pageController = PageController();

  // 当前科目和章节信息
  String subject = '';
  String chapter = '';
  String section = '';
  String subsection = '';

  // 页面来源类型（普通/收藏/试卷）
  String pageType = ''; // 'favorite' 表示收藏模式

  // 收藏来源类型（collectAdd/collectCancel 传参）:1=章节练习,2=历年真题,3=模拟考试
  int collectType = 1;

  // 试卷信息
  int totalScore = 0;
  int passScore = 0;
  dynamic paperId; // 试卷ID
  dynamic pageConfigId; // 页面配置ID（动态配置模式）

  // ====== 练习会话(practice)批量日志相关 ======
  // practice_id=0 首次提交,>0 续答(进入时调 practice/detail 回填)
  int practiceId = 0;
  // practice/detail 返回的 attempt_count,退出 SAVE 时作为 attempt_no 上报
  int attemptCount = 0;
  // 批量日志来源范围:CHAPTER/PAPER_PAST/PAPER_MOCK
  String sourceScope = 'CHAPTER';
  // 批量日志来源ID(章节 cate_id / 试卷 paper_id)
  int sourceId = 0;
  // 每题累计作答用时(秒),构建批量 answers 用
  final Map<int, int> _timeSpentByIndex = <int, int>{};
  // 入口原始 mode 参数(每日一练传 'prac',不记录批量日志)
  String _entryMode = '';
  // 题库题目类型(批量日志 question_type 参数,取自入口/章节列表 practice 信息)
  int _entryQuestionType = 0;
  // 是否正在批量提交日志(防交卷/退出并发重复提交)
  bool _logBatchSubmitting = false;

  // 获取当前题目
  Question get currentQuestion => questions.isNotEmpty
      ? questions[currentQuestionIndex.value]
      : Question(
          id: '',
          projectId: '',
          subjectId: '',
          chapterId: '',
          type: 'single',
          content: '',
          options: [],
          correctAnswers: [],
          explanation: '',
          difficulty: 'medium',
        );

  // 获取当前题目的用户答案
  List<int>? get currentUserAnswer => userAnswers[currentQuestionIndex.value];

  // 当前页面模式：EXAM（考试模式）、TRAINING（练习模式）、VIEW（背题模式）
  final RxString pageMode = 'TRAINING'.obs;

  // 切换页面模式
  // TRAINING/EXAM: 答题模式（不显示答案，自动跳转下一题）
  // VIEW: 背题模式（显示答案解析，不自动跳转）
  void changePageMode(String mode) {
    final String oldMode = pageMode.value;

    if (oldMode == mode) return; // 模式没变则不处理

    pageMode.value = mode;

    // 同步更新全局状态（持久化存储）
    if (Get.isRegistered<GlobalProjectController>()) {
      GlobalProjectController.to.setPageMode(mode);
    }

    // 统一设置视图和解析状态
    isDetailView.value = true;
    showExplanation.value = false;

    AppLog.d(
        '🔄🔄🔄 模式从 $oldMode 切换到 $mode (paperId=$paperId, pageType=$pageType) 🔄🔄🔄');

    // ====== 场景A：试卷模式切换到背题时重新加载 ======
    if (paperId != null && mode == 'VIEW' && oldMode != 'VIEW') {
      AppLog.d('🔄 切换到背题模式，重新加载试卷数据以确保获取答案');
      _reloadForViewMode();
    }

    // ====== 场景B：收藏模式切换模式时的特殊处理 ======
    if (pageType == 'favorite') {
      if (mode == 'VIEW') {
        // 收藏→背题：直接切换即可，数据已有完整答案（收藏列表自带 answer 字段）
        AppLog.d('📌 收藏模式切换到背题模式');
        showExplanation.value = false;
      } else {
        // 收藏→答题：重启计时器
        _ensureTimerRunning();
        AppLog.d('📌 收藏模式切换到答题模式 计时器已启动');
      }
    } else {
      // ====== 场景C：普通试卷模式 ======
      // 切换回答题模式时重启计时器
      if (mode != 'VIEW' && paperId != null) {
        Future.delayed(Duration(milliseconds: 100), () => _startTimer());
      }
    }

    update();
  }

  /// 为背题模式重新加载数据（确保带答案）
  Future<void> _reloadForViewMode() async {
    isLoading.value = true;
    try {
      // 使用相同的 paperId 重新加载，_loadQuestionsFromPaper 内部已始终传 show_answer=1
      await _loadQuestionsFromPaper(paperId);

      // 检查加载后的数据是否有答案
      if (questions.isNotEmpty) {
        int answerCount =
            questions.where((q) => q.correctAnswers.isNotEmpty).length;
        AppLog.d('背题模式重载完成: ${questions.length} $answerCount题有答案');

        if (answerCount == 0) {
          AppLog.d('⚠️ 警告：所有题目都没有答案数据！接口可能未返回答案字段');
        }
      }
    } catch (e) {
      AppLog.d('背题模式重载失败: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // 设置字体大小
  void setFontSize(double scale) {
    fontSizeScale.value = scale;
    update();
  }

  // 设置行距
  void setLineHeight(double height) {
    lineHeight.value = height;
    update();
  }

  // 切换自动跳转
  void toggleAutoNext(bool value) {
    isAutoNext.value = value;
    update();
  }

  // 切换自动显示解析
  void toggleAutoShowExplanation(bool value) {
    isAutoShowExplanation.value = value;
    update();
  }

  // 切换夜间模式
  void toggleDarkMode(bool value) {
    isDarkMode.value = value;
    update();
  }

  @override
  void onInit() {
    super.onInit();

    // ====== 无法忽略的启动标志 ======
    debugPrint('╔══════════════════════════════════════╗');
    debugPrint('QuestionTrainController onInit 启动');
    debugPrint('时间: ${DateTime.now()}');
    debugPrint('╚══════════════════════════════════════╝');
    AppLog.d(
        '🚀🚀🚀 QuestionTrainController onInit - NEW CODE LOADED at ${DateTime.now()} 🚀🚀🚀');

    // 初始化本地存储状态
    hasSeenSwipePrompt.value = _box.read('hasSeenSwipePrompt') ?? false;

    try {
      // 优先尝试从 URL 参数 获取参数，这通常更常用
      if (Get.parameters.containsKey('cate_id')) {
        var paramId = Get.parameters['cate_id'];
        // 尝试解析为 int 或保留为 String
        if (paramId != null && paramId.isNotEmpty) {
          // 如果是纯数字字符串，也可以转换为 int，但保留 string 也可以，只要后续处理一即可
          // 这里我们先存args 模拟结构，或者直接使用
          AppLog.d('URL Parameters 获取cate_id: $paramId');
        }
      }

      // 获取传递的参数
      final dynamic args = Get.arguments;

      // 1. 初始化页面模式：优先使用全局配置，否则默认为 TRAINING
      try {
        if (Get.isRegistered<GlobalProjectController>()) {
          final globalMode =
              GlobalProjectController.to.pageMode.value.toString().trim();
          if (globalMode == 'TRAINING' ||
              globalMode == 'EXAM' ||
              globalMode == 'VIEW') {
            pageMode.value = globalMode;
            AppLog.d('从全局配置初始化页面模式: ${pageMode.value}');
          } else {
            AppLog.d('全局配置模式无效: $globalMode，使用默认值 TRAINING');
            pageMode.value = 'TRAINING';
          }
        }
      } catch (e) {
        AppLog.d('获取全局页面模式失败: $e');
      }

      // 如果 pageMode 为空或无效，默认设置为 TRAINING
      if (pageMode.value.isEmpty) {
        pageMode.value = 'TRAINING';
        AppLog.d('默认设置页面模式为 TRAINING');
      }

      // 调试信息
      AppLog.d('QuestionTrainController Params: ${Get.parameters}');

      if (args != null && args is Map) {
        // 0. 识别页面来源类型（收藏模式）
        pageType = (args['pageType'] as String?) ?? '';

        // 收藏来源类型:优先取入口显式传参,未传则按 pageType 兜底
        // 1=章节练习,2=历年真题,3=模拟考试;收藏/错题/搜索等来源不明场景默认 1
        final typeArg = args['type'];
        if (typeArg != null) {
          collectType = int.tryParse(typeArg.toString()) ?? 1;
        } else if (pageType == 'past' || pageType == 'past_exams') {
          collectType = 2;
        } else if (pageType == 'mock' || pageType == 'mock_exams') {
          collectType = 3;
        } else {
          collectType = 1;
        }
        AppLog.d('🔖 收藏来源类型 collectType=$collectType (pageType=$pageType)');

        // 收藏模式：使用 cate_name 作为标题
        if (pageType == 'favorite') {
          subject = (args['cate_name'] as String?) ?? '收藏题目';
          AppLog.d('📌 检测到收藏模式: $subject');
        }

        // pageConfig 模式：从页面配置ID获取题目
        if (pageType == 'page_config') {
          pageConfigId = args['pageConfigId'];
          subject = (args['title'] as String?) ?? '题目练习';
          AppLog.d('🔧 检测到页面配置模式: pageConfigId=$pageConfigId, title=$subject');
        }

        // 优先使用传递的 subject，如果没有则尝试使用 title (通常来自试卷列表)
        subject =
            (args['subject'] as String?) ?? (args['title'] as String?) ?? '';
        chapter = (args['chapter'] as String?) ?? '';
        section = (args['sectionTitle'] as String?) ?? '';
        subsection = (args['subsectionTitle'] as String?) ?? '';

        // 2. 如果传递了 mode 参数，覆盖全局配置
        // 先存原始 mode(每日一练传 'prac' 用于排除批量日志)
        _entryMode = args['mode']?.toString().trim() ?? '';
        if (args['mode'] != null) {
          final modeStr = args['mode'].toString().trim();
          if (modeStr == 'TRAINING' || modeStr == 'EXAM' || modeStr == 'VIEW') {
            pageMode.value = modeStr;
            AppLog.d('从参数初始化页面模式: ${pageMode.value}');
          } else {
            AppLog.d('无效的 mode 参数: $modeStr，保持当前模式 ${pageMode.value}');
          }
        }

        // 看题模式默认进入详情页（原为列表页，现已改为直接进入答题页）
        if (pageMode.value == 'VIEW') {
          isDetailView.value = true;
          // 看题模式初始不显示解析，点击选项后显示
          showExplanation.value = false;
        } else {
          isDetailView.value = true;
        }

        // 获取试卷信息
        totalScore = (args['total_score'] is int)
            ? args['total_score']
            : int.tryParse(args['total_score']?.toString() ?? '0') ?? 0;
        passScore = (args['pass_score'] is int)
            ? args['pass_score']
            : int.tryParse(args['pass_score']?.toString() ?? '0') ?? 0;
        paperId = args['paper_id'];
        AppLog.d('🎯 paperId 赋值：$paperId (类型：${paperId.runtimeType})');

        // ====== 练习会话(practice)参数解析 ======
        // 章节/试卷列表返回 practice 信息,practice_id>0 表示续答(进入后调 practice/detail 回填)
        try {
          final practiceRaw = args['practice'];
          if (practiceRaw is Map) {
            // 列表 practice 对象的 status: NONE=无记录, FINISHED=已交卷, 其他=练习中(续答)
            final practiceStatus = practiceRaw['status']?.toString() ?? '';
            final rawPracticeId =
                int.tryParse(practiceRaw['practice_id']?.toString() ?? '') ?? 0;
            attemptCount =
                int.tryParse(practiceRaw['attempt_count']?.toString() ?? '') ?? 0;
            _entryQuestionType =
                int.tryParse(practiceRaw['question_type']?.toString() ?? '') ?? 0;
            // ★已交卷(FINISHED)的练习:不再续答旧答题卡,按新一轮开始(practice_id=0);
            // 否则后端 SUBMIT 会判重复交卷(replayed)返回旧结果,列表进度不更新
            if (practiceStatus == 'FINISHED') {
              practiceId = 0;
              AppLog.d('🧾 practice 已交卷(FINISHED),按新一轮开始(practice_id=0)');
            } else {
              practiceId = rawPracticeId;
            }
          } else {
            practiceId = int.tryParse(args['practice_id']?.toString() ?? '') ?? 0;
          }
        } catch (e) {
          AppLog.d('解析 practice 参数失败: $e');
        }
        if (_entryQuestionType == 0) {
          _entryQuestionType =
              int.tryParse(args['question_type']?.toString() ?? '') ??
                  int.tryParse(Get.parameters['question_type'] ?? '') ??
                  0;
        }

        // source_scope:入口已透传则直接用,否则按来源推导
        final scopeArg = args['source_scope'];
        if (scopeArg is String && scopeArg.isNotEmpty) {
          sourceScope = scopeArg;
        } else if (paperId != null) {
          sourceScope = pageType == 'past' ? 'PAPER_PAST' : 'PAPER_MOCK';
        } else {
          sourceScope = 'CHAPTER';
        }

        // source_id:入口透传优先,兜底 paper_id / cate_id
        sourceId = int.tryParse(args['source_id']?.toString() ?? '') ?? 0;
        if (sourceId == 0 && paperId != null) {
          sourceId = paperId is int
              ? paperId
              : int.tryParse(paperId.toString()) ?? 0;
        }
        if (sourceId == 0) {
          final cateRaw = args['cate_id'] ?? Get.parameters['cate_id'];
          sourceId = int.tryParse(cateRaw?.toString() ?? '') ?? 0;
        }
        AppLog.d(
            '🧾 practiceId=$practiceId, attemptCount=$attemptCount, sourceScope=$sourceScope, sourceId=$sourceId');

        // 初始化倒计时（试卷模式/考试模式）
        if (paperId != null || pageMode.value == 'EXAM') {
          int limitTime = (args['limit_time'] is int)
              ? args['limit_time']
              : int.tryParse(args['limit_time']?.toString() ?? '0') ?? 5400;
          // 如果没有传递 limit_time，默认90分钟(5400秒)
          if (limitTime <= 0) {
            limitTime = 5400;
            AppLog.d('⚠️ limit_time 未设置或无效，使用默认值90分钟');
          }
          _setRemaining(limitTime);
          examInitialSeconds = limitTime;
        }

        AppLog.d(
            '接收到的参数: subject=$subject, chapter=$chapter, mode=${pageMode.value}, paperId=$paperId, remainingSeconds=${remainingSeconds.value}');
      }
    } catch (e) {
      AppLog.d('接收参数时出错: $e');
    }

    // 启动计时器（所有模式都启动，根据 isCountdownMode 决定是否倒计时）
    // VIEW 模式也启动计时器（记录学习时长），但不强制要倒计时
    if (pageMode.value != 'VIEW') {
      _startTimer();
    }

    // 如果是看题模式，初始化不显示解析，等待用户点击选项后显示
    if (pageMode.value == 'VIEW') {
      showExplanation.value = false;
    } else if (pageMode.value == 'TRAINING') {
      // 练习模式默认不显示解析
      showExplanation.value = false;
    }

    // 加载题目数据
    _loadQuestions();
  }

  @override
  void onReady() {
    AppLog.d('🚀 QuestionTrainController onReady called');
    super.onReady();
  }

  @override
  void onClose() {
    // 退出页面时保存考试进度(供下次进入恢复)。
    // ★2026-08-14 修复:交卷成功后不保存(onClose 不再把已删除的进度写回,
    // 否则下次进入误弹"继续考试");未交卷(返回/失败)退出才保存
    if (!_isExamSubmitted) {
      _saveExamProgress();
    }

    // 清理所有定时器（防止内存泄漏）
    _timer?.cancel();
    _timer = null;
    _multiSelectDebounceTimer?.cancel();
    _multiSelectDebounceTimer = null;
    _singleSelectTimer?.cancel();
    _singleSelectTimer = null;

    pageController.dispose();
    super.onClose();
  }

  // 加载题目数据
  Future<void> _loadQuestions() async {
    AppLog.d(
        '📚 _loadQuestions 开始加载题目数据, paperId=$paperId, pageMode=${pageMode.value}');
    isLoading.value = true;
    errorMessage.value = '';
    questions.clear();

    try {
      final dynamic args = Get.arguments;
      dynamic cateId;
      dynamic subjectId;
      dynamic questionType;

      // 检查是否从 paper_id 加载（真题模式）
      if (paperId != null) {
        AppLog.d('📝 paperId 加载试题: $paperId');
        await _loadQuestionsFromPaper(paperId);
        return;
      }

      // 1. 优先从 URL Parameters 获取 cate_id
      if (Get.parameters.containsKey('cate_id')) {
        cateId = Get.parameters['cate_id'];
        AppLog.d('QuestionTrainController: Got cate_id from parameters: $cateId');
      }
      if (Get.parameters.containsKey('question_type')) {
        questionType = Get.parameters['question_type'];
        AppLog.d(
            'QuestionTrainController: Got question_type from parameters: $questionType');
      }

      AppLog.d('QuestionTrainController _loadQuestions args: $args');

      if (cateId == null && args != null && args is Map) {
        // 2. 其次获取明确传递的 cate_id (arguments)
        cateId = args['cate_id'];

        // 如果没有，尝试从 id 获取
        if (cateId == null) {
          cateId = args['id'];
        }

        // 兼容旧的 sectionData 结构 (虽然 View 层已经简化，但保留逻辑以防万一)
        if (cateId == null && args['sectionData'] is Map) {
          final sectionData = args['sectionData'];
          cateId = sectionData['id'] ?? sectionData['cate_id'];
          if (cateId == null && sectionData['raw'] is Map) {
            final raw = sectionData['raw'];
            cateId = raw['id'] ?? raw['cate_id'];
          }
        }

        subjectId = args['subject_id'] ?? args['subjectId'];
        questionType ??= args['question_type'] ?? args['questionType'];
      }

      AppLog.d('Parsed cate_id: $cateId (Type: ${cateId.runtimeType})');

      // 收藏/错题模式：直接从传入的 items 列表构建题目，不需 cate_id
      if ((pageType == 'favorite' || pageType == 'wrong') && cateId == null) {
        AppLog.d('📌 ${pageType == 'favorite' ? '收藏' : '错题'}模式：从 args.items 加载题目');
        if (pageType == 'wrong') {
          await _loadQuestionsFromWrong();
        } else {
          await _loadQuestionsFromFavorite();
        }
        return;
      }

      // 搜索模式：直接从传入的 items（搜索接口返回的原始题目）构建题目
      if (pageType == 'search') {
        AppLog.d('🔍 搜索模式：从 args.items 加载题目');
        await _loadQuestionsFromSearch();
        return;
      }

      // 页面配置模式：通过 pageConfigId 获取题目
      if (pageType == 'page_config' && pageConfigId != null) {
        AppLog.d('🔧 页面配置模式：通过 pageConfigId=$pageConfigId 获取题目');
        await _loadQuestionsFromPageConfig();
        return;
      }

      // 每日一练模式（prac）：不需要cate_id，随机返回10道题
      final isPracMode = (args?['mode']?.toString() ?? '') == 'prac';

      if (cateId == null && !isPracMode) {
        AppLog.d('⚠️ 参数错误：cate_id 为空，无法发起请求');
        errorMessage.value = '参数错误：无法获取章节ID';
        isLoading.value = false;
        return;
      }

      // 构建请求参数
      final Map<String, dynamic> queryParams = {};
      if (cateId != null) {
        queryParams['cate_id'] = cateId;
      }
      if (paperId != null) {
        queryParams['paper_id'] = paperId;
      }
      if (subjectId != null && subjectId.toString().isNotEmpty) {
        queryParams['subject_id'] = subjectId;
      }
      if (questionType != null && questionType.toString().isNotEmpty) {
        queryParams['question_type'] = questionType;
      }

      // 添加 mode 参数
      if (isPracMode) {
        queryParams['mode'] = 'prac';
      } else if (pageMode.value == 'TRAINING') {
        queryParams['mode'] = 'normal';
      } else if (pageMode.value == 'EXAM') {
        queryParams['mode'] = 'exam';
      }

      AppLog.d('Requesting questions with params: $queryParams');

      final response = await ApiClient.to.getExam(
        'question/train',
        queryParameters: queryParams,
      );

      AppLog.d('API Response Status: ${response.statusCode}');
      AppLog.d('API Response Data: ${response.data}');

      if (response.statusCode == 200) {
        var data = response.data;
        AppLog.d('Raw Response Data Type: ${data.runtimeType}');

        // 处理 String 类型的响应数据
        if (data is String) {
          try {
            data = jsonDecode(data);
            AppLog.d('Decoded JSON Data: $data');
          } catch (e) {
            AppLog.d('JSON decode error: $e');
          }
        }

        // 兼容 code 为字符串的情况
        final code = data is Map ? data['code'] : null;
        final isSuccess = code == 1 || code == '1';

        if (data is Map && isSuccess) {
          final responseData = data['data'];
          AppLog.d('Response Data Field: $responseData');

          List<dynamic> rawQuestions = [];

          if (responseData is Map && responseData.containsKey('data')) {
            rawQuestions = responseData['data'];
          } else if (responseData is List) {
            rawQuestions = responseData;
          }

          AppLog.d('Raw Questions Count: ${rawQuestions.length}');

          if (rawQuestions.isEmpty) {
            errorMessage.value = '暂无题目数据';
          } else {
            final parsedQuestions = <Question>[];
            for (var q in rawQuestions) {
              try {
                parsedQuestions.add(_parseQuestion(q));
              } catch (e) {
                AppLog.d('Error parsing question: $e, Data: $q');
              }
            }

            if (parsedQuestions.isEmpty) {
              errorMessage.value = '题目数据解析失败';
            } else {
              questions.assignAll(parsedQuestions);
              // 初始化收藏状态
              _initFavoriteStatus();
              // 跳转到第一个未做过的题
              _jumpToFirstUndoneQuestion();
              // practice_id>0 时拉取练习记录详情,回填上次作答并续答
              _maybeRestorePractice();
            }
          }
        } else {
          errorMessage.value =
              data is Map ? (data['msg'] ?? '获取题目失败') : '数据格式错误';
        }
      } else {
        errorMessage.value = '网络请求失败: ${response.statusCode}';
      }
    } catch (e) {
      AppLog.d('Error loading questions: $e');
      errorMessage.value = '加载题目出错，请稍后重试';
    } finally {
      isLoading.value = false;
    }
  }

  // ====== 从页面配置ID加载题目（动态配置模式）======
  Future<void> _loadQuestionsFromPageConfig() async {
    AppLog.d('🔧 ===== _loadQuestionsFromPageConfig 开始 =====');
    AppLog.d('🔧 pageConfigId=$pageConfigId, pageMode=${pageMode.value}');

    if (pageConfigId == null) {
      AppLog.d('⚠️ 参数错误：pageConfigId 为空');
      errorMessage.value = '页面配置 ID 为空';
      isLoading.value = false;
      return;
    }

    try {
      final response = await ApiClient.to.getExam(
        'paper/getQuestionsByPageConfig',
        queryParameters: {'id': pageConfigId},
      );

      AppLog.d('🔧 getQuestionsByPageConfig 返回: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = response.data;

        if (data['code'] == 1) {
          final listData = data['data'];
          final questionsRaw = (listData is Map)
              ? (listData['data'] as List?) ?? []
              : (listData is List ? listData : []);

          if (questionsRaw.isEmpty) {
            errorMessage.value = '暂无题目数据';
            AppLog.d('⚠️ 页面配置返回题目为空');
          } else {
            AppLog.d('🔧 获取 ${questionsRaw.length} 道题目');

            final parsedQuestions = <Question>[];
            for (var q in questionsRaw) {
              if (q is! Map) continue;
              try {
                final qMap = Map<String, dynamic>.from(q);
                parsedQuestions.add(_parseQuestion(qMap));
              } catch (e) {
                AppLog.d('⚠️ 解析单题失败: $e, 数据: ${q.keys}');
              }
            }

            if (parsedQuestions.isNotEmpty) {
              questions.assignAll(parsedQuestions);
              _initFavoriteStatus();
              // 跳转到第一个未做过的题
              _jumpToFirstUndoneQuestion();
              _ensureTimerRunning();
              AppLog.d('🔧 页面配置题目加载完成: ${parsedQuestions.length} 道题目');
            } else {
              errorMessage.value = '题目数据解析失败';
            }
          }
        } else {
          String msg = data['msg']?.toString() ?? '获取题目失败';
          // 检查是否需要开通会员
          final extra = data['data'];
          if (extra is Map && extra['need_open'] == true) {
            msg = '该功能仅针对会员开放，请开通会员后再试';
          }
          errorMessage.value = msg;
          AppLog.d('⚠️ API返回错误: $msg');
        }
      } else {
        errorMessage.value = '网络请求失败: ${response.statusCode}';
        AppLog.d('⚠️ 网络请求失败: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      AppLog.d('🔧 _loadQuestionsFromPageConfig 错误: $e');
      AppLog.d('堆栈: $stackTrace');
      errorMessage.value = '加载页面配置题目失败: $e';
    } finally {
      isLoading.value = false;
    }
  }

  // ====== 从试卷ID加载题目（真题模式）======
  // 根据 pageMode 决定是否请求带答案的数据
  Future<void> _loadQuestionsFromPaper(dynamic paperId) async {
    AppLog.d(
        '📝📝📝📝📝 _loadQuestionsFromPaper 被调用！！！ paperId=$paperId, pageMode=${pageMode.value} 📝📝📝📝📝');

    if (paperId == null) {
      AppLog.d('⚠️ paperId 为空，无法加载试题');
      errorMessage.value = '试卷 ID 为空';
      isLoading.value = false;
      return;
    }

    try {
      // 生成时间戳
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // 始终请求带答案的数据（包括正确答案和解析）
      // 答案的显示隐藏由前端UI 层根pageMode showExplanation 控制，而非接口层面限制
      AppLog.d('🌐 请求 API: paper/getExamQuestion');
      AppLog.d('参数：paper_id=$paperId, timestamp=$timestamp, show_answer=1(始终)');

      final Map<String, dynamic> queryParams = {
        'paper_id': paperId,
        'timestamp': timestamp,
        'show_answer': 1,
      };

      final response = await ApiClient.to.getExam(
        'paper/getExamQuestion',
        queryParameters: queryParams,
      );

      AppLog.d('API Response Status: ${response.statusCode}');
      AppLog.d('API Response Data: ${response.data}');

      if (response.statusCode == 200) {
        var data = response.data;

        // 处理 String 类型的响应数据
        if (data is String) {
          try {
            data = jsonDecode(data);
            AppLog.d('Decoded JSON Data: $data');
          } catch (e) {
            AppLog.d('JSON decode error: $e');
          }
        }

        // 兼容 code 为字符串的情况
        final code = data is Map ? data['code'] : null;
        final isSuccess = code == 1 || code == '1';

        if (data is Map && isSuccess) {
          final responseData = data['data'];
          AppLog.d('Response Data Field: $responseData');

          // ====== 从接口响应中提取试卷配置（含 limit_time）=====
          _extractPaperConfigFromResponse(responseData);

          List<dynamic> rawQuestions = [];

          // 解析题目列表
          if (responseData is Map) {
            // 优先检查 questions 字段（来paper API）
            if (responseData.containsKey('questions')) {
              rawQuestions = responseData['questions'];
              AppLog.d('从 questions 字段获取题目');
            } else if (responseData.containsKey('list')) {
              rawQuestions = responseData['list'];
              AppLog.d('从 list 字段获取题目');
            } else if (responseData.containsKey('paper') &&
                responseData['paper'] is Map) {
              // 有些 API 返回的是 { paper: {...}, questions: [...] }
              final paperData = responseData['paper'];
              if (paperData is Map && paperData.containsKey('questions')) {
                rawQuestions = paperData['questions'];
                AppLog.d('从 paper.questions 字段获取题目');
              }
            }
          } else if (responseData is List) {
            rawQuestions = responseData;
            AppLog.d('直接从 responseData 获取题目');
          }

          AppLog.d('Raw Questions Count: ${rawQuestions.length}');

          if (rawQuestions.isEmpty) {
            errorMessage.value = '暂无题目数据';
            AppLog.d('未找到题目数');
          } else {
            final parsedQuestions = <Question>[];
            for (var q in rawQuestions) {
              try {
                AppLog.d('📝 解析题目 ${q['title']}');
                parsedQuestions.add(_parseQuestionFromPaper(q));
              } catch (e) {
                AppLog.d('Error parsing question: $e, Data: $q');
              }
            }

            if (parsedQuestions.isEmpty) {
              errorMessage.value = '题目数据解析失败';
              AppLog.d('题目解析后为空');
            } else {
              questions.assignAll(parsedQuestions);
              // 初始化收藏状态
              _initFavoriteStatus();
              // 跳转到第一个未做过的题目
              _jumpToFirstUndoneQuestion();
              // ★检测上次未完成的考试进度(EXAM 试卷模式):弹窗询问继续/放弃
              _maybeRestoreExamProgress(paperId);
              // practice_id>0 时拉取练习记录详情,回填上次作答并续答
              _maybeRestorePractice();
              AppLog.d('成功加载 ${parsedQuestions.length} 道题');
              if (parsedQuestions.isNotEmpty) {
                final firstQ = parsedQuestions[0];
                AppLog.d(
                    '📋 第一道题解析结果: answer=${firstQ.answer}, correctAnswers=${firstQ.correctAnswers}');
              }
            }
          }
        } else {
          errorMessage.value =
              data is Map ? (data['msg'] ?? '获取题目失败') : '数据格式错误';
          AppLog.d('获取题目失败 ${errorMessage.value}');
        }
      } else {
        errorMessage.value = '网络请求失败 ${response.statusCode}';
        AppLog.d('网络请求失败 ${response.statusCode}');
      }
    } catch (e) {
      AppLog.d('Error loading questions from paper: $e');
      errorMessage.value = '加载题目出错，请稍后重试';
    } finally {
      isLoading.value = false;
    }
  }

  // ====== 从收藏列表加载题目（收藏模式）=====
  Future<void> _loadQuestionsFromFavorite() async {
    AppLog.d('📌 ===== _loadQuestionsFromFavorite 开始 =====');
    AppLog.d('📌 pageType=$pageType, pageMode=${pageMode.value}');

    try {
      final dynamic args = Get.arguments;
      if (args is! Map) {
        AppLog.d('args 不是 Map: ${args.runtimeType}');
        errorMessage.value = '收藏参数异常';
        return;
      }

      final itemsRaw = args['items'];
      AppLog.d(
          '📌 itemsRaw 类型: ${itemsRaw.runtimeType}, 数量: ${itemsRaw is List ? itemsRaw.length : "N/A"}');

      if (itemsRaw is! List || itemsRaw.isEmpty) {
        AppLog.d('items 为空或不是列表');
        errorMessage.value = '暂无收藏题目';
        return;
      }

      AppLog.d('📌 收藏题目数量: ${itemsRaw.length}');
      final parsedQuestions = <Question>[];

      int parseSuccessCount = 0;

      for (int idx = 0; idx < itemsRaw.length; idx++) {
        final item = itemsRaw[idx];
        if (item is! Map) continue;

        final itemMap = item as Map;

        // ====== 提取基本字段 ======
        final questionId = itemMap['question_id']?.toString() ??
            itemMap['id']?.toString() ??
            '';

        // title 可能在顶层或question 子对象中
        String title = itemMap['title']?.toString() ?? '';

        // kind / answer 同理
        String kindStr =
            (itemMap['kind'] as String?)?.toUpperCase() ?? 'SINGLE';
        String answer = itemMap['answer']?.toString() ?? '';

        // options_json 可能在顶层或 question 子对象内
        // 注意：options_json 可能是 List<Map> 或 String，不能无类型
        dynamic rawOptionsJson;
        dynamic rawOptionsImg;

        final topOptJson = itemMap['options_json'];
        if (topOptJson != null) {
          if (topOptJson is String && topOptJson.isNotEmpty) {
            rawOptionsJson = topOptJson;
          } else if (topOptJson is List && topOptJson.isNotEmpty) {
            rawOptionsJson = topOptJson;
          }
        }
        final topOptImg = itemMap['options_img'];
        if (topOptImg != null) {
          if (topOptImg is String && topOptImg.isNotEmpty) {
            rawOptionsImg = topOptImg;
          } else if (topOptImg is List && topOptImg.isNotEmpty) {
            rawOptionsImg = topOptImg;
          }
        }

        // 检查 question 子对象是否有更多/不同的数据
        final questionObj = itemMap['question'];
        if (questionObj is Map) {
          final qMap = <String, dynamic>{};
          for (final key in questionObj.keys) {
            qMap[key.toString()] = questionObj[key];
          }

          // 如果顶层没有 title，从子对象取
          if (title.isEmpty) title = qMap['title']?.toString() ?? '';
          // 如果顶层没有 kind，从子对象取
          if (kindStr == 'SINGLE' || kindStr.isEmpty) {
            kindStr = (qMap['kind']?.toString()?.toUpperCase()) ?? 'SINGLE';
          }
          // 如果顶层没有 answer，从子对象取
          if (answer.isEmpty) answer = qMap['answer']?.toString() ?? '';
          // 如果顶层没有 options_json，尝试从子对象取
          if (rawOptionsJson == null) {
            final subOpt = qMap['options_json'];
            if (subOpt is String && subOpt.isNotEmpty) {
              rawOptionsJson = subOpt;
            } else if (subOpt is List && subOpt.isNotEmpty) {
              rawOptionsJson = subOpt;
            }
          }
          if (rawOptionsImg == null) {
            final subImg = qMap['options_img'];
            if (subImg is String && subImg.isNotEmpty) {
              rawOptionsImg = subImg;
            } else if (subImg is List && subImg.isNotEmpty) {
              rawOptionsImg = subImg;
            }
          }
        }

        String kind = kindStr.toUpperCase().trim();
        if (kind.isEmpty) kind = 'SINGLE';

        AppLog.d(
            '📌 题[$idx]: id=$questionId, kind=$kind, answer=$answer, optType=${rawOptionsJson?.runtimeType}');
        AppLog.d(
            '📌 题[$idx]: title="${title.length > 50 ? title.substring(0, 50) : title}"');

        // ====== 解析选项 ======
        List<String> options =
            _parseOptionsWithImages(rawOptionsJson, rawOptionsImg, kind);
        AppLog.d('📌 题[$idx] 最终选项(${options.length}): $options');

        // ====== 计算正确答案索引 ======
        final correctAnswers = _parseAnswerToIndices(answer, options);
        AppLog.d('📌 题[$idx] correctAnswers: $correctAnswers');

        // ====== 映射 kind 到 type 字符串 ======
        String type = 'single';
        if (kind.contains('MULTI')) {
          type = 'multi';
        } else if (kind == 'JUDGE') {
          type = 'judgment';
        }

        parsedQuestions.add(Question(
          id: questionId,
          projectId: '',
          subjectId: '',
          type: type,
          kind: kind,
          content: title,
          options: options,
          correctAnswers: correctAnswers,
          answer: answer,
          explanation: itemMap['explain']?.toString() ?? '',
          difficulty:
              (itemMap['difficulty'] as String?)?.toLowerCase() ?? 'medium',
          chapterId: '',
          isCollected: true,
        ));
        parseSuccessCount++;
      }

      AppLog.d('📌 ===== 解析完成: 成功=$parseSuccessCount/${itemsRaw.length} =====');

      if (parsedQuestions.isEmpty) {
        errorMessage.value = '题目数据解析失败';
      } else {
        questions.assignAll(parsedQuestions);
        // 收藏模式全部标记为已收藏
        _initFavoriteStatus();
        // 跳转到第一个未做过的题目
        _jumpToFirstUndoneQuestion();

        // 收藏模式：确保计时器运行
        _ensureTimerRunning();

        AppLog.d('📌 ===== 收藏题目加载完成: ${parsedQuestions.length} =====');
      }
    } catch (e, stackTrace) {
      AppLog.d('_loadQuestionsFromFavorite 错误: $e');
      AppLog.d('堆栈: $stackTrace');
      errorMessage.value = '加载收藏题目失败: $e';
    } finally {
      isLoading.value = false;
    }
  }

  // ====== 从错题列表加载题目（错题模式）逻辑与收藏模式一致
  Future<void> _loadQuestionsFromWrong() async {
    AppLog.d('📌 ===== _loadQuestionsFromWrong 开始 =====');
    AppLog.d('📌 pageType=$pageType, pageMode=${pageMode.value}');

    try {
      final dynamic args = Get.arguments;
      if (args is! Map) {
        AppLog.d('args 不是 Map: ${args.runtimeType}');
        errorMessage.value = '错题参数异常';
        return;
      }

      final itemsRaw = args['items'];
      AppLog.d(
          '📌 itemsRaw 类型: ${itemsRaw.runtimeType}, 数量: ${itemsRaw is List ? itemsRaw.length : "N/A"}');

      if (itemsRaw is! List || itemsRaw.isEmpty) {
        AppLog.d('itemsRaw 为空或不是列表');
        errorMessage.value = '暂无错题';
        return;
      }

      AppLog.d('📌 错题数量: ${itemsRaw.length}');
      final parsedQuestions = <Question>[];

      int parseSuccessCount = 0;

      for (int idx = 0; idx < itemsRaw.length; idx++) {
        final item = itemsRaw[idx];
        if (item is! Map) continue;

        final itemMap = item as Map;

        String type = 'single';
        final kindStr = (itemMap['kind'] as String?)?.toUpperCase() ?? '';
        if (kindStr.contains('MULTI')) {
          type = 'multi';
        } else if (kindStr.contains('JUDGE') ||
            kindStr == 'TRUE_FALSE' ||
            kindStr == 'TF') {
          type = 'judgment';
        } else if (kindStr.contains('FILL') || kindStr == 'BLANK') {
          type = 'fill';
        } else if (kindStr.contains('SHORT') ||
            kindStr == 'ESSAY' ||
            kindStr == 'QA') {
          type = 'short';
        } else if (kindStr.isNotEmpty) {
          type = kindStr;
        }

        final title = itemMap['title']?.toString() ?? '';
        if (title.isEmpty) continue;

        final options = _parseOptionsWithImages(
            itemMap['options_json'], itemMap['options_img'], kindStr);

        final answerRaw = itemMap['answer']?.toString() ?? '';
        // 与收藏模式一致：将答案字符串转换为索引列表
        final correctAnswers = _parseAnswerToIndices(answerRaw, options);

        parsedQuestions.add(Question(
          id: (itemMap['question_id'] ?? itemMap['id'] ?? idx).toString(),
          projectId: '',
          subjectId: '',
          type: type,
          kind: kindStr,
          content: title,
          options: options,
          correctAnswers: correctAnswers,
          answer: answerRaw,
          explanation: itemMap['explain']?.toString() ?? '',
          difficulty:
              (itemMap['difficulty'] as String?)?.toLowerCase() ?? 'medium',
          chapterId: '',
          isCollected: false,
        ));
        parseSuccessCount++;
      }

      AppLog.d('📌 ===== 解析完成: 成功=$parseSuccessCount/${itemsRaw.length} =====');

      if (parsedQuestions.isEmpty) {
        errorMessage.value = '题目数据解析失败';
      } else {
        questions.assignAll(parsedQuestions);
        _initFavoriteStatus();
        // 跳转到第一个未做过的题目
        _jumpToFirstUndoneQuestion();
        _ensureTimerRunning();
        AppLog.d('📌 ===== 错题加载完成: ${parsedQuestions.length} =====');
      }
    } catch (e, stackTrace) {
      AppLog.d('_loadQuestionsFromWrong 错误: $e');
      AppLog.d('堆栈: $stackTrace');
      errorMessage.value = '加载错题失败: $e';
    } finally {
      isLoading.value = false;
    }
  }

  // ====== 从搜索结果加载题目（搜索模式）======
  // items 为搜索接口返回的原始题目数据，复用收藏/错题模式的解析思路
  Future<void> _loadQuestionsFromSearch() async {
    AppLog.d('🔍 ===== _loadQuestionsFromSearch 开始 =====');
    AppLog.d('🔍 pageType=$pageType, pageMode=${pageMode.value}');

    try {
      final dynamic args = Get.arguments;
      if (args is! Map) {
        AppLog.d('args 不是 Map: ${args.runtimeType}');
        errorMessage.value = '搜索参数异常';
        return;
      }

      final itemsRaw = args['items'];
      AppLog.d(
          '🔍 itemsRaw 类型: ${itemsRaw.runtimeType}, 数量: ${itemsRaw is List ? itemsRaw.length : "N/A"}');

      if (itemsRaw is! List || itemsRaw.isEmpty) {
        AppLog.d('items 为空或不是列表');
        errorMessage.value = '暂无题目数据';
        return;
      }

      AppLog.d('🔍 搜索题目数量: ${itemsRaw.length}');
      final parsedQuestions = <Question>[];
      int parseSuccessCount = 0;

      for (int idx = 0; idx < itemsRaw.length; idx++) {
        final item = itemsRaw[idx];
        if (item is! Map) continue;

        final itemMap = Map<String, dynamic>.from(item);

        // ====== 提取基本字段 ======
        final questionId = itemMap['id']?.toString() ??
            itemMap['question_id']?.toString() ??
            '';

        String title = itemMap['title']?.toString() ??
            itemMap['content']?.toString() ??
            '';

        // kind 优先取代码字段，其次 kind_text
        String kind = (itemMap['kind']?.toString() ??
                itemMap['kind_text']?.toString() ??
                'SINGLE')
            .toUpperCase();
        if (kind.isEmpty) kind = 'SINGLE';

        String answer = itemMap['answer']?.toString() ?? '';

        // 选项（兼容 options_json / options_img）
        final rawOptionsJson = itemMap['options_json'];
        final rawOptionsImg = itemMap['options_img'];

        AppLog.d(
            '🔍 题[$idx]: id=$questionId, kind=$kind, answer=$answer, optType=${rawOptionsJson?.runtimeType}');

        // ====== 解析选项 ======
        List<String> options =
            _parseOptionsWithImages(rawOptionsJson, rawOptionsImg, kind);
        AppLog.d('🔍 题[$idx] 最终选项(${options.length}): $options');

        // ====== 计算正确答案索引 ======
        final correctAnswers = _parseAnswerToIndices(answer, options);
        AppLog.d('🔍 题[$idx] correctAnswers: $correctAnswers');

        // ====== 映射 kind 到 type 字段字符串 ======
        String type = 'single';
        if (kind.contains('MULTI') || kind == 'X') {
          type = 'multi';
        } else if (kind.contains('JUDGE') ||
            kind == 'TRUE_FALSE' ||
            kind == 'TF') {
          type = 'judgment';
        }

        // 解析难度
        String difficulty = 'medium';
        final diffRaw = itemMap['difficulty']?.toString() ?? '';
        if (diffRaw == 'EASY' || diffRaw == 'easy') {
          difficulty = 'easy';
        } else if (diffRaw == 'HARD' || diffRaw == 'hard') {
          difficulty = 'hard';
        }

        parsedQuestions.add(Question(
          id: questionId,
          projectId: '',
          subjectId: itemMap['subject_id']?.toString() ?? '',
          type: type,
          kind: kind,
          content: title,
          options: options,
          correctAnswers: correctAnswers,
          answer: answer.isNotEmpty ? answer : null,
          explanation: itemMap['explain']?.toString() ??
              itemMap['explanation']?.toString() ??
              '',
          difficulty: difficulty,
          chapterId: '',
          isCollected: itemMap['collected'] == true ||
              itemMap['collected'] == 1 ||
              itemMap['is_collected'] == true,
          cateId: itemMap['cate_id']?.toString() ?? '',
        ));
        parseSuccessCount++;
      }

      AppLog.d('🔍 ===== 解析完成: 成功=$parseSuccessCount/${itemsRaw.length} =====');

      if (parsedQuestions.isEmpty) {
        errorMessage.value = '题目数据解析失败';
      } else {
        questions.assignAll(parsedQuestions);
        _initFavoriteStatus();
        // 跳转到第一个未做过的题
        _jumpToFirstUndoneQuestion();
        // 搜索模式：确保计时器运行
        _ensureTimerRunning();
        AppLog.d('🔍 ===== 搜索题目加载完成: ${parsedQuestions.length} =====');
      }
    } catch (e, stackTrace) {
      AppLog.d('_loadQuestionsFromSearch 错误: $e');
      AppLog.d('堆栈: $stackTrace');
      errorMessage.value = '加载搜索题目失败: $e';
    } finally {
      isLoading.value = false;
    }
  }

  /// 解析选项文本，并兼容后端单独返回的 options_img 图片选项。
  List<String> _parseOptionsWithImages(
      dynamic rawOpt, dynamic rawImg, String kind) {
    final textOptions = _parseOptionsMapDynamic(rawOpt, kind);
    final imageOptions = _parseOptionImagesDynamic(rawImg);

    if (imageOptions.isEmpty) {
      return textOptions.values.where((v) => v.trim().isNotEmpty).toList();
    }

    final keys = <String>{
      ...textOptions.keys,
      ...imageOptions.keys,
    }.toList()
      ..sort();

    final merged = <String>[];
    for (final key in keys) {
      final text = (textOptions[key] ?? '').trim();
      final imageUrl = imageOptions[key];
      if (imageUrl == null || imageUrl.isEmpty) {
        if (text.isNotEmpty) merged.add(text);
        continue;
      }

      final imageHtml = '<img src="$imageUrl" />';
      merged.add(text.isEmpty ? imageHtml : '$text<br />$imageHtml');
    }

    if (merged.isNotEmpty) {
      AppLog.d('🔍 _parseOptionsWithImages: 合并图片选项 ${merged.length} 个');
      return merged;
    }

    return textOptions.values.where((v) => v.trim().isNotEmpty).toList();
  }

  dynamic _pickRawOptions(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    if (rawOptions is List && rawOptions.isNotEmpty) {
      return rawOptions;
    }
    return json['options_json'];
  }

  Map<String, String> _parseOptionsMapDynamic(dynamic rawOpt, String kind) {
    final result = <String, String>{};

    if (rawOpt is List) {
      for (int i = 0; i < rawOpt.length; i++) {
        final item = rawOpt[i];
        final key = _extractOptionKey(item, i);
        final value = _extractOptionValue(item);
        result[key] = value;
      }
      AppLog.d('🔍 _parseOptionsMapDynamic: 从List提取 ${result.length} 个选项');
      if (result.values.any((v) => v.trim().isNotEmpty)) return result;
    }

    if (rawOpt is String && rawOpt.isNotEmpty) {
      final opts = _tryParseOptionsString(rawOpt);
      if (opts.isNotEmpty) return _optionsListToMap(opts);
    }

    if (kind.toUpperCase() == 'JUDGE') {
      return {'A': '正确', 'B': '错误'};
    }

    AppLog.d(
        '⚠️ _parseOptionsMapDynamic: 无法解析选项, type=${rawOpt?.runtimeType}, kind=$kind');
    return result;
  }

  Map<String, String> _parseOptionImagesDynamic(dynamic rawImg) {
    final result = <String, String>{};

    dynamic source = rawImg;
    if (rawImg is String && rawImg.trim().isNotEmpty) {
      try {
        source = jsonDecode(rawImg);
      } catch (_) {
        final cleaned = _cleanOptionImageUrl(rawImg);
        if (cleaned.isNotEmpty) result['A'] = cleaned;
        return result;
      }
    }

    if (source is List) {
      for (int i = 0; i < source.length; i++) {
        final item = source[i];
        final key = _extractOptionKey(item, i);
        final url = _cleanOptionImageUrl(_extractOptionValue(item));
        if (url.isNotEmpty) result[key] = url;
      }
    } else if (source is Map) {
      final keys = source.keys.map((k) => k.toString()).toList()..sort();
      for (final key in keys) {
        final url = _cleanOptionImageUrl(source[key]?.toString() ?? '');
        if (url.isNotEmpty) result[key.toUpperCase()] = url;
      }
    }

    return result;
  }

  String _extractOptionKey(dynamic item, int index) {
    if (item is Map) {
      final key = item['key'] ?? item['label'] ?? item['name'];
      if (key != null && key.toString().trim().isNotEmpty) {
        return key.toString().trim().toUpperCase();
      }
    }
    return String.fromCharCode(65 + index);
  }

  String _extractOptionValue(dynamic item) {
    if (item is Map) {
      return (item['value'] ?? item['text'] ?? item['content'] ?? '')
          .toString();
    }
    return item?.toString() ?? '';
  }

  Map<String, String> _optionsListToMap(List<String> options) {
    final result = <String, String>{};
    for (int i = 0; i < options.length; i++) {
      result[String.fromCharCode(65 + i)] = options[i];
    }
    return result;
  }

  String _cleanOptionImageUrl(String value) {
    var cleaned = value.trim();
    if (cleaned.isEmpty) return '';

    cleaned = cleaned
        .replaceAll(RegExp(r'^[`\s]+'), '')
        .replaceAll(RegExp(r'[`，,\s]+$'), '')
        .trim();

    if (cleaned.startsWith('<img')) {
      final match = RegExp(
        r'''src\s*=\s*(?:(["'])(.*?)\1|([^"'\s>]+))''',
        caseSensitive: false,
      ).firstMatch(cleaned);
      cleaned = (match?.group(2) ?? match?.group(3) ?? '').trim();
    }

    if (cleaned.startsWith('//')) {
      return 'https:$cleaned';
    }

    return cleaned;
  }

  /// 尝试解析 options_json 字符串（兼容标准 JSON 和非标准 Dart toString 格式）
  List<String> _tryParseOptionsString(String raw) {
    // 策略A: 直接当标准JSON 解析
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final sortedKeys = decoded.keys.map((k) => k.toString()).toList()
          ..sort();
        return sortedKeys
            .map((k) => decoded[k].toString())
            .where((v) => v.isNotEmpty)
            .toList();
      }
      if (decoded is List) {
        return _extractValuesFromList(decoded);
      }
    } catch (_) {}

    // 策略B: 修复非标准格式
    // 这种格式是 Dart Map/List 输出，key 没有引号
    if (raw.trimLeft().startsWith('[')) {
      try {
        final fixed = _fixDartToStringFormat(raw);
        if (fixed != null) {
          final decoded = jsonDecode(fixed);
          if (decoded is List) return _extractValuesFromList(decoded);
        }
      } catch (e) {
        AppLog.d('⚠️ _tryParseOptionsString: 格式修复也失败 $e');
      }
    }

    // 策略C: 正则兜底
    // 直接从字符串中提取所有的 value
    return _regexExtractValues(raw);
  }

  /// 修复 Dart .toString() 输出为符合 JSON 格式
  /// 例如: [{key: A, value: 呈同方向变化}] --> [{"key":"A","value":"呈同方向变化"}]
  String? _fixDartToStringFormat(String input) {
    try {
      final result = StringBuffer();
      int i = 0;

      while (i < input.length) {
        final ch = input[i];

        if (ch == '{' || ch == '[' || ch == ']' || ch == ',' || ch == ':') {
          result.write(ch);
          i++;
          // 跳过空白
          while (i < input.length && (input[i] == ' ' || input[i] == '\n')) i++;
          continue;
        }
        if (ch == '}') {
          result.write(ch);
          i++;
          continue;
        }
        if (ch == '"') {
          // 已有的双引号字符串，原样保留
          result.write(ch);
          i++;
          while (i < input.length && input[i] != '"') {
            if (input[i] == '\\') {
              result.write(input[i]);
              i++;
              if (i < input.length) {
                result.write(input[i]);
                i++;
              }
            } else {
              result.write(input[i]);
              i++;
            }
          }
          if (i < input.length) {
            result.write('"');
            i++;
          }
          continue;
        }

        // 无引号的 token（key 或值）读取到分隔符为止
        final start = i;
        while (i < input.length && !_isMapSeparator(input[i])) i++;
        final token = input.substring(start, i).trim();
        if (token.isNotEmpty) {
          result.write('"$token"');
        }
      }

      return result.toString();
    } catch (e) {
      AppLog.d('⚠️ _fixDartToStringFormat 异常: $e');
      return null;
    }
  }

  bool _isMapSeparator(String ch) {
    return ch == '{' ||
        ch == '}' ||
        ch == '[' ||
        ch == ']' ||
        ch == ',' ||
        ch == ':' ||
        ch == ' ';
  }

  /// 从解码后的 List 中提取 value 字段
  List<String> _extractValuesFromList(List decoded) {
    final opts = <String>[];
    for (final item in decoded) {
      if (item is Map) {
        final val = item['value'] ?? item['text'] ?? item['content'];
        if (val != null) opts.add(val.toString());
      } else if (item != null) {
        final str = item.toString();
        if (str.isNotEmpty) opts.add(str);
      }
    }
    AppLog.d('🔍 _extractValuesFromList: 提取 ${opts.length} 个选项');
    return opts;
  }

  /// 正则兜底提取 value: xxx
  List<String> _regexExtractValues(String raw) {
    final results = <String>[];
    // 匹配 value: 后面的内容（支持无引号）
    final regex = RegExp(r'value\s*:\s*([^,\}\]]+?)');
    final matches = regex.allMatches(raw);

    for (final match in matches) {
      String val = match.group(1)?.trim() ?? '';
      // 去除可能的引号
      if ((val.startsWith("'") && val.endsWith("'")) ||
          (val.startsWith('"') && val.endsWith('"'))) {
        val = val.substring(1, val.length - 1);
      }
      if (val.isNotEmpty) results.add(val);
    }

    if (results.isNotEmpty) {
      AppLog.d('🔍 _regexExtractValues: 用正则提取 ${results.length} 个选项');
    }
    return results;
  }

  /// 解析 options_json 为选项列表（仅处理 String 输入）
  List<String> _parseOptionsFromJson(
      String optionsJsonStr, String kind, String answer) {
    // 尝试解析 JSON
    if (optionsJsonStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(optionsJsonStr);
        if (decoded is Map) {
          // 按字母顺序排列
          final sortedKeys = decoded.keys.map((k) => k.toString()).toList()
            ..sort();
          final opts = sortedKeys
              .map((k) => decoded[k].toString())
              .where((v) => v.isNotEmpty)
              .toList();
          if (opts.isNotEmpty) return opts;
        } else if (decoded is List) {
          // 数组格式: ["选项A", "选项B", ...]
          final opts = decoded
              .map((v) => v.toString())
              .where((v) => v.isNotEmpty)
              .toList();
          if (opts.isNotEmpty) return opts;
        }
      } catch (e) {
        AppLog.d('⚠️ options_json JSON解析失败: $e, 原始长度: ${optionsJsonStr.length}');
      }
    }

    // 降级处理：根据题型生成默认选项
    if (kind == 'JUDGE') {
      return ['正确', '错误'];
    }

    // 非判断题但无选项数据 返回UI 会显示"暂无选项"）
    AppLog.d('⚠️ 无法解析选项，kind=$kind, answer=$answer');
    return [];
  }

  /// 将答案字符串(A/AB/ABC)转换为索引列表（[0], [0,1], [0,1,2]）
  List<int> _parseAnswerToIndices(String answer, List<String> options) {
    final indices = <int>[];
    if (answer.isEmpty) return indices;

    for (int i = 0; i < answer.length; i++) {
      final char = answer[i].toUpperCase();
      final code = char.codeUnitAt(0);
      if (code >= 65 && code <= 90) {
        // A-Z
        final idx = code - 65;
        // 只有在选项范围内才添加有效索引
        if (idx >= 0 && idx < options.length) {
          indices.add(idx);
        }
      }
    }
    return indices;
  }

  /// 确保计时器正在运行
  void _ensureTimerRunning() {
    if (_timer == null || !_timer!.isActive) {
      AppLog.d('📌 启动计时器（当前模式: ${pageMode.value}, 倒计时: $isCountdownMode）');
      _startTimer();
    }
  }

  // ====== 从接口响应中提取试卷配置（limit_time、total_score 等）======
  void _extractPaperConfigFromResponse(dynamic responseData) {
    if (responseData is! Map) return;

    dynamic limitTimeSource;

    // 优先从 paper 字段获取
    if (responseData.containsKey('paper') && responseData['paper'] is Map) {
      final paperData = responseData['paper'] as Map<String, dynamic>;
      limitTimeSource = paperData['limit_time'];

      // 同时更新总分和及格分
      if (paperData.containsKey('total_score')) {
        totalScore = (paperData['total_score'] is int)
            ? paperData['total_score']
            : int.tryParse(paperData['total_score']?.toString() ?? '0') ??
                totalScore;
      }
      if (paperData.containsKey('pass_score')) {
        passScore = (paperData['pass_score'] is int)
            ? paperData['pass_score']
            : int.tryParse(paperData['pass_score']?.toString() ?? '0') ??
                passScore;
      }

      AppLog.d(
          '📄 paper 字段提取配置: limit_time=$limitTimeSource, total_score=$totalScore, pass_score=$passScore');
    }

    // 其次尝试直接从 response data 获取
    if (limitTimeSource == null && responseData.containsKey('limit_time')) {
      limitTimeSource = responseData['limit_time'];
      AppLog.d('📄 response data 提取 limit_time: $limitTimeSource');
    }

    // 解析并更新倒计时
    if (limitTimeSource != null) {
      int apiLimitTime = 0;
      if (limitTimeSource is int) {
        apiLimitTime = limitTimeSource;
      } else if (limitTimeSource is String) {
        apiLimitTime = int.tryParse(limitTimeSource) ?? 0;
      } else if (limitTimeSource is double) {
        apiLimitTime = limitTimeSource.toInt();
      }

      if (apiLimitTime > 0) {
        _setRemaining(apiLimitTime);
        examInitialSeconds = apiLimitTime;
        AppLog.d('倒计时已更新为接口返回值 ${apiLimitTime}秒(${apiLimitTime ~/ 60}分钟)');
      } else {
        AppLog.d(
            '⚠️ 接口返回 limit_time 无效: $limitTimeSource，保持当前值 $remainingSeconds.value');
      }
    }
  }

  // 解析题目数据（从 paper API获取）
  Question _parseQuestionFromPaper(Map<String, dynamic> json) {
    // 解析题目 ID
    final questionId = json['id']?.toString() ?? '';

    // 解析题目类型
    String type = 'single';
    String kind = json['kind']?.toString() ?? 'SINGLE';

    // Map new kinds to functional types
    if (kind == 'MULTI' || kind == 'X') {
      type = 'multi';
    } else if (kind == 'JUDGE') {
      type = 'judgment';
    } else if (kind == 'SHORT') {
      type = 'short'; // 简答题
    } else {
      type = 'single';
    }

    // 解析题目内容
    final content = json['title']?.toString() ?? '';

    // ====== 简答题特殊处理 ======
    if (kind == 'SHORT') {
      AppLog.d('🔍[$questionId] 检测到简答题，跳过选项解析');

      // 解析解析（支持更多字段名）
      final explanation = json['explain']?.toString() ??
          json['explanation']?.toString() ??
          json['analysis']?.toString() ??
          '';

      // 解析难度
      String difficulty = 'medium';
      final difficultyStr = json['difficulty']?.toString() ?? '';
      if (difficultyStr == 'EASY') {
        difficulty = 'easy';
      } else if (difficultyStr == 'HARD') {
        difficulty = 'hard';
      }

      // 解析收藏状态
      final isCollected = json['collected'] == true ||
          json['collected'] == 1 ||
          json['is_collected'] == true;

      // 解析材料题相关字段
      final isMaterialChild = json['is_material_child'] ?? 0;
      final materialQuestionId = json['material_question_id'] ?? 0;
      final materialTitle = json['material_title']?.toString();
      final materialScore = json['material_score'] ?? 0;

      // 解析子题目列表（如果有）
      List<Question> materialQuestions = [];
      if (json['material_questions'] != null &&
          json['material_questions'] is List) {
        materialQuestions = (json['material_questions'] as List)
            .map((e) => _parseQuestionFromPaper(e))
            .toList();
      }

      return Question(
        id: questionId,
        projectId: json['project_id']?.toString() ?? '',
        subjectId: json['subject_id']?.toString() ?? '',
        chapterId: json['chapter_id']?.toString() ?? '',
        type: type,
        kind: kind,
        content: content,
        options: [], // 简答题没有选项
        correctAnswers: [], // 简答题没有固定答案索引
        answer: null, // 简答题的答案在answerDetail中
        explanation: explanation,
        difficulty: difficulty,
        isCollected: isCollected,
        cateId: json['cate_id']?.toString() ?? '',
        // 简答题相关
        answerDetail: json['answer'] != null && json['answer'] is Map
            ? AnswerDetail.fromJson(json['answer'])
            : null,
        // 材料题相关
        isMaterialChild: isMaterialChild,
        materialQuestionId: materialQuestionId,
        materialTitle: materialTitle,
        materialScore: materialScore,
        materialQuestions: materialQuestions,
        // 视频相关
        titleVideo: json['title_video']?.toString(),
        explainVideo: json['explain_video']?.toString(),
        titleVideoUrl: json['title_video_url']?.toString(),
        explainVideoUrl: json['explain_video_url']?.toString(),
      );
    }

    // ====== 选择题/判断题处理 ======
    final rawOptions = _pickRawOptions(json);
    final options =
        _parseOptionsWithImages(rawOptions, json['options_img'], kind);

    AppLog.d(
        '🔍[$questionId] 最终选项: ${options.isEmpty ? "⚠️ 空！" : options} (kind=$kind, 原始options类型=${json['options']?.runtimeType}, options_json类型=${json['options_json']?.runtimeType})');

    // ====== 增强的答案解析逻辑 ======
    List<int> correctAnswers = [];
    String answerStr = '';

    // 1. 直接尝试多种可能的答案字段名（按优先级排序）
    final answerFieldNames = [
      'answer',
      'answer_key',
      'right_answer',
      'correct_answer',
      'ans',
      'true_answer',
      'standard_answer'
    ];
    for (var fieldName in answerFieldNames) {
      if (json.containsKey(fieldName) &&
          json[fieldName]?.toString().isNotEmpty == true) {
        answerStr = json[fieldName]!.toString();
        AppLog.d('🔍[$questionId] 从字段 "$fieldName" 找到答案: $answerStr');
        break;
      }
    }

    // 2. 如果还没找到，尝试解析嵌套结构中的答案
    if (answerStr.isEmpty) {
      // 检查是否有 answer_object 或类似嵌套结构
      if (json['answer_object'] is Map) {
        answerStr = json['answer_object']['value']?.toString() ??
            json['answer_object']['answer']?.toString() ??
            '';
        if (answerStr.isNotEmpty)
          AppLog.d('🔍[$questionId] answer_object 获取答案: $answerStr');
      }
    }

    AppLog.d(
        '🔍 解析题目[$questionId] 答案: raw="$answerStr", 所有字段keys=${json.keys.toList()}');

    if (answerStr.isNotEmpty) {
      final answerKeys = answerStr.split(',').map((s) => s.trim()).toList();
      for (var key in answerKeys) {
        if (key.isNotEmpty) {
          int? index;
          // 支持大写字母 A,B,C...
          if (RegExp(r'^[A-Z]$').hasMatch(key)) {
            index = key.codeUnitAt(0) - 'A'.codeUnitAt(0);
          }
          // 支持小写字母 a,b,c...
          else if (RegExp(r'^[a-z]$').hasMatch(key)) {
            index = key.codeUnitAt(0) - 'a'.codeUnitAt(0);
          }
          // 支持数字 0,1,2...
          else if (RegExp(r'^\d+$').hasMatch(key)) {
            index = int.tryParse(key);
          }

          if (index != null && index >= 0) {
            correctAnswers.add(index);
          }
        }
      }
    }

    // 3. 如果还没找到答案，尝试从选项中提取（通过 is_right/is_correct 标记）
    if (correctAnswers.isEmpty && options.isNotEmpty) {
      AppLog.d('🔍[$questionId] 尝试从选项中提取答案 options原始数据: ${json['options']}');

      // 先检查 options 数组
      if (json['options'] is List) {
        int optIndex = 0;
        for (var opt in json['options']) {
          if (opt is Map) {
            final isRight = opt['is_right'] == true ||
                opt['is_correct'] == true ||
                opt['is_answer'] == true ||
                opt['right'] == 1 ||
                opt['correct'] == 1;
            if (isRight) {
              correctAnswers.add(optIndex);
              AppLog.d('🔍[$questionId] 选项$optIndex 标记为正确答案');
            }
          }
          optIndex++;
        }
      }

      // 再检查 options_json 数组
      if (correctAnswers.isEmpty && json['options_json'] is List) {
        int optIndex = 0;
        for (var opt in json['options_json']) {
          if (opt is Map) {
            final isRight = opt['is_right'] == true ||
                opt['is_correct'] == true ||
                opt['is_answer'] == true ||
                opt['right'] == 1;
            if (isRight) {
              correctAnswers.add(optIndex);
            }
          }
          optIndex++;
        }
      }

      if (correctAnswers.isNotEmpty) {
        answerStr =
            correctAnswers.map((i) => String.fromCharCode(65 + i)).join(',');
        AppLog.d('🔍[$questionId] 从选项中提取到答案: $answerStr');
      }
    }

    // 4. 最后的诊断日志
    if (correctAnswers.isEmpty) {
      AppLog.d('⚠️[$questionId] ⚠️ 未找到任何答案数据！题目可能缺少答案字段');
      AppLog.d('⚠️[$questionId] 完整JSON数据: $json');
    } else {
      AppLog.d('✅[$questionId] 成功解析答案: $answerStr -> indices=$correctAnswers');
    }

    // 解析解析（支持更多字段名）
    final explanation = json['explain']?.toString() ??
        json['explanation']?.toString() ??
        json['analysis']?.toString() ??
        json['content']?.toString() ?? // 有些API用content存解析
        '';

    // 解析难度
    String difficulty = 'medium';
    final difficultyStr = json['difficulty']?.toString() ?? '';
    if (difficultyStr == 'EASY') {
      difficulty = 'easy';
    } else if (difficultyStr == 'HARD') {
      difficulty = 'hard';
    }

    // 解析收藏状态
    final isCollected = json['collected'] == true ||
        json['collected'] == 1 ||
        json['is_collected'] == true;

    return Question(
      id: questionId,
      projectId: json['project_id']?.toString() ?? '',
      subjectId: json['subject_id']?.toString() ?? '',
      chapterId: json['chapter_id']?.toString() ?? '',
      type: type,
      kind: kind,
      content: content,
      options: options,
      correctAnswers: correctAnswers,
      answer: answerStr.isNotEmpty ? answerStr : null,
      explanation: explanation,
      difficulty: difficulty,
      isCollected: isCollected,
      cateId: json['cate_id']?.toString() ?? '',
    );
  }

  Question _parseQuestion(Map<String, dynamic> json) {
    // 解析题目 ID
    final questionId = json['id']?.toString() ?? '';

    // 解析题目类型
    String type = 'single';
    String kind = json['kind']?.toString() ?? 'SINGLE';

    if (kind == 'MULTI' || kind == 'X') {
      type = 'multi';
    } else if (kind == 'JUDGE') {
      type = 'judgment';
    } else if (kind == 'SHORT') {
      type = 'short'; // 简答题
    } else {
      type = 'single';
    }

    final content = json['title']?.toString() ?? '';

    // ====== 简答题特殊处理 ======
    if (kind == 'SHORT') {
      AppLog.d('🔍[$questionId] 检测到简答题，跳过选项解析');

      // 解析 question_status
      int? questionStatus;
      if (json.containsKey('question_status')) {
        final qs = json['question_status'];
        if (qs is int) {
          questionStatus = qs;
        } else {
          questionStatus = int.tryParse(qs.toString());
        }
      }

      // 解析用户之前选择的答案（用于恢复已答记录）
      // 简答题的用户答案是字符串，不是索引列表
      String? userAnswerStr;
      final userAnswerFields = [
        'user_answer',
        'my_answer',
        'selected_answer',
        'last_answer'
      ];
      for (var fieldName in userAnswerFields) {
        if (json.containsKey(fieldName) && json[fieldName] != null) {
          userAnswerStr = json[fieldName].toString();
          if (userAnswerStr.isNotEmpty) {
            AppLog.d('🔍[$questionId] 从字段 "$fieldName" 找到用户答案: $userAnswerStr');
            break;
          }
        }
      }

      // 解析材料题相关字段
      final isMaterialChild = json['is_material_child'] ?? 0;
      final materialQuestionId = json['material_question_id'] ?? 0;
      final materialTitle = json['material_title']?.toString();
      final materialScore = json['material_score'] ?? 0;

      // 解析子题目列表（如果有）
      List<Question> materialQuestions = [];
      if (json['material_questions'] != null &&
          json['material_questions'] is List) {
        materialQuestions = (json['material_questions'] as List)
            .map((e) => _parseQuestion(e))
            .toList();
      }

      return Question(
        id: questionId,
        projectId: json['project_id']?.toString() ?? '',
        subjectId: json['subject_id']?.toString() ?? '',
        chapterId: json['chapter_id']?.toString() ?? '',
        type: type,
        kind: kind,
        content: content,
        options: [], // 简答题没有选项
        correctAnswers: [], // 简答题没有固定答案索引
        answer: null, // 简答题的答案在answerDetail中
        explanation: json['explain']?.toString() ??
            json['explanation']?.toString() ??
            json['analysis']?.toString() ??
            '',
        difficulty: _parseDifficulty(json['difficulty']),
        isCollected: json['collected'] == true ||
            json['collected'] == 1 ||
            json['is_collected'] == true,
        cateId: json['cate_id']?.toString() ?? '',
        questionStatus: questionStatus,
        userAnswer: null, // 简答题不使用索引列表
        // 简答题相关
        answerDetail: json['answer'] != null && json['answer'] is Map
            ? AnswerDetail.fromJson(json['answer'])
            : null,
        // 材料题相关
        isMaterialChild: isMaterialChild,
        materialQuestionId: materialQuestionId,
        materialTitle: materialTitle,
        materialScore: materialScore,
        materialQuestions: materialQuestions,
        // 视频相关
        titleVideo: json['title_video']?.toString(),
        explainVideo: json['explain_video']?.toString(),
        titleVideoUrl: json['title_video_url']?.toString(),
        explainVideoUrl: json['explain_video_url']?.toString(),
      );
    }

    // ====== 选择题/判断题处理 ======
    final rawOptions = _pickRawOptions(json);
    final options =
        _parseOptionsWithImages(rawOptions, json['options_img'], kind);

    AppLog.d('🔍[$questionId] 最终选项: ${options.isEmpty ? "⚠️ 空！" : options}');

    // ====== 解析答案（增强版：兼容多种数据格式）======
    List<int> correctAnswers = [];
    String answerStr = '';

    // 1. 直接尝试多种可能的答案字段名
    final answerFieldNames = [
      'answer',
      'answer_key',
      'right_answer',
      'correct_answer',
      'ans',
      'true_answer',
      'standard_answer'
    ];
    for (var fieldName in answerFieldNames) {
      if (json.containsKey(fieldName) &&
          json[fieldName]?.toString().isNotEmpty == true) {
        answerStr = json[fieldName]!.toString();
        AppLog.d('🔍[$questionId] 从字段 "$fieldName" 找到答案: $answerStr');
        break;
      }
    }

    if (answerStr.isNotEmpty) {
      final answerKeys = answerStr.split(',').map((s) => s.trim()).toList();
      for (var key in answerKeys) {
        if (key.isNotEmpty) {
          int? index;
          if (RegExp(r'^[A-Z]$').hasMatch(key)) {
            index = key.codeUnitAt(0) - 'A'.codeUnitAt(0);
          } else if (RegExp(r'^[a-z]$').hasMatch(key)) {
            index = key.codeUnitAt(0) - 'a'.codeUnitAt(0);
          } else if (RegExp(r'^\d+$').hasMatch(key)) {
            index = int.tryParse(key);
          }

          if (index != null && index >= 0) {
            correctAnswers.add(index);
          }
        }
      }
    }

    // 2. 如果还没找到答案，尝试从选项中提取
    if (correctAnswers.isEmpty && options.isNotEmpty) {
      if (json['options'] is List) {
        int optIndex = 0;
        for (var opt in json['options']) {
          if (opt is Map) {
            final isRight = opt['is_right'] == true ||
                opt['is_correct'] == true ||
                opt['is_answer'] == true ||
                opt['right'] == 1 ||
                opt['correct'] == 1;
            if (isRight) correctAnswers.add(optIndex);
          }
          optIndex++;
        }
      }
      if (correctAnswers.isEmpty && json['options_json'] is List) {
        int optIndex = 0;
        for (var opt in json['options_json']) {
          if (opt is Map) {
            final isRight = opt['is_right'] == true ||
                opt['is_correct'] == true ||
                opt['is_answer'] == true;
            if (isRight) correctAnswers.add(optIndex);
          }
          optIndex++;
        }
      }
      if (correctAnswers.isNotEmpty) {
        answerStr =
            correctAnswers.map((i) => String.fromCharCode(65 + i)).join(',');
        AppLog.d('🔍[$questionId] 从选项中提取到答案: $answerStr');
      }
    }

    if (correctAnswers.isEmpty) {
      AppLog.d('⚠️[$questionId] 未找到任何答案数据！');
    } else {
      AppLog.d('✅[$questionId] 成功解析答案: $answerStr -> indices=$correctAnswers');
    }

    // 解析 question_status
    int? questionStatus;
    if (json.containsKey('question_status')) {
      final qs = json['question_status'];
      if (qs is int) {
        questionStatus = qs;
      } else {
        questionStatus = int.tryParse(qs.toString());
      }
    }

    // 解析用户之前选择的答案（用于恢复已答记录）
    List<int>? parsedUserAnswer;
    final userAnswerFields = [
      'user_answer',
      'my_answer',
      'selected_answer',
      'last_answer'
    ];
    for (var fieldName in userAnswerFields) {
      if (json.containsKey(fieldName) && json[fieldName] != null) {
        final ua = json[fieldName];
        if (ua is List) {
          parsedUserAnswer = ua
              .map((e) {
                if (e is int) return e;
                if (e is String) {
                  // 支持字母格式 A,B,C -> 0,1,2
                  if (RegExp(r'^[A-Z]$').hasMatch(e)) {
                    return e.codeUnitAt(0) - 'A'.codeUnitAt(0);
                  } else if (RegExp(r'^[a-z]$').hasMatch(e)) {
                    return e.codeUnitAt(0) - 'a'.codeUnitAt(0);
                  }
                  return int.tryParse(e) ?? -1;
                }
                return -1;
              })
              .where((i) => i >= 0)
              .toList();
          if (parsedUserAnswer.isNotEmpty) {
            AppLog.d('🔍[$questionId] 从字段 "$fieldName" 找到用户答案: $parsedUserAnswer');
            break;
          }
        } else if (ua is String && ua.isNotEmpty) {
          // 支持字符串格式 "A" 或 "A,B"
          final answerKeys = ua.split(',').map((s) => s.trim()).toList();
          final indices = <int>[];
          for (var key in answerKeys) {
            if (key.isEmpty) continue;
            int? index;
            if (RegExp(r'^[A-Z]$').hasMatch(key)) {
              index = key.codeUnitAt(0) - 'A'.codeUnitAt(0);
            } else if (RegExp(r'^[a-z]$').hasMatch(key)) {
              index = key.codeUnitAt(0) - 'a'.codeUnitAt(0);
            } else if (RegExp(r'^\d+$').hasMatch(key)) {
              index = int.tryParse(key);
            }
            if (index != null && index >= 0) {
              indices.add(index);
            }
          }
          if (indices.isNotEmpty) {
            parsedUserAnswer = indices;
            AppLog.d(
                '🔍[$questionId] 从字段 "$fieldName" 找到用户答案(字符串): $parsedUserAnswer');
            break;
          }
        }
      }
    }

    return Question(
      id: questionId,
      projectId: json['project_id']?.toString() ?? '',
      subjectId: json['subject_id']?.toString() ?? '',
      chapterId: json['chapter_id']?.toString() ?? '',
      type: type,
      kind: kind,
      content: json['title']?.toString() ?? '',
      options: options,
      correctAnswers: correctAnswers,
      answer: answerStr.isNotEmpty ? answerStr : null,
      explanation: json['explain']?.toString() ??
          json['explanation']?.toString() ??
          json['analysis']?.toString() ??
          '',
      difficulty: _parseDifficulty(json['difficulty']),
      isCollected: json['collected'] == true ||
          json['collected'] == 1 ||
          json['is_collected'] == true,
      cateId: json['cate_id']?.toString() ?? '',
      questionStatus: questionStatus,
      userAnswer: parsedUserAnswer,
    );
  }

  String _parseDifficulty(dynamic difficulty) {
    if (difficulty == 'EASY') return 'easy';
    if (difficulty == 'HARD') return 'hard';
    return 'medium'; // GENERAL -> medium
  }

  // 获取题型文本（供视图层使用）
  String getQuestionTypeText(Question question) {
    switch (question.kind) {
      case 'X':
        return '不定项选择题';
      case 'JUDGE':
        return '判断题';
      case 'SINGLE':
        return '单选题';
      case 'MULTI':
        return '多选题';
      case 'FILL':
        return '填空题';
      case 'SHORT':
        return '简答题';
      case 'MATERIAL':
        return '材料题';
      default:
        switch (question.type) {
          case 'single':
            return '单选题';
          case 'multi':
            return '多选题';
          case 'judgment':
            return '判断题';
          default:
            return '选择题';
        }
    }
  }

  // 格式化答案索引为字母（如 [0,1] -> "A,B"）
  String formatAnswerIndices(int index) {
    final question = questions[index];
    final indices = userAnswers[index];

    // 简答题：显示用户输入的文本答案
    if (question.kind == 'SHORT') {
      final answer = shortAnswers[index] ?? '';
      if (answer.isEmpty) return '未答';
      return answer;
    }

    // 选择题/判断题：转换为字母
    if (indices == null || indices.isEmpty) return '未答';
    // 简答题标记为已答（[-1]），但没有实际选项索引
    if (indices.length == 1 && indices[0] == -1) return '已答';
    return indices.map((i) => String.fromCharCode(65 + i)).join(',');
  }

  // 开始计时
  void _startTimer() {
    // 确保先取消已有计时器
    _timer?.cancel();
    _lastTickTime = DateTime.now();
    // 承接已累计的正计时(防止多次启动时丢失)
    _elapsedMs = elapsedSeconds.value * 1000;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();

      if (isCountdownMode) {
        // ★2026-08-14 修复:倒计时由墙钟绝对截止时刻重算(毫秒精度)。
        // 原按 tick 次数累减,diff 的 inSeconds 截断 + 回调延迟排队会系统性丢余数,
        // 主线程繁忙/模拟器上表现为"真实时间过了 2~3 秒倒计时才少 1 秒";
        // 改为截止时刻后,无论 tick 是否延迟每次都按真实流逝重算,退后台回前台也一次补准
        final end = _countdownEndTime;
        if (end == null) return;
        final remainMs = end.difference(now).inMilliseconds;
        final remainSec = remainMs > 0 ? (remainMs / 1000).ceil() : 0;
        if (remainingSeconds.value != remainSec) {
          remainingSeconds.value = remainSec;
        }
        if (remainMs <= 0) {
          _timer?.cancel();
          _timer = null;
          submitExam(auto: true);
        }
      } else {
        // 正计时:毫秒精度累加,显示向下取整(不丢 tick 余数)
        final diffMs = now.difference(_lastTickTime).inMilliseconds;
        _lastTickTime = now;
        if (diffMs > 0) {
          _elapsedMs += diffMs;
          final sec = _elapsedMs ~/ 1000;
          if (elapsedSeconds.value != sec) {
            elapsedSeconds.value = sec;
          }
        }
      }
    });
  }

  /// 设置倒计时剩余秒数并重算墙钟截止时刻
  /// (所有设置剩余时间的入口必须走这里,保证截止时刻与显示值一致)
  void _setRemaining(int seconds) {
    remainingSeconds.value = seconds;
    _countdownEndTime = DateTime.now().add(Duration(seconds: seconds));
  }

  // 交卷 - 调用后端 API
  Future<void> submitExam({bool auto = false}) async {
    // ★2026-08-14 修复:已交卷后禁止再次提交
    // (防止结果页返回答题页后重复点交卷,造成同一份答案重复提交)
    if (_isExamSubmitted) return;

    if (auto) {
      // ★2026-08-14 修复:倒计时归零走完整提交流程(跳过确认弹窗),
      // 不再直接退出丢答案;提交前先保存进度,失败时可恢复重试
      _saveExamProgress();
      SnackbarUtils.showInfo('时间已到，正在自动交卷...');
      await _doSubmit();
      return;
    }

    final confirm = await showConfirmDialog();
    if (!confirm) return;

    await _doSubmit();
  }

  // 构建提交数据并提交(手动/自动交卷共用)
  Future<void> _doSubmit() async {
    // 构建提交数据 - 按照后端要求的格式：{0: {id: xxx, answer: "A", material_id: 0}, 1: {...}}
    // 提交所有题目（包括未作答的，answer 为空字符串）
    final questionsData = <String, Map<String, dynamic>>{};
    for (int i = 0; i < questions.length; i++) {
      final question = questions[i];
      final userAnswer = userAnswers[i];

      String answerStr = '';
      if (question.kind == 'SHORT') {
        // 简答题：使用用户输入的文本答案
        answerStr = shortAnswers[i] ?? '';
      } else {
        // 选择题/判断题：将选项索引转换为字母（如 [0,1] -> "A,B"）
        if (userAnswer != null && userAnswer.isNotEmpty) {
          answerStr = userAnswer.map((idx) {
            return String.fromCharCode('A'.codeUnitAt(0) + idx);
          }).join(',');
        }
      }

      // id 转为整数
      final questionIdInt = question.id is int
          ? question.id
          : int.tryParse(question.id.toString()) ?? 0;

      questionsData[i.toString()] = {
        'id': questionIdInt,
        'answer': answerStr,
        'material_id':
            question.isMaterialChild == 1 ? question.materialQuestionId : 0,
      };
    }

    // 计算已用时间
    int usedSeconds = pageMode.value == 'EXAM'
        ? ((examInitialSeconds - remainingSeconds.value)
                .clamp(0, examInitialSeconds))
            .toInt()
        : elapsedSeconds.value;

    // 调试：打印提交数据
    AppLog.d('📝 提交数据:');
    AppLog.d('  paper_id: $paperId (类型: ${paperId?.runtimeType})');
    AppLog.d('  questions: $questionsData');
    AppLog.d(
        '  start_time: ${DateTime.now().millisecondsSinceEpoch ~/ 1000 - usedSeconds}');
    AppLog.d('  已答题目数 ${userAnswers.length}/${questions.length}');

    // ====== 分支处理：有 paperId vs 无 paperId ======
    final int paperIdInt =
        paperId is int ? paperId : int.tryParse(paperId.toString()) ?? 0;

    if (paperIdInt != 0) {
      // ====== 有 paperId：走原有的试卷/真题提交逻辑 ======
      await _submitPaperExam(paperIdInt, usedSeconds, questionsData);
    } else {
      // ====== 无 paperId：章节练习模式交卷 ======
      await _submitChapterPractice(usedSeconds, questionsData);
    }
  }

  // 试卷/真题模式交卷（原有逻辑）
  Future<void> _submitPaperExam(
    int paperIdInt,
    int usedSeconds,
    Map<String, Map<String, dynamic>> questionsData,
  ) async {
    try {
      isLoading.value = true;

      final formDataMap = <String, dynamic>{
        'paper_id': paperIdInt,
        'start_time':
            DateTime.now().millisecondsSinceEpoch ~/ 1000 - usedSeconds,
        'room_id': 0,
        'room_grade_id': 0,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      questionsData.forEach((key, value) {
        formDataMap['questions[$key][id]'] = value['id'];
        formDataMap['questions[$key][answer]'] = value['answer'];
        formDataMap['questions[$key][material_id]'] = value['material_id'];
      });

      final formData = dio.FormData.fromMap(formDataMap);

      final response = await ApiClient.to.postExam(
        'paper/submit',
        data: formData,
      );

      isLoading.value = false;

      if (response.statusCode == 200 && response.data['code'] == 1) {
        // 提交成功:标记已交卷并清除本地考试进度(下次进入正常开始,不弹恢复弹窗)
        _isExamSubmitted = true;
        // ★2026-08-14 修复:交卷成功立即停止倒计时,防止结果页停留期间
        // 计时器归零触发自动二次交卷/重复跳转结果页
        _timer?.cancel();
        _timer = null;
        if (paperId != null) {
          _box.remove('exam_progress_$paperId');
        }
        // ====== 批量提交答题日志(SUBMIT 交卷),失败静默不影响交卷主流程 ======
        await _submitLogBatch(action: 'SUBMIT');
        _navigateToResultPage(response.data['data'], usedSeconds);
      } else {
        SnackbarUtils.showError(response.data['msg'] ?? '提交失败，请重试');
      }
    } catch (e, stackTrace) {
      isLoading.value = false;
      _handleSubmitError(e, stackTrace);
    }
  }

  // 章节练习模式交卷（无 paperId）
  Future<void> _submitChapterPractice(
    int usedSeconds,
    Map<String, Map<String, dynamic>> questionsData,
  ) async {
    try {
      isLoading.value = true;

      // 统计答题结果并记录日志
      int correctCount = 0;
      int wrongCount = 0;
      int answeredCount = 0;

      for (int i = 0; i < questions.length; i++) {
        final question = questions[i];
        final userAnswer = userAnswers[i];

        if (userAnswer != null && userAnswer.isNotEmpty) {
          answeredCount++;

          if (question.kind == 'SHORT') {
            // 简答题：直接标记为正确（需要人工评分）
            correctCount++;
          } else {
            // 选择题/判断题
            final isCorrect = _listEquals(userAnswer, question.correctAnswers);

            if (isCorrect) {
              correctCount++;
            } else {
              wrongCount++;
            }
          }
        }
      }

      isLoading.value = false;

      // ====== 批量提交答题日志(SUBMIT 交卷),成功优先用后端成绩跳结果页 ======
      final batchData = await _submitLogBatch(action: 'SUBMIT');

      // ★2026-08-14 修复:交卷成功停止计时并标记已交卷
      // (此路径此前漏设 _isExamSubmitted,会导致 onClose 重复保存进度/可重复交卷)
      _timer?.cancel();
      _timer = null;
      _isExamSubmitted = true;

      AppLog.d(
          '✅ 章节练习交卷完成: 已答$answeredCount, 正确$correctCount, 错误$wrongCount, 总计${questions.length}');

      String nickname = '未设';
      try {
        nickname = AuthService.to.nickname ?? '未设';
      } catch (e) {
        AppLog.d('获取昵称失败: $e');
      }

      // 批量日志 SUBMIT 成功时优先用后端统计;失败回退本地统计(正确率制)
      // ★replayed=true 表示后端返回的是历史缓存结果(重复交卷),不使用,回退本地统计
      int finalScore;
      int finalTotalScore = 100;
      int finalPassScore = 60;
      int finalAnsweredCount = answeredCount;
      int finalCorrectCount = correctCount;
      int finalWrongCount = wrongCount;
      bool finalPassed;
      int finalDuration = usedSeconds;

      if (batchData != null &&
          batchData['submitted'] == true &&
          batchData['replayed'] != true) {
        finalScore = int.tryParse(batchData['score']?.toString() ?? '') ?? 0;
        finalTotalScore =
            int.tryParse(batchData['full_score']?.toString() ?? '') ?? 0;
        finalPassScore =
            int.tryParse(batchData['pass_score']?.toString() ?? '') ?? 0;
        finalAnsweredCount =
            int.tryParse(batchData['answered_count']?.toString() ?? '') ??
                answeredCount;
        finalCorrectCount = int.tryParse(batchData['correct_count']?.toString() ?? '') ??
            correctCount;
        finalWrongCount = int.tryParse(batchData['wrong_count']?.toString() ?? '') ??
            wrongCount;
        finalDuration = int.tryParse(batchData['actual_time_sec']?.toString() ?? '') ??
            usedSeconds;

        // ★章节练习后端未快照满分(full_score=0),回退百分制展示(accuracy_percent),
        // 与旧的"正确率>=60 通过"口径一致
        if (finalTotalScore <= 0) {
          finalScore = int.tryParse(
                  batchData['accuracy_percent']?.toString() ?? '') ??
              (answeredCount > 0
                  ? (correctCount / answeredCount * 100).round()
                  : 0);
          finalTotalScore = 100;
          finalPassScore = 60;
        }

        finalPassed = batchData['is_pass'] == true;
        // ★is_pass 可能为 null(如 pass_score=0 的试卷后端不返回 bool),
        // 回退按 score>=passScore 判定(pass_score<=0 视为恒通过,与 paper/submit 口径一致)
        if (batchData['is_pass'] == null) {
          finalPassed = finalPassScore <= 0 || finalScore >= finalPassScore;
        }
      } else {
        final double scorePercent = answeredCount > 0
            ? (correctCount / answeredCount * 100).roundToDouble()
            : 0.0;
        finalScore = scorePercent.toInt();
        finalPassed = scorePercent >= 60;
      }

      Get.toNamed(
        Routes.QUESTIONS_RESULT,
        arguments: {
          'title': subject.isNotEmpty ? subject : '章节练习',
          'nickname': nickname,
          'durationSeconds': finalDuration,
          'totalScore': finalTotalScore,
          'passScore': finalPassScore,
          'questionCount': questions.length,
          'answeredCount': finalAnsweredCount,
          'correctCount': finalCorrectCount,
          'wrongCount': finalWrongCount,
          'score': finalScore,
          'passed': finalPassed,
        },
      );
    } catch (e, stackTrace) {
      isLoading.value = false;
      AppLog.d('章节练习交卷出错: $e');
      AppLog.d('堆栈: $stackTrace');
      SnackbarUtils.showError('交卷失败: $e');
    }
  }

  // 跳转到结果页面（统一方法）
  void _navigateToResultPage(dynamic resultData, int usedSeconds) {
    final int finalScore = resultData['score'] ?? 0;
    final int total = resultData['total_question'] ?? questions.length;

    int clientWrongCount = 0;
    int clientAnsweredCount = 0;
    for (int i = 0; i < questions.length; i++) {
      if (userAnswers.containsKey(i) && (userAnswers[i]?.isNotEmpty ?? false)) {
        clientAnsweredCount++;
        if (answerResults[i] != null && !answerResults[i]!) {
          clientWrongCount++;
        }
      }
    }
    final int wrongCount = clientWrongCount;
    final int correctCount = clientAnsweredCount - clientWrongCount;
    final bool passed = resultData['is_passed'] ?? (finalScore >= passScore);

    String nickname = '未设';
    try {
      nickname = AuthService.to.nickname ?? '未设';
    } catch (e) {
      AppLog.d('获取昵称失败: $e');
    }

    Get.toNamed(
      Routes.QUESTIONS_RESULT,
      arguments: {
        'title': subject.isNotEmpty ? subject : '考试试卷',
        'nickname': nickname,
        'durationSeconds': usedSeconds,
        'totalScore': totalScore,
        'passScore': passScore > 0 ? passScore : 60,
        'questionCount': total,
        'answeredCount': clientAnsweredCount,
        'correctCount': correctCount,
        'wrongCount': wrongCount,
        'score': finalScore,
        'passed': passed,
        'grade_id': resultData['grade_id'],
      },
    );
  }

  // 处理交卷错误（统一方法）
  void _handleSubmitError(dynamic e, StackTrace stackTrace) {
    AppLog.d('交卷出错: $e');
    AppLog.d('堆栈: $stackTrace');
    if (e is dio.DioException) {
      AppLog.d('=== 完整错误响应 ===');
      AppLog.d('Status: ${e.response?.statusCode}');
      final data = e.response?.data?.toString() ?? '';
      for (int i = 0; i < data.length; i += 1000) {
        final end = (i + 1000 < data.length) ? i + 1000 : data.length;
        AppLog.d(data.substring(i, end));
      }
      AppLog.d('===================');
    }
    SnackbarUtils.showError('提交失败: $e');
  }

  // 显示确认对话框
  Future<bool> showConfirmDialog() async {
    int answeredCount = userAnswers.length;
    int unansweredCount = questions.length - answeredCount;

    return await CommonDialog.show(
      title: '温馨提示',
      content: '当前已答题目 $answeredCount道，未答题目$unansweredCount道，是否确定交卷？',
      confirmText: '确定交卷',
      cancelText: '取消',
      barrierDismissible: false,
    );
  }

  // 标记滑动提示已读
  void markSwipePromptAsSeen() {
    hasSeenSwipePrompt.value = true;
    _box.write('hasSeenSwipePrompt', true);
  }

  Timer? _multiSelectDebounceTimer;
  Timer? _singleSelectTimer;

  // 选择答案 - 核心交互逻辑
  // 答题模式(TRAINING/EXAM): 不显示答案，自动跳转下一题
  // 背题模式(VIEW): 显示答案解析，不自动跳转
  void selectAnswer(int optionIndex) {
    // 练习模式下，如果显示了解析（已提交），则不能修改答案
    if ((pageMode.value == 'TRAINING' || pageMode.value == 'EXAM') &&
        showExplanation.value) return;

    final currentIndex = currentQuestionIndex.value;
    final question = questions[currentIndex];

    if (question.type == 'single' || question.type == 'judgment') {
      // 单选题或判断题：直接赋值
      final newAnswer = [optionIndex];
      userAnswers[currentIndex] = newAnswer;
      // 调用 _checkAnswer 方法，同时记录答题时间
      _checkAnswer(currentIndex, newAnswer);

      // 使用微任务确保UI更新后再执行后续逻辑
      Future.microtask(() {
        if (pageMode.value == 'VIEW') {
          // ====== 背题模式 ======
          // 显示答案解析，不自动跳转，用户手动滑动看下一题
          showExplanation.value = true;
        } else {
          // ====== 答题模式 (TRAINING/EXAM) ======
          // 不显示解析，自动跳转到下一题
          _scheduleAutoNext(currentIndex, isMulti: false);
        }
      });
    } else {
      // 多选题：切换选中状态
      final currentAnswers = List<int>.from(userAnswers[currentIndex] ?? []);
      if (currentAnswers.contains(optionIndex)) {
        currentAnswers.remove(optionIndex);
      } else {
        currentAnswers.add(optionIndex);
        currentAnswers.sort();
      }
      userAnswers[currentIndex] = currentAnswers;
      // 调用 _checkAnswer 方法，同时记录答题时间
      _checkAnswer(currentIndex, currentAnswers);

      Future.microtask(() {
        if (pageMode.value == 'VIEW') {
          // ====== 背题模式 ======
          // 多选题不自动显示解析，需要用户点击"查看解析"按钮
          // 这样用户可以先选择完所有答案后再查看解析
        } else {
          // ====== 答题模式 (TRAINING/EXAM) ======
          // 自动跳转到下一题
          _scheduleAutoNext(currentIndex, isMulti: true);
        }
      });
    }

    // 考试模式自动保存进度
    if (pageMode.value == 'EXAM') {
      _saveExamProgress();
    }
  }

  // 延迟自动跳转下一题（仅用于答题模式 TRAINING/EXAM)
  void _scheduleAutoNext(int currentIndex, {required bool isMulti}) {
    if (!isAutoNext.value) return; // 用户关闭了自动跳转
    final timer = isMulti ? _multiSelectDebounceTimer : _singleSelectTimer;
    timer?.cancel();

    // 单选题或判断题延迟500ms跳转，让用户看清楚选中效果
    // 多选题延迟1200ms，让用户有时间选择多个答案
    final delayMs = isMulti ? 1200 : 500;

    final newTimer = Timer(
      Duration(milliseconds: delayMs),
      () {
        if (currentQuestionIndex.value == currentIndex) {
          if (currentIndex < questions.length - 1) {
            // 答题模式：直接跳转下一题，不显示解析
            pageController.nextPage(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          } else {
            // 最后一题：弹出答题结果
            showAnswerCard();
          }
        }
      },
    );

    if (isMulti) {
      _multiSelectDebounceTimer = newTimer;
    } else {
      _singleSelectTimer = newTimer;
    }
  }

  // 检查答题结果
  // 记录本题累计答题用时(批量提交日志时上报,不再逐题调 logAdd)
  void _checkAnswer(int index, List<int> userAnswer) {
    final question = questions[index];
    final isCorrect = _listEquals(userAnswer, question.correctAnswers);
    answerResults[index] = isCorrect;

    if (!_shouldTrackLog) {
      return;
    }

    // 计算本题累计作答用时(秒),并重置本题开始时间(再次修改答案时继续累计)
    int timeSpent = 0;
    if (_questionStartTime != null) {
      timeSpent = DateTime.now().difference(_questionStartTime!).inSeconds;
      _questionStartTime = DateTime.now();
    }
    _timeSpentByIndex[index] = (_timeSpentByIndex[index] ?? 0) + timeSpent;

    AppLog.d('📝 题目 $index 累计作答用时: ${_timeSpentByIndex[index]} 秒');
  }

  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // 提交当前题答案（多选题手动提交）
  void submitCurrentQuestion() {
    if (pageMode.value != 'TRAINING') return;

    final currentIndex = currentQuestionIndex.value;
    final userAnswer = userAnswers[currentIndex];

    if (userAnswer == null || userAnswer.isEmpty) {
      SnackbarUtils.showInfo('请先选择答案');
      return;
    }

    _checkAnswer(currentIndex, userAnswer);
    showExplanation.value = true;
  }

  // 切换解析显示状态
  void toggleExplanation() {
    showExplanation.value = !showExplanation.value;
  }

  // 提交答案（主要是多选题需要确认，单选题通常自动下一题或直接显示结果，这里简单实现为显示解析）
  void submitAnswer() {
    showExplanation.value = true;
  }

  // 更新简答题答案
  void updateShortAnswer(int index, String answer) {
    shortAnswers[index] = answer;
    AppLog.d('📝 更新简答题答案: index=$index, answer=$answer');
  }

  // 提交简答题答案
  void submitShortAnswer(int index) {
    final answer = shortAnswers[index] ?? '';
    if (answer.isEmpty) {
      SnackbarUtils.showInfo('请先输入答案');
      return;
    }

    // 标记为已答（使用 [-1] 表示简答题已答）
    userAnswers[index] = [-1];

    // 累计本题作答用时(批量提交日志时上报,不再逐题调 logAdd)
    if (_shouldTrackLog && _questionStartTime != null) {
      final timeSpent =
          DateTime.now().difference(_questionStartTime!).inSeconds;
      _questionStartTime = DateTime.now();
      _timeSpentByIndex[index] = (_timeSpentByIndex[index] ?? 0) + timeSpent;
    }

    // 显示解析
    showExplanation.value = true;

    // 答题模式（TRAINING/EXAM）下才自动跳转下一题，背题模式（VIEW）不跳转
    if (pageMode.value != 'VIEW') {
      Future.delayed(const Duration(seconds: 2), () {
        if (currentQuestionIndex.value == index) {
          if (currentQuestionIndex.value < questions.length - 1) {
            pageController.nextPage(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        }
      });
    }

    AppLog.d('✅ 简答题答案已提交: index=$index, answer=$answer');
  }

  // 下一题
  void nextQuestion() {
    if (currentQuestionIndex.value < questions.length - 1) {
      pageController.nextPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // 最后一题
      SnackbarUtils.showInfo('已经是最后一题了');
    }
  }

  // 上一题
  void previousQuestion() {
    if (pageMode.value == 'EXAM') {
      // 考试模式禁止回退? 用户需 "顺序答题（默认只能下一题）"
      // 但通常考试系统也允许检查上一题.. 不过根据用户描述 "顺序答题", 暂且禁止或者提示
      SnackbarUtils.showInfo('考试模式下只能按顺序答题');
      return;
    }

    if (currentQuestionIndex.value > 0) {
      pageController.previousPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      SnackbarUtils.showInfo('已经是第一题了');
    }
  }

  // 保存考试进度
  void _saveExamProgress() {
    if (pageMode.value == 'EXAM' && paperId != null) {
      final progressData = {
        'userAnswers': userAnswers,
        'shortAnswers': shortAnswers,
        'remainingSeconds': remainingSeconds.value,
        'currentQuestionIndex': currentQuestionIndex.value,
        'timestamp': DateTime.now().toIso8601String(),
      };
      _box.write('exam_progress_$paperId', progressData);
    }
  }

  // 检测并恢复上次未完成的考试进度(仅 EXAM 试卷模式)
  Future<void> _maybeRestoreExamProgress(dynamic paperId) async {
    if (paperId == null || questions.isEmpty) return;
    final key = 'exam_progress_$paperId';
    final saved = _box.read<Map<String, dynamic>>(key);
    if (saved == null || saved.isEmpty) return;

    // 剩余时间按保存时刻墙钟衰减(切后台/隔天进入不会"白赚"时间)
    final savedRemaining =
        (saved['remainingSeconds'] as num?)?.toInt() ?? 0;
    final savedTs = DateTime.tryParse(saved['timestamp']?.toString() ?? '');
    final elapsedSinceSaved =
        savedTs == null ? 0 : DateTime.now().difference(savedTs).inSeconds;
    final remaining = savedRemaining - elapsedSinceSaved;
    if (remaining <= 0) {
      // 上次考试已超时:删除进度,重新开始
      _box.remove(key);
      SnackbarUtils.showInfo('上次考试已超时，请重新开始');
      return;
    }

    final mm = remaining ~/ 60;
    final ss = (remaining % 60).toString().padLeft(2, '0');
    final continueExam = await CommonDialog.show(
      title: '继续考试',
      content: '检测到未完成的考试，剩余时间 $mm:$ss，是否继续作答？',
      confirmText: '继续',
      cancelText: '放弃',
    );

    if (continueExam == true) {
      // 恢复答案
      final savedAnswers = saved['userAnswers'];
      if (savedAnswers is Map) {
        final restored = <int, List<int>>{};
        savedAnswers.forEach((k, v) {
          final idx = int.tryParse(k.toString());
          if (idx != null && v is List) {
            restored[idx] =
                List<int>.from(v.whereType<num>().map((e) => e.toInt()));
          }
        });
        if (restored.isNotEmpty) userAnswers.assignAll(restored);
      }
      final savedShorts = saved['shortAnswers'];
      if (savedShorts is Map) {
        final restored = <int, String>{};
        savedShorts.forEach((k, v) {
          final idx = int.tryParse(k.toString());
          if (idx != null) restored[idx] = v?.toString() ?? '';
        });
        if (restored.isNotEmpty) shortAnswers.assignAll(restored);
      }
      // 恢复剩余时间与题目位置
      _setRemaining(remaining);
      final target = ((saved['currentQuestionIndex'] as num?)?.toInt() ?? 0)
          .clamp(0, questions.length - 1);
      currentQuestionIndex.value = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (pageController.hasClients) {
          pageController.jumpToPage(target);
        }
      });
    } else {
      // 放弃:删除进度,重新开始
      _box.remove(key);
    }
  }

  // 切换详情/列表视图 (看题模式)
  void toggleDetailView() {
    isDetailView.value = !isDetailView.value;
  }

  // 从列表进入详情视图
  // @param index 索引值
  // @return 无
  void enterDetailView(int index) {
    currentQuestionIndex.value = index;
    isDetailView.value = true;
    // 确保 PageView 跳转到对应页
    if (pageController.hasClients) {
      pageController.jumpToPage(index);
    }
  }

  // 更新当前索引（由 PageView 滑动触发）
  void updateCurrentIndex(int index) {
    currentQuestionIndex.value = index;

    // 记录新题目的开始时间
    _questionStartTime = DateTime.now();
    AppLog.d('⏱️ 题目 $index 开始时间已更新: $_questionStartTime');

    if (pageMode.value == 'VIEW') {
      // 背题模式：切换题目时隐藏解析，等待用户点击选项后显示
      showExplanation.value = false;
    } else {
      // 答题模式：始终隐藏解析（答题时不显示答案）
      showExplanation.value = false;
    }
  }

  // 构建完整答题卡 answers(批量提交用)
  // user_answer 格式:单选/判断="A" 字符串;多选/不定项=数组(★即使只选一个也["A"]);
  // 填空=数组(★即使一个也["答案"]);简答=文本;未答=null
  List<Map<String, dynamic>> _buildAnswers() {
    final answers = <Map<String, dynamic>>[];
    for (int i = 0; i < questions.length; i++) {
      final question = questions[i];
      final questionId =
          int.tryParse(question.id.toString()) ?? 0;

      bool answered = false;
      dynamic userAnswerValue;
      if (question.kind == 'SHORT') {
        // 简答题:文本
        final shortText = shortAnswers[i];
        if (shortText != null && shortText.isNotEmpty) {
          answered = true;
          userAnswerValue = shortText;
        }
      } else if (question.kind == 'FILL') {
        // 填空题:★后端要求数组(单个答案也包成数组)
        final shortText = shortAnswers[i];
        if (shortText != null && shortText.isNotEmpty) {
          answered = true;
          userAnswerValue = [shortText];
        }
      } else {
        final userAnswer = userAnswers[i];
        if (userAnswer != null && userAnswer.isNotEmpty) {
          answered = true;
          final letterList = userAnswer
              .map((e) => String.fromCharCode('A'.codeUnitAt(0) + e))
              .toList();
          final isMulti = question.kind == 'MULTI' || question.kind == 'X';
          if (isMulti) {
            // 多选/不定项:★后端要求恒为数组(即使只选一个)
            userAnswerValue = letterList;
          } else {
            // 单选/判断:字符串
            userAnswerValue = letterList.first;
          }
        }
      }

      answers.add({
        'question_id': questionId,
        'answered': answered,
        'user_answer': userAnswerValue,
        'time_spent': _timeSpentByIndex[i] ?? 0,
        'viewed_answer': false,
        'is_marked': favoriteQuestions[i] ?? false,
        'order_index': i,
        'extra': null,
      });
    }
    return answers;
  }

  // 批量提交答题日志(action: SAVE=退出暂存, SUBMIT=交卷)
  // 成功返回响应 data(SUBMIT 含成绩),失败返回 null(静默,不影响主流程)
  Future<Map<String, dynamic>?> _submitLogBatch(
      {required String action}) async {
    if (!_shouldTrackLog) {
      return null;
    }
    // 防并发重复提交(交卷与退出竞态)
    if (_logBatchSubmitting) {
      AppLog.d('🛡️ 批量日志提交进行中,跳过本次 $action');
      return null;
    }
    _logBatchSubmitting = true;

    try {
      // 本场累计答题时长(秒)
      final int usedSeconds = isCountdownMode
          ? ((examInitialSeconds - remainingSeconds.value)
                  .clamp(0, examInitialSeconds))
              .toInt()
          : elapsedSeconds.value;

      final answers = _buildAnswers();
      final questionIds = questions
          .map((q) => int.tryParse(q.id.toString()) ?? 0)
          .toList();

      final params = <String, dynamic>{
        'action': action,
        'practice_id': practiceId,
        'source_type': paperId != null ? 'PAPER' : 'TRAIN',
        'source_id': sourceId,
        'source_scope': sourceScope,
        'answer_mode': 'PRACTICE', // 答题模式写死 PRACTICE
        'question_type': _entryQuestionType,
        // ★完整题序 SAVE/SUBMIT 都传:首次 SAVE 建记录时后端据此落 question_ids(NOT NULL),
        // 否则续答时 practice/detail 返回的 question_ids 为空
        'question_ids': jsonEncode(questionIds),
        'elapsed_time_sec': usedSeconds,
        'platform': 'app',
        'answers': jsonEncode(answers),
      };

      if (action == 'SAVE') {
        // 暂存:带当前轮次与断点下标,供下次续答恢复
        params['attempt_no'] = attemptCount > 0 ? attemptCount : 1;
        params['current_index'] = currentQuestionIndex.value;
      } else {
        // 交卷:交卷时间戳
        params['submitted_at'] =
            DateTime.now().millisecondsSinceEpoch ~/ 1000;
      }

      // APP 系统标识(可选字段,尽量带上)
      try {
        params['app_platform'] = Platform.isAndroid ? 'android' : 'ios';
      } catch (_) {}

      AppLog.d('🌐 批量提交答题日志 logBatchAdd action=$action, practiceId=$practiceId');
      AppLog.d('📡 answers 数量: ${answers.length}, questionIds 数量: ${questionIds.length}');

      // 5 秒超时保护:日志记录不阻塞交卷/退出主流程
      final response = await _examRepository
          .addLogBatch(params)
          .timeout(const Duration(seconds: 5));

      if (response.isSuccess) {
        final data = response.data;
        if (data is Map && data['replayed'] == true) {
          AppLog.d('⚠️ logBatchAdd 返回 replayed=true(后端判重复交卷,返回历史缓存结果): $data');
        }
        AppLog.d('✅ logBatchAdd 成功: $data');
        // SAVE 时若后端返回新 practice_id,同步更新(交卷/后续使用)
        if (action == 'SAVE' && data is Map) {
          final newPracticeId =
              int.tryParse(data['practice_id']?.toString() ?? '');
          if (newPracticeId != null && newPracticeId > 0) {
            practiceId = newPracticeId;
            AppLog.d('🆕 SAVE 返回新 practice_id: $practiceId');
          }
        }
        if (data is Map) {
          return Map<String, dynamic>.from(data);
        }
        return null;
      }
      AppLog.d('❌ logBatchAdd 失败: code=${response.code}, msg=${response.message}');
      return null;
    } catch (e, stackTrace) {
      AppLog.d('❌ 批量提交答题日志失败: $e');
      AppLog.d('📋 错误堆栈: $stackTrace');
      // 不影响正常答题/交卷/退出流程,只打印日志
      return null;
    } finally {
      _logBatchSubmitting = false;
    }
  }

  // practice_id>0 时拉取练习记录详情,回填上次作答并跳到断点续答
  Future<void> _maybeRestorePractice() async {
    if (practiceId <= 0) {
      return;
    }
    if (!_shouldTrackLog) {
      return;
    }

    try {
      AppLog.d('🧾 practiceId=$practiceId >0,拉取练习记录详情回填');
      final response = await _examRepository.getPracticeDetail(practiceId);

      if (!response.isSuccess || response.data is! Map) {
        AppLog.d('⚠️ practice/detail 失败: code=${response.code}, msg=${response.message}');
        return;
      }

      final data = response.data as Map;

      // 记录 attempt_count(退出 SAVE 时作为 attempt_no 上报)
      final practiceRaw = data['practice'];
      if (practiceRaw is Map) {
        attemptCount =
            int.tryParse(practiceRaw['attempt_count']?.toString() ?? '') ?? 0;
        AppLog.d('🧾 attemptCount=$attemptCount');
      }

      // answers: question_id => 作答详情,按题号匹配回填
      final answersRaw = data['answers'];
      if (answersRaw is Map && answersRaw.isNotEmpty) {
        AppLog.d('🧾 practice/detail answers 数量: ${answersRaw.length}, keys: ${answersRaw.keys.take(5).toList()}');
        for (int i = 0; i < questions.length; i++) {
          final question = questions[i];
          final questionId = int.tryParse(question.id.toString()) ?? 0;
          final answerDetail = answersRaw[questionId] ??
              answersRaw[questionId.toString()];
          if (answerDetail is! Map) {
            continue;
          }

          final userAnswerRaw = answerDetail['user_answer'];
          // ★detail 接口 answers 条目不含 answered 字段(实际字段: user_answer/is_correct/
          // viewed_answer/is_marked/score/time_spent),按 user_answer 是否为空兜底判断已答
          final hasAnswer = userAnswerRaw != null &&
              (userAnswerRaw is List
                  ? userAnswerRaw.isNotEmpty
                  : userAnswerRaw.toString().isNotEmpty);
          final answered = answerDetail['answered'] == true || hasAnswer;
          // is_marked 后端为 0/1 int(非 bool)
          final isMarked = answerDetail['is_marked'] == true ||
              answerDetail['is_marked'] == 1;
          final isCorrectRaw = answerDetail['is_correct'];
          final timeSpent =
              int.tryParse(answerDetail['time_spent']?.toString() ?? '') ?? 0;

          if (isMarked) {
            favoriteQuestions[i] = true;
          }
          if (timeSpent > 0) {
            _timeSpentByIndex[i] = timeSpent;
          }

          if (!answered || userAnswerRaw == null) {
            continue;
          }

          // 回填答案:简答=文本;填空=数组(元素拼接);字符串="A"(单选/判断);数组=["A","C"](多选/不定项)
          if (question.kind == 'SHORT') {
            shortAnswers[i] = userAnswerRaw.toString();
            userAnswers[i] = [-1];
          } else if (question.kind == 'FILL') {
            // 填空后端返回数组(单个答案也是数组),拼接后回填文本框
            final fillText = userAnswerRaw is List
                ? userAnswerRaw.map((e) => e.toString()).join(',')
                : userAnswerRaw.toString();
            shortAnswers[i] = fillText;
            userAnswers[i] = [-1];
          } else {
            // 兼容后端存储格式:数组["A","C"] / 字符串 "A" / 逗号串 "A,B"
            final rawList = userAnswerRaw is List
                ? userAnswerRaw.map((e) => e.toString()).toList()
                : userAnswerRaw.toString().split(',');
            final indices = <int>[];
            for (final letter in rawList) {
              final upper = letter.trim().toUpperCase();
              if (upper.isEmpty) continue;
              final idx = upper.codeUnitAt(0) - 'A'.codeUnitAt(0);
              if (idx >= 0 && idx < question.options.length) {
                indices.add(idx);
              }
            }
            if (indices.isNotEmpty) {
              userAnswers[i] = indices;
            }
          }
          // 对错优先用后端 is_correct(0/1),缺失时本地判定(供答题卡/解析显示)
          if (isCorrectRaw == 1 || isCorrectRaw == true) {
            answerResults[i] = true;
          } else if (isCorrectRaw == 0 || isCorrectRaw == false) {
            answerResults[i] = false;
          } else if (question.kind != 'SHORT') {
            answerResults[i] =
                _listEquals(userAnswers[i], question.correctAnswers);
          }
          AppLog.d('🧾 回填题目 $i (id=$questionId) 作答: $userAnswerRaw');
        }
      } else {
        AppLog.d(
            '⚠️ practice/detail 未返回 answers(为空),跳过回填——续答时前序答案将缺失');
      }

      // 断点恢复:跳到上次作答的下标(列表 practice 的 current_index)
      int resumeIndex = -1;
      if (practiceRaw is Map) {
        resumeIndex =
            int.tryParse(practiceRaw['current_index']?.toString() ?? '') ?? -1;
      }
      if (resumeIndex >= 0 && resumeIndex < questions.length) {
        AppLog.d('🧾 断点续答: 跳到第 $resumeIndex 题');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (pageController.hasClients) {
            pageController.jumpToPage(resumeIndex);
          }
        });
      }
    } catch (e, stackTrace) {
      AppLog.d('❌ 拉取练习记录详情失败: $e');
      AppLog.d('📋 堆栈: $stackTrace');
      // 回填失败不影响正常答题,静默
    }
  }

  // 跳转到指定题目
  void jumpToQuestion(int index) {
    if (index >= 0 && index < questions.length) {
      pageController.jumpToPage(index);
      // updateCurrentIndex 会被 PageView 触发，所以这里不需要手动调用
    }
  }

  // (底部弹出 (底部弹出)
  void showAnswerCard() {
    final context = Get.context;
    if (context == null) return;

    Get.bottomSheet(
      _buildAnswerCardContent(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
    );
  }

  // 答题卡内容
  Widget _buildAnswerCardContent() {
    final isDark = isDarkMode.value;

    return Obx(() => Container(
          constraints: BoxConstraints(
            maxHeight: Get.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(ScreenAdapter.radius(32))),
          ),
          padding: EdgeInsets.all(ScreenAdapter.width(32)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动条
              Container(
                width: ScreenAdapter.width(120),
                height: ScreenAdapter.height(8),
                margin: EdgeInsets.only(bottom: ScreenAdapter.height(30)),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF555555) : Colors.grey[300],
                  borderRadius: BorderRadius.circular(ScreenAdapter.radius(4)),
                ),
              ),

              // 顶部标题和关闭按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: ScreenAdapter.width(48)), // 占位，让标题居中
                  Text(
                    '答题卡',
                    style: TextStyle(
                      fontSize: ScreenAdapter.fontSize(46),
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Get.back(),
                    child: Icon(Icons.close,
                        color: isDark ? Colors.white : Colors.black87,
                        size: ScreenAdapter.width(60)),
                  ),
                ],
              ),

              // 题目网格（每行5个，最多显示6行题目编号）
              SizedBox(
                height: _calcGridHeight(),
                child: ClipRect(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // 根据可用宽度精确计算每行高度
                      final crossAxisCount = 5;
                      final spacing = 10.0;
                      final crossAxisSpacing = 12.0;
                      final aspectRatio = 1.15;
                      final availableWidth = constraints.maxWidth;
                      final itemWidth = (availableWidth -
                              crossAxisSpacing * (crossAxisCount - 1)) /
                          crossAxisCount;
                      final itemHeight = itemWidth / aspectRatio;
                      final rowHeight = itemHeight + spacing;

                      return GridView.builder(
                        shrinkWrap: questions.length <= 30,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          crossAxisSpacing: crossAxisSpacing,
                          mainAxisSpacing: spacing,
                          childAspectRatio: aspectRatio,
                          mainAxisExtent: itemHeight,
                        ),
                        itemCount: questions.length,
                        itemBuilder: (context, index) {
                          bool isCurrent = currentQuestionIndex.value == index;
                          bool isAnswered = userAnswers.containsKey(index) &&
                              (userAnswers[index]?.isNotEmpty ?? false);
                          bool? isCorrect = answerResults[index];
                          final question = questions[index];
                          final questionStatus = question.questionStatus;

                          Color bgColor =
                              isDark ? const Color(0xFF3D3D3D) : Colors.white;
                          Color borderColor = isDark
                              ? const Color(0xFF555555)
                              : Colors.grey[300]!;
                          Color textColor =
                              isDark ? Colors.white70 : Colors.black87;

                          // 优先根据 questionStatus 判断颜色
                          if (questionStatus == 2) {
                            // 已做正确
                            bgColor = const Color(0xFF52C41A);
                            borderColor = bgColor;
                            textColor = Colors.white;
                          } else if (questionStatus == 3) {
                            // 已做错误
                            bgColor = const Color(0xFFF5222D);
                            borderColor = bgColor;
                            textColor = Colors.white;
                          } else if (isAnswered) {
                            // 已作答但没有 questionStatus 或 questionStatus 为未做
                            if (pageMode.value == 'TRAINING' &&
                                isCorrect != null &&
                                showExplanation.value) {
                              // 练习模式已查看结果，显示对错颜色（绿/红）
                              bgColor = isCorrect
                                  ? const Color(0xFF52C41A)
                                  : const Color(0xFFF5222D);
                              borderColor = bgColor;
                              textColor = Colors.white;
                            } else {
                              // 已作答但未查看结果，显示蓝底白字（实心）
                              bgColor = const Color(0xFF1890FF);
                              borderColor = bgColor;
                              textColor = Colors.white;
                            }
                          } else if (isCurrent) {
                            // 当前题目但未作答，显示蓝色边框+原底蓝字（空心，与已作答区分）
                            borderColor = const Color(0xFF1890FF);
                            textColor = const Color(0xFF1890FF);
                          }

                          return GestureDetector(
                            onTap: () {
                              jumpToQuestion(index);
                              Get.back();
                            },
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: bgColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: borderColor,
                                    width: isCurrent ? 1.5 : 1.0),
                              ),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: ScreenAdapter.fontSize(32),
                                  color: textColor,
                                  fontWeight: isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              // 提交按钮 (考试模式和练习模式都显示)
              if (pageMode.value == 'EXAM' || pageMode.value == 'TRAINING') ...[
                SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: ScreenAdapter.height(20)),
                      SizedBox(
                        width: double.infinity,
                        height: ScreenAdapter.height(128),
                        child: ElevatedButton(
                          onPressed: () {
                            Get.back();
                            submitExam();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1890FF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  ScreenAdapter.radius(60)),
                            ),
                            elevation: 0,
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            '提交',
                            style: TextStyle(
                              fontSize: ScreenAdapter.fontSize(44),
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ));
  }

  // 计算网格高度：最多显示6行，不满6行按实际行数（无空白）
  double _calcGridHeight() {
    // 基于屏幕宽度计算每行实际高度（需扣除 Container 的 padding）
    final screenWidth = Get.width - ScreenAdapter.width(32) * 2;
    const crossAxisCount = 5;
    const crossAxisSpacing = 12.0;
    const spacing = 10.0;
    const aspectRatio = 1.15;

    final itemWidth = (screenWidth - crossAxisSpacing * (crossAxisCount - 1)) /
        crossAxisCount;
    final itemHeight = itemWidth / aspectRatio;
    final rowHeight = itemHeight + spacing;

    final totalRows = (questions.length / crossAxisCount).ceil();
    final displayRows = totalRows.clamp(1, 6);
    return rowHeight * displayRows;
  }

  // 构建图例项
  Widget _buildLegendItem(bool isDark, Color color, String label,
      {bool hasBorder = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: ScreenAdapter.width(28),
          height: ScreenAdapter.width(28),
          decoration: BoxDecoration(
            color: hasBorder ? Colors.white : color,
            shape: BoxShape.circle,
            border: hasBorder
                ? Border.all(color: Colors.grey[400]!, width: 1.5)
                : null,
          ),
        ),
        SizedBox(width: ScreenAdapter.width(8)),
        Text(
          label,
          style: TextStyle(
            fontSize: ScreenAdapter.fontSize(24),
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ],
    );
  }

  // 切换收藏状态（调用 API）
  Future<void> toggleFavorite() async {
    final currentIndex = currentQuestionIndex.value;
    if (currentIndex < 0 || currentIndex >= questions.length) return;
    if (isCollecting.value) return; // 防止重复点击

    final question = questions[currentIndex];
    final questionId = question.id;

    // ⚠️ 关键修复：只依赖 favoriteQuestions map 判断当前状态
    // 不再依赖 question.isCollected（因为收藏模式加载时硬编码为 true，不会随操作更新）
    final isCurrentlyFav = favoriteQuestions[currentIndex] ?? false;

    AppLog.d(
        '🔖 切换收藏: questionId=$questionId (${questionId.runtimeType}), 当前状态=$isCurrentlyFav -> ${!isCurrentlyFav}, pageType=$pageType');

    isCollecting.value = true; // 开始加载
    try {
      String apiUrl;
      if (isCurrentlyFav) {
        // 取消收藏
        apiUrl = 'question/collectCancel';
      } else {
        // 添加收藏
        apiUrl = 'question/collectAdd';
      }

      // 确保 question_id 为整数
      // 如果 questionId 不是整数，转换为 0
      // 这里假设 API 接口需要整数参数
      final intQuestionId = int.tryParse(questionId.toString()) ?? 0;
      AppLog.d(
          '🔖 调用API: $apiUrl, question_id=$intQuestionId, type=$collectType');

      final response = await ApiClient.to.postExam(
        apiUrl,
        data: {
          'question_id': intQuestionId,
          // 收藏来源类型:1=章节练习,2=历年真题,3=模拟考试(collectAdd/collectCancel 同传)
          'type': collectType,
        },
      );

      AppLog.d('🔖 收藏API响应 status=${response.statusCode}, data=${response.data}');

      if (response.statusCode == 200 && response.data is Map) {
        final code = response.data['code'];
        if (code == 1 || code == '1') {
          // 成功：更新收藏状态 map（UI 从此 map 读取）
          final newFavState = !isCurrentlyFav;
          favoriteQuestions[currentIndex] = newFavState;

          AppLog.d('🔖 收藏操作成功: ${newFavState ? "已添加到收藏" : "已取消收藏"}');
        } else {
          AppLog.d('⚠️ 收藏API返回错误: code=$code, msg=${response.data['msg']}');
        }
      } else {
        AppLog.d('⚠️ 收藏API请求失败: statusCode=${response.statusCode}');
      }
    } catch (e, stackTrace) {
      AppLog.d('收藏操作出错: $e');
      AppLog.d('堆栈: $stackTrace');
    } finally {
      isCollecting.value = false; // 结束加载
    }
  }

  // 从题目数据初始化收藏状态
  // 从题目数据初始化收藏状态
  void _initFavoriteStatus() {
    favoriteQuestions.clear();
    for (int i = 0; i < questions.length; i++) {
      if (questions[i].isCollected) {
        favoriteQuestions[i] = true;
      }
    }

    final collectedCount = favoriteQuestions.values.where((v) => v).length;
    AppLog.d('🔖 收藏状态初始化完成: ${questions.length} 题中 $collectedCount 题已收藏');

    // 恢复用户之前的答题记录
    _restoreUserAnswers();

    // 记录第一题的开始时间
    if (questions.isNotEmpty) {
      _questionStartTime = DateTime.now();
      AppLog.d('⏱️ 第一题开始时间已记录');
    }
  }

  // 恢复用户之前的答题记录（从 Question.userAnswer 字段）
  void _restoreUserAnswers() {
    int restoredCount = 0;
    for (int i = 0; i < questions.length; i++) {
      final question = questions[i];
      if (question.userAnswer != null && question.userAnswer!.isNotEmpty) {
        userAnswers[i] = List<int>.from(question.userAnswer!);
        restoredCount++;

        // 如果有用户答案，同时恢复答题结果（基于 questionStatus）
        if (question.questionStatus == 2) {
          answerResults[i] = true; // 正确
        } else if (question.questionStatus == 3) {
          answerResults[i] = false; // 错误
        }
      }
    }
    if (restoredCount > 0) {
      AppLog.d('✅ 恢复用户答题记录: $restoredCount/${questions.length} 题已恢复答案');
    } else {
      AppLog.d('ℹ️ 无历史答题记录需要恢复');
    }
  }

  // 查找第一个未做过的题目索引 (question_status == 1)
  void _jumpToFirstUndoneQuestion() {
    if (questions.isEmpty) return;

    int targetIndex = 0; // 默认第一题
    for (int i = 0; i < questions.length; i++) {
      final qs = questions[i].questionStatus;
      // question_status == 1 表示未做，找到第一个这样的题目
      if (qs == 1) {
        targetIndex = i;
        AppLog.d('🎯 找到第一个未做题 索引=$i');
        break;
      }
    }

    // 如果所有题都做过了 (没有找到 question_status == 1)，则留在第一题
    currentQuestionIndex.value = targetIndex;
    AppLog.d('🎯 设置初始题目索引: $targetIndex');

    // 使用 WidgetsBinding 确保在第一帧后跳转，更可靠
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pageController.hasClients) {
        pageController.jumpToPage(targetIndex);
        AppLog.d('🎯 PageView 已跳转到索引: $targetIndex');
      } else {
        AppLog.d('⚠️ pageController 还没有客户端，无法跳转');
        // 如果还没有客户端，再尝试一次
        Future.delayed(const Duration(milliseconds: 100), () {
          if (pageController.hasClients) {
            pageController.jumpToPage(targetIndex);
            AppLog.d('🎯 第二次尝试：PageView 已跳转到索引: $targetIndex');
          }
        });
      }
    });
  }

  // 处理返回按钮退出逻辑
  Future<bool> onWillPop() async {
    // 防止屏幕边缘滑动导致的误触，统一提示
    final confirmed = await showExitDialog(message: '确定退出吗？');
    if (!confirmed) {
      return false;
    }
    // 确认退出:未交卷时批量暂存答题记录(SAVE),供下次进入续答;
    // 失败静默不阻塞退出(logBatchAdd 内部已打印)
    if (!_isExamSubmitted) {
      await _submitLogBatch(action: 'SAVE');
    }
    return true;
  }

  // 显示退出确认对话框 (使用 Get.dialog 无动画)
  Future<bool> showExitDialog({String message = '确定退出吗？'}) async {
    final completer = Completer<bool>();

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '退出提示',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF333333),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Get.back();
                        completer.complete(false);
                      },
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '取消',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Get.back();
                        completer.complete(true);
                      },
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A9EF5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '确定',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
      transitionDuration: Duration.zero,
    );

    return completer.future;
  }
}

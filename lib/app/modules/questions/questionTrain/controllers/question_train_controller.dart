import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart' show compute;
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

// ★2026-08-26 机械拆分:解析器/加载器/答题卡 Widget 拆到独立 part 文件(同库共享私有成员)
part 'question_train_controller_parsers.dart';
part 'question_train_controller_loaders.dart';
part 'question_train_controller_ui.dart';

class QuestionTrainController extends GetxController
    with _QuestionTrainLoaders, _QuestionTrainUi {
  final GetStorage _box = GetStorage();
  final ExamRepository _examRepository = ExamRepository();

  // GetStorage 键(集中管理,勿散落内联)
  static const String _kHasSeenSwipePrompt = 'hasSeenSwipePrompt';
  static const String _kExamProgressKeyPrefix = 'exam_progress_';

  // 记录每道题的开始时间（用于计算答题用时）
  DateTime? _questionStartTime;

  // 计时器上一次 tick 的墙钟时间(退后台/卡顿后按真实流逝时间补扣,防切后台"暂停"考试刷时间)
  DateTime _lastTickTime = DateTime.now();

  // 当前题目列表
  @override
  final RxList<Question> questions = <Question>[].obs;

  // 加载状态
  @override
  final RxBool isLoading = true.obs;
  @override
  final RxString errorMessage = ''.obs;

  // 当前题目索引
  @override
  final RxInt currentQuestionIndex = 0.obs;

  // 用户答案记录：Map<题目索引, 用户选择的答案索引列表>
  @override
  final RxMap<int, List<int>> userAnswers = <int, List<int>>{}.obs;

  // 简答题答案记录：Map<题目索引, 用户输入的答案>
  final RxMap<int, String> shortAnswers = <int, String>{}.obs;

  // 答题结果记录：Map<题目索引, 是否正确>
  @override
  final RxMap<int, bool> answerResults = <int, bool>{}.obs;

  // 收藏的题目：Map<题目索引, 是否收藏>
  final RxMap<int, bool> favoriteQuestions = <int, bool>{}.obs;

  // 收藏操作加载状态
  final RxBool isCollecting = false.obs;

  // 是否显示答案解释
  @override
  final RxBool showExplanation = false.obs;

  // 控制是否允许返回
  final RxBool canPopNow = false.obs;

  // 新增设置项状态
  final RxDouble fontSizeScale = 1.0.obs; // 字体大小缩放
  final RxDouble lineHeight = 1.5.obs; // 行距 (默认1.5)
  final RxBool isAutoNext = true.obs; // 自动跳转 (默认开启)
  final RxBool isAutoShowExplanation = false.obs; // 自动显示解析 (默认关闭)
  @override
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
  @override
  final RxInt remainingSeconds = 0.obs; // 倒计时秒数
  Timer? _timer; // 使用可空类型，避免late 初始化问题
  @override
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
  @override
  final PageController pageController = PageController();

  // 当前科目和章节信息
  String subject = '';
  String chapter = '';
  String section = '';
  String subsection = '';

  // 页面来源类型（普通/收藏/试卷）
  @override
  String pageType = ''; // 'favorite' 表示收藏模式

  // 收藏来源类型（collectAdd/collectCancel 传参）:1=章节练习,2=历年真题,3=模拟考试
  int collectType = 1;

  // 试卷信息
  @override
  int totalScore = 0;
  @override
  int passScore = 0;
  dynamic paperId; // 试卷ID
  @override
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
  @override
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
    hasSeenSwipePrompt.value = _box.read(_kHasSeenSwipePrompt) ?? false;

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
    // ★2026-08-26:先取消防抖写盘 Timer,未交卷时直接落盘兜底(恢复弹窗行为不变)
    _cancelExamProgressDebounce();
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
    _shortAnswerJumpTimer?.cancel();
    _shortAnswerJumpTimer = null;

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

  /// 解析选项文本，并兼容后端单独返回的 options_img 图片选项。

  /// 确保计时器正在运行
  @override
  void _ensureTimerRunning() {
    if (_timer == null || !_timer!.isActive) {
      AppLog.d('📌 启动计时器（当前模式: ${pageMode.value}, 倒计时: $isCountdownMode）');
      _startTimer();
    }
  }

  // ====== 从接口响应中提取试卷配置（limit_time、total_score 等）======

  // 解析题目数据（从 paper API获取）

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
  @override
  void _setRemaining(int seconds) {
    remainingSeconds.value = seconds;
    _countdownEndTime = DateTime.now().add(Duration(seconds: seconds));
  }

  // 交卷 - 调用后端 API
  @override
  Future<void> submitExam({bool auto = false}) async {
    // ★2026-08-14 修复:已交卷后禁止再次提交
    // (防止结果页返回答题页后重复点交卷,造成同一份答案重复提交)
    if (_isExamSubmitted) return;

    if (auto) {
      // ★2026-08-14 修复:倒计时归零走完整提交流程(跳过确认弹窗),
      // 不再直接退出丢答案;提交前先保存进度,失败时可恢复重试
      _cancelExamProgressDebounce();
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
    // ★2026-08-26:先取消防抖写盘,防止交卷成功 _box.remove 进度后 pending 写盘把进度写回
    _cancelExamProgressDebounce();
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
          _box.remove('$_kExamProgressKeyPrefix$paperId');
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
    _box.write(_kHasSeenSwipePrompt, true);
  }

  Timer? _multiSelectDebounceTimer;
  Timer? _singleSelectTimer;
  // 考试进度防抖写盘 Timer(连续作答合并为一次写盘,GetStorage 同步 I/O 每题一写会掉帧)
  Timer? _examProgressDebounceTimer;
  // 简答题提交后自动跳转 Timer(★2026-08-26:保存引用,onClose 取消防访问已 dispose 的 pageController)
  Timer? _shortAnswerJumpTimer;

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

    // 考试模式自动保存进度(500ms 防抖合并写盘,连续作答不阻塞 UI)
    if (pageMode.value == 'EXAM') {
      _scheduleSaveExamProgress();
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
      // ★2026-08-26 修复:保存 Timer 引用并在 onClose 取消,防止用户 2 秒内退出页面后
      // 回调仍访问已 dispose 的 pageController;回调前再查 isClosed 兜底
      _shortAnswerJumpTimer?.cancel();
      _shortAnswerJumpTimer = Timer(const Duration(seconds: 2), () {
        if (isClosed) return;
        if (currentQuestionIndex.value == index) {
          if (currentQuestionIndex.value < questions.length - 1) {
            pageController.nextPage(
              duration: const Duration(milliseconds: 300),
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

  // 考试进度防抖写盘:连续作答合并为一次写盘(GetStorage 为同步 I/O,每题一写会掉帧)
  // ★2026-08-26 优化:退出/交卷/自动交卷前必须先 _cancelExamProgressDebounce 再直接
  // _saveExamProgress 落盘,否则 pending 写盘可能在交卷清除进度后把进度写回
  void _scheduleSaveExamProgress() {
    if (pageMode.value != 'EXAM' || paperId == null) return;
    _examProgressDebounceTimer?.cancel();
    _examProgressDebounceTimer =
        Timer(const Duration(milliseconds: 500), _saveExamProgress);
  }

  // 取消防抖写盘 Timer(交卷/退出时先取消,再按需直接落盘)
  void _cancelExamProgressDebounce() {
    _examProgressDebounceTimer?.cancel();
    _examProgressDebounceTimer = null;
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
      _box.write('$_kExamProgressKeyPrefix$paperId', progressData);
    }
  }

  // 检测并恢复上次未完成的考试进度(仅 EXAM 试卷模式)
  @override
  Future<void> _maybeRestoreExamProgress(dynamic paperId) async {
    if (paperId == null || questions.isEmpty) return;
    final key = '$_kExamProgressKeyPrefix$paperId';
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
  @override
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
  @override
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
  @override
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
}

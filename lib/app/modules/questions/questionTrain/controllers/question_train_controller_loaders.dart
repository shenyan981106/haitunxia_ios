part of 'question_train_controller.dart';

// ===== 5 路题目加载器(mixin,访问 QuestionTrainController 私有状态) =====
// ★2026-08-26 自 question_train_controller.dart 机械拆出,逻辑零改动;解析循环已接入 compute 后台 isolate

mixin _QuestionTrainLoaders {
  // ===== 以下抽象成员由 QuestionTrainController 实现(拆分时声明,勿删) =====
  String get pageType;
  dynamic get pageConfigId;
  RxString get pageMode;
  RxString get errorMessage;
  RxBool get isLoading;
  RxList<Question> get questions;
  int get totalScore;
  set totalScore(int value);
  int get passScore;
  set passScore(int value);
  int get examInitialSeconds;
  set examInitialSeconds(int value);
  RxInt get remainingSeconds;
  void _setRemaining(int seconds);
  void _initFavoriteStatus();
  void _jumpToFirstUndoneQuestion();
  void _ensureTimerRunning();
  Future<void> _maybeRestoreExamProgress(dynamic paperId);
  Future<void> _maybeRestorePractice();
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

            // ★2026-08-26 优化:解析整包丢后台 isolate(compute),主线程不再串行 jsonDecode+正则
            final parsedQuestions = await compute(_parseQuestionList, questionsRaw);

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
            // ★2026-08-26 优化:解析整包丢后台 isolate(compute),主线程不再串行 jsonDecode+正则
            final parsedQuestions = await compute(_parseQuestionListFromPaper, rawQuestions);

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
      // ★2026-08-26 优化:解析整包丢后台 isolate(compute),主线程不再串行 jsonDecode+正则
      final parsedQuestions = await compute(_parseFavoriteItems, itemsRaw);

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
      // ★2026-08-26 优化:解析整包丢后台 isolate(compute),主线程不再串行 jsonDecode+正则
      final parsedQuestions = await compute(_parseWrongItems, itemsRaw);

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
      // ★2026-08-26 优化:解析整包丢后台 isolate(compute),主线程不再串行 jsonDecode+正则
      final parsedQuestions = await compute(_parseSearchItems, itemsRaw);

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
}

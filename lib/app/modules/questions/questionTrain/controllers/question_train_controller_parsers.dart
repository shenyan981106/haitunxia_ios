part of 'question_train_controller.dart';

// ===== 题目/选项解析器(纯函数,无状态访问,可进 compute 后台 isolate) =====
// ★2026-08-26 自 question_train_controller.dart 机械拆出,逻辑零改动

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


// ===== compute 后台 isolate 解析入口(纯函数,行为与原循环一致:逐题 try-catch + 日志) =====
// ★2026-08-26 新增,配合 loaders 使用;Question 为纯数据类,同 isolate group 可跨 isolate 传输

List<Question> _parseQuestionList(List<dynamic> raw) {
  final parsed = <Question>[];
  for (var q in raw) {
    if (q is! Map) continue;
    try {
      final qMap = Map<String, dynamic>.from(q);
      parsed.add(_parseQuestion(qMap));
    } catch (e) {
      AppLog.d('⚠️ 解析单题失败: $e, 数据: ${q.keys}');
    }
  }
  return parsed;
}

List<Question> _parseQuestionListFromPaper(List<dynamic> raw) {
  final parsed = <Question>[];
  for (var q in raw) {
    try {
      AppLog.d('📝 解析题目 ${q['title']}');
      parsed.add(_parseQuestionFromPaper(q));
    } catch (e) {
      AppLog.d('Error parsing question: $e, Data: $q');
    }
  }
  return parsed;
}
List<Question> _parseFavoriteItems(List<dynamic> items) {
  final parsedQuestions = <Question>[];
  int parseSuccessCount = 0;
  for (int idx = 0; idx < items.length; idx++) {
    final item = items[idx];
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

  AppLog.d('📌 ===== 解析完成: 成功=$parseSuccessCount/${items.length} =====');
  return parsedQuestions;
}

List<Question> _parseWrongItems(List<dynamic> items) {
  final parsedQuestions = <Question>[];
  int parseSuccessCount = 0;
  for (int idx = 0; idx < items.length; idx++) {
    final item = items[idx];
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

  AppLog.d('📌 ===== 解析完成: 成功=$parseSuccessCount/${items.length} =====');
  return parsedQuestions;
}

List<Question> _parseSearchItems(List<dynamic> items) {
  final parsedQuestions = <Question>[];
  int parseSuccessCount = 0;
  for (int idx = 0; idx < items.length; idx++) {
    final item = items[idx];
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

  AppLog.d('🔍 ===== 解析完成: 成功=$parseSuccessCount/${items.length} =====');
  return parsedQuestions;
}

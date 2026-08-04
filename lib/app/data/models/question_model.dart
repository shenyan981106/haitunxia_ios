class ChapterModel {
  final String title;
  final List<SectionModel> sections;

  ChapterModel({
    required this.title,
    required this.sections,
  });

  factory ChapterModel.fromJson(Map<String, dynamic> json) {
    return ChapterModel(
      title: json['title'],
      sections: (json['sections'] as List)
          .map((section) => SectionModel.fromJson(section))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'sections': sections.map((section) => section.toJson()).toList(),
    };
  }
}

class SectionModel {
  final String title;
  final int questionCount;
  final int doneCount;
  final int accuracy;
  final String? difficulty;
  final String? status;
  final List<SubsectionModel>? subsections;

  SectionModel({
    required this.title,
    required this.questionCount,
    required this.doneCount,
    required this.accuracy,
    this.difficulty,
    this.status,
    this.subsections,
  });

  factory SectionModel.fromJson(Map<String, dynamic> json) {
    return SectionModel(
      title: json['title'],
      questionCount: json['questionCount'] ?? 0,
      doneCount: json['doneCount'] ?? 0,
      accuracy: json['accuracy'] ?? 0,
      difficulty: json['difficulty'],
      status: json['status'],
      subsections: json['subsections'] != null
          ? (json['subsections'] as List)
              .map((subsection) => SubsectionModel.fromJson(subsection))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'questionCount': questionCount,
      'doneCount': doneCount,
      'accuracy': accuracy,
      'difficulty': difficulty,
      'status': status,
      'subsections':
          subsections?.map((subsection) => subsection.toJson()).toList(),
    };
  }
}

class SubsectionModel {
  final String title;
  final int count;
  final String difficulty;
  final String status;

  SubsectionModel({
    required this.title,
    required this.count,
    required this.difficulty,
    required this.status,
  });

  factory SubsectionModel.fromJson(Map<String, dynamic> json) {
    return SubsectionModel(
      title: json['title'],
      count: json['count'],
      difficulty: json['difficulty'],
      status: json['status'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'count': count,
      'difficulty': difficulty,
      'status': status,
    };
  }
}

// 答案配置项（用于简答题的关键词评分）
class AnswerConfig {
  final String answer;
  final String score;

  AnswerConfig({
    required this.answer,
    required this.score,
  });

  factory AnswerConfig.fromJson(Map<String, dynamic> json) {
    return AnswerConfig(
      answer: json['answer']?.toString() ?? '',
      score: json['score']?.toString() ?? '0',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'answer': answer,
      'score': score,
    };
  }
}

// 答案详情（用于简答题）
class AnswerDetail {
  final String answer;
  final List<AnswerConfig> config;

  AnswerDetail({
    required this.answer,
    required this.config,
  });

  factory AnswerDetail.fromJson(Map<String, dynamic> json) {
    return AnswerDetail(
      answer: json['answer']?.toString() ?? '',
      config: json['config'] != null
          ? (json['config'] as List)
              .map((e) => AnswerConfig.fromJson(e))
              .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'answer': answer,
      'config': config.map((e) => e.toJson()).toList(),
    };
  }
}

// 题目模型
class Question {
  final String id;
  final String projectId;
  final String subjectId;
  final String type; // single/multi/judgment
  final String kind; // X, JUDGE, SINGLE, MULTI, FILL, SHORT, MATERIAL
  final String content;
  final List<String> options;
  final List<int> correctAnswers;
  final String? answer;
  final String explanation;
  final String difficulty;
  final String? videoUrl;
  final bool isCollected; // 是否已收
  final String cateId; // 题库ID
  final int? questionStatus; // 题目状态：1-未做 2-已做正确 3-已做错误
  final List<int>? userAnswer; // 用户之前选择的答案索引（用于恢复已答记录）

  // 简答题相关字段
  final AnswerDetail? answerDetail; // 简答题答案详情

  // 材料题相关字段
  final int isMaterialChild; // 是否是材料题子题（0-否，1-是）
  final int materialQuestionId; // 父题目ID
  final String? materialTitle; // 材料题标题
  final int materialScore; // 材料题分数
  final List<Question> materialQuestions; // 子题目列表

  // 视频相关字段
  final String? titleVideo;
  final String? explainVideo;
  final String? titleVideoUrl;
  final String? explainVideoUrl;

  Question({
    required this.id,
    required this.projectId,
    required this.subjectId,
    required this.type,
    this.kind = 'SINGLE',
    required this.content,
    required this.options,
    required this.correctAnswers,
    this.answer,
    required this.explanation,
    this.difficulty = 'medium',
    this.videoUrl,
    required String chapterId,
    this.isCollected = false,
    this.cateId = '',
    this.questionStatus,
    this.userAnswer,
    this.answerDetail,
    this.isMaterialChild = 0,
    this.materialQuestionId = 0,
    this.materialTitle,
    this.materialScore = 0,
    this.materialQuestions = const [],
    this.titleVideo,
    this.explainVideo,
    this.titleVideoUrl,
    this.explainVideoUrl,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id']?.toString() ?? '',
      projectId: json['projectId']?.toString() ?? '',
      subjectId: json['subjectId']?.toString() ?? '',
      type: json['type']?.toString() ?? 'single',
      kind: json['kind']?.toString() ?? 'SINGLE',
      content: json['content']?.toString() ?? '',
      options: List<String>.from(json['options'] ?? []),
      correctAnswers: List<int>.from(json['correctAnswers'] ?? []),
      answer: json['answer']?.toString(),
      explanation: json['explanation']?.toString() ?? '',
      difficulty: json['difficulty']?.toString() ?? 'medium',
      videoUrl: json['videoUrl'] ?? json['video'] ?? json['video_url'],
      chapterId: '',
      isCollected: json['isCollected'] ?? false,
      cateId: json['cate_id']?.toString() ?? '',
      questionStatus: json['question_status'] is int
          ? json['question_status']
          : int.tryParse(json['question_status']?.toString() ?? ''),
      userAnswer: json['user_answer'] != null
          ? (json['user_answer'] is List
              ? List<int>.from(json['user_answer'])
              : null)
          : null,
      // 简答题相关
      answerDetail: json['answer'] != null && json['answer'] is Map
          ? AnswerDetail.fromJson(json['answer'])
          : null,
      // 材料题相关
      isMaterialChild: json['is_material_child'] ?? 0,
      materialQuestionId: json['material_question_id'] ?? 0,
      materialTitle: json['material_title']?.toString(),
      materialScore: json['material_score'] ?? 0,
      materialQuestions: json['material_questions'] != null
          ? (json['material_questions'] as List)
              .map((e) => Question.fromJson(e))
              .toList()
          : [],
      // 视频相关
      titleVideo: json['title_video']?.toString(),
      explainVideo: json['explain_video']?.toString(),
      titleVideoUrl: json['title_video_url']?.toString(),
      explainVideoUrl: json['explain_video_url']?.toString(),
    );
  }
}

import 'package:dio/dio.dart' as dio;
import 'package:get/get.dart';
import '../models/address_model.dart';
import '../models/api_response.dart';
import '../models/global_project_model.dart';
import '../models/home_model.dart';
import 'base_repository.dart';

/// 考试相关数据仓库
/// 处理考试项目、科目、章节、题目等数据的获取
class ExamRepository extends BaseRepository {
  /// 获取 Repository 实例
  static ExamRepository get to => Get.find<ExamRepository>();

  /// 获取首页公共数据（使用 exam_type）
  /// [examType] 考试类型代码 (zjjjs, cjjjs, yjjjs, ejjjs, shggz)
  Future<ApiResponse<GlobalExamData>> getCommonIndex(String examType) async {
    try {
      final response = await apiClient.exam(
        'common/index',
        queryParameters: {'exam_type': examType},
      );
      return handleResponse<GlobalExamData>(
        response,
        (json) => GlobalExamData.fromJson(json),
      );
    } catch (e) {
      return handleError<GlobalExamData>(e);
    }
  }

  /// 获取首页数据（使用 subject_id）
  /// [subjectId] 科目ID
  Future<ApiResponse<HomeData>> getHomeData({required String subjectId}) async {
    try {
      final response = await apiClient.exam(
        'common/index',
        queryParameters: {'subject_id': subjectId},
      );
      return handleResponse<HomeData>(
        response,
        (json) => HomeData.fromJson(json),
      );
    } catch (e) {
      return handleError<HomeData>(e);
    }
  }

  /// 获取考试倒计时信息
  Future<ApiResponse<GlobalExamCountdown>> getExamCountdown(
      String examType) async {
    final response = await getCommonIndex(examType);
    if (response.isSuccess && response.data != null) {
      return ApiResponse(
        code: response.code,
        message: response.message,
        data: response.data?.examCountdown,
      );
    }
    return ApiResponse(
      code: response.code,
      message: response.message,
      data: null,
    );
  }

  /// 获取科目列表
  /// [projectId] 项目ID
  Future<ApiResponse<List<SubjectInfo>>> getSubjects(String projectId) async {
    try {
      final response = await apiClient.exam(
        'subject/list',
        queryParameters: {'project_id': projectId},
      );
      return handleResponse<List<SubjectInfo>>(
        response,
        (json) {
          if (json['list'] is List) {
            return (json['list'] as List)
                .map((e) => SubjectInfo.fromJson(e))
                .toList();
          }
          return [];
        },
      );
    } catch (e) {
      return handleError<List<SubjectInfo>>(e);
    }
  }

  /// 获取章节列表
  /// [subjectId] 科目ID
  Future<ApiResponse<List<ChapterInfo>>> getChapters(String subjectId) async {
    try {
      final response = await apiClient.exam(
        'chapter/list',
        queryParameters: {'subject_id': subjectId},
      );
      return handleResponse<List<ChapterInfo>>(
        response,
        (json) {
          if (json['list'] is List) {
            return (json['list'] as List)
                .map((e) => ChapterInfo.fromJson(e))
                .toList();
          }
          return [];
        },
      );
    } catch (e) {
      return handleError<List<ChapterInfo>>(e);
    }
  }

  /// 获取题目列表
  /// [params] 查询参数
  Future<ApiResponse<QuestionListData>> getQuestions(
    Map<String, dynamic> params,
  ) async {
    try {
      final response = await apiClient.exam(
        'question/list',
        queryParameters: params,
      );
      return handleResponse<QuestionListData>(
        response,
        (json) => QuestionListData.fromJson(json),
      );
    } catch (e) {
      return handleError<QuestionListData>(e);
    }
  }

  /// 获取题目详情
  /// [questionId] 题目ID
  Future<ApiResponse<QuestionInfo>> getQuestionDetail(String questionId) async {
    try {
      final response = await apiClient.exam(
        'question/detail',
        queryParameters: {'id': questionId},
      );
      return handleResponse<QuestionInfo>(
        response,
        (json) => QuestionInfo.fromJson(json),
      );
    } catch (e) {
      return handleError<QuestionInfo>(e);
    }
  }

  /// 提交答案
  /// [data] 答题数据
  Future<ApiResponse<SubmitResult>> submitAnswer(
      Map<String, dynamic> data) async {
    try {
      final response = await apiClient.exam(
        'answer/submit',
        method: 'POST',
        data: data,
      );
      return handleResponse<SubmitResult>(
        response,
        (json) => SubmitResult.fromJson(json),
      );
    } catch (e) {
      return handleError<SubmitResult>(e);
    }
  }

  /// 获取练习记录
  /// [params] 查询参数
  Future<ApiResponse<PracticeRecordData>> getPracticeRecords(
    Map<String, dynamic> params,
  ) async {
    try {
      final response = await apiClient.exam(
        'practice/records',
        queryParameters: params,
      );
      return handleResponse<PracticeRecordData>(
        response,
        (json) => PracticeRecordData.fromJson(json),
      );
    } catch (e) {
      return handleError<PracticeRecordData>(e);
    }
  }

  /// 获取收藏列表
  /// [params] 查询参数
  Future<ApiResponse<List<FavoriteInfo>>> getFavorites(
    Map<String, dynamic> params,
  ) async {
    try {
      final response = await apiClient.exam(
        'favorite/list',
        queryParameters: params,
      );
      return handleResponse<List<FavoriteInfo>>(
        response,
        (json) {
          if (json['list'] is List) {
            return (json['list'] as List)
                .map((e) => FavoriteInfo.fromJson(e))
                .toList();
          }
          return [];
        },
      );
    } catch (e) {
      return handleError<List<FavoriteInfo>>(e);
    }
  }

  /// 添加收藏
  /// [questionId] 题目ID
  Future<ApiResponse<void>> addFavorite(String questionId) async {
    try {
      final response = await apiClient.exam(
        'favorite/add',
        method: 'POST',
        data: {'question_id': questionId},
      );
      return handleResponse<void>(response, null);
    } catch (e) {
      return handleError<void>(e);
    }
  }

  /// 取消收藏
  /// [questionId] 题目ID
  Future<ApiResponse<void>> removeFavorite(String questionId) async {
    try {
      final response = await apiClient.exam(
        'favorite/remove',
        method: 'POST',
        data: {'question_id': questionId},
      );
      return handleResponse<void>(response, null);
    } catch (e) {
      return handleError<void>(e);
    }
  }

  /// 获取错题本
  /// [params] 查询参数
  Future<ApiResponse<List<WrongQuestionInfo>>> getWrongQuestions(
    Map<String, dynamic> params,
  ) async {
    try {
      final response = await apiClient.exam(
        'wrong/list',
        queryParameters: params,
      );
      return handleResponse<List<WrongQuestionInfo>>(
        response,
        (json) {
          if (json['list'] is List) {
            return (json['list'] as List)
                .map((e) => WrongQuestionInfo.fromJson(e))
                .toList();
          }
          return [];
        },
      );
    } catch (e) {
      return handleError<List<WrongQuestionInfo>>(e);
    }
  }

  /// 提交举报/反馈
  /// [data] 举报数据
  Future<ApiResponse<void>> submitReport(Map<String, dynamic> data) async {
    try {
      final response = await apiClient.exam(
        'report/submit',
        method: 'POST',
        data: data,
      );
      return handleResponse<void>(response, null);
    } catch (e) {
      return handleError<void>(e);
    }
  }

  /// 上传图片
  /// [imagePath] 图片文件路径
  Future<ApiResponse<String>> uploadImage(String imagePath) async {
    try {
      final response =
          await apiClient.uploadFile<Map<String, dynamic>>(imagePath);
      return handleResponse<String>(
        response,
        (json) => json['url']?.toString() ?? json['data']?.toString() ?? '',
      );
    } catch (e) {
      return handleError<String>(e);
    }
  }

  /// 提交反馈
  /// [data] 反馈数据
  Future<ApiResponse<void>> submitFeedback(Map<String, dynamic> data) async {
    try {
      final response = await apiClient.exam(
        'feedback/submit',
        method: 'POST',
        data: data,
      );
      return handleResponse<void>(response, null);
    } catch (e) {
      return handleError<void>(e);
    }
  }

  /// 搜索题目
  /// [keyword] 搜索关键词
  /// [subjectId] 科目ID（可选）
  Future<ApiResponse<Map<String, dynamic>>> searchQuestions(
    String keyword, {
    String? subjectId,
  }) async {
    try {
      final params = <String, dynamic>{'keyword': keyword};
      if (subjectId != null) {
        params['subject_id'] = subjectId;
      }
      final response = await apiClient.exam(
        'question/search',
        queryParameters: params,
      );
      return handleResponse<Map<String, dynamic>>(
        response,
        (json) => json is Map ? Map<String, dynamic>.from(json) : {},
      );
    } catch (e) {
      return handleError<Map<String, dynamic>>(e);
    }
  }

  /// 批量提交完整答题卡（交卷 SUBMIT / 退出暂存 SAVE）
  /// [data] 提交参数（answers/question_ids 为 JSON 字符串）
  /// practice_id=0 首次提交，>0 续答提交
  Future<ApiResponse<dynamic>> addLogBatch(Map<String, dynamic> data) async {
    try {
      final formData = dio.FormData.fromMap(data);
      final response = await apiClient.exam(
        'question/logBatchAdd',
        method: 'POST',
        data: formData,
      );
      return handleResponse<dynamic>(response, (json) => json);
    } catch (e) {
      return handleError<dynamic>(e);
    }
  }

  /// 获取练习记录详情（practice_id>0 时进入续答回填）
  /// [practiceId] 练习会话ID
  /// 返回: {practice, question_ids, order_snapshot, answers, logs}
  /// ★后端参数键为 id(非 practice_id)
  Future<ApiResponse<dynamic>> getPracticeDetail(int practiceId) async {
    try {
      final response = await apiClient.exam(
        'practice/detail',
        queryParameters: {'id': practiceId},
      );
      return handleResponse<dynamic>(response, (json) => json);
    } catch (e) {
      return handleError<dynamic>(e);
    }
  }

  // ==================== 收货地址(api/address/*、api/area/* 顶级路径,不走 addons/exam 前缀) ====================

  /// 获取收货地址列表(后端按 is_default 倒序、id 倒序,默认地址排最前)
  Future<ApiResponse<List<AddressModel>>> getAddressList() async {
    try {
      final response = await apiClient.get('api/address/lists');
      return handleResponse<List<AddressModel>>(
        response,
        (json) {
          if (json['list'] is List) {
            return (json['list'] as List)
                .map((e) => AddressModel.fromJson(e))
                .toList();
          }
          return [];
        },
      );
    } catch (e) {
      return handleError<List<AddressModel>>(e);
    }
  }

  /// 新增收货地址
  /// [data] consignee/phone/province/city/district/detail/is_default
  /// ★FastAdmin 体系必须 form-urlencoded(项目默认 JSON 头,需 Options 覆盖)
  Future<ApiResponse<bool>> addAddress(Map<String, dynamic> data) async {
    try {
      final response = await apiClient.post(
        'api/address/add',
        data: data,
        options:
            dio.Options(contentType: dio.Headers.formUrlEncodedContentType),
      );
      return handleResponse<bool>(response, (json) => true);
    } catch (e) {
      return handleError<bool>(e);
    }
  }

  /// 编辑收货地址
  /// [data] id + consignee/phone/province/city/district/detail/is_default
  /// ★必须完整传其余字段(含 is_default,否则保持原值)
  Future<ApiResponse<bool>> editAddress(Map<String, dynamic> data) async {
    try {
      final response = await apiClient.post(
        'api/address/edit',
        data: data,
        options:
            dio.Options(contentType: dio.Headers.formUrlEncodedContentType),
      );
      return handleResponse<bool>(response, (json) => true);
    } catch (e) {
      return handleError<bool>(e);
    }
  }

  /// 删除收货地址
  Future<ApiResponse<bool>> deleteAddress(int id) async {
    try {
      final response = await apiClient.post(
        'api/address/delete',
        data: {'id': id},
        options:
            dio.Options(contentType: dio.Headers.formUrlEncodedContentType),
      );
      return handleResponse<bool>(response, (json) => true);
    } catch (e) {
      return handleError<bool>(e);
    }
  }

  /// 省市区列表(三级联动)
  /// 不传参数查省份;传 [province] 查该省城市;传 [city] 查该市区县
  /// ★data 为裸数组 [{value,name}],不走 handleResponse 的 fromJson(Map) 路径,手动解析
  Future<ApiResponse<List<AreaOption>>> getAreaList(
      {int? province, int? city}) async {
    try {
      final String path;
      final Map<String, dynamic>? params;
      if (city != null) {
        path = 'api/area/district';
        params = {'city': city};
      } else if (province != null) {
        path = 'api/area/city';
        params = {'province': province};
      } else {
        path = 'api/area/province';
        params = null;
      }
      final response = await apiClient.get(path, queryParameters: params);
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final raw = response.data as Map<String, dynamic>;
        if (raw['data'] is List) {
          final list = (raw['data'] as List)
              .map((e) => AreaOption.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          return ApiResponse(
            code: raw['code'] is int ? raw['code'] : 0,
            message: raw['msg']?.toString() ?? '',
            data: list,
          );
        }
        return ApiResponse(
          code: -1,
          message: raw['msg']?.toString() ?? '获取地区失败',
          data: null,
        );
      }
      return ApiResponse(
        code: response.statusCode ?? -1,
        message: '请求失败: ${response.statusMessage}',
        data: null,
      );
    } catch (e) {
      return handleError<List<AreaOption>>(e);
    }
  }
}

/// 全局考试数据
class GlobalExamData {
  final GlobalSystem? system;
  final List<GlobalNotice>? notices;
  final List<GlobalRoom>? rooms;
  final GlobalPoint? point;
  final GlobalExamCountdown? examCountdown;

  GlobalExamData({
    this.system,
    this.notices,
    this.rooms,
    this.point,
    this.examCountdown,
  });

  factory GlobalExamData.fromJson(Map<String, dynamic> json) {
    return GlobalExamData(
      system:
          json['system'] != null ? GlobalSystem.fromJson(json['system']) : null,
      notices: json['notices'] != null
          ? (json['notices'] as List)
              .map((e) => GlobalNotice.fromJson(e))
              .toList()
          : [],
      rooms: json['rooms'] != null
          ? (json['rooms'] as List).map((e) => GlobalRoom.fromJson(e)).toList()
          : [],
      point: json['point'] != null ? GlobalPoint.fromJson(json['point']) : null,
      examCountdown: json['exam_countdown'] != null
          ? GlobalExamCountdown.fromJson(json['exam_countdown'])
          : null,
    );
  }
}

/// 科目信息
class SubjectInfo {
  final String id;
  final String name;
  final String? description;
  final int? questionCount;
  final double? progress;

  SubjectInfo({
    required this.id,
    required this.name,
    this.description,
    this.questionCount,
    this.progress,
  });

  factory SubjectInfo.fromJson(Map<String, dynamic> json) {
    return SubjectInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      questionCount: json['question_count'] ?? json['questionCount'],
      progress: (json['progress'] ?? 0.0).toDouble(),
    );
  }
}

/// 章节信息
class ChapterInfo {
  final String id;
  final String name;
  final String? subjectId;
  final int? questionCount;
  final int? doneCount;

  ChapterInfo({
    required this.id,
    required this.name,
    this.subjectId,
    this.questionCount,
    this.doneCount,
  });

  factory ChapterInfo.fromJson(Map<String, dynamic> json) {
    return ChapterInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      subjectId: json['subject_id']?.toString(),
      questionCount: json['question_count'] ?? json['questionCount'],
      doneCount: json['done_count'] ?? json['doneCount'],
    );
  }
}

/// 题目列表数据
class QuestionListData {
  final List<QuestionInfo> list;
  final int total;
  final int page;
  final int pageSize;

  QuestionListData({
    required this.list,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory QuestionListData.fromJson(Map<String, dynamic> json) {
    return QuestionListData(
      list: json['list'] != null
          ? (json['list'] as List).map((e) => QuestionInfo.fromJson(e)).toList()
          : [],
      total: json['total'] ?? 0,
      page: json['page'] ?? 1,
      pageSize: json['page_size'] ?? json['pageSize'] ?? 20,
    );
  }
}

/// 题目信息
class QuestionInfo {
  final String id;
  final String content;
  final String type;
  final List<String> options;
  final List<int> correctAnswers;
  final String? explanation;
  final String? difficulty;

  QuestionInfo({
    required this.id,
    required this.content,
    required this.type,
    required this.options,
    required this.correctAnswers,
    this.explanation,
    this.difficulty,
  });

  factory QuestionInfo.fromJson(Map<String, dynamic> json) {
    return QuestionInfo(
      id: json['id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      type: json['type']?.toString() ?? 'single',
      options:
          json['options'] != null ? List<String>.from(json['options']) : [],
      correctAnswers: json['correct_answers'] != null
          ? List<int>.from(json['correct_answers'])
          : [],
      explanation: json['explanation']?.toString(),
      difficulty: json['difficulty']?.toString(),
    );
  }
}

/// 提交结果
class SubmitResult {
  final bool isCorrect;
  final String? message;
  final int? score;

  SubmitResult({
    required this.isCorrect,
    this.message,
    this.score,
  });

  factory SubmitResult.fromJson(Map<String, dynamic> json) {
    return SubmitResult(
      isCorrect: json['is_correct'] ?? json['isCorrect'] ?? false,
      message: json['message']?.toString(),
      score: json['score'],
    );
  }
}

/// 练习记录数据
class PracticeRecordData {
  final List<PracticeRecord> list;
  final int total;

  PracticeRecordData({
    required this.list,
    required this.total,
  });

  factory PracticeRecordData.fromJson(Map<String, dynamic> json) {
    return PracticeRecordData(
      list: json['list'] != null
          ? (json['list'] as List)
              .map((e) => PracticeRecord.fromJson(e))
              .toList()
          : [],
      total: json['total'] ?? 0,
    );
  }
}

/// 练习记录
class PracticeRecord {
  final String id;
  final String questionId;
  final String questionContent;
  final bool isCorrect;
  final DateTime? createTime;

  PracticeRecord({
    required this.id,
    required this.questionId,
    required this.questionContent,
    required this.isCorrect,
    this.createTime,
  });

  factory PracticeRecord.fromJson(Map<String, dynamic> json) {
    return PracticeRecord(
      id: json['id']?.toString() ?? '',
      questionId: json['question_id']?.toString() ?? '',
      questionContent: json['question_content']?.toString() ?? '',
      isCorrect: json['is_correct'] ?? false,
      createTime: json['create_time'] != null
          ? DateTime.tryParse(json['create_time'])
          : null,
    );
  }
}

/// 收藏信息
class FavoriteInfo {
  final String id;
  final String questionId;
  final String questionContent;
  final DateTime? createTime;

  FavoriteInfo({
    required this.id,
    required this.questionId,
    required this.questionContent,
    this.createTime,
  });

  factory FavoriteInfo.fromJson(Map<String, dynamic> json) {
    return FavoriteInfo(
      id: json['id']?.toString() ?? '',
      questionId: json['question_id']?.toString() ?? '',
      questionContent: json['question_content']?.toString() ?? '',
      createTime: json['create_time'] != null
          ? DateTime.tryParse(json['create_time'])
          : null,
    );
  }
}

/// 错题信息
class WrongQuestionInfo {
  final String id;
  final String questionId;
  final String questionContent;
  final int wrongCount;
  final DateTime? lastWrongTime;

  WrongQuestionInfo({
    required this.id,
    required this.questionId,
    required this.questionContent,
    required this.wrongCount,
    this.lastWrongTime,
  });

  factory WrongQuestionInfo.fromJson(Map<String, dynamic> json) {
    return WrongQuestionInfo(
      id: json['id']?.toString() ?? '',
      questionId: json['question_id']?.toString() ?? '',
      questionContent: json['question_content']?.toString() ?? '',
      wrongCount: json['wrong_count'] ?? 0,
      lastWrongTime: json['last_wrong_time'] != null
          ? DateTime.tryParse(json['last_wrong_time'])
          : null,
    );
  }
}

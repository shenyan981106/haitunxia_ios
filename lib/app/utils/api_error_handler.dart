import 'package:dio/dio.dart';
import '../services/snackbar_utils.dart';

/// 统一API错误处理工具类
/// 提供标准化的网络请求错误处理，消除重复代码
class ApiErrorHandler {
  // ==================== 核心方法 ====================

  /// 处理API请求异常（推荐使用）
  /// 
  /// 用法示例：
  /// ```dart
  /// try {
  ///   final response = await ApiClient.to.get('xxx');
  ///   // 处理响应...
  /// } on DioException catch (e) {
  ///   ApiErrorHandler.handleDioError(e, fallbackMessage: '获取数据失败');
  /// } catch (e) {
  ///   ApiErrorHandler.handleError(e, fallbackMessage: '操作失败');
  /// }
  /// ```
  
  /// 处理Dio异常
  /// [e] DioException对象
  /// [fallbackMessage] 自定义默认错误信息（当无法提取具体错误时显示）
  static void handleDioError(DioException e, {String? fallbackMessage}) {
    final message = _extractDioErrorMessage(e);
    SnackbarUtils.showError(message ?? fallbackMessage ?? '网络请求失败');
  }

  /// 处理通用异常
  /// [e] 异常对象
  /// [fallbackMessage] 自定义默认错误信息
  static void handleError(dynamic e, {String? fallbackMessage = '操作失败'}) {
    if (e is DioException) {
      handleDioError(e, fallbackMessage: fallbackMessage);
    } else {
      SnackbarUtils.showError(_extractGeneralErrorMessage(e) ?? fallbackMessage!);
    }
  }

  // ==================== 错误消息提取（私有方法） ====================

  /// 从DioException中提取友好的错误消息
  static String? _extractDioErrorMessage(DioException e) {
    // 优先级1：从响应体中提取服务端返回的错误信息
    if (e.response?.data is Map) {
      final data = e.response!.data as Map;
      
      // FastAdmin 标准格式：{code: 0, msg: "错误信息"}
      if (data['msg'] != null) {
        return data['msg'].toString();
      }
      
      // 其他常见格式
      if (data['message'] != null) {
        return data['message'].toString();
      }
      if (data['error'] != null) {
        return data['error'].toString();
      }
    }
    
    // 优先级2：根据异常类型生成友好提示
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时，请检查网络';
      case DioExceptionType.sendTimeout:
        return '请求超时，请重试';
      case DioExceptionType.receiveTimeout:
        return '响应超时，请重试';
      case DioExceptionType.badResponse:
        // 已在上面处理了response body，这里只处理HTTP状态码
        final statusCode = e.response?.statusCode;
        if (statusCode == 401) return '登录已过期，请重新登录';
        if (statusCode == 403) return '没有权限访问';
        if (statusCode == 404) return '请求的资源不存在';
        if (statusCode == 500) return '服务器内部错误';
        if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
          return '服务器维护中，请稍后重试';
        }
        return '请求失败 ($statusCode)';
      case DioExceptionType.cancel:
        return null; // 用户主动取消，不显示错误
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络设置';
      default:
        break;
    }
    
    // 优先级3：使用DioException的message字段
    return e.message;
  }

  /// 从通用异常中提取错误消息
  static String? _extractGeneralErrorMessage(dynamic e) {
    if (e == null) return null;
    
    final str = e.toString().trim();
    
    // 过滤掉一些无意义的错误信息
    if (str.isEmpty || str == 'null' || str == 'Null') {
      return null;
    }
    
    // 截断过长的错误信息（避免UI显示问题）
    if (str.length > 200) {
      return '${str.substring(0, 200)}...';
    }
    
    return str;
  }
}

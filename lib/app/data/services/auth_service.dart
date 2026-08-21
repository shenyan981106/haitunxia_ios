import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    as fss;
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart'
    as fss_ohos;
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../models/user_model.dart';
import '../providers/api_client.dart';

/// 认证服务
/// 负责管理登录状态、Token存储、用户信息
/// 使用 GetxService 实现全局单例
/// ★2026-08-14 起 token/user 改用安全存储加密落盘(android/ios/web 官方
/// flutter_secure_storage,ohos 用 TPC 适配 flutter_secure_storage_ohos,
/// 运行时按 Platform.operatingSystem == 'ohos' 选择,遵循 08 文档规则);
/// 旧 GetStorage 明文数据首次启动自动迁移后删除。
class AuthService extends GetxService {
  static AuthService get to => Get.find();

  /// 旧明文存储(仅用于老版本数据迁移)
  final GetStorage _storage = GetStorage();

  /// 安全存储(加密):官方实现(android/ios/macos/web/windows)
  final fss.FlutterSecureStorage _secureStorage = fss.FlutterSecureStorage();

  /// 安全存储(加密):鸿蒙 TPC 适配实现
  final fss_ohos.FlutterSecureStorage _ohosStorage =
      fss_ohos.FlutterSecureStorage();

  /// 持久化串行队列:保证 写/删 顺序执行,防止 登出删除 与 重新登录写入 竞态
  Future<void> _persistQueue = Future.value();

  // ==================== 响应式状态 ====================

  /// 登录状态
  final RxBool isLoggedIn = false.obs;

  /// 用户信息
  final Rx<UserModel?> user = Rx<UserModel?>(null);

  /// Token
  final RxnString token = RxnString();

  /// 加载状态
  final RxBool isLoading = false.obs;

  // ==================== 存储Key ====================

  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';

  // ==================== 生命周期 ====================

  @override
  void onInit() {
    super.onInit();
    // 触发登录态恢复(异步读安全存储);main.dart 会 await [ready] 保证启动时序
    ready;
  }

  /// 登录态恢复完成的 future(登录/登出判断前 await 此 future 即可)
  late final Future<void> ready = _loadAuthState();

  // ==================== 安全存储封装(平台选择) ====================

  Future<String?> _readSecure(String key) async {
    if (Platform.operatingSystem == 'ohos') {
      return _ohosStorage.read(key: key);
    }
    return _secureStorage.read(key: key);
  }

  Future<void> _writeSecure(String key, String value) async {
    if (Platform.operatingSystem == 'ohos') {
      await _ohosStorage.write(key: key, value: value);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  Future<void> _deleteSecure(String key) async {
    if (Platform.operatingSystem == 'ohos') {
      await _ohosStorage.delete(key: key);
    } else {
      await _secureStorage.delete(key: key);
    }
  }

  /// 按序执行持久化动作(串行队列)
  void _enqueuePersist(Future<void> Function() action) {
    _persistQueue = _persistQueue.then((_) => action()).catchError((e) {
      debugPrint('AuthService: 持久化失败: $e');
    });
  }

  // ==================== 核心方法 ====================

  /// 加载本地存储的认证状态(安全存储优先;无数据时从旧 GetStorage 迁移)
  Future<void> _loadAuthState() async {
    try {
      String? storedToken;
      String? storedUserJson;

      try {
        storedToken = await _readSecure(_tokenKey);
        storedUserJson = await _readSecure(_userKey);
      } catch (e) {
        debugPrint('AuthService: 读取安全存储失败: $e');
      }

      // 安全存储无数据 → 迁移旧 GetStorage 明文(老版本升级用户不用重新登录)
      if (storedToken == null || storedToken.isEmpty) {
        final legacyToken = _storage.read<String>(_tokenKey);
        if (legacyToken != null && legacyToken.isNotEmpty) {
          storedToken = legacyToken;
          final legacyUser = _storage.read<Map<String, dynamic>>(_userKey);
          if (legacyUser != null) {
            storedUserJson = jsonEncode(legacyUser);
          }
          _enqueuePersist(() async {
            await _writeSecure(_tokenKey, legacyToken);
            if (storedUserJson != null) {
              await _writeSecure(_userKey, storedUserJson);
            }
            // 迁移完成后清除明文
            _storage.remove(_tokenKey);
            _storage.remove(_userKey);
          });
          debugPrint('AuthService: 已迁移旧登录态至安全存储');
        }
      }

      if (storedToken != null && storedToken.isNotEmpty) {
        token.value = storedToken;
        if (storedUserJson != null && storedUserJson.isNotEmpty) {
          try {
            user.value = UserModel.fromJson(
              Map<String, dynamic>.from(jsonDecode(storedUserJson)),
            );
          } catch (e) {
            debugPrint('AuthService: 用户信息解析失败: $e');
          }
        }
        isLoggedIn.value = true;
        // token 会自动同步到 ApiClient（通过拦截器）

        // 启动后立即获取最新用户信息
        fetchUserInfo();
      } else {
        _clearState();
      }
    } catch (e) {
      debugPrint('AuthService: 加载认证状态失败: $e');
      _clearState();
    }
  }

  /// 获取用户详情
  /// 接口: /addons/exam/user/info
  Future<void> fetchUserInfo() async {
    try {
      final response = await ApiClient.to.post('addons/exam/user/info');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map && data['code'] == 1) {
          final result = data['data'];
          if (result is Map) {
            final userMap = Map<String, dynamic>.from(result);
            final updatedUser = UserModel.fromJson(userMap);
            user.value = updatedUser;
            _enqueuePersist(
              () => _writeSecure(_userKey, jsonEncode(updatedUser.toJson())),
            );

            debugPrint('AuthService: 用户信息已更新');
          }
        }
      }
    } catch (e) {
      debugPrint('AuthService: 获取用户信息失败: $e');
    }
  }

  /// 保存认证状态(加密写入安全存储,串行队列)
  void _saveAuthState(String newToken, UserModel newUser) {
    _enqueuePersist(() async {
      await _writeSecure(_tokenKey, newToken);
      await _writeSecure(_userKey, jsonEncode(newUser.toJson()));
    });
  }

  /// 清除认证状态
  void _clearState() {
    token.value = null;
    user.value = null;
    isLoggedIn.value = false;
    // 异步清理安全存储与旧明文(串行队列,与写入不竞态)
    _enqueuePersist(() async {
      await _deleteSecure(_tokenKey);
      await _deleteSecure(_userKey);
      _storage.remove(_tokenKey);
      _storage.remove(_userKey);
    });
  }

  // ==================== 对外接口 ====================

  /// 设置登录状态（登录成功后调用）
  void setAuth(String newToken, UserModel newUser) {
    token.value = newToken;
    user.value = newUser;
    isLoggedIn.value = true;
    _saveAuthState(newToken, newUser);
    // token 会自动同步到 ApiClient（通过拦截器）
  }

  /// 清除认证状态（登出或Token过期时调用）
  void clearAuth() {
    _clearState();
    // ApiClient 会自动处理token（通过拦截器）
  }

  /// 更新用户信息
  void updateUser(UserModel updatedUser) {
    user.value = updatedUser;
    final currentToken = token.value;
    if (currentToken != null) {
      _enqueuePersist(
        () => _writeSecure(_userKey, jsonEncode(updatedUser.toJson())),
      );
    }
  }

  /// 检查是否已登录
  bool checkLogin() {
    return isLoggedIn.value && token.value != null;
  }

  /// 获取用户ID
  int? get userId => user.value?.id;

  /// 获取昵称
  String? get nickname => user.value?.nickname ?? user.value?.mobile;

  /// 获取头像URL
  String? get avatar => user.value?.avatar;

  /// 打印当前用户信息
  void printUserInfo() {
    debugPrint('========== 当前用户信息 ==========');
    debugPrint('userId: $userId');
    debugPrint('nickname: $nickname');
    debugPrint('mobile: ${user.value?.mobile}');
    debugPrint('avatar: $avatar');
    debugPrint('=================================');
  }
}

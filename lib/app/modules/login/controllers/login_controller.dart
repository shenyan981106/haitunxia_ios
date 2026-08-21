import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../data/providers/api_client.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/models/user_model.dart';
import '../../../services/snackbar_utils.dart';
import '../../../routes/app_pages.dart';
import '../../../utils/validators.dart';
import '../../../utils/api_error_handler.dart';

/// 登录控制器
/// 负责：手机号输入验证、发送验证码、验证码登录
class LoginController extends GetxController {
  // ==================== 控制器 ====================
  // 注意：TextEditingController 自身已具备通知机制，不要再包成 Rx。
  // 之前用 Rx<TextEditingController> 会在 onClose dispose 后仍返回已释放的实例，
  // 导致新页面绑到已 dispose 的控制器，出现输入框乱码 / 无响应 / 样式错乱。
  final phoneController = TextEditingController();
  final codeController = TextEditingController();

  // ==================== 状态 ====================
  final phone = ''.obs; // 手机号（响应式，驱动按钮状态）
  final verificationCode = ''.obs; // 验证码输入
  final isLoading = false.obs; // 加载状态
  final isCountingDown = false.obs; // 倒计时状态
  final countdownSeconds = 60.obs; // 倒计时秒数
  final isAgreed = false.obs; // 协议勾选状态

  // ==================== 定时器管理 ====================
  Timer? _countdownTimer; // 验证码倒计时定时器

  // ==================== 发送验证码 ====================
  /// 发送验证码（API: addons/exam/user/sendCode）
  Future<void> sendVerificationCode() async {
    // ★2026-08-14 修复:请求进行中禁止重复发送。快速连点会产生双请求 +
    // 双跳转 verification 页(压栈竞态导致 controller 销毁时机错乱,偶发崩溃)
    if (isLoading.value) return;

    final phoneNumber = phoneController.text.trim();

    // 1. 验证手机号格式（使用统一验证器）
    final phoneError = Validators.validatePhone(phoneNumber);
    if (phoneError != null) {
      SnackbarUtils.showError(phoneError);
      return;
    }

    // 2. 检查是否同意协议
    if (!isAgreed.value) {
      _showAgreementSheet(phoneNumber);
      return;
    }

    await _doSendVerification(phoneNumber);
  }

  /// 实际发送验证码请求
  Future<void> _doSendVerification(String phoneNumber) async {
    try {
      isLoading.value = true;

      // 调用发送验证码接口
      debugPrint('========== 发送验证码请求参数 ==========');
      debugPrint('手机号: $phoneNumber');
      debugPrint('event: mobilelogin');
      debugPrint('=======================================');

      final response = await ApiClient.to.post(
        'addons/exam/user/sendCode',
        data: {'mobile': phoneNumber, 'event': 'mobilelogin'},
      );

      // FastAdmin 标准响应格式判断
      if (response.statusCode == 200) {
        final data = response.data;
        debugPrint('========== 发送验证码接口返回 ==========');
        debugPrint('response.data: $data');
        debugPrint('=======================================');
        if (data['code'] == 1) {
          SnackbarUtils.showSuccess('验证码已发送');
          _startCountdown();
          Get.toNamed(Routes.VERIFICATION);
        } else {
          SnackbarUtils.showError(data['msg'] ?? '发送失败');
        }
      }
    } on DioException catch (e) {
      ApiErrorHandler.handleDioError(e, fallbackMessage: '发送验证码失败');
    } catch (e) {
      ApiErrorHandler.handleError(e, fallbackMessage: '发送验证码失败');
    } finally {
      isLoading.value = false;
    }
  }

  // ==================== 验证码登录 ====================
  /// 验证码登录（API: addons/exam/user/appLogin）
  /// 验证通过后保存Token并跳转首页
  Future<void> login() async {
    // ★2026-08-14 修复:防重复提交(连点两次会发两个登录请求)
    if (isLoading.value) return;

    final phoneNumber = phoneController.text.trim();
    final code = verificationCode.value.trim();

    // 1. 验证验证码（使用统一验证器）
    final codeError = Validators.validateVerificationCode(code);
    if (codeError != null) {
      SnackbarUtils.showError(codeError);
      return;
    }

    try {
      isLoading.value = true;

      // 调用登录验证接口
      final response = await ApiClient.to.post(
        'addons/exam/user/appLogin',
        data: {'mobile': phoneNumber, 'code': code},
      );

      if (response.statusCode == 200) {
        final data = response.data;

        // FastAdmin 标准响应格式判断
        if (data['code'] == 1) {
          final result = data['data'] ?? {};

          // 获取Token（FastAdmin使用token字段）
          final token = result['token']?.toString() ?? '';
          if (token.isEmpty) {
            SnackbarUtils.showError('登录失败：未获取到Token');
            return;
          }

          // 获取用户信息
          final userMap = result['user'] is Map
              ? Map<String, dynamic>.from(result['user'])
              : <String, dynamic>{};

          // 调试打印：查看实际返回的用户数据结构
          debugPrint('========== 登录返回的用户数据 ==========');
          debugPrint('userMap: $userMap');
          debugPrint('username字段: ${userMap['username']}');
          debugPrint('avatar字段: ${userMap['avatar']}');
          debugPrint('=======================================');

          // 保存认证信息
          final user = UserModel.fromJson(userMap);
          AuthService.to.setAuth(token, user);
          SnackbarUtils.showSuccess('登录成功');
          Get.offAllNamed(Routes.TABS);
        } else {
          SnackbarUtils.showError(data['msg'] ?? '验证码错误');
        }
      }
    } on DioException catch (e) {
      ApiErrorHandler.handleDioError(e, fallbackMessage: '登录失败');
    } catch (e) {
      ApiErrorHandler.handleError(e, fallbackMessage: '登录失败');
    } finally {
      isLoading.value = false;
    }
  }

  // ==================== 倒计时 ====================
  /// 启动60秒倒计时
  void _startCountdown() {
    // 先清理旧的倒计时定时器（防止多个Timer同时运行）
    _countdownTimer?.cancel();

    countdownSeconds.value = 60;
    isCountingDown.value = true;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdownSeconds.value > 0) {
        countdownSeconds.value--;
      } else {
        isCountingDown.value = false;
        timer.cancel();
        _countdownTimer = null; // 清空引用
      }
    });
  }

  // ==================== 协议弹窗 ====================
  /// 显示协议确认弹窗
  void _showAgreementSheet(String phoneNumber) {
    Get.dialog(
      Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '用户协议和隐私政策',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Color(0xFF999999),
                      ),
                      onPressed: () => Get.back(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '进入下一步前，请先阅读并同意《用户协议》、《隐私政策》',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF666666),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: OutlinedButton(
                        onPressed: () => Get.back(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF666666),
                          side: const BorderSide(color: Color(0xFFDDDDDD)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text('不同意'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5,
                      child: ElevatedButton(
                        onPressed: () {
                          isAgreed.value = true;
                          Get.back();
                          _doSendVerification(phoneNumber);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0164E5),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text('同意并继续'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  // ==================== 生命周期 ====================
  @override
  void onClose() {
    _countdownTimer?.cancel();
    _countdownTimer = null;

    // ★2026-08-14 修复:TextEditingController 延迟到路由动画结束后再释放。
    // 登录成功走 Get.offAllNamed(TABS) 或 401 全局跳转时,GetX 会同步 dispose
    // 本 controller,但旧页面在路由替换/键盘收起动画期间仍可能 rebuild
    // (焦点/insets 变化),build 里访问已 dispose 的 phoneController/codeController
    // 会偶发崩溃("A TextEditingController was used after being disposed")。
    // 延迟 500ms(覆盖默认过渡动画)再释放,此时视图已卸载,安全;
    // 期间即使重进登录页也是新实例(LoginBinding fenix:true 重建),互不影响。
    Future.delayed(const Duration(milliseconds: 500), () {
      phoneController.dispose();
      codeController.dispose();
    });

    super.onClose();
  }
}

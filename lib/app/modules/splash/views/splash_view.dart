import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../data/services/auth_service.dart';
import '../../../routes/app_pages.dart';
import '../../login/views/agreement_view.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  final GetStorage _storage = GetStorage();
  final String _agreementKey = 'user_agreed';
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    _checkAgreement();
  }

  void _checkAgreement() {
    final hasAgreed = _storage.read<bool>(_agreementKey) ?? false;
    if (hasAgreed) {
      _navigateToHome();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showAgreementDialog();
      });
    }
  }

  void _navigateToHome() {
    Future.delayed(const Duration(seconds: 2), () {
      final String initialRoute =
          AuthService.to.checkLogin() ? AppPages.INITIAL : Routes.LOGIN;
      Get.offAllNamed(
          initialRoute == AppPages.INITIAL ? '/tabs' : initialRoute);
    });
  }

  void _handleAgree() {
    _storage.write(_agreementKey, true);
    Navigator.pop(context);
    _navigateToHome();
  }

  void _handleDisagree() {
    SystemNavigator.pop();
  }

  void _showAgreementDialog() {
    if (_dialogShown) return;
    _dialogShown = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.8,
              padding: EdgeInsets.fromLTRB(32.w, 48.h, 32.w, 48.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24.w),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '感谢您选择海豚侠',
                    style: TextStyle(
                      fontSize: 48.sp,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    '让学习变成一种乐趣',
                    style: TextStyle(
                      fontSize: 38.sp,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 32.h),
                  Center(
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.8 * 0.9,
                      child: Container(
                        constraints: BoxConstraints(maxHeight: 400.h),
                        child: SingleChildScrollView(
                          child: RichText(
                            text: TextSpan(
                              text: '请您知悉并仔细阅读',
                              style: TextStyle(
                                fontSize: 36.sp,
                                color: const Color(0xFF666666),
                                height: 1.8,
                              ),
                              children: [
                                TextSpan(
                                  text: '《用户协议》',
                                  style: TextStyle(
                                    fontSize: 36.sp,
                                    color: const Color(0xFF507DAF),
                                    height: 1.8,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      _dialogShown = false;
                                      Navigator.pop(context);
                                      Get.to(() => const AgreementView(
                                            initialIndex: 0,
                                          ))?.then((_) {
                                        _showAgreementDialog();
                                      });
                                    },
                                ),
                                const TextSpan(
                                  text: '和',
                                ),
                                TextSpan(
                                  text: '《隐私政策》',
                                  style: TextStyle(
                                    fontSize: 36.sp,
                                    color: const Color(0xFF507DAF),
                                    height: 1.8,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      _dialogShown = false;
                                      Navigator.pop(context);
                                      Get.to(() => const AgreementView(
                                            initialIndex: 1,
                                          ))?.then((_) {
                                        _showAgreementDialog();
                                      });
                                    },
                                ),
                                const TextSpan(
                                  text:
                                      '，点击"同意"后即可享受到海豚侠提供的服务。\n为了保证您的正常使用，海豚侠将联网提供必要服务，并在需要开启对应功能时，再提醒您进行授权其他权限的操作。详见《全部权限及说明》。\n若您点击"不同意"，您将进入"基础模式"后联网使用我们为您提供的基础功能。或者，您可以直接退出本应用。',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 48.h),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 96.h,
                          child: OutlinedButton(
                            onPressed: _handleDisagree,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF666666),
                              side: const BorderSide(color: Color(0xFFDDDDDD)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(48.h),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            child: Text(
                              '不同意',
                              style: TextStyle(
                                fontSize: 36.sp,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 24.w),
                      Expanded(
                        child: SizedBox(
                          height: 96.h,
                          child: ElevatedButton(
                            onPressed: _handleAgree,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0066FF),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(48.h),
                              ),
                              padding: EdgeInsets.zero,
                              elevation: 0,
                            ),
                            child: Text(
                              '同意',
                              style: TextStyle(
                                fontSize: 36.sp,
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE8F0FE),
              Color(0xFFD4E4FF),
              Color(0xFFF0F5FF),
              Colors.white,
            ],
            stops: [0.0, 0.3, 0.6, 1.0],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Spacer(flex: 2),
            Text(
              '让学习更简单',
              style: TextStyle(
                fontSize: 45,
                fontWeight: FontWeight.w500,
                fontStyle: FontStyle.italic,
                color: const Color(0xFF0066FF),
              ),
            ),
            const Spacer(flex: 3),
            Container(
              margin: EdgeInsets.only(bottom: 60),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: const Color(0xFF0066FF), width: 2),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 35,
                      height: 35,
                      fit: BoxFit.contain,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    '海豚侠',
                    style: TextStyle(
                      fontSize: 25,
                      color: const Color(0xFF0066FF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

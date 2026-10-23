
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'login_page.dart';
import 'role_route.dart';


class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();

    // ننتظر حتى تجهز الصفحة ثم نتحقق من المستخدم
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUser();
    });
  }

  Future<void> _checkUser() async {
    try {
      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;

      final user = auth.currentUser;

      // =====================================================
      // لا يوجد مستخدم مسجل الدخول
      // =====================================================

      if (user == null) {
        _goToLogin();
        return;
      }

      debugPrint('المستخدم الحالي: ${user.email}');
      debugPrint('UID: ${user.uid}');

      // =====================================================
      // جلب بيانات المستخدم من Firestore
      // =====================================================

      final userDoc = await firestore
          .collection('users')
          .doc(user.uid)
          .get();

      // =====================================================
      // المستخدم غير موجود في Firestore
      // =====================================================

      if (!userDoc.exists) {
        debugPrint('المستخدم غير موجود في Firestore');

        await auth.signOut();

        _goToLogin();
        return;
      }

      final data = userDoc.data() ?? {};

      debugPrint('بيانات المستخدم: $data');

      // =====================================================
      // التحقق من حالة الحساب
      // =====================================================

      final bool active = data['active'] == true;

      if (!active) {
        await auth.signOut();

        if (!mounted) return;

        await _showMessage(
          'هذا الحساب غير نشط',
        );

        _goToLogin();
        return;
      }

      // =====================================================
      // الدور
      // =====================================================

      final String role =
          data['role']?.toString().trim() ?? '';

      debugPrint('دور المستخدم: $role');

      // =====================================================
      // التوجيه حسب الدور
      // =====================================================

      final RoleRoute route = resolveRoleRoute(
        role: role,
        data: data,
      );

      if (route.hasError) {
        await auth.signOut();

        if (!mounted) return;

        await _showMessage(
          route.error!,
        );

        _goToLogin();
        return;
      }

      _go(
        route.page!,
      );
      return;
    } catch (e, stackTrace) {
      debugPrint('================================');
      debugPrint('Splash Error: $e');
      debugPrint('StackTrace: $stackTrace');
      debugPrint('================================');

      if (!mounted) return;

      // في حالة حدوث أي خطأ نذهب لتسجيل الدخول
      _goToLogin();
    }
  }

  // =========================================================
  // الانتقال إلى Login
  // =========================================================

  void _goToLogin() {
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginPage(),
      ),
      (route) => false,
    );
  }

  // =========================================================
  // الانتقال إلى أي صفحة
  // =========================================================

  void _go(Widget page) {
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => page,
      ),
      (route) => false,
    );
  }

  // =========================================================
  // رسالة
  // =========================================================

  Future<void> _showMessage(String message) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text(
              'تنبيه',
            ),
            content: Text(
              message,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'موافق',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================================================
  // واجهة Splash
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}


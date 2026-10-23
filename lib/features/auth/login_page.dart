import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

import '../admin/admin_page.dart';
import 'role_route.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // ============================================================
  // Firebase
  // ============================================================

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  // ============================================================
  // Controllers
  // ============================================================

  final TextEditingController _usernameController =
      TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  // ============================================================
  // الحالة
  // ============================================================

  bool _loading = false;
  bool _obscurePassword = true;

  // ============================================================
  // إعدادات تسجيل الدخول
  // ============================================================

  static const String _userEmailDomain =
      '@users.azal.local';

  static const String _adminEmail =
      'ahmedul2020@gmail.com';

  // ============================================================
  // الحساب التجريبي
  // ============================================================

  static const String _demoUsername =
      'demo';

  static const String _demoPassword =
      'Demo@123456';

  static const String _demoEmail =
      'demo@users.azal.local';

  // ============================================================
  // Dispose
  // ============================================================

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();

    super.dispose();
  }

  // ============================================================
  // إنشاء بريد المستخدم
  // ============================================================

  String _buildAuthEmail(
    String username,
  ) {
    return '${username.trim()}$_userEmailDomain';
  }

  // ============================================================
  // هل المستخدم حساب تجريبي؟
  // ============================================================

  bool _isDemoLogin(
    String login,
  ) {
    final String value =
        login.trim().toLowerCase();

    return value ==
            _demoUsername.toLowerCase() ||
        value ==
            _demoEmail.toLowerCase();
  }

  // ============================================================
  // الدخول المباشر بالحساب التجريبي
  // ============================================================

  Future<void> _loginDemoAccount() async {
    if (_loading) {
      return;
    }

    // تعبئة بيانات الحساب التجريبي داخلياً
    _usernameController.text =
        _demoUsername;

    _passwordController.text =
        _demoPassword;

    // تسجيل الدخول مباشرة
    await _login();
  }

  // ============================================================
  // تسجيل الدخول
  // ============================================================

  Future<void> _login() async {
    if (_loading) {
      return;
    }

    final String login =
        _usernameController.text.trim();

    final String password =
        _passwordController.text.trim();

    // ==========================================================
    // التحقق من البيانات
    // ==========================================================

    if (login.isEmpty ||
        password.isEmpty) {
      _showMessage(
        'يرجى إدخال اسم المستخدم وكلمة المرور',
      );

      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
    });

    try {
      // ========================================================
      // تحديد بريد Firebase Authentication
      // ========================================================

      String authEmail;

      // ========================================================
      // الحساب التجريبي
      // ========================================================

      if (_isDemoLogin(login)) {
        authEmail = _demoEmail;
      }

      // ========================================================
      // المدير الرئيسي
      // ========================================================

      else if (login.toLowerCase() ==
          _adminEmail.toLowerCase()) {
        authEmail = _adminEmail;
      }

      // ========================================================
      // بريد إلكتروني عادي
      // ========================================================

      else if (login.contains('@')) {
        authEmail = login;
      }

      // ========================================================
      // اسم مستخدم
      // ========================================================

      else {
        authEmail =
            _buildAuthEmail(login);
      }

      debugPrint(
        'Login email: $authEmail',
      );

      // ========================================================
      // Firebase Authentication
      // ========================================================

      final UserCredential credential =
          await _auth.signInWithEmailAndPassword(
        email: authEmail,
        password: password,
      );

      final User? firebaseUser =
          credential.user;

      // ========================================================
      // التحقق من المستخدم
      // ========================================================

      if (firebaseUser == null) {
        _showMessage(
          'تعذر تسجيل الدخول',
        );

        return;
      }

      debugPrint(
        'Logged user UID: ${firebaseUser.uid}',
      );

      debugPrint(
        'Logged user email: ${firebaseUser.email}',
      );

      // ========================================================
      // المدير الرئيسي
      // ========================================================

      if (firebaseUser.email?.toLowerCase() ==
          _adminEmail.toLowerCase()) {
        if (!mounted) {
          return;
        }

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const AdminPage(),
          ),
          (route) => false,
        );

        return;
      }

      // ========================================================
      // جلب بيانات المستخدم من Firestore
      //
      // users/{Firebase Auth UID}
      // ========================================================

      final DocumentSnapshot<
          Map<String, dynamic>> userDoc =
          await _firestore
              .collection('users')
              .doc(firebaseUser.uid)
              .get();

      // ========================================================
      // لا توجد بيانات للمستخدم
      // ========================================================

      if (!userDoc.exists) {
        await _auth.signOut();

        _showMessage(
          'لا توجد بيانات لهذا المستخدم في النظام',
        );

        return;
      }

      final Map<String, dynamic> data =
          userDoc.data() ?? {};

      debugPrint(
        'User data: $data',
      );

      // ========================================================
      // حالة الحساب
      // ========================================================

      final bool active =
          data['active'] == true;

      if (!active) {
        await _auth.signOut();

        _showMessage(
          'هذا الحساب غير مفعل',
        );

        return;
      }

      // ========================================================
      // الدور
      // ========================================================

      final String role =
          (data['role'] ?? '')
              .toString()
              .trim();

      // ========================================================
      // التوجيه حسب موقع المستخدم في الهيكل الإداري
      // ========================================================

      final RoleRoute route = resolveRoleRoute(
        role: role,
        data: data,
      );

      if (route.hasError) {
        await _auth.signOut();

        _showMessage(
          route.error!,
        );

        return;
      }

      if (!mounted) {
        return;
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => route.page!,
        ),
        (route) => false,
      );

      return;
    }

    // ============================================================
    // أخطاء Firebase Authentication
    // ============================================================

    on FirebaseAuthException catch (e) {
      debugPrint(
        'Firebase Auth Error: ${e.code}',
      );

      debugPrint(
        'Firebase Auth Message: ${e.message}',
      );

      String message;

      switch (e.code) {
        case 'invalid-credential':
          message =
              'اسم المستخدم أو كلمة المرور غير صحيحة';
          break;

        case 'user-not-found':
          message =
              'المستخدم غير موجود';
          break;

        case 'wrong-password':
          message =
              'كلمة المرور غير صحيحة';
          break;

        case 'invalid-email':
          message =
              'البريد الإلكتروني غير صحيح';
          break;

        case 'user-disabled':
          message =
              'حساب المستخدم معطل';
          break;

        case 'too-many-requests':
          message =
              'تم إجراء محاولات كثيرة، حاول لاحقاً';
          break;

        case 'network-request-failed':
          message =
              'تأكد من اتصال الإنترنت';
          break;

        default:
          message =
              'حدث خطأ أثناء تسجيل الدخول: '
              '${e.message ?? e.code}';
      }

      _showMessage(message);
    }

    // ============================================================
    // أي خطأ آخر
    // ============================================================

    catch (e) {
      debugPrint(
        'Login Error: $e',
      );

      _showMessage(
        'حدث خطأ غير متوقع: $e',
      );
    }

    // ============================================================
    // إيقاف التحميل
    // ============================================================

    finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // رسالة خطأ
  // ============================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    AppWidgets.showError(
      context,
      message,
    );
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Directionality(
      textDirection:
          TextDirection.rtl,
      child: Scaffold(
        backgroundColor:
            AppColors.background,
        body: LayoutBuilder(
          builder: (
            context,
            constraints,
          ) {
            final bool isDesktop =
                constraints.maxWidth >=
                    800;

            return Center(
              child:
                  SingleChildScrollView(
                padding:
                    EdgeInsets.symmetric(
                  horizontal:
                      isDesktop ? 40 : 20,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(
                    maxWidth: 1050,
                  ),
                  child: isDesktop
                      ? _buildDesktopLayout()
                      : _buildMobileLayout(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // واجهة الكمبيوتر
  // ============================================================

  Widget _buildDesktopLayout() {
    return Container(
      decoration:
          BoxDecoration(
        color:
            AppColors.surface,
        borderRadius:
            BorderRadius.circular(
          24,
        ),
        border: Border.all(
          color:
              AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withValues(
              alpha: 0.08,
            ),
            blurRadius: 30,
            offset:
                const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior:
          Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child:
                  _buildWelcomePanel(),
            ),
            Expanded(
              flex: 5,
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  45,
                ),
                child:
                    _buildLoginForm(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // واجهة الهاتف
  // ============================================================

  Widget _buildMobileLayout() {
    return Container(
      constraints:
          const BoxConstraints(
        maxWidth: 500,
      ),
      child: Column(
        children: [
          _buildMobileHeader(),

          AppSpacing.verticalLg,

          AppCard(
            padding:
                const EdgeInsets.all(
              24,
            ),
            child:
                _buildLoginForm(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // لوحة الترحيب
  // ============================================================

  Widget _buildWelcomePanel() {
    return Container(
      constraints:
          const BoxConstraints(
        minHeight: 580,
      ),
      decoration:
          const BoxDecoration(
        gradient:
            LinearGradient(
          begin:
              Alignment.topRight,
          end:
              Alignment.bottomLeft,
          colors: [
            AppColors.primaryDark,
            AppColors.primary,
            AppColors.primaryLight,
          ],
        ),
      ),
      child: Padding(
        padding:
            const EdgeInsets.all(
          45,
        ),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration:
                  BoxDecoration(
                color:
                    Colors.white.withValues(
                  alpha: 0.15,
                ),
                borderRadius:
                    BorderRadius.circular(
                  22,
                ),
                border: Border.all(
                  color:
                      Colors.white.withValues(
                    alpha: 0.25,
                  ),
                ),
              ),
              child:
                  const Icon(
                Icons
                    .account_tree_rounded,
                color:
                    Colors.white,
                size: 46,
              ),
            ),

            AppSpacing.verticalLg,

            const Text(
              'نظام إدارة المشاريع',
              style: TextStyle(
                fontSize: 32,
                fontWeight:
                    FontWeight.bold,
                color:
                    Colors.white,
                height: 1.4,
              ),
            ),

            AppSpacing.verticalSm,

            Text(
              'منصة متكاملة لإدارة المشاريع '
              'والبنود والتنفيذ والموارد.',
              style: TextStyle(
                fontSize: 16,
                color:
                    Colors.white.withValues(
                  alpha: 0.88,
                ),
                height: 1.8,
              ),
            ),

            AppSpacing.verticalLg,

            _buildFeature(
              Icons
                  .business_center_outlined,
              'إدارة المشاريع',
            ),

            _buildFeature(
              Icons
                  .engineering_outlined,
              'متابعة المهندسين والتنفيذ',
            ),

            _buildFeature(
              Icons
                  .local_shipping_outlined,
              'إدارة السائقين والوقود',
            ),

            _buildFeature(
              Icons
                  .analytics_outlined,
              'التقارير والمتابعة',
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ميزة
  // ============================================================

  Widget _buildFeature(
    IconData icon,
    String title,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 16,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration:
                BoxDecoration(
              color:
                  Colors.white.withValues(
                alpha: 0.12,
              ),
              borderRadius:
                  BorderRadius.circular(
                12,
              ),
            ),
            child:
                Icon(
              icon,
              color:
                  Colors.white,
              size: 22,
            ),
          ),

          AppSpacingHorizontal.md,

          Expanded(
            child:
                Text(
              title,
              style:
                  const TextStyle(
                color:
                    Colors.white,
                fontSize: 14,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // رأس الهاتف
  // ============================================================

  Widget _buildMobileHeader() {
    return Column(
      children: [
        Container(
          width: 82,
          height: 82,
          decoration:
              BoxDecoration(
            color:
                AppColors.primary,
            borderRadius:
                BorderRadius.circular(
              22,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    AppColors.primary
                        .withValues(
                  alpha: 0.25,
                ),
                blurRadius: 18,
                offset:
                    const Offset(0, 8),
              ),
            ],
          ),
          child:
              const Icon(
            Icons
                .account_tree_rounded,
            color:
                Colors.white,
            size: 46,
          ),
        ),

        AppSpacing.verticalMd,

        const Text(
          'نظام إدارة المشاريع',
          style:
              AppTextStyles.pageTitle,
          textAlign:
              TextAlign.center,
        ),

        AppSpacing.verticalXs,

        const Text(
          'مرحباً بك، سجل الدخول للمتابعة',
          style:
              AppTextStyles.bodySecondary,
          textAlign:
              TextAlign.center,
        ),
      ],
    );
  }

  // ============================================================
  // نموذج تسجيل الدخول
  // ============================================================

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children: [
        const Text(
          'تسجيل الدخول',
          style:
              AppTextStyles.pageTitle,
        ),

        AppSpacing.verticalXs,

        const Text(
          'أدخل بيانات حسابك للوصول إلى النظام',
          style:
              AppTextStyles.bodySecondary,
        ),

        AppSpacing.verticalLg,

        // ======================================================
        // اسم المستخدم
        // ======================================================

        AppTextField(
          controller:
              _usernameController,
          label:
              'اسم المستخدم أو البريد الإلكتروني',
          hint:
              'أدخل اسم المستخدم أو البريد',
          prefixIcon:
              Icons.person_outline,
          enabled:
              !_loading,
        ),

        AppSpacing.verticalMd,

        // ======================================================
        // كلمة المرور
        // ======================================================

        AppTextField(
          controller:
              _passwordController,
          label:
              'كلمة المرور',
          hint:
              'أدخل كلمة المرور',
          prefixIcon:
              Icons.lock_outline,
          obscureText:
              _obscurePassword,
          enabled:
              !_loading,
          suffixIcon:
              IconButton(
            tooltip:
                _obscurePassword
                    ? 'إظهار كلمة المرور'
                    : 'إخفاء كلمة المرور',
            icon:
                Icon(
              _obscurePassword
                  ? Icons
                      .visibility_outlined
                  : Icons
                      .visibility_off_outlined,
            ),
            onPressed:
                _loading
                    ? null
                    : () {
                        setState(() {
                          _obscurePassword =
                              !_obscurePassword;
                        });
                      },
          ),
        ),

        AppSpacing.verticalLg,

        // ======================================================
        // زر تسجيل الدخول
        // ======================================================

        AppButton(
          text:
              'تسجيل الدخول',
          icon:
              Icons.login_rounded,
          onPressed:
              _loading
                  ? null
                  : _login,
          loading:
              _loading,
          expanded:
              true,
        ),

        AppSpacing.verticalMd,

        // ======================================================
        // الدخول المباشر بالحساب التجريبي
        // ======================================================

        OutlinedButton.icon(
          onPressed:
              _loading
                  ? null
                  : _loginDemoAccount,
          icon:
              const Icon(
            Icons
                .play_circle_outline_rounded,
          ),
          label:
              const Text(
            'الدخول بالحساب التجريبي',
          ),
          style:
              OutlinedButton.styleFrom(
            minimumSize:
                const Size(
              double.infinity,
              50,
            ),
            shape:
                RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(
                12,
              ),
            ),
          ),
        ),

        AppSpacing.verticalMd,

        // ======================================================
        // معلومات الحساب التجريبي
        // ======================================================

        Container(
          padding:
              const EdgeInsets.all(
            14,
          ),
          decoration:
              BoxDecoration(
            color:
                AppColors.background,
            borderRadius:
                BorderRadius.circular(
              12,
            ),
            border: Border.all(
              color:
                  AppColors.border,
            ),
          ),
          child:
              const Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                color:
                    AppColors.info,
                size: 20,
              ),

              AppSpacingHorizontal.sm,

              Expanded(
                child:
                    Text(
                  'الحساب التجريبي يتيح الدخول '
                  'مباشرة إلى لوحة مدير المشروع.',
                  style:
                      AppTextStyles.small,
                ),
              ),
            ],
          ),
        ),

        AppSpacing.verticalLg,

        // ======================================================
        // اسم النظام
        // ======================================================

        const Center(
          child:
              Text(
            'نظام إدارة المشاريع',
            style:
                AppTextStyles.small,
          ),
        ),
      ],
    );
  }
}
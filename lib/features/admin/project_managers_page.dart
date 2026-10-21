
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

// =============================================================
// صفحة مديري المشاريع
// =============================================================

class ProjectManagersPage extends StatefulWidget {
  const ProjectManagersPage({
    super.key,
  });

  @override
  State<ProjectManagersPage> createState() =>
      _ProjectManagersPageState();
}

class _ProjectManagersPageState
    extends State<ProjectManagersPage> {
  // ============================================================
  // Controllers
  // ============================================================

  final GlobalKey<FormState> _formKey =
      GlobalKey<FormState>();

  final TextEditingController _nameController =
      TextEditingController();

  final TextEditingController _phoneController =
      TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  final TextEditingController _searchController =
      TextEditingController();

  // ============================================================
  // Firestore
  // ============================================================

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  // ============================================================
  // بيانات المشروع
  // ============================================================

  String? _selectedProjectId;
  String? _selectedProjectName;

  // ============================================================
  // حالة الصفحة
  // ============================================================

  bool _loading = false;
  bool _obscurePassword = true;

  // ============================================================
  // البحث
  // ============================================================

  String _searchText = '';

  // ============================================================
  // بيانات الحساب التجريبي
  // ============================================================

  static const String _demoUsername = 'demo';

  static const String _demoPassword =
      'Demo@123456';

  static const String _demoEmail =
      'demo@users.azal.local';

  // ============================================================
  // Dispose
  // ============================================================

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _searchController.dispose();

    super.dispose();
  }

  // ============================================================
  // تحويل رقم الهاتف إلى بريد داخلي لـ Firebase
  // ============================================================

  String _internalEmail(String phone) {
    return '${phone.trim()}@users.azal.local';
  }

  // ============================================================
  // إنشاء مدير مشروع عادي
  // ============================================================

  Future<void> _createManager() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedProjectId == null) {
      AppWidgets.showWarning(
        context,
        'اختر المشروع',
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    FirebaseApp? secondaryApp;

    try {
      // ==========================================================
      // بيانات الحساب
      // ==========================================================

      final String name =
          _nameController.text.trim();

      final String phone =
          _phoneController.text.trim();

      final String password =
          _passwordController.text.trim();

      final String internalEmail =
          _internalEmail(phone);

      // ==========================================================
      // التأكد من وجود المشروع
      // ==========================================================

      final projectDoc = await _firestore
          .collection('projects')
          .doc(_selectedProjectId)
          .get();

      if (!projectDoc.exists) {
        throw Exception(
          'المشروع غير موجود',
        );
      }

      final projectData =
          projectDoc.data();

      if (projectData == null) {
        throw Exception(
          'تعذر قراءة بيانات المشروع',
        );
      }

      // ==========================================================
      // التأكد أن المشروع ليس لديه مدير
      // ==========================================================

      final currentManagerId =
          projectData['managerId'];

      if (currentManagerId != null &&
          currentManagerId
              .toString()
              .isNotEmpty) {
        throw Exception(
          'هذا المشروع مرتبط بمدير مشروع بالفعل',
        );
      }

      // ==========================================================
      // التأكد أن رقم الهاتف غير مستخدم
      // ==========================================================

      final phoneQuery = await _firestore
          .collection('users')
          .where(
            'phone',
            isEqualTo: phone,
          )
          .limit(1)
          .get();

      if (phoneQuery.docs.isNotEmpty) {
        throw Exception(
          'رقم الهاتف مستخدم بالفعل',
        );
      }

      // ==========================================================
      // التأكد من اسم المستخدم
      // ==========================================================

      final usernameQuery =
          await _firestore
              .collection('users')
              .where(
                'username',
                isEqualTo: phone,
              )
              .limit(1)
              .get();

      if (usernameQuery.docs.isNotEmpty) {
        throw Exception(
          'اسم المستخدم مستخدم بالفعل',
        );
      }

      // ==========================================================
      // إنشاء Firebase App ثانوي
      // ==========================================================

      secondaryApp =
          await Firebase.initializeApp(
        name:
            'managerCreation_${DateTime.now().microsecondsSinceEpoch}',
        options:
            Firebase.app().options,
      );

      final FirebaseAuth secondaryAuth =
          FirebaseAuth.instanceFor(
        app: secondaryApp,
      );

      // ==========================================================
      // إنشاء الحساب في Firebase Authentication
      // ==========================================================

      final UserCredential credential =
          await secondaryAuth
              .createUserWithEmailAndPassword(
        email: internalEmail,
        password: password,
      );

      final User? createdUser =
          credential.user;

      if (createdUser == null) {
        throw Exception(
          'تعذر إنشاء حساب مدير المشروع',
        );
      }

      final String uid =
          createdUser.uid;

      // ==========================================================
      // إنشاء المستخدم في Firestore
      // ==========================================================

      await _firestore
          .collection('users')
          .doc(uid)
          .set({
        'name': name,
        'username': phone,
        'phone': phone,
        'authEmail': internalEmail,
        'role': 'project_manager',
        'projectId': _selectedProjectId,
        'projectName': _selectedProjectName,
        'active': true,
        'isDemo': false,
        'mustChangePassword': true,
        'createdAt':
            FieldValue.serverTimestamp(),
      });

      // ==========================================================
      // ربط المدير بالمشروع
      // ==========================================================

      await _firestore
          .collection('projects')
          .doc(_selectedProjectId)
          .update({
        'managerId': uid,
        'managerName': name,
      });

      // ==========================================================
      // تسجيل خروج الحساب الثانوي
      // ==========================================================

      await secondaryAuth.signOut();

      // ==========================================================
      // حفظ البيانات قبل تنظيف النموذج
      // ==========================================================

      final String managerName = name;
      final String managerPhone = phone;
      final String managerPassword =
          password;

      // ==========================================================
      // تنظيف النموذج
      // ==========================================================

      _clearForm();

      // ==========================================================
      // عرض بيانات الدخول
      // ==========================================================

      if (mounted) {
        await _showManagerCredentials(
          name: managerName,
          phone: managerPhone,
          password: managerPassword,
        );
      }
    } on FirebaseAuthException catch (e) {
      String message =
          'حدث خطأ أثناء إنشاء الحساب';

      if (e.code ==
          'email-already-in-use') {
        message =
            'رقم الهاتف مستخدم بالفعل';
      } else if (e.code ==
          'invalid-email') {
        message =
            'حدث خطأ في إنشاء الحساب';
      } else if (e.code ==
          'weak-password') {
        message =
            'كلمة السر ضعيفة';
      } else if (e.code ==
          'operation-not-allowed') {
        message =
            'تسجيل الدخول بالبريد وكلمة السر غير مفعل في Firebase';
      }

      if (mounted) {
        AppWidgets.showError(
          context,
          message,
        );
      }
    } catch (e) {
      if (mounted) {
        final message =
            e.toString().replaceFirst(
                  'Exception: ',
                  '',
                );

        AppWidgets.showError(
          context,
          message,
        );
      }
    } finally {
      // ==========================================================
      // حذف Firebase App الثانوي
      // ==========================================================

      if (secondaryApp != null) {
        try {
          await secondaryApp.delete();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // إنشاء الحساب التجريبي
  // ============================================================

  Future<void> _createDemoManager(
    BuildContext dialogContext,
  ) async {
    if (_selectedProjectId == null) {
      AppWidgets.showWarning(
        dialogContext,
        'اختر المشروع أولاً',
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    FirebaseApp? secondaryApp;

    try {
      // ==========================================================
      // التأكد من وجود المشروع
      // ==========================================================

      final projectDoc = await _firestore
          .collection('projects')
          .doc(_selectedProjectId)
          .get();

      if (!projectDoc.exists) {
        throw Exception(
          'المشروع غير موجود',
        );
      }

      final projectData =
          projectDoc.data();

      if (projectData == null) {
        throw Exception(
          'تعذر قراءة بيانات المشروع',
        );
      }

      // ==========================================================
      // التأكد أن المشروع ليس لديه مدير
      // ==========================================================

      final currentManagerId =
          projectData['managerId'];

      if (currentManagerId != null &&
          currentManagerId
              .toString()
              .isNotEmpty) {
        throw Exception(
          'هذا المشروع مرتبط بمدير مشروع بالفعل',
        );
      }

      // ==========================================================
      // التأكد أن حساب demo غير موجود
      // ==========================================================

      final demoQuery = await _firestore
          .collection('users')
          .where(
            'username',
            isEqualTo: _demoUsername,
          )
          .limit(1)
          .get();

      if (demoQuery.docs.isNotEmpty) {
        throw Exception(
          'الحساب التجريبي demo موجود بالفعل',
        );
      }

      // ==========================================================
      // إنشاء Firebase App ثانوي
      // ==========================================================

      secondaryApp =
          await Firebase.initializeApp(
        name:
            'demoManager_${DateTime.now().microsecondsSinceEpoch}',
        options:
            Firebase.app().options,
      );

      final FirebaseAuth secondaryAuth =
          FirebaseAuth.instanceFor(
        app: secondaryApp,
      );

      // ==========================================================
      // إنشاء الحساب في Firebase Authentication
      // ==========================================================

      final UserCredential credential =
          await secondaryAuth
              .createUserWithEmailAndPassword(
        email: _demoEmail,
        password: _demoPassword,
      );

      final User? createdUser =
          credential.user;

      if (createdUser == null) {
        throw Exception(
          'تعذر إنشاء الحساب التجريبي',
        );
      }

      final String uid =
          createdUser.uid;

      // ==========================================================
      // إنشاء المستخدم في Firestore
      // ==========================================================

      await _firestore
          .collection('users')
          .doc(uid)
          .set({
        'name': 'مدير تجريبي',
        'username': _demoUsername,
        'phone': '',
        'authEmail': _demoEmail,
        'role': 'project_manager',
        'projectId': _selectedProjectId,
        'projectName': _selectedProjectName,
        'active': true,
        'isDemo': true,
        'mustChangePassword': false,
        'createdAt':
            FieldValue.serverTimestamp(),
      });

      // ==========================================================
      // ربط الحساب بالمشروع
      // ==========================================================

      await _firestore
          .collection('projects')
          .doc(_selectedProjectId)
          .update({
        'managerId': uid,
        'managerName': 'مدير تجريبي',
      });

      // ==========================================================
      // تسجيل الخروج من الحساب الثانوي
      // ==========================================================

      await secondaryAuth.signOut();

      // ==========================================================
      // إغلاق نافذة الإنشاء
      // ==========================================================

      if (dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }

      // ==========================================================
      // تنظيف الاختيار
      // ==========================================================

      _selectedProjectId = null;
      _selectedProjectName = null;

      // ==========================================================
      // عرض بيانات الحساب
      // ==========================================================

      if (mounted) {
        await _showDemoManagerCredentials();
      }
    } on FirebaseAuthException catch (e) {
      String message =
          'حدث خطأ أثناء إنشاء الحساب التجريبي';

      if (e.code ==
          'email-already-in-use') {
        message =
            'الحساب التجريبي demo موجود بالفعل';
      } else if (e.code ==
          'weak-password') {
        message =
            'كلمة السر الافتراضية ضعيفة';
      } else if (e.code ==
          'operation-not-allowed') {
        message =
            'تسجيل الدخول بالبريد وكلمة السر غير مفعل في Firebase';
      }

      if (dialogContext.mounted) {
        AppWidgets.showError(
          dialogContext,
          message,
        );
      }
    } catch (e) {
      if (dialogContext.mounted) {
        final message =
            e.toString().replaceFirst(
                  'Exception: ',
                  '',
                );

        AppWidgets.showError(
          dialogContext,
          message,
        );
      }
    } finally {
      // ==========================================================
      // حذف Firebase App الثانوي
      // ==========================================================

      if (secondaryApp != null) {
        try {
          await secondaryApp.delete();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // تنظيف النموذج
  // ============================================================

  void _clearForm() {
    _nameController.clear();
    _phoneController.clear();
    _passwordController.clear();

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedProjectId = null;
      _selectedProjectName = null;
    });
  }

  // ============================================================
  // بيانات دخول المدير العادي
  // ============================================================

  Future<void> _showManagerCredentials({
    required String name,
    required String phone,
    required String password,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تم إنشاء مدير المشروع',
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'مدير المشروع: $name',
                    style:
                        AppTextStyles.cardTitle,
                  ),

                  AppSpacing.verticalMd,

                  const Text(
                    'اسم المستخدم',
                    style:
                        AppTextStyles.bodySecondary,
                  ),

                  AppSpacing.verticalXs,

                  _CredentialBox(
                    value: phone,
                    tooltip:
                        'نسخ رقم الهاتف',
                    onCopy: () async {
                      await Clipboard
                          .setData(
                        ClipboardData(
                          text: phone,
                        ),
                      );

                      if (dialogContext
                          .mounted) {
                        AppWidgets
                            .showSuccess(
                          dialogContext,
                          'تم نسخ رقم الهاتف',
                        );
                      }
                    },
                  ),

                  AppSpacing.verticalMd,

                  const Text(
                    'كلمة السر المؤقتة',
                    style:
                        AppTextStyles.bodySecondary,
                  ),

                  AppSpacing.verticalXs,

                  _CredentialBox(
                    value: password,
                    tooltip:
                        'نسخ كلمة السر',
                    onCopy: () async {
                      await Clipboard
                          .setData(
                        ClipboardData(
                          text: password,
                        ),
                      );

                      if (dialogContext
                          .mounted) {
                        AppWidgets
                            .showSuccess(
                          dialogContext,
                          'تم نسخ كلمة السر',
                        );
                      }
                    },
                  ),

                  AppSpacing.verticalMd,

                  Container(
                    padding:
                        const EdgeInsets.all(
                      12,
                    ),
                    decoration:
                        BoxDecoration(
                      color: AppColors.warning
                          .withValues(
                        alpha: 0.10,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                      border: Border.all(
                        color: AppColors.warning
                            .withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color:
                              AppColors.warning,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'كلمة السر مؤقتة، ويجب تغييرها عند أول تسجيل دخول.',
                            style:
                                AppTextStyles
                                    .small,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              AppButton(
                text: 'تم',
                icon: Icons.check,
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // بيانات الحساب التجريبي
  // ============================================================

  Future<void>
      _showDemoManagerCredentials() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Directionality(
          textDirection:
              TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(
                  Icons.science_outlined,
                  color: AppColors.primary,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تم إنشاء الحساب التجريبي',
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'مدير تجريبي',
                    style:
                        AppTextStyles.cardTitle,
                  ),

                  AppSpacing.verticalMd,

                  const Text(
                    'اسم المستخدم',
                    style:
                        AppTextStyles.bodySecondary,
                  ),

                  AppSpacing.verticalXs,

                  _CredentialBox(
                    value:
                        _demoUsername,
                    tooltip:
                        'نسخ اسم المستخدم',
                    onCopy: () async {
                      await Clipboard
                          .setData(
                        const ClipboardData(
                          text: _demoUsername,
                        ),
                      );

                      if (dialogContext
                          .mounted) {
                        AppWidgets
                            .showSuccess(
                          dialogContext,
                          'تم نسخ اسم المستخدم',
                        );
                      }
                    },
                  ),

                  AppSpacing.verticalMd,

                  const Text(
                    'كلمة السر',
                    style:
                        AppTextStyles.bodySecondary,
                  ),

                  AppSpacing.verticalXs,

                  _CredentialBox(
                    value:
                        _demoPassword,
                    tooltip:
                        'نسخ كلمة السر',
                    onCopy: () async {
                      await Clipboard
                          .setData(
                        const ClipboardData(
                          text: _demoPassword,
                        ),
                      );

                      if (dialogContext
                          .mounted) {
                        AppWidgets
                            .showSuccess(
                          dialogContext,
                          'تم نسخ كلمة السر',
                        );
                      }
                    },
                  ),

                  AppSpacing.verticalMd,

                  Container(
                    padding:
                        const EdgeInsets.all(
                      12,
                    ),
                    decoration:
                        BoxDecoration(
                      color: AppColors.primary
                          .withValues(
                        alpha: 0.10,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                      border: Border.all(
                        color: AppColors
                            .primary
                            .withValues(
                          alpha: 0.30,
                        ),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Icon(
                          Icons
                              .science_outlined,
                          color:
                              AppColors.primary,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'هذا حساب تجريبي ويمكن استخدامه لاختبار لوحة مدير المشروع.',
                            style:
                                AppTextStyles
                                    .small,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              AppButton(
                text: 'تم',
                icon: Icons.check,
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // اختيار المشروع
  // ============================================================

  Widget _buildProjectDropdown() {
    return StreamBuilder<
        QuerySnapshot<
            Map<String, dynamic>>>(
      stream: _firestore
          .collection('projects')
          .where(
            'status',
            isEqualTo: 'active',
          )
          .snapshots(),
      builder: (
        context,
        snapshot,
      ) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }

        if (snapshot.hasError) {
          return AppError(
            message:
                'خطأ في تحميل المشاريع',
            onRetry: () {
              setState(() {});
            },
          );
        }

        final docs =
            snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const AppEmpty(
            message:
                'لا توجد مشاريع نشطة',
            icon:
                Icons.business_outlined,
          );
        }

        final sortedDocs = [...docs];

        sortedDocs.sort(
          (a, b) {
            final dataA = a.data();
            final dataB = b.data();

            final nameA =
                dataA['name']
                        ?.toString() ??
                    '';

            final nameB =
                dataB['name']
                        ?.toString() ??
                    '';

            return nameA.compareTo(
              nameB,
            );
          },
        );

        return AppDropdown<String>(
          value: _selectedProjectId,
          label: 'المشروع',
          prefixIcon:
              Icons.business_outlined,
          items: sortedDocs.map(
            (doc) {
              final data =
                  doc.data();

              final String projectName =
                  data['name']
                          ?.toString() ??
                      'بدون اسم';

              final String projectCode =
                  data['code']
                          ?.toString() ??
                      '';

              final String title =
                  projectCode.isEmpty
                      ? projectName
                      : '$projectName - $projectCode';

              return DropdownMenuItem<
                  String>(
                value: doc.id,
                child: Text(
                  title,
                  overflow:
                      TextOverflow.ellipsis,
                ),
              );
            },
          ).toList(),
          onChanged: (value) {
            if (value == null) {
              return;
            }

            final doc =
                sortedDocs.firstWhere(
              (item) =>
                  item.id == value,
            );

            final data =
                doc.data();

            setState(() {
              _selectedProjectId =
                  value;

              _selectedProjectName =
                  data['name']
                      ?.toString();
            });
          },
        );
      },
    );
  }

  // ============================================================
  // نموذج إنشاء المدير العادي
  // ============================================================

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          AppSectionTitle(
            title:
                'إنشاء مدير مشروع',
            icon:
                Icons.person_add_outlined,
          ),

          AppSpacing.verticalMd,

          AppTextField(
            controller:
                _nameController,
            label:
                'اسم مدير المشروع',
            hint:
                'مثال: أحمد محمد',
            prefixIcon:
                Icons.person_outline,
            validator: (value) {
              if (value == null ||
                  value.trim().isEmpty) {
                return 'أدخل اسم مدير المشروع';
              }

              return null;
            },
          ),

          AppSpacing.verticalMd,

          AppTextField(
            controller:
                _phoneController,
            label:
                'رقم الهاتف',
            hint:
                'مثال: 777123456',
            helperText:
                'رقم الهاتف سيكون اسم المستخدم',
            prefixIcon:
                Icons.phone_outlined,
            keyboardType:
                TextInputType.phone,
            validator: (value) {
              if (value == null ||
                  value.trim().isEmpty) {
                return 'أدخل رقم الهاتف';
              }

              if (value.trim().length <
                  9) {
                return 'أدخل رقم هاتف صحيح';
              }

              return null;
            },
          ),

          AppSpacing.verticalMd,

          TextFormField(
            controller:
                _passwordController,
            obscureText:
                _obscurePassword,
            decoration:
                InputDecoration(
              labelText:
                  'كلمة السر المؤقتة',
              hintText:
                  'أدخل كلمة السر',
              prefixIcon:
                  const Icon(
                Icons.lock_outline,
              ),
              suffixIcon:
                  IconButton(
                tooltip:
                    _obscurePassword
                        ? 'إظهار كلمة السر'
                        : 'إخفاء كلمة السر',
                icon: Icon(
                  _obscurePassword
                      ? Icons
                          .visibility_outlined
                      : Icons
                          .visibility_off_outlined,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword =
                        !_obscurePassword;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null ||
                  value.length < 6) {
                return 'كلمة السر يجب أن تكون 6 أحرف على الأقل';
              }

              return null;
            },
          ),

          AppSpacing.verticalMd,

          _buildProjectDropdown(),

          AppSpacing.verticalLg,

          AppButton(
            text: _loading
                ? 'جاري إنشاء الحساب...'
                : 'إنشاء مدير المشروع',
            icon: _loading
                ? null
                : Icons
                    .person_add_outlined,
            loading: _loading,
            expanded: true,
            onPressed: _loading
                ? null
                : _createManager,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // البحث في المديرين
  // ============================================================

  List<
          QueryDocumentSnapshot<
              Map<String, dynamic>>>
      _filterManagers(
    List<
            QueryDocumentSnapshot<
                Map<String, dynamic>>>
        docs,
  ) {
    final search =
        _searchText
            .trim()
            .toLowerCase();

    if (search.isEmpty) {
      return docs;
    }

    return docs.where(
      (doc) {
        final data =
            doc.data();

        final name =
            data['name']
                    ?.toString()
                    .toLowerCase() ??
                '';

        final phone =
            data['phone']
                    ?.toString()
                    .toLowerCase() ??
                '';

        final username =
            data['username']
                    ?.toString()
                    .toLowerCase() ??
                '';

        final projectName =
            data['projectName']
                    ?.toString()
                    .toLowerCase() ??
                '';

        return name.contains(
              search,
            ) ||
            phone.contains(
              search,
            ) ||
            username.contains(
              search,
            ) ||
            projectName.contains(
              search,
            );
      },
    ).toList();
  }

  // ============================================================
  // قائمة مديري المشاريع
  // ============================================================

  Widget _buildManagersList() {
    return StreamBuilder<
        QuerySnapshot<
            Map<String, dynamic>>>(
      stream: _firestore
          .collection('users')
          .where(
            'role',
            isEqualTo:
                'project_manager',
          )
          .snapshots(),
      builder: (
        context,
        snapshot,
      ) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const AppLoading(
            message:
                'جاري تحميل مديري المشاريع...',
          );
        }

        if (snapshot.hasError) {
          return AppError(
            message:
                'حدث خطأ أثناء تحميل مديري المشاريع',
            onRetry: () {
              setState(() {});
            },
          );
        }

        final allDocs =
            snapshot.data?.docs.toList() ??
                [];

        allDocs.sort(
          (a, b) {
            final nameA =
                a.data()['name']
                        ?.toString() ??
                    '';

            final nameB =
                b.data()['name']
                        ?.toString() ??
                    '';

            return nameA.compareTo(
              nameB,
            );
          },
        );

        final docs =
            _filterManagers(
          allDocs,
        );

        if (docs.isEmpty) {
          return AppEmpty(
            message:
                _searchText
                        .trim()
                        .isEmpty
                    ? 'لا يوجد مديرو مشاريع حتى الآن'
                    : 'لا توجد نتائج مطابقة للبحث',
            icon:
                Icons
                    .manage_accounts_outlined,
          );
        }

        return ListView.builder(
          padding:
              const EdgeInsets.only(
            bottom: 100,
          ),
          itemCount:
              docs.length,
          itemBuilder:
              (context, index) {
            final doc =
                docs[index];

            final data =
                doc.data();

            final String name =
                data['name']
                        ?.toString() ??
                    'بدون اسم';

            final String phone =
                data['phone']
                        ?.toString() ??
                    '';

            final String username =
                data['username']
                        ?.toString() ??
                    '';

            final String projectName =
                data['projectName']
                        ?.toString() ??
                    'غير مرتبط';

            final bool active =
                data['active'] ==
                    true;

            final bool isDemo =
                data['isDemo'] ==
                    true;

            final bool
                mustChangePassword =
                data[
                        'mustChangePassword'] ==
                    true;

            return Padding(
              padding:
                  const EdgeInsets.only(
                bottom: 12,
              ),
              child: AppCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration:
                              BoxDecoration(
                            color: AppColors
                                .admin
                                .withValues(
                              alpha:
                                  0.10,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              15,
                            ),
                          ),
                          child:
                              const Icon(
                            Icons
                                .manage_accounts_outlined,
                            color:
                                AppColors
                                    .admin,
                            size: 29,
                          ),
                        ),

                        const SizedBox(
                          width: 14,
                        ),

                        Expanded(
                          child:
                              Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child:
                                        Text(
                                      name,
                                      style:
                                          AppTextStyles
                                              .cardTitle,
                                      overflow:
                                          TextOverflow
                                              .ellipsis,
                                    ),
                                  ),

                                  if (isDemo) ...[
                                    const SizedBox(
                                      width:
                                          8,
                                    ),
                                    const AppStatusBadge(
                                      text:
                                          'تجريبي',
                                      color:
                                          AppColors
                                              .primary,
                                    ),
                                  ],
                                ],
                              ),

                              const SizedBox(
                                height: 6,
                              ),

                              Text(
                                username.isEmpty
                                    ? phone.isEmpty
                                        ? 'لا يوجد اسم مستخدم'
                                        : phone
                                    : username,
                                style:
                                    AppTextStyles
                                        .bodySecondary,
                              ),

                              const SizedBox(
                                height: 4,
                              ),

                              Text(
                                projectName,
                                style:
                                    AppTextStyles
                                        .bodySecondary,
                              ),
                            ],
                          ),
                        ),

                        AppStatusBadge(
                          text:
                              active
                                  ? 'نشط'
                                  : 'معطل',
                          color:
                              active
                                  ? AppColors
                                      .success
                                  : AppColors
                                      .danger,
                        ),
                      ],
                    ),

                    AppSpacing.verticalMd,

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppStatusBadge(
                          text:
                              'المشروع: $projectName',
                          color:
                              AppColors
                                  .primary,
                        ),

                        if (isDemo)
                          const AppStatusBadge(
                            text:
                                'حساب تجريبي',
                            color:
                                AppColors
                                    .primary,
                          ),

                        if (mustChangePassword)
                          const AppStatusBadge(
                            text:
                                'يجب تغيير كلمة السر',
                            color:
                                AppColors
                                    .warning,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // فتح نموذج إنشاء المدير العادي
  // ============================================================

  void _openCreateManagerDialog() {
    _clearForm();

    showDialog(
      context: context,
      builder: (_) {
        return Directionality(
          textDirection:
              TextDirection.rtl,
          child: AlertDialog(
            title: const Text(
              'إنشاء مدير مشروع',
            ),
            content:
                SingleChildScrollView(
              child: _buildForm(),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // فتح نموذج الحساب التجريبي
  // ============================================================

  void _openCreateDemoManagerDialog() {
    setState(() {
      _selectedProjectId =
          null;
      _selectedProjectName =
          null;
    });

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection:
              TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(
                  Icons.science_outlined,
                  color:
                      AppColors.primary,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'إنشاء حساب تجريبي',
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment
                        .stretch,
                children: [
                  const Text(
                    'اختر المشروع فقط، وسيتم إنشاء حساب مدير تجريبي بالبيانات الافتراضية.',
                    style:
                        AppTextStyles
                            .bodySecondary,
                  ),

                  AppSpacing.verticalLg,

                  _buildProjectDropdown(),

                  AppSpacing.verticalLg,

                  Container(
                    padding:
                        const EdgeInsets.all(
                      12,
                    ),
                    decoration:
                        BoxDecoration(
                      color: AppColors
                          .primary
                          .withValues(
                        alpha: 0.08,
                      ),
                      borderRadius:
                          BorderRadius
                              .circular(
                        12,
                      ),
                      border:
                          Border.all(
                        color: AppColors
                            .primary
                            .withValues(
                          alpha: 0.25,
                        ),
                      ),
                    ),
                    child:
                        const Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          'بيانات الدخول الافتراضية',
                          style:
                              AppTextStyles
                                  .cardTitle,
                        ),
                        SizedBox(
                          height: 8,
                        ),
                        Text(
                          'اسم المستخدم: demo',
                          style:
                              AppTextStyles
                                  .bodySecondary,
                        ),
                        SizedBox(
                          height: 4,
                        ),
                        Text(
                          'كلمة السر: Demo@123456',
                          style:
                              AppTextStyles
                                  .bodySecondary,
                        ),
                      ],
                    ),
                  ),

                  AppSpacing.verticalLg,

                  AppButton(
                    text: _loading
                        ? 'جاري إنشاء الحساب...'
                        : 'إنشاء الحساب التجريبي',
                    icon: _loading
                        ? null
                        : Icons
                            .science_outlined,
                    loading:
                        _loading,
                    expanded: true,
                    onPressed: _loading
                        ? null
                        : () {
                            _createDemoManager(
                              dialogContext,
                            );
                          },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // الصفحة
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return AppScaffold(
      title: 'مديرو المشاريع',
      showBackButton: true,

      // ========================================================
      // أزرار أعلى الصفحة
      // ========================================================

      actions: [
        // الحساب التجريبي
        IconButton(
          tooltip:
              'إنشاء حساب تجريبي',
          onPressed: _loading
              ? null
              : _openCreateDemoManagerDialog,
          icon: const Icon(
            Icons.science_outlined,
          ),
        ),

        // إضافة مدير مشروع
        IconButton(
          tooltip:
              'إضافة مدير مشروع',
          onPressed: _loading
              ? null
              : _openCreateManagerDialog,
          icon: const Icon(
            Icons.person_add_outlined,
          ),
        ),
      ],

      // ========================================================
      // أزرار أسفل الصفحة
      // ========================================================

      floatingActionButton:
          Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag:
                'demo_manager_button',
            onPressed: _loading
                ? null
                : _openCreateDemoManagerDialog,
            icon: const Icon(
              Icons.science_outlined,
            ),
            label: const Text(
              'حساب تجريبي',
            ),
          ),

          const SizedBox(
            width: 12,
          ),

          FloatingActionButton.extended(
            heroTag:
                'add_manager_button',
            onPressed: _loading
                ? null
                : _openCreateManagerDialog,
            icon: const Icon(
              Icons.person_add_outlined,
            ),
            label: const Text(
              'إضافة مدير',
            ),
          ),
        ],
      ),

      child: Directionality(
        textDirection:
            TextDirection.rtl,
        child: AppPage(
          scrollable: false,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .stretch,
            children: [
              // ==================================================
              // رأس الصفحة
              // ==================================================

              AppPageHeader(
                title:
                    'إدارة مديري المشاريع',
                subtitle:
                    'إنشاء حسابات مديري المشاريع وربط كل مدير بمشروع واحد.',
                icon: Icons
                    .manage_accounts_outlined,
              ),

              AppSpacing.verticalLg,

              // ==================================================
              // البحث
              // ==================================================

              AppTextField(
                controller:
                    _searchController,
                label: 'البحث',
                hint:
                    'ابحث بالاسم أو رقم الهاتف أو المشروع',
                prefixIcon:
                    Icons.search,
                onChanged: (value) {
                  setState(() {
                    _searchText =
                        value;
                  });
                },
              ),

              AppSpacing.verticalLg,

              // ==================================================
              // الإحصائيات
              // ==================================================

              StreamBuilder<
                  QuerySnapshot<
                      Map<String,
                          dynamic>>>(
                stream: _firestore
                    .collection(
                        'users')
                    .where(
                      'role',
                      isEqualTo:
                          'project_manager',
                    )
                    .snapshots(),
                builder: (
                  context,
                  snapshot,
                ) {
                  final docs =
                      snapshot.data
                              ?.docs ??
                          [];

                  final int active =
                      docs.where(
                    (doc) =>
                        doc.data()[
                            'active'] ==
                        true,
                  ).length;

                  final int inactive =
                      docs.length -
                          active;

                  final int demo =
                      docs.where(
                    (doc) =>
                        doc.data()[
                            'isDemo'] ==
                        true,
                  ).length;

                  return AppResponsiveGrid(
                    minItemWidth:
                        220,
                    spacing: 16,
                    children: [
                      AppStatCard(
                        title:
                            'إجمالي المديرين',
                        value:
                            '${docs.length}',
                        icon: Icons
                            .manage_accounts_outlined,
                        color: AppColors
                            .primary,
                      ),

                      AppStatCard(
                        title:
                            'المديرون النشطون',
                        value:
                            '$active',
                        icon: Icons
                            .check_circle_outline,
                        color: AppColors
                            .success,
                      ),

                      AppStatCard(
                        title:
                            'المديرون المعطلون',
                        value:
                            '$inactive',
                        icon: Icons
                            .cancel_outlined,
                        color: AppColors
                            .danger,
                      ),

                      AppStatCard(
                        title:
                            'الحسابات التجريبية',
                        value:
                            '$demo',
                        icon: Icons
                            .science_outlined,
                        color: AppColors
                            .primary,
                      ),
                    ],
                  );
                },
              ),

              AppSpacing.verticalXl,

              // ==================================================
              // عنوان القائمة
              // ==================================================

              AppSectionTitle(
                title:
                    'قائمة مديري المشاريع',
                icon:
                    Icons
                        .list_alt_outlined,
              ),

              AppSpacing.verticalMd,

              // ==================================================
              // القائمة
              // ==================================================

              Expanded(
                child:
                    _buildManagersList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// صندوق بيانات الدخول
// =============================================================

class _CredentialBox
    extends StatelessWidget {
  final String value;
  final String tooltip;
  final VoidCallback onCopy;

  const _CredentialBox({
    required this.value,
    required this.tooltip,
    required this.onCopy,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration:
          BoxDecoration(
        color:
            AppColors.background,
        borderRadius:
            BorderRadius.circular(
          12,
        ),
        border:
            Border.all(
          color:
              AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              value,
              style:
                  const TextStyle(
                fontSize: 17,
                fontWeight:
                    FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),

          IconButton(
            tooltip: tooltip,
            onPressed: onCopy,
            icon: const Icon(
              Icons.copy_outlined,
            ),
          ),
        ],
      ),
    );
  }
}


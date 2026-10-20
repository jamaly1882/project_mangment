
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({
    super.key,
    this.initialSupervisor = false,
  });

  /// فتح الصفحة على تبويب المشرفين مباشرة.
  final bool initialSupervisor;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage>
    with SingleTickerProviderStateMixin {
  // ============================================================
  // Firebase
  // ============================================================

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  // ============================================================
  // Tab Controller
  // ============================================================

  late final TabController _tabController;

  // Stream ثابت للمشاريع الفعالة.
  // مهم: لا ننشئ Stream جديدًا داخل نافذة الحوار عند كل setDialogState.
  late final Stream<QuerySnapshot<Map<String, dynamic>>>
      _activeProjectsStream;

  // ============================================================
  // البحث
  // ============================================================

  final TextEditingController _searchController =
      TextEditingController();

  String _searchText = '';

  // ============================================================
  // دورة الحياة
  // ============================================================

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      initialIndex: widget.initialSupervisor ? 1 : 0,
      length: 2,
      vsync: this,
    );

    // لا نستخدم orderBy مع where لتجنب الاعتماد على Composite Index.
    // سيتم ترتيب المشاريع محليًا في _buildProjectsSelector.
    _activeProjectsStream = _firestore
        .collection('projects')
        .where('status', isEqualTo: 'active')
        .snapshots();

    _searchController.addListener(
      _onSearchChanged,
    );

    _tabController.addListener(
      _onTabChanged,
    );
  }

  void _onSearchChanged() {
    if (!mounted) return;

    setState(() {
      _searchText =
          _searchController.text.trim().toLowerCase();
    });
  }

  void _onTabChanged() {
    if (!mounted) return;

    // لا نحتاج setState أثناء سحب TabBarView
    // إلا عند اكتمال تغيير التبويب.
    if (_tabController.indexIsChanging) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(
      _onTabChanged,
    );

    _searchController.removeListener(
      _onSearchChanged,
    );

    _tabController.dispose();
    _searchController.dispose();

    super.dispose();
  }

  // ============================================================
  // الدور الحالي
  // ============================================================

  String get _currentRole {
    return _tabController.index == 0
        ? 'engineer'
        : 'supervisor';
  }

  bool get _currentIsEngineer {
    return _currentRole == 'engineer';
  }

  // ============================================================
  // إنشاء مستخدم Firebase Authentication
  // باستخدام Firebase App ثانوي
  // ============================================================

  Future<UserCredential> _createSecondaryAuthUser({
    required String email,
    required String password,
  }) async {
    final FirebaseApp secondaryApp =
        await Firebase.initializeApp(
      name:
          'usersCreation_${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );

    try {
      final FirebaseAuth secondaryAuth =
          FirebaseAuth.instanceFor(
        app: secondaryApp,
      );

      return await secondaryAuth
          .createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } finally {
      await secondaryApp.delete();
    }
  }

  // ============================================================
  // البريد الداخلي
  // ============================================================

  String _buildAuthEmail(
    String username,
  ) {
    return '${username.trim()}@users.azal.local';
  }

  // ============================================================
  // إضافة مستخدم
  // ============================================================

  Future<void> _showAddUserDialog({
    required String role,
  }) async {
    final nameController =
        TextEditingController();

    final usernameController =
        TextEditingController();

    final passwordController =
        TextEditingController();

    final formKey =
        GlobalKey<FormState>();

    List<String> selectedProjectIds = [];
    List<String> selectedProjectNames = [];

    bool active = true;
    bool obscurePassword = true;
    bool loading = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            final isEngineer =
                role == 'engineer';

            return Directionality(
              textDirection:
                  TextDirection.rtl,
              child: AlertDialog(
                titlePadding:
                    const EdgeInsets.fromLTRB(
                  24,
                  20,
                  24,
                  10,
                ),
                contentPadding:
                    const EdgeInsets.fromLTRB(
                  24,
                  10,
                  24,
                  10,
                ),
                actionsPadding:
                    const EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16,
                ),
                title: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
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
                      ),
                      child: Icon(
                        isEngineer
                            ? Icons.engineering
                            : Icons.supervisor_account,
                        color:
                            AppColors.primary,
                      ),
                    ),
                    AppSpacingHorizontal.md,
                    Expanded(
                      child: Text(
                        isEngineer
                            ? 'إضافة مهندس'
                            : 'إضافة مشرف',
                        style:
                            AppTextStyles
                                .sectionTitle,
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 600,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize:
                            MainAxisSize.min,
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .stretch,
                        children: [
                          // ==================================================
                          // الاسم
                          // ==================================================

                          AppTextField(
                            controller:
                                nameController,
                            label:
                                'اسم المستخدم',
                            hint:
                                'أدخل الاسم الكامل',
                            prefixIcon:
                                Icons.person,
                            enabled:
                                !loading,
                            validator:
                                (value) {
                              if (value ==
                                      null ||
                                  value
                                      .trim()
                                      .isEmpty) {
                                return 'أدخل اسم المستخدم';
                              }

                              return null;
                            },
                          ),

                          AppSpacing.verticalMd,

                          // ==================================================
                          // اسم المستخدم
                          // ==================================================

                          AppTextField(
                            controller:
                                usernameController,
                            label:
                                'اسم المستخدم / رقم الهاتف',
                            hint:
                                'مثال: 777123456',
                            prefixIcon:
                                Icons.phone,
                            keyboardType:
                                TextInputType
                                    .phone,
                            enabled:
                                !loading,
                            onChanged:
                                (_) {
                              setDialogState(
                                () {},
                              );
                            },
                            validator:
                                (value) {
                              if (value ==
                                      null ||
                                  value
                                      .trim()
                                      .isEmpty) {
                                return 'أدخل اسم المستخدم';
                              }

                              if (value
                                  .contains(
                                '@',
                              )) {
                                return 'أدخل اسم المستخدم فقط بدون @';
                              }

                              return null;
                            },
                          ),

                          AppSpacing.verticalMd,

                          // ==================================================
                          // كلمة المرور
                          // ==================================================

                          TextFormField(
                            controller:
                                passwordController,
                            enabled:
                                !loading,
                            obscureText:
                                obscurePassword,
                            textAlign:
                                TextAlign.right,
                            decoration:
                                InputDecoration(
                              labelText:
                                  'كلمة المرور',
                              hintText:
                                  '6 أحرف أو أرقام على الأقل',
                              prefixIcon:
                                  const Icon(
                                Icons.lock,
                              ),
                              suffixIcon:
                                  IconButton(
                                tooltip:
                                    obscurePassword
                                        ? 'إظهار كلمة المرور'
                                        : 'إخفاء كلمة المرور',
                                onPressed:
                                    loading
                                        ? null
                                        : () {
                                            setDialogState(
                                              () {
                                                obscurePassword =
                                                    !obscurePassword;
                                              },
                                            );
                                          },
                                icon:
                                    Icon(
                                  obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                              ),
                            ),
                            validator:
                                (value) {
                              if (value ==
                                      null ||
                                  value.isEmpty) {
                                return 'أدخل كلمة المرور';
                              }

                              if (value.length <
                                  6) {
                                return 'كلمة المرور يجب أن تكون 6 أحرف أو أرقام على الأقل';
                              }

                              return null;
                            },
                          ),

                          AppSpacing.verticalLg,

                          // ==================================================
                          // المشاريع
                          // ==================================================

                          AppSectionTitle(
                            title:
                                'المشاريع التي يعمل بها',
                            icon:
                                Icons.business,
                          ),

                          AppSpacing.verticalSm,

                          _buildProjectsSelector(
                            selectedProjectIds:
                                selectedProjectIds,
                            setDialogState:
                                setDialogState,
                            loading:
                                loading,
                            onChanged:
                                (
                              ids,
                              names,
                            ) {
                              selectedProjectIds =
                                  ids;
                              selectedProjectNames =
                                  names;
                            },
                          ),

                          AppSpacing.verticalSm,

                          Container(
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration:
                                BoxDecoration(
                              color: AppColors
                                  .primary
                                  .withValues(
                                alpha: 0.07,
                              ),
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                10,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.business,
                                  size: 20,
                                  color:
                                      AppColors
                                          .primary,
                                ),
                                AppSpacingHorizontal
                                    .sm,
                                Expanded(
                                  child: Text(
                                    selectedProjectIds
                                            .isEmpty
                                        ? 'لم يتم اختيار أي مشروع'
                                        : 'تم اختيار ${selectedProjectIds.length} مشروع',
                                    style:
                                        const TextStyle(
                                      fontWeight:
                                          FontWeight
                                              .w600,
                                      color:
                                          AppColors
                                              .primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          AppSpacing.verticalMd,

                          // ==================================================
                          // حالة المستخدم
                          // ==================================================

                          SwitchListTile(
                            value:
                                active,
                            contentPadding:
                                EdgeInsets.zero,
                            title:
                                const Text(
                              'المستخدم فعال',
                              style:
                                  AppTextStyles
                                      .cardTitle,
                            ),
                            subtitle:
                                Text(
                              active
                                  ? 'يمكنه تسجيل الدخول إلى النظام'
                                  : 'لن يستطيع تسجيل الدخول',
                              style:
                                  AppTextStyles
                                      .bodySecondary,
                            ),
                            activeThumbColor:
                                AppColors
                                    .success,
                            onChanged:
                                loading
                                    ? null
                                    : (
                                        value,
                                      ) {
                                        setDialogState(
                                          () {
                                            active =
                                                value;
                                          },
                                        );
                                      },
                          ),

                          AppSpacing.verticalSm,

                          // ==================================================
                          // البريد الداخلي
                          // ==================================================

                          if (usernameController
                              .text
                              .trim()
                              .isNotEmpty)
                            AppCard(
                              color: AppColors
                                  .primary
                                  .withValues(
                                alpha: 0.05,
                              ),
                              padding:
                                  const EdgeInsets
                                      .all(
                                12,
                              ),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  const Icon(
                                    Icons
                                        .alternate_email,
                                    color:
                                        AppColors
                                            .primary,
                                  ),
                                  AppSpacingHorizontal
                                      .sm,
                                  Expanded(
                                    child:
                                        Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment
                                              .start,
                                      children: [
                                        const Text(
                                          'حساب Firebase الداخلي',
                                          style:
                                              AppTextStyles
                                                  .cardTitle,
                                        ),
                                        const SizedBox(
                                          height:
                                              4,
                                        ),
                                        Text(
                                          _buildAuthEmail(
                                            usernameController
                                                .text
                                                .trim(),
                                          ),
                                          style:
                                              AppTextStyles
                                                  .bodySecondary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  AppOutlinedButton(
                    text: 'إلغاء',
                    icon: Icons.close,
                    onPressed:
                        loading
                            ? null
                            : () {
                                Navigator.of(
                                  dialogContext,
                                ).pop();
                              },
                  ),
                  AppButton(
                    text: isEngineer
                        ? 'إنشاء المهندس'
                        : 'إنشاء المشرف',
                    icon:
                        Icons.person_add,
                    loading: loading,
                    onPressed:
                        loading
                            ? null
                            : () async {
                                if (!formKey
                                    .currentState!
                                    .validate()) {
                                  return;
                                }

                                if (selectedProjectIds
                                    .isEmpty) {
                                  AppWidgets
                                      .showWarning(
                                    context,
                                    'يجب اختيار مشروع واحد على الأقل',
                                  );
                                  return;
                                }

                                setDialogState(
                                  () {
                                    loading =
                                        true;
                                  },
                                );

                                try {
                                  final name =
                                      nameController
                                          .text
                                          .trim();

                                  final username =
                                      usernameController
                                          .text
                                          .trim();

                                  final password =
                                      passwordController
                                          .text;

                                  final authEmail =
                                      _buildAuthEmail(
                                    username,
                                  );

                                  // ==========================================
                                  // فحص التكرار
                                  // ==========================================

                                  final existingUser =
                                      await _firestore
                                          .collection(
                                            'users',
                                          )
                                          .where(
                                            'username',
                                            isEqualTo:
                                                username,
                                          )
                                          .limit(
                                            1,
                                          )
                                          .get();

                                  if (existingUser
                                      .docs
                                      .isNotEmpty) {
                                    throw Exception(
                                      'اسم المستخدم مستخدم بالفعل',
                                    );
                                  }

                                  // ==========================================
                                  // إنشاء Authentication
                                  // ==========================================

                                  final credential =
                                      await _createSecondaryAuthUser(
                                    email:
                                        authEmail,
                                    password:
                                        password,
                                  );

                                  final firebaseUser =
                                      credential
                                          .user;

                                  if (firebaseUser ==
                                      null) {
                                    throw Exception(
                                      'فشل إنشاء حساب المستخدم',
                                    );
                                  }

                                  // ==========================================
                                  // Firestore
                                  // ==========================================

                                  await _firestore
                                      .collection(
                                        'users',
                                      )
                                      .doc(
                                        firebaseUser
                                            .uid,
                                      )
                                      .set({
                                    'name':
                                        name,
                                    'username':
                                        username,
                                    'phone':
                                        username,
                                    'authEmail':
                                        authEmail,
                                    'role':
                                        role,
                                    'projectIds':
                                        selectedProjectIds,
                                    'projectNames':
                                        selectedProjectNames,
                                    'active':
                                        active,
                                    'mustChangePassword':
                                        true,
                                    'createdAt':
                                        FieldValue
                                            .serverTimestamp(),
                                    'createdBy':
                                        FirebaseAuth
                                            .instance
                                            .currentUser
                                            ?.uid,
                                  });

                                  if (!mounted) {
                                    return;
                                  }

                                  // مهم: لا نستدعي setDialogState بعد إغلاق الحوار.
                                  // تغيير loading مباشرة هنا ثم إغلاق الحوار يمنع
                                  // خطأ Flutter: Tried to build dirty widget in the wrong build scope.
                                  loading = false;

                                  Navigator.of(
                                    dialogContext,
                                  ).pop();

                                  AppWidgets
                                      .showSuccess(
                                    context,
                                    isEngineer
                                        ? 'تم إنشاء المهندس بنجاح'
                                        : 'تم إنشاء المشرف بنجاح',
                                  );
                                } on FirebaseAuthException catch (e) {
                                  String message =
                                      'حدث خطأ أثناء إنشاء حساب Firebase';

                                  if (e.code ==
                                      'email-already-in-use') {
                                    message =
                                        'اسم المستخدم موجود بالفعل في نظام الدخول';
                                  } else if (e.code ==
                                      'weak-password') {
                                    message =
                                        'كلمة المرور ضعيفة';
                                  } else if (e.code ==
                                      'invalid-email') {
                                    message =
                                        'بيانات حساب الدخول غير صحيحة';
                                  } else if (e.message !=
                                      null) {
                                    message =
                                        e.message!;
                                  }

                                  if (mounted) {
                                    setDialogState(() {
                                      loading = false;
                                    });

                                    AppWidgets
                                        .showError(
                                      context,
                                      message,
                                    );
                                  }
                                } catch (e) {
                                  // في حالة الخطأ يبقى الحوار مفتوحًا، لذلك هنا فقط
                                  // نستخدم setDialogState لإيقاف حالة التحميل.
                                  if (mounted) {
                                    setDialogState(() {
                                      loading = false;
                                    });

                                    AppWidgets
                                        .showError(
                                      context,
                                      'حدث خطأ:\n$e',
                                    );
                                  }
                                }
                              },
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    usernameController.dispose();
    passwordController.dispose();
  }

  // ============================================================
  // اختيار المشاريع
  // ============================================================

  Widget _buildProjectsSelector({
    required List<String> selectedProjectIds,
    required StateSetter setDialogState,
    required bool loading,
    required void Function(
      List<String> ids,
      List<String> names,
    ) onChanged,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _activeProjectsStream,
      builder: (
        context,
        snapshot,
      ) {
        if (snapshot.hasError) {
          return AppError(
            message:
                'تعذر تحميل المشاريع: ${snapshot.error}',
          );
        }

        if (snapshot.connectionState ==
                ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SizedBox(
            height: 100,
            child: AppLoading(
              message: 'جاري تحميل المشاريع...',
            ),
          );
        }

        final projects = List<
            QueryDocumentSnapshot<Map<String, dynamic>>>.from(
          snapshot.data?.docs ?? [],
        );

        // ترتيب محلي لتجنب Composite Index.
        projects.sort(
          (a, b) {
            final aName =
                a.data()['name']?.toString().trim().toLowerCase() ??
                    '';
            final bName =
                b.data()['name']?.toString().trim().toLowerCase() ??
                    '';
            return aName.compareTo(bName);
          },
        );

        if (projects.isEmpty) {
          return const AppEmpty(
            icon: Icons.business_outlined,
            title: 'لا توجد مشاريع',
            message: 'يجب إضافة مشروع فعال أولًا',
          );
        }

        return AppCard(
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 280,
            ),
            child: ListView.separated(
              key: const PageStorageKey<String>(
                'active-projects-selector',
              ),
              shrinkWrap: true,
              itemCount: projects.length,
              separatorBuilder: (
                context,
                index,
              ) {
                return const Divider(
                  height: 1,
                );
              },
              itemBuilder: (
                context,
                index,
              ) {
                final doc = projects[index];
                final data = doc.data();

                final projectName =
                    data['name']?.toString() ??
                        'بدون اسم';

                final code =
                    data['code']?.toString() ?? '';

                final isSelected =
                    selectedProjectIds.contains(doc.id);

                return CheckboxListTile(
                  key: ValueKey(
                    'project_${doc.id}',
                  ),
                  value: isSelected,
                  dense: true,
                  controlAffinity:
                      ListTileControlAffinity.leading,
                  activeColor: AppColors.primary,
                  title: Text(
                    projectName,
                    style: AppTextStyles.body,
                  ),
                  subtitle: code.isEmpty
                      ? null
                      : Text(
                          code,
                          style: AppTextStyles.small,
                        ),
                  onChanged: loading
                      ? null
                      : (checked) {
                          final ids =
                              List<String>.from(
                            selectedProjectIds,
                          );

                          if (checked == true) {
                            if (!ids.contains(doc.id)) {
                              ids.add(doc.id);
                            }
                          } else {
                            ids.remove(doc.id);
                          }

                          final names = projects
                              .where(
                                (project) =>
                                    ids.contains(project.id),
                              )
                              .map(
                                (project) =>
                                    project.data()['name']
                                        ?.toString() ??
                                    'بدون اسم',
                              )
                              .toList();

                          // تحديث حالة الحوار فقط.
                          // لا يوجد Navigator.pop هنا.
                          setDialogState(
                            () {
                              onChanged(
                                ids,
                                names,
                              );
                            },
                          );
                        },
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // تغيير حالة المستخدم
  // ============================================================

  Future<void> _toggleUserStatus(
    DocumentSnapshot<Map<String, dynamic>>
        doc,
  ) async {
    final data = doc.data();

    if (data == null) {
      return;
    }

    final currentActive =
        data['active'] == true;

    final confirmed =
        await AppWidgets.showConfirmDialog(
      context: context,
      title: currentActive
          ? 'تعطيل المستخدم'
          : 'تفعيل المستخدم',
      message: currentActive
          ? 'هل تريد تعطيل المستخدم "${data['name'] ?? ''}"؟'
          : 'هل تريد تفعيل المستخدم "${data['name'] ?? ''}"؟',
      confirmText:
          currentActive
              ? 'تعطيل'
              : 'تفعيل',
      danger: currentActive,
    );

    if (!confirmed) {
      return;
    }

    try {
      await _firestore
          .collection('users')
          .doc(doc.id)
          .update({
        'active': !currentActive,
        'updatedAt':
            FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      AppWidgets.showSuccess(
        context,
        currentActive
            ? 'تم تعطيل المستخدم'
            : 'تم تفعيل المستخدم',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء تحديث حالة المستخدم',
      );
    }
  }

  // ============================================================
  // حذف بيانات المستخدم
  // ============================================================

  Future<void> _deleteUserDocument(
    DocumentSnapshot<Map<String, dynamic>>
        doc,
  ) async {
    final data = doc.data();

    if (data == null) {
      return;
    }

    final confirmed =
        await AppWidgets.showConfirmDialog(
      context: context,
      title:
          'حذف بيانات المستخدم',
      message:
          'هل تريد حذف بيانات المستخدم "${data['name'] ?? ''}" من Firestore؟\n\n'
          'تنبيه: هذا الإجراء لا يحذف حساب Firebase Authentication.',
      confirmText:
          'حذف',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await _firestore
          .collection('users')
          .doc(doc.id)
          .delete();

      if (!mounted) {
        return;
      }

      AppWidgets.showSuccess(
        context,
        'تم حذف بيانات المستخدم',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء حذف بيانات المستخدم',
      );
    }
  }

  // ============================================================
  // فلترة المستخدمين
  // ============================================================

  List<QueryDocumentSnapshot<Map<String, dynamic>>>
      _filterUsers(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>
        users,
  ) {
    if (_searchText.isEmpty) {
      return users;
    }

    return users.where(
      (doc) {
        final data = doc.data();

        final name =
            data['name']
                    ?.toString()
                    .toLowerCase() ??
                '';

        final username =
            data['username']
                    ?.toString()
                    .toLowerCase() ??
                '';

        final phone =
            data['phone']
                    ?.toString()
                    .toLowerCase() ??
                '';

        final projectNames =
            (data['projectNames'] as List?)
                    ?.map(
                      (e) => e
                          .toString()
                          .toLowerCase(),
                    )
                    .join(' ') ??
                '';

        return name.contains(
              _searchText,
            ) ||
            username.contains(
              _searchText,
            ) ||
            phone.contains(
              _searchText,
            ) ||
            projectNames.contains(
              _searchText,
            );
      },
    ).toList();
  }

  // ============================================================
  // قائمة المستخدمين
  // ============================================================

  Widget _buildUsersList({
    required String role,
  }) {
    return StreamBuilder<
        QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('users')
          .where(
            'role',
            isEqualTo: role,
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
                'جاري تحميل المستخدمين...',
          );
        }

        if (snapshot.hasError) {
          return const AppError(
            message:
                'حدث خطأ أثناء تحميل المستخدمين',
          );
        }

        final users =
            _filterUsers(
          snapshot.data?.docs ?? [],
        );

        if (users.isEmpty) {
          return _EmptyUsersView(
            role: role,
            hasSearch:
                _searchText.isNotEmpty,
            onAdd: () {
              _showAddUserDialog(
                role: role,
              );
            },
          );
        }

        return ListView.separated(
          padding:
              const EdgeInsets.only(
            bottom: 100,
          ),
          physics:
              const AlwaysScrollableScrollPhysics(),
          itemCount:
              users.length,
          separatorBuilder:
              (
            context,
            index,
          ) {
            return AppSpacing
                .verticalSm;
          },
          itemBuilder:
              (
            context,
            index,
          ) {
            final doc =
                users[index];

            return _UserCard(
              doc: doc,
              role: role,
              onToggleStatus:
                  () {
                _toggleUserStatus(
                  doc,
                );
              },
              onDelete: () {
                _deleteUserDocument(
                  doc,
                );
              },
            );
          },
        );
      },
    );
  }

  // ============================================================
  // زر إضافة المستخدم
  // ============================================================

  void _addCurrentUser() {
    _showAddUserDialog(
      role: _currentRole,
    );
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return AppScaffold(
      title: 'المستخدمون',

      // ==========================================================
      // زر الإضافة في AppBar
      // ==========================================================

      actions: [
        IconButton(
          tooltip:
              _currentIsEngineer
                  ? 'إضافة مهندس'
                  : 'إضافة مشرف',
          onPressed:
              _addCurrentUser,
          icon: const Icon(
            Icons.person_add,
          ),
        ),
      ],

      // ==========================================================
      // زر الإضافة السفلي
      // ==========================================================

      floatingActionButton:
          AnimatedBuilder(
        animation:
            _tabController,
        builder:
            (
          context,
          child,
        ) {
          final isEngineer =
              _tabController.index ==
                  0;

          return FloatingActionButton.extended(
            heroTag:
                'users_add_fab',
            onPressed:
                _addCurrentUser,
            icon: const Icon(
              Icons.person_add,
            ),
            label: Text(
              isEngineer
                  ? 'إضافة مهندس'
                  : 'إضافة مشرف',
            ),
          );
        },
      ),

      // ==========================================================
      // مهم:
      // AppPage هنا غير قابلة للتمرير لأن لدينا Expanded.
      // ==========================================================

      child: AppPage(
        scrollable: false,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            // ======================================================
            // رأس الصفحة
            // ======================================================

            AppPageHeader(
              title:
                  'إدارة المستخدمين',
              subtitle:
                  'إدارة المهندسين والمشرفين وحسابات الدخول',
              icon:
                  Icons.people,
            ),

            AppSpacing.verticalMd,

            // ======================================================
            // البحث
            // ======================================================

            AppTextField(
              controller:
                  _searchController,
              label:
                  'البحث',
              hint:
                  'ابحث بالاسم أو اسم المستخدم أو المشروع...',
              prefixIcon:
                  Icons.search,
            ),

            AppSpacing.verticalMd,

            // ======================================================
            // التبويبات
            // ======================================================

            AppCard(
              padding:
                  EdgeInsets.zero,
              child: TabBar(
                controller:
                    _tabController,
                labelColor:
                    AppColors.primary,
                unselectedLabelColor:
                    AppColors
                        .textSecondary,
                indicatorColor:
                    AppColors.primary,
                indicatorSize:
                    TabBarIndicatorSize
                        .tab,
                tabs: const [
                  Tab(
                    icon: Icon(
                      Icons.engineering,
                    ),
                    text:
                        'المهندسون',
                  ),
                  Tab(
                    icon: Icon(
                      Icons.supervisor_account,
                    ),
                    text:
                        'المشرفون',
                  ),
                ],
              ),
            ),

            AppSpacing.verticalMd,

            // ======================================================
            // القوائم
            // ======================================================

            Expanded(
              child: TabBarView(
                controller:
                    _tabController,
                children: [
                  _buildUsersList(
                    role:
                        'engineer',
                  ),
                  _buildUsersList(
                    role:
                        'supervisor',
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

// ==================================================================
// بطاقة المستخدم
// ==================================================================

class _UserCard extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>>
      doc;

  final String role;

  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  const _UserCard({
    required this.doc,
    required this.role,
    required this.onToggleStatus,
    required this.onDelete,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final data =
        doc.data() ?? {};

    final name =
        data['name']
                ?.toString() ??
            'بدون اسم';

    final username =
        data['username']
                ?.toString() ??
            '-';

    final phone =
        data['phone']
                ?.toString() ??
            '-';

    final authEmail =
        data['authEmail']
                ?.toString() ??
            '-';

    final active =
        data['active'] == true;

    final projectNames =
        (data['projectNames'] as List?)
                ?.map(
                  (e) => e.toString(),
                )
                .toList() ??
            [];

    final isEngineer =
        role == 'engineer';

    final roleColor =
        isEngineer
            ? AppColors.engineer
            : AppColors.supervisor;

    return AppCard(
      padding:
          const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          // ========================================================
          // الأيقونة
          // ========================================================

          Container(
            width: 54,
            height: 54,
            decoration:
                BoxDecoration(
              color:
                  roleColor.withValues(
                alpha: 0.10,
              ),
              borderRadius:
                  BorderRadius.circular(
                14,
              ),
            ),
            child: Icon(
              isEngineer
                  ? Icons.engineering
                  : Icons.supervisor_account,
              color:
                  roleColor,
              size: 28,
            ),
          ),

          AppSpacingHorizontal.md,

          // ========================================================
          // البيانات
          // ========================================================

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style:
                            AppTextStyles
                                .cardTitle,
                      ),
                    ),
                    AppStatusBadge(
                      text: active
                          ? 'فعال'
                          : 'معطل',
                      color: active
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                  ],
                ),

                AppSpacing
                    .verticalSm,

                AppInfoRow(
                  icon:
                      Icons.person_outline,
                  label:
                      'اسم المستخدم',
                  value:
                      username,
                ),

                AppSpacing
                    .verticalXs,

                AppInfoRow(
                  icon:
                      Icons.phone,
                  label:
                      'الهاتف',
                  value:
                      phone,
                ),

                AppSpacing
                    .verticalSm,

                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    const Icon(
                      Icons.business,
                      size: 18,
                      color: AppColors
                          .textSecondary,
                    ),
                    AppSpacingHorizontal
                        .sm,
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          const Text(
                            'المشاريع',
                            style:
                                AppTextStyles
                                    .small,
                          ),
                          const SizedBox(
                            height: 5,
                          ),
                          if (projectNames
                              .isEmpty)
                            const Text(
                              'لا توجد مشاريع مرتبطة',
                              style:
                                  AppTextStyles
                                      .bodySecondary,
                            )
                          else
                            Wrap(
                              spacing: 6,
                              runSpacing:
                                  6,
                              children:
                                  projectNames
                                      .map(
                                (
                                  projectName,
                                ) {
                                  return AppStatusBadge(
                                    text:
                                        projectName,
                                    color:
                                        AppColors
                                            .primary,
                                  );
                                },
                              ).toList(),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                AppSpacing
                    .verticalSm,

                Text(
                  authEmail,
                  style:
                      AppTextStyles
                          .small,
                ),
              ],
            ),
          ),

          // ========================================================
          // القائمة
          // ========================================================

          PopupMenuButton<String>(
            tooltip:
                'خيارات المستخدم',
            onSelected:
                (
              value,
            ) {
              if (value ==
                  'toggle') {
                onToggleStatus();
              } else if (value ==
                  'delete') {
                onDelete();
              }
            },
            itemBuilder:
                (
              context,
            ) {
              return [
                PopupMenuItem<String>(
                  value:
                      'toggle',
                  child: Row(
                    children: [
                      Icon(
                        active
                            ? Icons.block
                            : Icons
                                .check_circle,
                        color: active
                            ? AppColors
                                .danger
                            : AppColors
                                .success,
                      ),
                      AppSpacingHorizontal
                          .sm,
                      Text(
                        active
                            ? 'تعطيل المستخدم'
                            : 'تفعيل المستخدم',
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value:
                      'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons
                            .delete_outline,
                        color:
                            AppColors
                                .danger,
                      ),
                      SizedBox(
                        width: 10,
                      ),
                      Text(
                        'حذف بيانات Firestore',
                        style:
                            TextStyle(
                          color:
                              AppColors
                                  .danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }
}

// ==================================================================
// لا يوجد مستخدمون
// ==================================================================

class _EmptyUsersView
    extends StatelessWidget {
  final String role;
  final bool hasSearch;
  final VoidCallback onAdd;

  const _EmptyUsersView({
    required this.role,
    required this.hasSearch,
    required this.onAdd,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final isEngineer =
        role == 'engineer';

    return Center(
      child: SingleChildScrollView(
        padding:
            const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              hasSearch
                  ? Icons.search_off
                  : isEngineer
                      ? Icons.engineering
                      : Icons.supervisor_account,
              size: 80,
              color:
                  AppColors.textLight,
            ),

            AppSpacing.verticalLg,

            Text(
              hasSearch
                  ? 'لا توجد نتائج'
                  : isEngineer
                      ? 'لا يوجد مهندسون'
                      : 'لا يوجد مشرفون',
              style:
                  AppTextStyles
                      .sectionTitle,
              textAlign:
                  TextAlign.center,
            ),

            AppSpacing.verticalSm,

            Text(
              hasSearch
                  ? 'لم يتم العثور على مستخدم مطابق للبحث'
                  : isEngineer
                      ? 'يمكنك إضافة أول مهندس من الزر أدناه'
                      : 'يمكنك إضافة أول مشرف بنود من الزر أدناه',
              style:
                  AppTextStyles
                      .bodySecondary,
              textAlign:
                  TextAlign.center,
            ),

            if (!hasSearch) ...[
              AppSpacing.verticalLg,
              AppButton(
                text:
                    isEngineer
                        ? 'إضافة مهندس'
                        : 'إضافة مشرف',
                icon:
                    Icons.person_add,
                onPressed:
                    onAdd,
              ),
            ],
          ],
        ),
      ),
    );
  }
}


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

import 'districts_page.dart';

// =============================================================
// صفحة المحافظات
// =============================================================

class GovernoratesPage extends StatefulWidget {
  const GovernoratesPage({
    super.key,
  });

  @override
  State<GovernoratesPage> createState() =>
      _GovernoratesPageState();
}

class _GovernoratesPageState extends State<GovernoratesPage> {
  // ============================================================
  // Firestore
  // ============================================================

  final FirebaseFirestore firestore =
      FirebaseFirestore.instance;

  final CollectionReference<Map<String, dynamic>> governorates =
      FirebaseFirestore.instance.collection('governorates');

  // ============================================================
  // البحث
  // ============================================================

  final TextEditingController _searchController =
      TextEditingController();

  String _searchText = '';

  // ============================================================
  // Dispose
  // ============================================================

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // إضافة محافظة
  // ============================================================

  Future<void> _addGovernorate() async {
    final TextEditingController controller =
        TextEditingController();

    final formKey = GlobalKey<FormState>();

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text(
              'إضافة محافظة',
            ),
            content: SizedBox(
              width: 450,
              child: Form(
                key: formKey,
                child: TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'اسم المحافظة',
                    hintText: 'مثال: إب',
                    prefixIcon: Icon(
                      Icons.location_city_outlined,
                    ),
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'يرجى إدخال اسم المحافظة';
                    }

                    return null;
                  },
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    false,
                  );
                },
                child: const Text(
                  'إلغاء',
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) {
                    return;
                  }

                  final String name =
                      controller.text.trim();

                  try {
                    // ==========================================
                    // التأكد من عدم التكرار
                    // ==========================================

                    final existing =
                        await governorates
                            .where(
                              'name',
                              isEqualTo: name,
                            )
                            .limit(1)
                            .get();

                    if (existing.docs.isNotEmpty) {
                      if (!mounted) {
                        return;
                      }

                      AppWidgets.showWarning(
                        context,
                        'هذه المحافظة موجودة بالفعل',
                      );

                      return;
                    }

                    // ==========================================
                    // الإضافة
                    // ==========================================

                    await governorates.add({
                      'name': name,
                      'active': true,
                      'createdAt':
                          FieldValue.serverTimestamp(),
                      'updatedAt':
                          FieldValue.serverTimestamp(),
                    });

                    if (!mounted) {
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      true,
                    );
                  } catch (e) {
                    if (!mounted) {
                      return;
                    }

                    AppWidgets.showError(
                      context,
                      'حدث خطأ أثناء إضافة المحافظة: $e',
                    );
                  }
                },
                icon: const Icon(
                  Icons.add,
                ),
                label: const Text(
                  'إضافة',
                ),
              ),
            ],
          ),
        );
      },
    );

    controller.dispose();

    if (result == true && mounted) {
      AppWidgets.showSuccess(
        context,
        'تمت إضافة المحافظة بنجاح',
      );
    }
  }

  // ============================================================
  // تعديل المحافظة
  // ============================================================

  Future<void> _editGovernorate(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? {};

    final TextEditingController controller =
        TextEditingController(
      text: data['name']?.toString() ?? '',
    );

    final formKey = GlobalKey<FormState>();

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text(
              'تعديل المحافظة',
            ),
            content: SizedBox(
              width: 450,
              child: Form(
                key: formKey,
                child: TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'اسم المحافظة',
                    prefixIcon: Icon(
                      Icons.location_city_outlined,
                    ),
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'يرجى إدخال اسم المحافظة';
                    }

                    return null;
                  },
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    false,
                  );
                },
                child: const Text(
                  'إلغاء',
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) {
                    return;
                  }

                  final String name =
                      controller.text.trim();

                  try {
                    // ==========================================
                    // منع التكرار
                    // ==========================================

                    final existing =
                        await governorates
                            .where(
                              'name',
                              isEqualTo: name,
                            )
                            .limit(2)
                            .get();

                    final bool duplicate =
                        existing.docs.any(
                      (item) => item.id != doc.id,
                    );

                    if (duplicate) {
                      if (!mounted) {
                        return;
                      }

                      AppWidgets.showWarning(
                        context,
                        'هذه المحافظة موجودة بالفعل',
                      );

                      return;
                    }

                    // ==========================================
                    // التعديل
                    // ==========================================

                    await governorates.doc(doc.id).update({
                      'name': name,
                      'updatedAt':
                          FieldValue.serverTimestamp(),
                    });

                    if (!mounted) {
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      true,
                    );
                  } catch (e) {
                    if (!mounted) {
                      return;
                    }

                    AppWidgets.showError(
                      context,
                      'حدث خطأ أثناء تعديل المحافظة: $e',
                    );
                  }
                },
                icon: const Icon(
                  Icons.save_outlined,
                ),
                label: const Text(
                  'حفظ',
                ),
              ),
            ],
          ),
        );
      },
    );

    controller.dispose();

    if (result == true && mounted) {
      AppWidgets.showSuccess(
        context,
        'تم تعديل المحافظة بنجاح',
      );
    }
  }

  // ============================================================
  // تفعيل / تعطيل المحافظة
  // ============================================================

  Future<void> _toggleGovernorate(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? {};

    final bool active = data['active'] != false;

    final String name =
        data['name']?.toString() ?? 'هذه المحافظة';

    final bool confirmed =
        await AppWidgets.showConfirmDialog(
      context: context,
      title: active
          ? 'تعطيل المحافظة'
          : 'تفعيل المحافظة',
      message: active
          ? 'هل تريد تعطيل "$name"؟'
          : 'هل تريد تفعيل "$name"؟',
      confirmText: active
          ? 'تعطيل'
          : 'تفعيل',
      cancelText: 'إلغاء',
      danger: active,
    );

    if (!confirmed) {
      return;
    }

    try {
      await governorates.doc(doc.id).update({
        'active': !active,
        'updatedAt':
            FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      AppWidgets.showSuccess(
        context,
        active
            ? 'تم تعطيل المحافظة'
            : 'تم تفعيل المحافظة',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء تغيير حالة المحافظة: $e',
      );
    }
  }

  // ============================================================
  // حذف المحافظة
  // ============================================================

  Future<void> _deleteGovernorate(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? {};

    final String name =
        data['name']?.toString() ?? 'هذه المحافظة';

    final bool confirmed =
        await AppWidgets.showConfirmDialog(
      context: context,
      title: 'حذف المحافظة',
      message:
          'هل أنت متأكد من حذف "$name"؟\n\n'
          'سيتم حذف المحافظة نهائياً.',
      confirmText: 'حذف',
      cancelText: 'إلغاء',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await governorates.doc(doc.id).delete();

      if (!mounted) {
        return;
      }

      AppWidgets.showSuccess(
        context,
        'تم حذف المحافظة بنجاح',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء حذف المحافظة: $e',
      );
    }
  }

  // ============================================================
  // فتح المديريات
  // ============================================================

  void _openDistricts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const DistrictsPage(),
      ),
    );
  }

  // ============================================================
  // البحث
  // ============================================================

  List<QueryDocumentSnapshot<Map<String, dynamic>>>
      _filterGovernorates(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final String search =
        _searchText.trim().toLowerCase();

    if (search.isEmpty) {
      return docs;
    }

    return docs.where(
      (doc) {
        final data = doc.data();

        final String name =
            data['name']
                    ?.toString()
                    .toLowerCase() ??
                '';

        return name.contains(search);
      },
    ).toList();
  }

  // ============================================================
  // عدد المحافظات النشطة
  // ============================================================

  int _countActive(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs
        .where(
          (doc) => doc.data()['active'] != false,
        )
        .length;
  }

  // ============================================================
  // عدد المحافظات غير النشطة
  // ============================================================

  int _countInactive(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs
        .where(
          (doc) => doc.data()['active'] == false,
        )
        .length;
  }

  // ============================================================
  // Drawer
  // ============================================================

  Widget _buildDrawer() {
    return AppDrawer(
      userName: 'مدير النظام',
      roleName: 'مدير النظام',
      projectName: 'إدارة المحافظات',
      items: [
        // ========================================================
        // الرئيسية
        // ========================================================

        AppDrawerItem(
          title: 'الرئيسية',
          icon: Icons.dashboard_outlined,
          selected: false,
          onTap: () {
            Navigator.pop(context);
            Navigator.pop(context);
          },
        ),

        // ========================================================
        // المحافظات
        // ========================================================

        AppDrawerItem(
          title: 'المحافظات',
          icon: Icons.location_city_outlined,
          selected: true,
          onTap: () {
            Navigator.pop(context);
          },
        ),

        // ========================================================
        // المديريات
        // ========================================================

        AppDrawerItem(
          title: 'المديريات',
          icon: Icons.location_on_outlined,
          selected: false,
          onTap: () {
            Navigator.pop(context);
            _openDistricts();
          },
        ),
      ],
      onLogout: () async {
        await FirebaseAuth.instance.signOut();

        if (!mounted) {
          return;
        }

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const _LoggedOutPage(),
          ),
          (route) => false,
        );
      },
    );
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إدارة المحافظات',
      drawer: _buildDrawer(),
      actions: [
        // ========================================================
        // تحديث
        // ========================================================

        IconButton(
          tooltip: 'تحديث',
          icon: const Icon(
            Icons.refresh_outlined,
          ),
          onPressed: () {
            setState(() {});
          },
        ),

        // ========================================================
        // إضافة
        // ========================================================

        IconButton(
          tooltip: 'إضافة محافظة',
          icon: const Icon(
            Icons.add_location_alt_outlined,
          ),
          onPressed: _addGovernorate,
        ),

        const SizedBox(
          width: 8,
        ),
      ],
      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: _addGovernorate,
        icon: const Icon(
          Icons.add,
        ),
        label: const Text(
          'إضافة محافظة',
        ),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: StreamBuilder<
            QuerySnapshot<Map<String, dynamic>>>(
          stream: governorates
              .orderBy('name')
              .snapshots(),
          builder: (
            context,
            snapshot,
          ) {
            // ==================================================
            // تحميل
            // ==================================================

            if (snapshot.connectionState ==
                ConnectionState.waiting) {
              return AppPage(
                child: AppLoading(
                  message:
                      'جاري تحميل المحافظات...',
                ),
              );
            }

            // ==================================================
            // خطأ
            // ==================================================

            if (snapshot.hasError) {
              return AppPage(
                child: AppError(
                  message:
                      'حدث خطأ أثناء تحميل المحافظات',
                  onRetry: () {
                    setState(() {});
                  },
                ),
              );
            }

            // ==================================================
            // البيانات
            // ==================================================

            final allDocs =
                snapshot.data?.docs ?? [];

            final docs =
                _filterGovernorates(allDocs);

            // ==================================================
            // الصفحة
            // ==================================================

            return AppPage(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  // ==================================================
                  // رأس الصفحة
                  // ==================================================

                  AppPageHeader(
                    title: 'إدارة المحافظات',
                    subtitle:
                        'إضافة وتعديل وتنشيط وتعطيل وحذف المحافظات.',
                    icon:
                        Icons.location_city_outlined,
                    trailing: AppButton(
                      text: 'إضافة محافظة',
                      icon: Icons.add,
                      onPressed: _addGovernorate,
                    ),
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
                        'ابحث باسم المحافظة',
                    prefixIcon: Icons.search,
                    onChanged: (value) {
                      setState(() {
                        _searchText = value;
                      });
                    },
                  ),

                  AppSpacing.verticalLg,

                  // ==================================================
                  // الإحصائيات
                  // ==================================================

                  AppSectionTitle(
                    title: 'نظرة عامة',
                    icon:
                        Icons.analytics_outlined,
                  ),

                  AppSpacing.verticalMd,

                  AppResponsiveGrid(
                    minItemWidth: 220,
                    spacing: 16,
                    children: [
                      // ================================================
                      // إجمالي المحافظات
                      // ================================================

                      AppStatCard(
                        title:
                            'إجمالي المحافظات',
                        value:
                            '${allDocs.length}',
                        icon: Icons
                            .location_city_outlined,
                        color:
                            AppColors.primary,
                      ),

                      // ================================================
                      // النشطة
                      // ================================================

                      AppStatCard(
                        title:
                            'المحافظات النشطة',
                        value:
                            '${_countActive(allDocs)}',
                        icon: Icons
                            .check_circle_outline,
                        color:
                            AppColors.success,
                      ),

                      // ================================================
                      // غير النشطة
                      // ================================================

                      AppStatCard(
                        title: 'غير النشطة',
                        value:
                            '${_countInactive(allDocs)}',
                        icon: Icons
                            .cancel_outlined,
                        color:
                            AppColors.danger,
                      ),
                    ],
                  ),

                  AppSpacing.verticalXl,

                  // ==================================================
                  // قائمة المحافظات
                  // ==================================================

                  AppSectionTitle(
                    title:
                        'قائمة المحافظات',
                    icon:
                        Icons.list_alt_outlined,
                    trailing: Text(
                      '${docs.length} محافظة',
                      style:
                          AppTextStyles
                              .bodySecondary,
                    ),
                  ),

                  AppSpacing.verticalMd,

                  // ==================================================
                  // لا توجد بيانات
                  // ==================================================

                  if (docs.isEmpty)
                    AppEmpty(
                      message:
                          _searchText.isEmpty
                              ? 'لا توجد محافظات مضافة حتى الآن'
                              : 'لا توجد نتائج مطابقة للبحث',
                      icon: Icons
                          .location_off_outlined,
                    )

                  // ==================================================
                  // القائمة
                  // ==================================================

                  else
                    ...docs.map(
                      (doc) {
                        return _GovernorateCard(
                          data: doc.data(),
                          onEdit: () =>
                              _editGovernorate(
                            doc,
                          ),
                          onToggle: () =>
                              _toggleGovernorate(
                            doc,
                          ),
                          onDelete: () =>
                              _deleteGovernorate(
                            doc,
                          ),
                        );
                      },
                    ),

                  AppSpacing.verticalXl,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// =============================================================
// بطاقة المحافظة
// =============================================================

class _GovernorateCard extends StatelessWidget {
  final Map<String, dynamic> data;

  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _GovernorateCard({
    required this.data,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final String name =
        data['name']?.toString() ?? 'بدون اسم';

    final bool active =
        data['active'] != false;

    return AppCard(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            // ========================================================
            // الأيقونة
            // ========================================================

            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.info.withValues(
                  alpha: 0.10,
                ),
                borderRadius:
                    BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.location_city_outlined,
                color: AppColors.info,
                size: 28,
              ),
            ),

            const SizedBox(
              width: 14,
            ),

            // ========================================================
            // بيانات المحافظة
            // ========================================================

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style:
                        AppTextStyles.cardTitle,
                  ),

                  const SizedBox(
                    height: 7,
                  ),

                  AppStatusBadge(
                    text: active
                        ? 'نشطة'
                        : 'غير نشطة',
                    color: active
                        ? AppColors.success
                        : AppColors.danger,
                  ),
                ],
              ),
            ),

            const SizedBox(
              width: 8,
            ),

            // ========================================================
            // الإجراءات
            // ========================================================

            PopupMenuButton<String>(
              tooltip: 'إجراءات',
              onSelected: (value) {
                if (value == 'edit') {
                  onEdit();
                } else if (value == 'toggle') {
                  onToggle();
                } else if (value == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (context) => [
                // ==============================================
                // تعديل
                // ==============================================

                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_outlined,
                      ),
                      SizedBox(
                        width: 10,
                      ),
                      Text(
                        'تعديل',
                      ),
                    ],
                  ),
                ),

                // ==============================================
                // تفعيل / تعطيل
                // ==============================================

                PopupMenuItem<String>(
                  value: 'toggle',
                  child: Row(
                    children: [
                      Icon(
                        active
                            ? Icons.block_outlined
                            : Icons
                                .check_circle_outline,
                        color: active
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      Text(
                        active
                            ? 'تعطيل'
                            : 'تفعيل',
                      ),
                    ],
                  ),
                ),

                // ==============================================
                // حذف
                // ==============================================

                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        color: AppColors.danger,
                      ),
                      SizedBox(
                        width: 10,
                      ),
                      Text(
                        'حذف',
                        style: TextStyle(
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              child: const Icon(
                Icons.more_vert,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// صفحة تسجيل الخروج المؤقتة
// =============================================================

class _LoggedOutPage extends StatelessWidget {
  const _LoggedOutPage();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: AppCard(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.logout_outlined,
                  size: 60,
                  color: AppColors.primary,
                ),

                const SizedBox(
                  height: 20,
                ),

                const Text(
                  'تم تسجيل الخروج',
                  style: AppTextStyles.pageTitle,
                ),

                const SizedBox(
                  height: 10,
                ),

                const Text(
                  'يمكنك تسجيل الدخول مرة أخرى',
                  style:
                      AppTextStyles.bodySecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
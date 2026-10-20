
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

import 'material_types_page.dart';

// =============================================================
// صفحة المواد
// =============================================================

class MaterialPage extends StatefulWidget {
  const MaterialPage({
    super.key,
  });

  @override
  State<MaterialPage> createState() => _MaterialPageState();
}

class _MaterialPageState extends State<MaterialPage> {
  // ============================================================
  // Firestore
  // ============================================================

  final FirebaseFirestore firestore =
      FirebaseFirestore.instance;

  final CollectionReference<Map<String, dynamic>> materials =
      FirebaseFirestore.instance.collection('materials');

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
  // فتح أنواع المادة
  // ============================================================

  Future<void> openMaterialTypes(
    String materialId,
    String materialName,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialTypesPage(
          materialId: materialId,
          materialName: materialName,
        ),
      ),
    );
  }

  // ============================================================
  // إضافة / تعديل مادة
  // ============================================================

  Future<void> showMaterialDialog({
    DocumentSnapshot<Map<String, dynamic>>? doc,
  }) async {
    final controller = TextEditingController(
      text: doc?.data()?['name']?.toString() ?? '',
    );

    final formKey = GlobalKey<FormState>();

    final bool isEditing = doc != null;

    // ==========================================================
    // بيانات المادة الجديدة
    // ==========================================================

    String? createdMaterialId;
    String? createdMaterialName;

    // ==========================================================
    // فتح نافذة الإضافة / التعديل
    // ==========================================================

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(
              isEditing ? 'تعديل المادة' : 'إضافة مادة',
              style: AppTextStyles.sectionTitle,
            ),

            content: SizedBox(
              width: 450,
              child: Form(
                key: formKey,
                child: TextFormField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'اسم المادة',
                    hintText: 'مثال: وقود',
                    prefixIcon: Icon(
                      Icons.inventory_2_outlined,
                    ),
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'أدخل اسم المادة';
                    }

                    return null;
                  },
                ),
              ),
            ),

            actions: [
              // ==================================================
              // إلغاء
              // ==================================================

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

              // ==================================================
              // إضافة / حفظ
              // ==================================================

              ElevatedButton.icon(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) {
                    return;
                  }

                  final String name =
                      controller.text.trim();

                  try {
                    // ==================================================
                    // منع التكرار
                    // ==================================================

                    final duplicateSnapshot =
                        await materials
                            .where(
                              'name',
                              isEqualTo: name,
                            )
                            .get();

                    final bool duplicate =
                        duplicateSnapshot.docs.any(
                      (item) => item.id != doc?.id,
                    );

                    if (duplicate) {
                      if (!dialogContext.mounted) {
                        return;
                      }

                      AppWidgets.showWarning(
                        dialogContext,
                        'هذه المادة موجودة مسبقاً',
                      );

                      return;
                    }

                    // ==================================================
                    // إضافة مادة جديدة
                    // ==================================================

                    if (!isEditing) {
                      final DocumentReference<
                          Map<String, dynamic>> newDoc =
                          await materials.add({
                        'name': name,
                        'active': true,
                        'createdAt':
                            FieldValue.serverTimestamp(),
                        'updatedAt':
                            FieldValue.serverTimestamp(),
                      });

                      // حفظ بيانات المادة الجديدة
                      createdMaterialId = newDoc.id;
                      createdMaterialName = name;

                      if (!dialogContext.mounted) {
                        return;
                      }

                      Navigator.pop(
                        dialogContext,
                        true,
                      );

                      return;
                    }

                    // ==================================================
                    // تعديل المادة
                    // ==================================================

                    await doc!.reference.update({
                      'name': name,
                      'updatedAt':
                          FieldValue.serverTimestamp(),
                    });

                    if (!dialogContext.mounted) {
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      true,
                    );
                  } catch (e) {
                    if (!dialogContext.mounted) {
                      return;
                    }

                    AppWidgets.showError(
                      dialogContext,
                      'حدث خطأ: $e',
                    );
                  }
                },
                icon: const Icon(
                  Icons.save_outlined,
                ),
                label: Text(
                  isEditing ? 'حفظ' : 'إضافة',
                ),
              ),
            ],
          ),
        );
      },
    );

    // ==========================================================
    // التخلص من Controller
    // ==========================================================

    controller.dispose();

    // ==========================================================
    // إلغاء أو فشل العملية
    // ==========================================================

    if (!mounted || result != true) {
      return;
    }

    // ==========================================================
    // إضافة مادة جديدة
    // ==========================================================

    if (!isEditing &&
        createdMaterialId != null &&
        createdMaterialName != null) {
      AppWidgets.showSuccess(
        context,
        'تمت إضافة المادة بنجاح',
      );

      // ========================================================
      // فتح صفحة إضافة نوع المادة مباشرة
      // ========================================================

      await openMaterialTypes(
        createdMaterialId!,
        createdMaterialName!,
      );

      return;
    }

    // ==========================================================
    // تعديل مادة موجودة
    // ==========================================================

    if (isEditing) {
      AppWidgets.showSuccess(
        context,
        'تم تعديل المادة بنجاح',
      );
    }
  }

  // ============================================================
  // تفعيل / تعطيل المادة
  // ============================================================

  Future<void> toggleMaterial(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();

    if (data == null) {
      return;
    }

    final bool isActive =
        data['active'] != false;

    final String name =
        data['name']?.toString() ?? 'هذه المادة';

    // ==========================================================
    // تأكيد التعطيل
    // ==========================================================

    if (isActive) {
      final bool confirmed =
          await AppWidgets.showConfirmDialog(
        context: context,
        title: 'تعطيل المادة',
        message:
            'هل تريد تعطيل المادة "$name"؟',
        confirmText: 'تعطيل',
        cancelText: 'إلغاء',
        danger: true,
      );

      if (!confirmed) {
        return;
      }
    }

    // ==========================================================
    // تحديث الحالة
    // ==========================================================

    try {
      await doc.reference.update({
        'active': !isActive,
        'updatedAt':
            FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      AppWidgets.showSuccess(
        context,
        isActive
            ? 'تم تعطيل المادة'
            : 'تم تفعيل المادة',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء تغيير حالة المادة: $e',
      );
    }
  }

  // ============================================================
  // حذف المادة
  // ============================================================

  Future<void> deleteMaterial(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();

    if (data == null) {
      return;
    }

    final String name =
        data['name']?.toString() ?? 'هذه المادة';

    // ==========================================================
    // تأكيد الحذف
    // ==========================================================

    final bool confirmed =
        await AppWidgets.showConfirmDialog(
      context: context,
      title: 'حذف المادة',
      message:
          'هل أنت متأكد من حذف "$name"؟\n\n'
          'سيتم حذف المادة نهائياً.',
      confirmText: 'حذف',
      cancelText: 'إلغاء',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    // ==========================================================
    // الحذف
    // ==========================================================

    try {
      await doc.reference.delete();

      if (!mounted) {
        return;
      }

      AppWidgets.showSuccess(
        context,
        'تم حذف المادة بنجاح',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء حذف المادة: $e',
      );
    }
  }

  // ============================================================
  // فلترة المواد
  // ============================================================

  List<QueryDocumentSnapshot<Map<String, dynamic>>>
      filterMaterials(
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
  // عدد المواد النشطة
  // ============================================================

  int countActive(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where(
      (doc) {
        return doc.data()['active'] != false;
      },
    ).length;
  }

  // ============================================================
  // عدد المواد المعطلة
  // ============================================================

  int countInactive(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where(
      (doc) {
        return doc.data()['active'] == false;
      },
    ).length;
  }

  // ============================================================
  // الصفحة
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return AppScaffold(
      title: 'المواد',

      // ========================================================
      // أزرار أعلى الصفحة
      // ========================================================

      actions: [
        // ======================================================
        // تحديث
        // ======================================================

        IconButton(
          tooltip: 'تحديث',
          onPressed: () {
            setState(() {});
          },
          icon: const Icon(
            Icons.refresh_outlined,
          ),
        ),

        // ======================================================
        // إضافة
        // ======================================================

        IconButton(
          tooltip: 'إضافة مادة',
          onPressed: () {
            showMaterialDialog();
          },
          icon: const Icon(
            Icons.add,
          ),
        ),

        const SizedBox(
          width: 8,
        ),
      ],

      // ========================================================
      // زر الإضافة العائم
      // ========================================================

      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: () {
          showMaterialDialog();
        },
        icon: const Icon(
          Icons.add,
        ),
        label: const Text(
          'إضافة مادة',
        ),
      ),

      // ========================================================
      // المحتوى
      // ========================================================

      child: Directionality(
        textDirection: TextDirection.rtl,

        child: StreamBuilder<
            QuerySnapshot<Map<String, dynamic>>>(
          stream: materials.snapshots(),

          builder: (
            context,
            snapshot,
          ) {
            // ==================================================
            // التحميل
            // ==================================================

            if (snapshot.connectionState ==
                ConnectionState.waiting) {
              return AppPage(
                child: AppLoading(
                  message:
                      'جاري تحميل المواد...',
                ),
              );
            }

            // ==================================================
            // الخطأ
            // ==================================================

            if (snapshot.hasError) {
              return AppPage(
                child: AppError(
                  message:
                      'حدث خطأ أثناء تحميل المواد',
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
                snapshot.data?.docs.toList() ?? [];

            // ==================================================
            // ترتيب المواد حسب الاسم
            // ==================================================

            allDocs.sort(
              (a, b) {
                final String nameA =
                    a.data()['name']?.toString() ??
                        '';

                final String nameB =
                    b.data()['name']?.toString() ??
                        '';

                return nameA.compareTo(nameB);
              },
            );

            // ==================================================
            // البحث
            // ==================================================

            final docs =
                filterMaterials(allDocs);

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
                    title: 'إدارة المواد',
                    subtitle:
                        'إضافة المواد وتعديلها وإدارة أنواع كل مادة.',
                    icon:
                        Icons.inventory_2_outlined,
                    trailing: AppButton(
                      text: 'إضافة مادة',
                      icon: Icons.add,
                      onPressed: () {
                        showMaterialDialog();
                      },
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
                        'ابحث باسم المادة',
                    prefixIcon:
                        Icons.search,
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
                      // إجمالي المواد
                      // ================================================

                      AppStatCard(
                        title:
                            'إجمالي المواد',
                        value:
                            '${allDocs.length}',
                        icon:
                            Icons.inventory_2_outlined,
                        color:
                            AppColors.primary,
                      ),

                      // ================================================
                      // المواد النشطة
                      // ================================================

                      AppStatCard(
                        title:
                            'المواد النشطة',
                        value:
                            '${countActive(allDocs)}',
                        icon:
                            Icons.check_circle_outline,
                        color:
                            AppColors.success,
                      ),

                      // ================================================
                      // المواد المعطلة
                      // ================================================

                      AppStatCard(
                        title:
                            'المواد المعطلة',
                        value:
                            '${countInactive(allDocs)}',
                        icon:
                            Icons.cancel_outlined,
                        color:
                            AppColors.danger,
                      ),
                    ],
                  ),

                  AppSpacing.verticalXl,

                  // ==================================================
                  // قائمة المواد
                  // ==================================================

                  AppSectionTitle(
                    title:
                        'قائمة المواد',
                    icon:
                        Icons.list_alt_outlined,
                    trailing: Text(
                      '${docs.length} مادة',
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
                          _searchText
                                  .trim()
                                  .isEmpty
                              ? 'لا توجد مواد حتى الآن'
                              : 'لا توجد نتائج مطابقة للبحث',
                      icon:
                          Icons.inventory_2_outlined,
                    )

                  // ==================================================
                  // قائمة المواد
                  // ==================================================

                  else
                    ...docs.map(
                      (doc) {
                        final data =
                            doc.data();

                        final String name =
                            data['name']
                                    ?.toString() ??
                                'بدون اسم';

                        final bool active =
                            data['active'] !=
                                false;

                        return _MaterialCard(
                          name: name,
                          active: active,

                          // ==========================================
                          // الأنواع
                          // ==========================================

                          onTypes: () {
                            openMaterialTypes(
                              doc.id,
                              name,
                            );
                          },

                          // ==========================================
                          // تعديل
                          // ==========================================

                          onEdit: () {
                            showMaterialDialog(
                              doc: doc,
                            );
                          },

                          // ==========================================
                          // تفعيل / تعطيل
                          // ==========================================

                          onToggle: () {
                            toggleMaterial(
                              doc,
                            );
                          },

                          // ==========================================
                          // حذف
                          // ==========================================

                          onDelete: () {
                            deleteMaterial(
                              doc,
                            );
                          },
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
// بطاقة المادة
// =============================================================

class _MaterialCard extends StatelessWidget {
  final String name;
  final bool active;

  final VoidCallback onTypes;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _MaterialCard({
    required this.name,
    required this.active,
    required this.onTypes,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return AppCard(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),

      child: Padding(
        padding: const EdgeInsets.all(4),

        child: Column(
          children: [
            // ========================================================
            // معلومات المادة
            // ========================================================

            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,

                  decoration:
                      BoxDecoration(
                    color:
                        AppColors.warning.withValues(
                      alpha: 0.12,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      15,
                    ),
                  ),

                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color:
                        AppColors.warning,
                    size: 28,
                  ),
                ),

                const SizedBox(
                  width: 14,
                ),

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
                            : 'معطلة',
                        color: active
                            ? AppColors.success
                            : AppColors.danger,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            AppSpacing.verticalMd,

            // ========================================================
            // الإجراءات
            // ========================================================

            Wrap(
              spacing: 8,
              runSpacing: 8,

              children: [
                // ======================================================
                // الأنواع
                // ======================================================

                AppButton(
                  text: 'الأنواع',
                  icon:
                      Icons.list_alt_outlined,
                  onPressed: onTypes,
                ),

                // ======================================================
                // تعديل
                // ======================================================

                AppOutlinedButton(
                  text: 'تعديل',
                  icon:
                      Icons.edit_outlined,
                  onPressed: onEdit,
                ),

                // ======================================================
                // تفعيل / تعطيل
                // ======================================================

                AppOutlinedButton(
                  text: active
                      ? 'تعطيل'
                      : 'تفعيل',
                  icon: active
                      ? Icons
                          .visibility_off_outlined
                      : Icons
                          .visibility_outlined,
                  onPressed: onToggle,
                ),

                // ======================================================
                // حذف
                // ======================================================

                AppOutlinedButton(
                  text: 'حذف',
                  icon:
                      Icons.delete_outline,
                  onPressed:
                      onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}



import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

import 'item_types_page.dart';

// =============================================================
// صفحة البنود
// =============================================================

class ItemBandPage extends StatefulWidget {
  const ItemBandPage({
    super.key,
  });

  @override
  State<ItemBandPage> createState() => _ItemBandPageState();
}

class _ItemBandPageState extends State<ItemBandPage> {
  // ============================================================
  // Firestore
  // ============================================================

  final FirebaseFirestore firestore =
      FirebaseFirestore.instance;

  final CollectionReference<Map<String, dynamic>> items =
      FirebaseFirestore.instance.collection(
        'item_definitions',
      );

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
  // فتح أنواع البند
  // ============================================================

  Future<void> openItemTypes(
    String itemDefinitionId,
    String itemDefinitionName,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemTypesPage(
          itemDefinitionId: itemDefinitionId,
          itemDefinitionName: itemDefinitionName,
        ),
      ),
    );
  }

  // ============================================================
  // إضافة / تعديل بند
  // ============================================================

  Future<void> showItemDialog({
    DocumentSnapshot<Map<String, dynamic>>? doc,
  }) async {
    final controller = TextEditingController(
      text: doc?.data()?['name']?.toString() ?? '',
    );

    final formKey = GlobalKey<FormState>();

    final bool isEditing = doc != null;

    // ==========================================================
    // بيانات البند الجديد
    // ==========================================================

    String? createdItemId;
    String? createdItemName;

    // ==========================================================
    // فتح Dialog
    // ==========================================================

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(
              isEditing ? 'تعديل البند' : 'إضافة بند',
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
                    labelText: 'اسم البند',
                    hintText: 'مثال: أعمال الحفر',
                    prefixIcon: Icon(
                      Icons.category_outlined,
                    ),
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'أدخل اسم البند';
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
                    // التأكد من عدم التكرار
                    // ==================================================

                    final duplicateSnapshot =
                        await items
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
                        'هذا البند موجود مسبقاً',
                      );

                      return;
                    }

                    // ==================================================
                    // إضافة بند جديد
                    // ==================================================

                    if (!isEditing) {
                      final DocumentReference<
                          Map<String, dynamic>> newDoc =
                          await items.add({
                        'name': name,
                        'active': true,
                        'createdAt':
                            FieldValue.serverTimestamp(),
                        'updatedAt':
                            FieldValue.serverTimestamp(),
                      });

                      // حفظ بيانات البند الجديد
                      createdItemId = newDoc.id;
                      createdItemName = name;

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
                    // تعديل البند
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
    // إلغاء
    // ==========================================================

    if (!mounted || result != true) {
      return;
    }

    // ==========================================================
    // إضافة بند جديد
    // ==========================================================

    if (!isEditing &&
        createdItemId != null &&
        createdItemName != null) {
      AppWidgets.showSuccess(
        context,
        'تمت إضافة البند بنجاح',
      );

      // ========================================================
      // فتح صفحة إضافة النوع مباشرة
      // ========================================================

      await openItemTypes(
        createdItemId!,
        createdItemName!,
      );

      return;
    }

    // ==========================================================
    // تعديل بند
    // ==========================================================

    if (isEditing) {
      AppWidgets.showSuccess(
        context,
        'تم تعديل البند بنجاح',
      );
    }
  }

  // ============================================================
  // تفعيل / تعطيل البند
  // ============================================================

  Future<void> toggleItem(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();

    if (data == null) {
      return;
    }

    final bool isActive =
        data['active'] != false;

    final String name =
        data['name']?.toString() ?? 'هذا البند';

    // ==========================================================
    // تأكيد التعطيل
    // ==========================================================

    if (isActive) {
      final bool confirmed =
          await AppWidgets.showConfirmDialog(
        context: context,
        title: 'تعطيل البند',
        message:
            'هل تريد تعطيل البند "$name"؟',
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
            ? 'تم تعطيل البند'
            : 'تم تفعيل البند',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء تغيير حالة البند: $e',
      );
    }
  }

  // ============================================================
  // حذف البند
  // ============================================================

  Future<void> deleteItem(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();

    if (data == null) {
      return;
    }

    final String name =
        data['name']?.toString() ?? 'هذا البند';

    // ==========================================================
    // تأكيد الحذف
    // ==========================================================

    final bool confirmed =
        await AppWidgets.showConfirmDialog(
      context: context,
      title: 'حذف البند',
      message:
          'هل أنت متأكد من حذف "$name"؟\n\n'
          'سيتم حذف البند نهائياً.',
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
        'تم حذف البند بنجاح',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء حذف البند: $e',
      );
    }
  }

  // ============================================================
  // فلترة البنود
  // ============================================================

  List<QueryDocumentSnapshot<Map<String, dynamic>>>
      filterItems(
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
  // عدد البنود النشطة
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
  // عدد البنود غير النشطة
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
      title: 'البنود',

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
          tooltip: 'إضافة بند',
          onPressed: () {
            showItemDialog();
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
          showItemDialog();
        },
        icon: const Icon(
          Icons.add,
        ),
        label: const Text(
          'إضافة بند',
        ),
      ),

      // ========================================================
      // المحتوى
      // ========================================================

      child: Directionality(
        textDirection: TextDirection.rtl,

        child: StreamBuilder<
            QuerySnapshot<Map<String, dynamic>>>(
          stream: items.snapshots(),

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
                      'جاري تحميل البنود...',
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
                      'حدث خطأ أثناء تحميل البنود',
                  onRetry: () {
                    setState(() {});
                  },
                ),
              );
            }

            // ==================================================
            // جميع البنود
            // ==================================================

            final allDocs =
                snapshot.data?.docs.toList() ?? [];

            // ==================================================
            // ترتيب البنود حسب الاسم
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
            // البنود بعد البحث
            // ==================================================

            final docs = filterItems(
              allDocs,
            );

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
                    title: 'إدارة البنود',
                    subtitle:
                        'إضافة البنود وتعديلها وإدارة أنواع كل بند.',
                    icon:
                        Icons.category_outlined,
                    trailing: AppButton(
                      text: 'إضافة بند',
                      icon: Icons.add,
                      onPressed: () {
                        showItemDialog();
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
                        'ابحث باسم البند',
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
                      // إجمالي البنود
                      // ================================================

                      AppStatCard(
                        title:
                            'إجمالي البنود',
                        value:
                            '${allDocs.length}',
                        icon:
                            Icons.category_outlined,
                        color:
                            AppColors.primary,
                      ),

                      // ================================================
                      // البنود النشطة
                      // ================================================

                      AppStatCard(
                        title:
                            'البنود النشطة',
                        value:
                            '${countActive(allDocs)}',
                        icon:
                            Icons.check_circle_outline,
                        color:
                            AppColors.success,
                      ),

                      // ================================================
                      // البنود المعطلة
                      // ================================================

                      AppStatCard(
                        title:
                            'البنود المعطلة',
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
                  // عنوان القائمة
                  // ==================================================

                  AppSectionTitle(
                    title:
                        'قائمة البنود',
                    icon:
                        Icons.list_alt_outlined,
                    trailing: Text(
                      '${docs.length} بند',
                      style:
                          AppTextStyles.bodySecondary,
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
                              ? 'لا توجد بنود حتى الآن'
                              : 'لا توجد نتائج مطابقة للبحث',
                      icon:
                          Icons.category_outlined,
                    )

                  // ==================================================
                  // البنود
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

                        return _ItemCard(
                          name: name,
                          active: active,

                          // ==========================================
                          // الأنواع
                          // ==========================================

                          onTypes: () {
                            openItemTypes(
                              doc.id,
                              name,
                            );
                          },

                          // ==========================================
                          // تعديل
                          // ==========================================

                          onEdit: () {
                            showItemDialog(
                              doc: doc,
                            );
                          },

                          // ==========================================
                          // تفعيل / تعطيل
                          // ==========================================

                          onToggle: () {
                            toggleItem(
                              doc,
                            );
                          },

                          // ==========================================
                          // حذف
                          // ==========================================

                          onDelete: () {
                            deleteItem(
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
// بطاقة البند
// =============================================================

class _ItemCard extends StatelessWidget {
  final String name;
  final bool active;

  final VoidCallback onTypes;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _ItemCard({
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
            // معلومات البند
            // ========================================================

            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,

                  decoration:
                      BoxDecoration(
                    color:
                        AppColors.primary.withValues(
                      alpha: 0.10,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      15,
                    ),
                  ),

                  child: const Icon(
                    Icons.category_outlined,
                    color:
                        AppColors.primary,
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
                            ? 'نشط'
                            : 'معطل',

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
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


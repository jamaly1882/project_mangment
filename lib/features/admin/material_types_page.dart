import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

// =============================================================
// صفحة أنواع المادة
// =============================================================

class MaterialTypesPage extends StatefulWidget {
  final String materialId;
  final String materialName;

  const MaterialTypesPage({
    super.key,
    required this.materialId,
    required this.materialName,
  });

  @override
  State<MaterialTypesPage> createState() => _MaterialTypesPageState();
}

class _MaterialTypesPageState extends State<MaterialTypesPage> {
  // ============================================================
  // Firestore
  // ============================================================

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // ============================================================
  // مرجع أنواع المادة
  // ============================================================

  CollectionReference<Map<String, dynamic>> get typesReference {
    return firestore
        .collection('materials')
        .doc(widget.materialId)
        .collection('types');
  }

  // ============================================================
  // البحث
  // ============================================================

  final TextEditingController _searchController =
      TextEditingController();

  String _searchText = '';

  // ============================================================
  // الوحدات
  // ============================================================

  final List<String> units = [
    'لتر',
    'كجم',
    'طن',
    'م3',
    'م2',
    'قطعة',
    'كيس',
    'ساعة',
    'يوم',
    'أخرى',
  ];

  // ============================================================
  // Dispose
  // ============================================================

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // إضافة / تعديل نوع المادة
  // ============================================================

  Future<void> showTypeDialog({
    DocumentSnapshot<Map<String, dynamic>>? doc,
  }) async {
    final data = doc?.data();

    final TextEditingController nameController = TextEditingController(
      text: data?['name']?.toString() ?? '',
    );

    String selectedUnit = data?['unit']?.toString() ?? 'لتر';

    if (!units.contains(selectedUnit)) {
      selectedUnit = 'أخرى';
    }

    final formKey = GlobalKey<FormState>();

    final bool isEditing = doc != null;

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text(
                  isEditing ? 'تعديل نوع المادة' : 'إضافة نوع مادة',
                  style: AppTextStyles.sectionTitle,
                ),
                content: SizedBox(
                  width: 450,
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ==================================================
                        // اسم النوع
                        // ==================================================

                        TextFormField(
                          controller: nameController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'اسم النوع',
                            hintText: 'مثال: ديزل',
                            prefixIcon: Icon(
                              Icons.local_gas_station_outlined,
                            ),
                          ),
                          validator: (value) {
                            if (value == null ||
                                value.trim().isEmpty) {
                              return 'أدخل اسم النوع';
                            }

                            return null;
                          },
                        ),

                        AppSpacing.verticalMd,

                        // ==================================================
                        // الوحدة
                        // ==================================================

                        AppDropdown<String>(
                          value: selectedUnit,
                          label: 'الوحدة',
                          prefixIcon: Icons.straighten_outlined,
                          items: units.map(
                            (unit) {
                              return DropdownMenuItem<String>(
                                value: unit,
                                child: Text(unit),
                              );
                            },
                          ).toList(),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }

                            setDialogState(() {
                              selectedUnit = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  // ========================================================
                  // إلغاء
                  // ========================================================

                  TextButton(
                    onPressed: () {
                      Navigator.pop(
                        dialogContext,
                        false,
                      );
                    },
                    child: const Text('إلغاء'),
                  ),

                  // ========================================================
                  // حفظ
                  // ========================================================

                  ElevatedButton.icon(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }

                      final String name = nameController.text.trim();

                      try {
                        // ==================================================
                        // منع التكرار
                        // ==================================================

                        final duplicateSnapshot = await typesReference
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
                          if (!mounted) {
                            return;
                          }

                          AppWidgets.showWarning(
                            context,
                            'هذا النوع موجود مسبقاً',
                          );

                          return;
                        }

                        // ==================================================
                        // إضافة
                        // ==================================================

                        if (!isEditing) {
                          await typesReference.add({
                            'name': name,
                            'unit': selectedUnit,
                            'active': true,
                            'createdAt':
                                FieldValue.serverTimestamp(),
                            'updatedAt':
                                FieldValue.serverTimestamp(),
                          });
                        }

                        // ==================================================
                        // تعديل
                        // ==================================================

                        else {
                          await doc.reference.update({
                            'name': name,
                            'unit': selectedUnit,
                            'updatedAt':
                                FieldValue.serverTimestamp(),
                          });
                        }

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
      },
    );

    nameController.dispose();

    // ==========================================================
    // رسالة النجاح
    // ==========================================================

    if (result == true && mounted) {
      AppWidgets.showSuccess(
        context,
        isEditing
            ? 'تم تعديل النوع بنجاح'
            : 'تمت إضافة النوع بنجاح',
      );
    }
  }

  // ============================================================
  // تفعيل / تعطيل نوع المادة
  // ============================================================

  Future<void> toggleType(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();

    if (data == null) {
      return;
    }

    final bool isActive = data['active'] != false;

    final String name = data['name']?.toString() ?? 'هذا النوع';

    // ==========================================================
    // تأكيد التعطيل
    // ==========================================================

    if (isActive) {
      final bool confirmed = await AppWidgets.showConfirmDialog(
        context: context,
        title: 'تعطيل النوع',
        message: 'هل تريد تعطيل النوع "$name"؟',
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
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      AppWidgets.showSuccess(
        context,
        isActive ? 'تم تعطيل النوع' : 'تم تفعيل النوع',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء تغيير حالة النوع: $e',
      );
    }
  }

  // ============================================================
  // حذف النوع
  // ============================================================

  Future<void> deleteType(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();

    if (data == null) {
      return;
    }

    final String name = data['name']?.toString() ?? 'هذا النوع';

    final bool confirmed = await AppWidgets.showConfirmDialog(
      context: context,
      title: 'حذف نوع المادة',
      message:
          'هل أنت متأكد من حذف "$name"؟\n\n'
          'سيتم حذف النوع نهائياً.',
      confirmText: 'حذف',
      cancelText: 'إلغاء',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await doc.reference.delete();

      if (!mounted) {
        return;
      }

      AppWidgets.showSuccess(
        context,
        'تم حذف النوع بنجاح',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء حذف النوع: $e',
      );
    }
  }

  // ============================================================
  // فلترة الأنواع
  // ============================================================

  List<QueryDocumentSnapshot<Map<String, dynamic>>> filterTypes(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final String search = _searchText.trim().toLowerCase();

    if (search.isEmpty) {
      return docs;
    }

    return docs.where(
      (doc) {
        final data = doc.data();

        final String name =
            data['name']?.toString().toLowerCase() ?? '';

        final String unit =
            data['unit']?.toString().toLowerCase() ?? '';

        return name.contains(search) || unit.contains(search);
      },
    ).toList();
  }

  // ============================================================
  // عدد الأنواع النشطة
  // ============================================================

  int countActive(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs
        .where(
          (doc) => doc.data()['active'] != false,
        )
        .length;
  }

  // ============================================================
  // عدد الأنواع المعطلة
  // ============================================================

  int countInactive(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs
        .where(
          (doc) => doc.data()['active'] == false,
        )
        .length;
  }

  // ============================================================
  // الصفحة
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'أنواع المادة',
      showBackButton: true,
      actions: [
        // ========================================================
        // إضافة
        // ========================================================

        IconButton(
          tooltip: 'إضافة نوع',
          onPressed: () {
            showTypeDialog();
          },
          icon: const Icon(
            Icons.add,
          ),
        ),

        const SizedBox(
          width: 8,
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showTypeDialog();
        },
        icon: const Icon(
          Icons.add,
        ),
        label: const Text(
          'إضافة نوع',
        ),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: typesReference.snapshots(),
          builder: (
            context,
            snapshot,
          ) {
            // ==================================================
            // التحميل
            // ==================================================

            if (snapshot.connectionState == ConnectionState.waiting) {
              return AppPage(
                child: AppLoading(
                  message: 'جاري تحميل أنواع المادة...',
                ),
              );
            }

            // ==================================================
            // الخطأ
            // ==================================================

            if (snapshot.hasError) {
              return AppPage(
                child: AppError(
                  message: 'حدث خطأ أثناء تحميل أنواع المادة',
                  onRetry: () {
                    setState(() {});
                  },
                ),
              );
            }

            // ==================================================
            // البيانات
            // ==================================================

            final allDocs = snapshot.data?.docs.toList() ?? [];

            // ==================================================
            // ترتيب الأنواع
            // ==================================================

            allDocs.sort(
              (a, b) {
                final String nameA =
                    a.data()['name']?.toString() ?? '';

                final String nameB =
                    b.data()['name']?.toString() ?? '';

                return nameA.compareTo(nameB);
              },
            );

            // ==================================================
            // البحث
            // ==================================================

            final docs = filterTypes(allDocs);

            return AppPage(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ==================================================
                  // المادة الرئيسية
                  // ==================================================

                  AppCard(
                    child: Row(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.inventory_2_outlined,
                            color: AppColors.warning,
                            size: 30,
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
                                'المادة الرئيسية',
                                style: AppTextStyles.bodySecondary,
                              ),
                              const SizedBox(
                                height: 4,
                              ),
                              Text(
                                widget.materialName,
                                style: AppTextStyles.cardTitle,
                              ),
                            ],
                          ),
                        ),
                        AppStatusBadge(
                          text: '${allDocs.length} نوع',
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),

                  AppSpacing.verticalLg,

                  // ==================================================
                  // عنوان الصفحة
                  // ==================================================

                  AppPageHeader(
                    title: 'إدارة أنواع المادة',
                    subtitle:
                        'إضافة أنواع المادة وتحديد وحدة القياس وإدارة حالتها.',
                    icon: Icons.category_outlined,
                    trailing: AppButton(
                      text: 'إضافة نوع',
                      icon: Icons.add,
                      onPressed: () {
                        showTypeDialog();
                      },
                    ),
                  ),

                  AppSpacing.verticalLg,

                  // ==================================================
                  // البحث
                  // ==================================================

                  AppTextField(
                    controller: _searchController,
                    label: 'البحث',
                    hint: 'ابحث باسم النوع أو الوحدة',
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
                    icon: Icons.analytics_outlined,
                  ),

                  AppSpacing.verticalMd,

                  AppResponsiveGrid(
                    minItemWidth: 220,
                    spacing: 16,
                    children: [
                      // ================================================
                      // إجمالي الأنواع
                      // ================================================

                      AppStatCard(
                        title: 'إجمالي الأنواع',
                        value: '${allDocs.length}',
                        icon: Icons.category_outlined,
                        color: AppColors.primary,
                      ),

                      // ================================================
                      // الأنواع النشطة
                      // ================================================

                      AppStatCard(
                        title: 'الأنواع النشطة',
                        value: '${countActive(allDocs)}',
                        icon: Icons.check_circle_outline,
                        color: AppColors.success,
                      ),

                      // ================================================
                      // الأنواع المعطلة
                      // ================================================

                      AppStatCard(
                        title: 'الأنواع المعطلة',
                        value: '${countInactive(allDocs)}',
                        icon: Icons.cancel_outlined,
                        color: AppColors.danger,
                      ),
                    ],
                  ),

                  AppSpacing.verticalXl,

                  // ==================================================
                  // قائمة الأنواع
                  // ==================================================

                  AppSectionTitle(
                    title: 'قائمة الأنواع',
                    icon: Icons.list_alt_outlined,
                    trailing: Text(
                      '${docs.length} نوع',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ),

                  AppSpacing.verticalMd,

                  // ==================================================
                  // لا توجد بيانات
                  // ==================================================

                  if (docs.isEmpty)
                    AppEmpty(
                      message: _searchText.trim().isEmpty
                          ? 'لا توجد أنواع لهذه المادة'
                          : 'لا توجد نتائج مطابقة للبحث',
                      icon: Icons.category_outlined,
                    )

                  // ==================================================
                  // قائمة الأنواع
                  // ==================================================

                  else
                    ...docs.map(
                      (doc) {
                        final data = doc.data();

                        final String name =
                            data['name']?.toString() ?? 'بدون اسم';

                        final String unit =
                            data['unit']?.toString() ?? 'غير محددة';

                        final bool active = data['active'] != false;

                        return _MaterialTypeCard(
                          name: name,
                          unit: unit,
                          active: active,
                          onEdit: () {
                            showTypeDialog(
                              doc: doc,
                            );
                          },
                          onToggle: () {
                            toggleType(doc);
                          },
                          onDelete: () {
                            deleteType(doc);
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
// بطاقة نوع المادة
// =============================================================

class _MaterialTypeCard extends StatelessWidget {
  final String name;
  final String unit;
  final bool active;

  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _MaterialTypeCard({
    required this.name,
    required this.unit,
    required this.active,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12,
      ),
      child: AppCard(
        child: Column(
          children: [
            // ========================================================
            // معلومات النوع
            // ========================================================

            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(
                      alpha: 0.10,
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.local_gas_station_outlined,
                    color: AppColors.info,
                    size: 28,
                  ),
                ),
                const SizedBox(
                  width: 14,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: AppTextStyles.cardTitle,
                      ),
                      const SizedBox(
                        height: 8,
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          AppStatusBadge(
                            text: 'الوحدة: $unit',
                            color: AppColors.info,
                          ),
                          AppStatusBadge(
                            text: active ? 'نشط' : 'معطل',
                            color: active
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                        ],
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
                // تعديل
                // ======================================================

                AppOutlinedButton(
                  text: 'تعديل',
                  icon: Icons.edit_outlined,
                  onPressed: onEdit,
                ),

                // ======================================================
                // تفعيل / تعطيل
                // ======================================================

                AppOutlinedButton(
                  text: active ? 'تعطيل' : 'تفعيل',
                  icon: active
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  onPressed: onToggle,
                ),

                // ======================================================
                // حذف
                // ======================================================

                AppOutlinedButton(
                  text: 'حذف',
                  icon: Icons.delete_outline,
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
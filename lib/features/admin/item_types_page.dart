import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/constants/previous_prices.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/costs.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

// =============================================================
// صفحة أنواع البند
// =============================================================

class ItemTypesPage extends StatefulWidget {
  final String itemDefinitionId;
  final String itemDefinitionName;

  const ItemTypesPage({
    super.key,
    required this.itemDefinitionId,
    required this.itemDefinitionName,
  });

  @override
  State<ItemTypesPage> createState() => _ItemTypesPageState();
}

class _ItemTypesPageState extends State<ItemTypesPage> {
  // ============================================================
  // Firestore
  // ============================================================

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // ============================================================
  // البحث
  // ============================================================

  final TextEditingController _searchController =
      TextEditingController();

  String _searchText = '';

  // ============================================================
  // مرجع أنواع البند
  // ============================================================

  CollectionReference<Map<String, dynamic>> get typesReference {
    return firestore
        .collection('item_definitions')
        .doc(widget.itemDefinitionId)
        .collection('types');
  }

  // ============================================================
  // Dispose
  // ============================================================

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // إضافة / تعديل نوع
  // ============================================================

  Future<void> showTypeDialog({
    DocumentSnapshot<Map<String, dynamic>>? doc,
  }) async {
    final data = doc?.data();

    final controller = TextEditingController(
      text: data?['name']?.toString() ?? '',
    );

    // كود البند في خلاصة أسعار 1447هـ (اختياري للأنواع القديمة).
    final codeController = TextEditingController(
      text: (data?['code'] ?? data?['previousPriceCode'])
              ?.toString() ??
          '',
    );

    // سعر الوحدة السابق (1447هـ) — «سعر سابق».
    final dynamic existingPrice = data?['previousPrice'];
    final previousPriceController = TextEditingController(
      text: existingPrice is num
          ? ProjectCosts.toEditText(existingPrice.toDouble())
          : '',
    );

    String? selectedUnit = (data?['unit'] ?? '').toString().trim().isEmpty
        ? null
        : data!['unit'].toString().trim();

    final units = <String>{
      ...previousTypeUnits,
      if (selectedUnit != null) selectedUnit,
    }.toList();

    final formKey = GlobalKey<FormState>();

    final bool isEditing = doc != null;

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(
              isEditing ? 'تعديل نوع البند' : 'إضافة نوع',
              style: AppTextStyles.sectionTitle,
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: controller,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'اسم النوع',
                          hintText: 'مثال: حفر ترابي',
                          prefixIcon: Icon(
                            Icons.list_alt_outlined,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'أدخل اسم النوع';
                          }

                          return null;
                        },
                      ),
                      AppSpacing.verticalSm,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: codeController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'كود البند (1447هـ)',
                                hintText: 'مثال: 12',
                                prefixIcon: Icon(Icons.tag_outlined),
                              ),
                              validator: (value) {
                                final text = (value ?? '').trim();
                                if (text.isEmpty) return null;
                                if (int.tryParse(text) == null) {
                                  return 'الكود يجب أن يكون رقمًا';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedUnit,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'الوحدة',
                                prefixIcon: Icon(Icons.straighten_outlined),
                              ),
                              items: units
                                  .map(
                                    (unit) => DropdownMenuItem<String>(
                                      value: unit,
                                      child: Text(unit),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                selectedUnit = value;
                              },
                            ),
                          ),
                        ],
                      ),
                      AppSpacing.verticalSm,
                      TextFormField(
                        controller: previousPriceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'سعر سابق (${previousPricesYear})',
                          hintText: 'سعر الوحدة من خلاصة الأسعار',
                          prefixIcon: Icon(Icons.price_change_outlined),
                          suffixText: 'ريال',
                          helperText: 'يُقترح تلقائيًا عند تسعير البند',
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return null;
                          final parsed = double.tryParse(
                            text.replaceAll('٫', '.').replaceAll(',', '.'),
                          );
                          if (parsed == null || parsed < 0) {
                            return 'أدخل سعرًا صحيحًا';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
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
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) {
                    return;
                  }

                  final String name = controller.text.trim();
                  final String codeText = codeController.text.trim();
                  final int? code =
                      codeText.isEmpty ? null : int.tryParse(codeText);
                  final String priceText = previousPriceController.text
                      .trim()
                      .replaceAll('٫', '.')
                      .replaceAll(',', '.');
                  final double? previousPrice =
                      priceText.isEmpty ? null : double.tryParse(priceText);

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

                    final bool duplicate = duplicateSnapshot.docs.any(
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

                    // منع تكرار كود البند داخل البند نفسه.
                    if (code != null) {
                      final codeSnapshot = await typesReference
                          .where('code', isEqualTo: code)
                          .get();

                      final bool codeTaken = codeSnapshot.docs.any(
                        (item) => item.id != doc?.id,
                      );

                      if (codeTaken) {
                        if (!mounted) {
                          return;
                        }

                        AppWidgets.showWarning(
                          context,
                          'كود البند $code مستخدم لنوع آخر في هذا البند',
                        );

                        return;
                      }
                    }

                    // ==================================================
                    // إضافة النوع
                    // ==================================================

                    final priceFields = <String, dynamic>{
                      'code': code,
                      'previousPriceCode': code,
                      'unit': selectedUnit,
                      'previousPrice': previousPrice,
                      'previousPriceYear': previousPricesYear,
                      if (code != null && previousPrice != null)
                        'previousPriceSource': previousPricesSource,
                    };

                    if (!isEditing) {
                      await typesReference.add({
                        'name': name,
                        ...priceFields,
                        'active': true,
                        'createdAt': FieldValue.serverTimestamp(),
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                    }

                    // ==================================================
                    // تعديل النوع
                    // ==================================================

                    else {
                      await doc.reference.update({
                        'name': name,
                        ...priceFields,
                        'updatedAt': FieldValue.serverTimestamp(),
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

    controller.dispose();
    codeController.dispose();
    previousPriceController.dispose();

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
  // تفعيل / تعطيل النوع
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
      title: 'حذف النوع',
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
        final String code =
            (data['code'] ?? data['previousPriceCode'] ?? '').toString();

        return name.contains(search) || code.contains(search);
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
  // عدد الأنواع التي لها سعر سابق (1447هـ)
  // ============================================================

  int countWithPreviousPrice(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final price = doc.data()['previousPrice'];
      return price is num && price > 0;
    }).length;
  }

  // ============================================================
  // الصفحة
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'أنواع البند',
      showBackButton: true,
      actions: [
        // ========================================================
        // تحديث
        // ========================================================

        IconButton(
          tooltip: 'تحديث',
          onPressed: () {
            setState(() {});
          },
          icon: const Icon(
            Icons.refresh_outlined,
          ),
        ),

        // ========================================================
        // إضافة نوع
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
            // تحميل
            // ==================================================

            if (snapshot.connectionState == ConnectionState.waiting) {
              return AppPage(
                child: AppLoading(
                  message: 'جاري تحميل أنواع البند...',
                ),
              );
            }

            // ==================================================
            // خطأ
            // ==================================================

            if (snapshot.hasError) {
              return AppPage(
                child: AppError(
                  message: 'حدث خطأ أثناء تحميل أنواع البند',
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

            // ==================================================
            // الصفحة
            // ==================================================

            return AppPage(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ==================================================
                  // رأس الصفحة
                  // ==================================================

                  AppPageHeader(
                    title: 'أنواع البند',
                    subtitle: 'إدارة الأنواع التابعة للبند الرئيسي.',
                    icon: Icons.list_alt_outlined,
                    trailing: AppButton(
                      text: 'إضافة نوع',
                      icon: Icons.add,
                      onPressed: () {
                        showTypeDialog();
                      },
                    ),
                  ),

                  AppSpacing.verticalMd,

                  // ==================================================
                  // البند الرئيسي
                  // ==================================================

                  AppCard(
                    color: AppColors.primary.withValues(
                      alpha: 0.05,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(
                              alpha: 0.10,
                            ),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Icon(
                            Icons.category_outlined,
                            color: AppColors.primary,
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
                              const Text(
                                'البند الرئيسي',
                                style: AppTextStyles.small,
                              ),
                              const SizedBox(
                                height: 5,
                              ),
                              Text(
                                widget.itemDefinitionName,
                                style: AppTextStyles.sectionTitle,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  AppSpacing.verticalLg,

                  // ==================================================
                  // البحث
                  // ==================================================

                  AppTextField(
                    controller: _searchController,
                    label: 'البحث',
                    hint: 'ابحث باسم النوع',
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
                        icon: Icons.list_alt_outlined,
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

                      // ================================================
                      // أنواع لها سعر سابق (1447هـ)
                      // ================================================

                      AppStatCard(
                        title: 'أنواع لها سعر سابق',
                        value: '${countWithPreviousPrice(allDocs)}',
                        icon: Icons.price_change_outlined,
                        color: AppColors.info,
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
                          ? 'لا توجد أنواع لهذا البند'
                          : 'لا توجد نتائج مطابقة للبحث',
                      icon: Icons.list_alt_outlined,
                    )

                  // ==================================================
                  // القائمة
                  // ==================================================

                  else
                    ...docs.map(
                      (doc) {
                        final data = doc.data();

                        final String name =
                            data['name']?.toString() ?? 'بدون اسم';

                        final bool active = data['active'] != false;

                        final rawCode =
                            data['code'] ?? data['previousPriceCode'];
                        final int? code = rawCode is num
                            ? rawCode.toInt()
                            : int.tryParse(rawCode?.toString() ?? '');

                        final String unit =
                            (data['unit'] ?? '').toString().trim();

                        final rawPrice = data['previousPrice'];
                        final double? previousPrice =
                            rawPrice is num ? rawPrice.toDouble() : null;

                        return _TypeCard(
                          name: name,
                          active: active,
                          code: code,
                          unit: unit,
                          previousPrice: previousPrice,
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
// بطاقة النوع
// =============================================================

class _TypeCard extends StatelessWidget {
  final String name;
  final bool active;

  /// كود البند في خلاصة أسعار 1447هـ (إن وُجد).
  final int? code;

  /// وحدة البند (م3، م2، م.ط …).
  final String unit;

  /// سعر الوحدة السابق لعام 1447هـ.
  final double? previousPrice;

  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _TypeCard({
    required this.name,
    required this.active,
    this.code,
    this.unit = '',
    this.previousPrice,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
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
                    Icons.list_alt_outlined,
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
                        height: 7,
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          AppStatusBadge(
                            text: active ? 'نشط' : 'معطل',
                            color: active
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                          if (code != null)
                            AppStatusBadge(
                              text: 'كود $code',
                              color: AppColors.info,
                            ),
                          if (unit.isNotEmpty)
                            AppStatusBadge(
                              text: unit,
                              color: AppColors.primary,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ========================================================
            // سعر سابق (1447هـ)
            // ========================================================

            if (previousPrice != null && previousPrice! > 0) ...[
              AppSpacing.verticalSm,
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: AppInfoRow(
                  label: 'سعر سابق (${previousPricesYear})',
                  value: '${ProjectCosts.formatMoney(previousPrice!)}',
                  icon: Icons.price_change_outlined,
                ),
              ),
            ],

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
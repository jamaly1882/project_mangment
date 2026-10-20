import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

import 'add_item_page.dart';
import 'item_details_page.dart';

class ItemsPage extends StatelessWidget {
  final String projectId;

  const ItemsPage({
    super.key,
    required this.projectId,
  });

  // =========================================================
  // Firestore
  // =========================================================

  CollectionReference<Map<String, dynamic>> get itemsCollection =>
      FirebaseFirestore.instance.collection('items');

  // =========================================================
  // تحويل القيمة إلى double
  // =========================================================

  double _toDouble(dynamic value) {
    if (value is int) {
      return value.toDouble();
    }

    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  // =========================================================
  // تنسيق الرقم
  // =========================================================

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(2);
  }

  // =========================================================
  // تنسيق التاريخ
  // =========================================================

  String _formatDate(dynamic value) {
    if (value == null) {
      return 'غير محدد';
    }

    if (value is Timestamp) {
      final date = value.toDate();

      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    }

    return 'غير محدد';
  }

  // =========================================================
  // فتح صفحة التفاصيل
  // =========================================================

  void _openDetails(
    BuildContext context,
    String itemId,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemDetailsPage(
          projectId: projectId,
          itemId: itemId,
        ),
      ),
    );
  }

  // =========================================================
  // إضافة بند
  // =========================================================

  void _addItem(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddItemPage(
          projectId: projectId,
        ),
      ),
    );
  }

  // =========================================================
  // إضافة كمية منفذة
  // =========================================================

  Future<void> _showAddQuantityDialog(
    BuildContext context,
    String itemId,
    Map<String, dynamic> data,
  ) async {
    final contractQuantity = _toDouble(
      data['contractQuantity'],
    );

    final executedQuantity = _toDouble(
      data['executedQuantity'],
    );

    final unit = data['unit']?.toString() ?? '';

    final remaining = contractQuantity - executedQuantity;

    if (remaining <= 0) {
      AppWidgets.showWarning(
        context,
        'تم تنفيذ كامل الكمية التعاقدية لهذا البند',
      );

      return;
    }

    final controller = TextEditingController();

    final quantity = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        String? errorText;

        return StatefulBuilder(
          builder: (
            context,
            setState,
          ) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(
                    Icons.add_chart,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'إضافة كمية منفذة',
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ===========================================
                    // اسم البند
                    // ===========================================

                    Text(
                      data['name']?.toString() ?? 'بدون اسم',
                      style: AppTextStyles.cardTitle,
                    ),

                    AppSpacing.verticalMd,

                    // ===========================================
                    // الكمية التعاقدية
                    // ===========================================

                    AppInfoRow(
                      icon: Icons.assignment,
                      label: 'الكمية التعاقدية',
                      value:
                          '${_formatNumber(contractQuantity)} $unit',
                    ),

                    AppSpacing.verticalSm,

                    // ===========================================
                    // المنفذ سابقًا
                    // ===========================================

                    AppInfoRow(
                      icon: Icons.done_all,
                      label: 'المنفذ سابقًا',
                      value:
                          '${_formatNumber(executedQuantity)} $unit',
                    ),

                    AppSpacing.verticalSm,

                    // ===========================================
                    // المتبقي
                    // ===========================================

                    AppInfoRow(
                      icon: Icons.pending_actions,
                      label: 'المتبقي',
                      value:
                          '${_formatNumber(remaining)} $unit',
                    ),

                    AppSpacing.verticalLg,

                    // ===========================================
                    // إدخال الكمية
                    // ===========================================

                    TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'الكمية الجديدة',
                        hintText: 'أدخل الكمية المنفذة',
                        suffixText: unit.isEmpty ? null : unit,
                        prefixIcon: const Icon(
                          Icons.add,
                        ),
                        errorText: errorText,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        final entered = double.tryParse(
                          value.trim(),
                        );

                        if (entered == null) {
                          setState(() {
                            errorText = null;
                          });

                          return;
                        }

                        if (entered <= 0) {
                          setState(() {
                            errorText =
                                'يجب أن تكون الكمية أكبر من صفر';
                          });

                          return;
                        }

                        if (entered > remaining) {
                          setState(() {
                            errorText =
                                'الكمية أكبر من المتبقي '
                                '(${_formatNumber(remaining)} $unit)';
                          });

                          return;
                        }

                        setState(() {
                          errorText = null;
                        });
                      },
                    ),

                    AppSpacing.verticalSm,

                    Text(
                      'الكمية المدخلة ستضاف إلى الكمية المنفذة الحالية.',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final value = double.tryParse(
                      controller.text.trim(),
                    );

                    if (value == null || value <= 0) {
                      setState(() {
                        errorText =
                            'أدخل كمية صحيحة أكبر من صفر';
                      });

                      return;
                    }

                    if (value > remaining) {
                      setState(() {
                        errorText =
                            'الكمية أكبر من المتبقي '
                            '(${_formatNumber(remaining)} $unit)';
                      });

                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      value,
                    );
                  },
                  icon: const Icon(
                    Icons.save,
                  ),
                  label: const Text(
                    'إضافة الكمية',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (quantity == null || quantity <= 0) {
      return;
    }

    await _saveExecutedQuantity(
      context,
      itemId,
      quantity,
    );
  }

  // =========================================================
  // حفظ الكمية المنفذة
  // =========================================================

  Future<void> _saveExecutedQuantity(
    BuildContext context,
    String itemId,
    double addedQuantity,
  ) async {
    try {
      await FirebaseFirestore.instance.runTransaction(
        (transaction) async {
          final ref = itemsCollection.doc(itemId);

          final snapshot = await transaction.get(ref);

          if (!snapshot.exists) {
            throw Exception(
              'البند غير موجود',
            );
          }

          final data = snapshot.data() ?? {};

          final contractQuantity = _toDouble(
            data['contractQuantity'],
          );

          final currentExecutedQuantity = _toDouble(
            data['executedQuantity'],
          );

          final newExecutedQuantity =
              currentExecutedQuantity + addedQuantity;

          if (newExecutedQuantity > contractQuantity) {
            throw Exception(
              'لا يمكن تجاوز الكمية التعاقدية',
            );
          }

          transaction.update(
            ref,
            {
              'executedQuantity': newExecutedQuantity,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        },
      );

      if (!context.mounted) {
        return;
      }

      AppWidgets.showSuccess(
        context,
        'تمت إضافة الكمية بنجاح',
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
      );
    }
  }

  // =========================================================
  // Build
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'بنود المشروع',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addItem(context),
        icon: const Icon(
          Icons.add,
        ),
        label: const Text(
          'إضافة بند',
        ),
      ),
      child: AppPage(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          100,
        ),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: itemsCollection
              .where(
                'projectId',
                isEqualTo: projectId,
              )
              .snapshots(),
          builder: (
            context,
            snapshot,
          ) {
            // ===================================================
            // تحميل
            // ===================================================

            if (snapshot.connectionState ==
                ConnectionState.waiting) {
              return const AppLoading(
                message: 'جاري تحميل البنود...',
              );
            }

            // ===================================================
            // خطأ
            // ===================================================

            if (snapshot.hasError) {
              return const AppError(
                message: 'حدث خطأ أثناء تحميل البنود',
              );
            }

            final documents = snapshot.data?.docs ?? [];

            // ===================================================
            // لا توجد بنود
            // ===================================================

            if (documents.isEmpty) {
              return const AppEmpty(
                icon: Icons.list_alt,
                title: 'لا توجد بنود لهذا المشروع',
                message:
                    'اضغط على "إضافة بند" لإنشاء أول بند',
              );
            }

            // ===================================================
            // عنوان الصفحة والقائمة
            // ===================================================

            return Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                AppPageHeader(
                  title: 'بنود المشروع',
                  subtitle:
                      'عرض البنود والكميات التعاقدية والمنفذة والمتبقية',
                  icon: Icons.assignment,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(
                        alpha: 0.10,
                      ),
                      borderRadius:
                          BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${documents.length} بند',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                AppSpacing.verticalMd,

                // =================================================
                // القائمة
                // =================================================

                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(
                      bottom: 20,
                    ),
                    itemCount: documents.length,
                    itemBuilder: (
                      context,
                      index,
                    ) {
                      final doc = documents[index];

                      final data = doc.data();

                      return Padding(
                        padding:
                            const EdgeInsets.only(
                          bottom: 14,
                        ),
                        child: _ItemCard(
                          itemId: doc.id,
                          data: data,
                          formatDate: _formatDate,
                          toDouble: _toDouble,
                          formatNumber: _formatNumber,
                          onDetails: () {
                            _openDetails(
                              context,
                              doc.id,
                            );
                          },
                          onAddQuantity: () {
                            _showAddQuantityDialog(
                              context,
                              doc.id,
                              data,
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
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
  final String itemId;

  final Map<String, dynamic> data;

  final String Function(dynamic) formatDate;

  final double Function(dynamic) toDouble;

  final String Function(double) formatNumber;

  final VoidCallback onDetails;

  final VoidCallback onAddQuantity;

  const _ItemCard({
    required this.itemId,
    required this.data,
    required this.formatDate,
    required this.toDouble,
    required this.formatNumber,
    required this.onDetails,
    required this.onAddQuantity,
  });

  @override
  Widget build(BuildContext context) {
    // =========================================================
    // البيانات
    // =========================================================

    final name =
        data['name']?.toString() ?? 'بدون اسم';

    final code =
        data['code']?.toString() ?? '-';

    final engineerId =
        data['engineerId']?.toString();

    // =========================================================
    // الكمية التعاقدية
    // =========================================================

    final contractQuantity = toDouble(
      data['contractQuantity'],
    );

    // =========================================================
    // الكمية المنفذة
    // =========================================================

    final actualQuantity = toDouble(
      data['executedQuantity'],
    );

    // =========================================================
    // الوحدة
    // =========================================================

    final unit =
        data['unit']?.toString() ?? '';

    // =========================================================
    // المتبقي
    // =========================================================

    final calculatedRemaining =
        contractQuantity - actualQuantity;

    final remaining =
        calculatedRemaining < 0
            ? 0.0
            : calculatedRemaining;

    // =========================================================
    // نسبة الإنجاز
    // =========================================================

    final progress = contractQuantity <= 0
        ? 0.0
        : (actualQuantity / contractQuantity)
            .clamp(
              0.0,
              1.0,
            )
            .toDouble();

    // =========================================================
    // مدة العقد
    // =========================================================

    final durationDays =
        data['durationDays'];

    // =========================================================
    // هل اكتملت الكمية؟
    // =========================================================

    final isCompleted =
        contractQuantity > 0 &&
        actualQuantity >= contractQuantity;

    // =========================================================
    // تفاصيل البند
    // =========================================================

    final hasDetails =
        data['detailsAdded'] == true;

    // =========================================================
    // البطاقة
    // =========================================================

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          // =====================================================
          // رأس البند
          // =====================================================

          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color:
                      AppColors.primary.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius:
                      BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.construction,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),

              AppSpacingHorizontal.md,

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                      style: AppTextStyles.cardTitle
                          .copyWith(
                        fontSize: 18,
                      ),
                    ),

                    AppSpacing.verticalXs,

                    Text(
                      'الكود: $code',
                      style:
                          AppTextStyles.bodySecondary,
                    ),
                  ],
                ),
              ),

              // =================================================
              // حالة التنفيذ
              // =================================================

              if (isCompleted)
                Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        AppColors.success.withValues(
                      alpha: 0.10,
                    ),
                    borderRadius:
                        BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color:
                            AppColors.success,
                        size: 18,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'مكتمل',
                        style: TextStyle(
                          color:
                              AppColors.success,
                          fontWeight:
                              FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else if (hasDetails)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color:
                        AppColors.success.withValues(
                      alpha: 0.10,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Tooltip(
                    message:
                        'تمت إضافة التفاصيل',
                    child: Icon(
                      Icons.check_circle,
                      color:
                          AppColors.success,
                      size: 22,
                    ),
                  ),
                ),
            ],
          ),

          AppSpacing.verticalMd,

          const Divider(),

          AppSpacing.verticalMd,

          // =====================================================
          // المعلومات الأساسية
          // =====================================================

          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppInfoRow(
                  icon: Icons.engineering,
                  label: 'المهندس',
                  value:
                      engineerId ?? '-',
                ),
              ),

              AppSpacingHorizontal.md,

              Expanded(
                child: AppInfoRow(
                  icon: Icons.assignment,
                  label: 'الكمية التعاقدية',
                  value:
                      '${formatNumber(contractQuantity)} $unit',
                ),
              ),
            ],
          ),

          AppSpacing.verticalMd,

          // =====================================================
          // التنفيذ والمتبقي
          // =====================================================

          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppInfoRow(
                  icon: Icons.done_all,
                  label: 'المنفذ',
                  value:
                      '${formatNumber(actualQuantity)} $unit',
                ),
              ),

              AppSpacingHorizontal.md,

              Expanded(
                child: AppInfoRow(
                  icon:
                      Icons.pending_actions,
                  label: 'المتبقي',
                  value:
                      '${formatNumber(remaining)} $unit',
                ),
              ),
            ],
          ),

          AppSpacing.verticalLg,

          // =====================================================
          // نسبة الإنجاز
          // =====================================================

          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'نسبة الإنجاز',
                style:
                    AppTextStyles.body.copyWith(
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(1)}%',
                style:
                    AppTextStyles.body.copyWith(
                  fontWeight:
                      FontWeight.bold,
                  color:
                      AppColors.primary,
                ),
              ),
            ],
          ),

          AppSpacing.verticalSm,

          AppProgress(
            value: progress,
          ),

          AppSpacing.verticalMd,

          // =====================================================
          // تواريخ العقد
          // =====================================================

          Container(
            padding:
                const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius:
                  BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.border,
              ),
            ),
            child: Column(
              children: [
                AppInfoRow(
                  icon:
                      Icons.calendar_month,
                  label: 'بداية العقد',
                  value: formatDate(
                    data[
                        'contractStartDate'],
                  ),
                ),

                AppSpacing.verticalMd,

                AppInfoRow(
                  icon: Icons.event,
                  label: 'نهاية العقد',
                  value: formatDate(
                    data[
                        'contractEndDate'],
                  ),
                ),

                AppSpacing.verticalMd,

                AppInfoRow(
                  icon: Icons.timelapse,
                  label: 'مدة العقد',
                  value: durationDays ==
                          null
                      ? 'غير محددة'
                      : '$durationDays يوم',
                ),
              ],
            ),
          ),

          AppSpacing.verticalMd,

          // =====================================================
          // أزرار الكميات والتفاصيل
          // =====================================================

          Row(
            children: [
              // =================================================
              // إضافة كمية
              // =================================================

              Expanded(
                child: AppButton(
                  text: isCompleted
                      ? 'تم التنفيذ'
                      : 'إضافة كمية',
                  icon: isCompleted
                      ? Icons.check_circle
                      : Icons.add_chart,
                  expanded: true,
                  onPressed: isCompleted
                      ? null
                      : onAddQuantity,
                ),
              ),

              AppSpacingHorizontal.sm,

              // =================================================
              // التفاصيل
              // =================================================

              Expanded(
                child: AppOutlinedButton(
                  text: hasDetails
                      ? 'التفاصيل'
                      : 'إضافة التفاصيل',
                  icon: hasDetails
                      ? Icons.edit_note
                      : Icons.playlist_add,
                  expanded: true,
                  onPressed: onDetails,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
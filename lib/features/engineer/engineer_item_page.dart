import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

class EngineerItemPage extends StatefulWidget {
  final String itemId;

  const EngineerItemPage({
    super.key,
    required this.itemId,
  });

  @override
  State<EngineerItemPage> createState() =>
      _EngineerItemPageState();
}

class _EngineerItemPageState
    extends State<EngineerItemPage> {
  // ============================================================
  // Firestore
  // ============================================================

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  // ============================================================
  // حقل الكمية
  // ============================================================

  final TextEditingController _quantityController =
      TextEditingController();

  // ============================================================
  // حالات الصفحة
  // ============================================================

  bool _saving = false;
  bool _checkingAdditionalWorks = false;

  String? _lastCheckedSignature;

  // ============================================================
  // التخلص من المتحكم
  // ============================================================

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  // ============================================================
  // تحويل الرقم إلى double
  // ============================================================

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  // ============================================================
  // تنسيق الكمية
  // ============================================================

  String _formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(2);
  }

  // ============================================================
  // Timestamp إلى DateTime
  // ============================================================

  DateTime? _timestampToDate(dynamic value) {
    if (value is Timestamp) {
      final DateTime date = value.toDate();

      return DateTime(
        date.year,
        date.month,
        date.day,
      );
    }

    return null;
  }

  // ============================================================
  // تنسيق التاريخ
  // ============================================================

  String _formatDate(dynamic value) {
    final DateTime? date = _timestampToDate(value);

    if (date == null) {
      return 'غير محدد';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // ============================================================
  // جلب اسم المشروع
  // ============================================================

  Future<String> _getProjectName(
    String projectId,
  ) async {
    if (projectId.isEmpty) {
      return 'مشروع غير محدد';
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await _firestore
              .collection('projects')
              .doc(projectId)
              .get();

      if (!doc.exists) {
        return 'مشروع غير موجود';
      }

      final Map<String, dynamic> data =
          doc.data() ?? {};

      final String name =
          (data['name'] ??
                  data['projectName'] ??
                  data['title'] ??
                  '')
              .toString()
              .trim();

      if (name.isEmpty) {
        return 'مشروع بدون اسم';
      }

      return name;
    } catch (e) {
      debugPrint(
        'Error loading project name: $e',
      );

      return 'تعذر تحميل اسم المشروع';
    }
  }

  // ============================================================
  // تاريخ اليوم
  // ============================================================

  DateTime _today() {
    final DateTime now = DateTime.now();

    return DateTime(
      now.year,
      now.month,
      now.day,
    );
  }

  // ============================================================
  // هل انتهت المدة؟
  // ============================================================

  bool _isTimeEnded(
    DateTime endDate,
  ) {
    final DateTime today = _today();

    return today.isAfter(endDate) ||
        today.isAtSameMomentAs(endDate);
  }

  // ============================================================
  // إنشاء معرف للبيانات التي تم فحصها
  // ============================================================

  String _buildCheckSignature(
    Map<String, dynamic> item,
  ) {
    final double contractQuantity =
        _toDouble(
      item['contractQuantity'],
    );

    final double executedQuantity =
        _toDouble(
      item['executedQuantity'],
    );

    final DateTime? executionEndDate =
        _timestampToDate(
      item['executionEndDate'],
    );

    return [
      widget.itemId,
      contractQuantity,
      executedQuantity,
      executionEndDate?.millisecondsSinceEpoch,
    ].join('|');
  }

  // ============================================================
  // فحص الأعمال الإضافية
  // ============================================================

  Future<void> _checkAdditionalWorks(
    Map<String, dynamic> item,
  ) async {
    if (_checkingAdditionalWorks) {
      return;
    }

    final dynamic executionStartValue =
        item['executionStartDate'];

    final dynamic executionEndValue =
        item['executionEndDate'];

    if (executionStartValue == null ||
        executionEndValue == null) {
      return;
    }

    final DateTime? executionStartDate =
        _timestampToDate(
      executionStartValue,
    );

    final DateTime? executionEndDate =
        _timestampToDate(
      executionEndValue,
    );

    if (executionStartDate == null ||
        executionEndDate == null) {
      return;
    }

    final String signature =
        _buildCheckSignature(item);

    if (_lastCheckedSignature == signature) {
      return;
    }

    _lastCheckedSignature = signature;

    final double contractQuantity =
        _toDouble(
      item['contractQuantity'],
    );

    final double executedQuantity =
        _toDouble(
      item['executedQuantity'],
    );

    final String itemId = widget.itemId;

    final String projectId =
        item['projectId']?.toString().trim() ?? '';

    String itemName =
        item['name']?.toString().trim() ?? '';

    if (itemName.isEmpty) {
      itemName =
          item['typeName']?.toString().trim() ?? '';
    }

    if (itemName.isEmpty) {
      itemName = 'بدون اسم';
    }

    final String typeName =
        item['typeName']?.toString().trim() ??
            'بدون نوع';

    final String unit =
        item['unit']?.toString().trim() ?? '';

    final User? currentUser =
        FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return;
    }

    if (mounted) {
      setState(() {
        _checkingAdditionalWorks = true;
      });
    }

    try {
      final String projectName =
          await _getProjectName(projectId);

      // ==========================================================
      // الحالة الأولى:
      // الكمية تجاوزت الكمية التعاقدية
      // ==========================================================

      if (executedQuantity > contractQuantity) {
        final double additionalQuantity =
            executedQuantity - contractQuantity;

        await _firestore
            .collection('additional_works')
            .doc('${itemId}_quantity')
            .set(
          {
            'itemId': itemId,
            'projectId': projectId,
            'projectName': projectName,
            'itemName': itemName,
            'typeName': typeName,
            'reason': 'زيادة كمية',
            'additionalQuantity':
                additionalQuantity,
            'additionalDays': 0,
            'unit': unit,
            'status': 'pending',
            'updatedAt':
                FieldValue.serverTimestamp(),
            'createdBy': currentUser.uid,
          },
          SetOptions(merge: true),
        );
      }

      // ==========================================================
      // الحالة الثانية:
      // انتهى الوقت والكمية غير مكتملة
      // ==========================================================

      final bool timeEnded =
          _isTimeEnded(executionEndDate);

      final bool quantityIncomplete =
          executedQuantity < contractQuantity;

      if (timeEnded && quantityIncomplete) {
        final double additionalQuantity =
            contractQuantity - executedQuantity;

        final DateTime today = _today();

        int additionalDays = today
            .difference(executionEndDate)
            .inDays;

        if (additionalDays < 0) {
          additionalDays = 0;
        }

        await _firestore
            .collection('additional_works')
            .doc('${itemId}_time')
            .set(
          {
            'itemId': itemId,
            'projectId': projectId,
            'projectName': projectName,
            'itemName': itemName,
            'typeName': typeName,
            'reason':
                'انتهاء مدة العقد والكمية لم تنتهِ',
            'additionalQuantity':
                additionalQuantity,
            'additionalDays': additionalDays,
            'unit': unit,
            'status': 'pending',
            'updatedAt':
                FieldValue.serverTimestamp(),
            'createdBy': currentUser.uid,
          },
          SetOptions(merge: true),
        );
      }

      // ==========================================================
      // الحالة الثالثة:
      // الوقت انتهى والكمية مكتملة
      // ==========================================================

      if (timeEnded &&
          executedQuantity >= contractQuantity) {
        debugPrint(
          'انتهت المدة والكمية مكتملة، لا يوجد عمل إضافي.',
        );
      }
    } catch (e) {
      debugPrint(
        'Error checking additional works: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingAdditionalWorks = false;
        });
      }
    }
  }

  // ============================================================
  // حفظ التنفيذ
  // ============================================================

  Future<void> _saveExecution(
    Map<String, dynamic> item,
  ) async {
    if (_saving) {
      return;
    }

    final User? currentUser =
        FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      AppWidgets.showError(
        context,
        'المستخدم غير مسجل الدخول',
      );
      return;
    }

    final String quantityText =
        _quantityController.text.trim();

    if (quantityText.isEmpty) {
      AppWidgets.showWarning(
        context,
        'أدخل الكمية المنفذة',
      );
      return;
    }

    final double executionQuantity =
        double.tryParse(quantityText) ?? -1;

    if (executionQuantity <= 0) {
      AppWidgets.showWarning(
        context,
        'يجب أن تكون الكمية المنفذة أكبر من صفر',
      );
      return;
    }

    // ============================================================
    // بيانات البند
    // ============================================================

    final String projectId =
        item['projectId']?.toString().trim() ?? '';

    String itemName =
        item['name']?.toString().trim() ?? '';

    if (itemName.isEmpty) {
      itemName =
          item['typeName']?.toString().trim() ?? '';
    }

    if (itemName.isEmpty) {
      itemName = 'بدون اسم';
    }

    final String typeName =
        item['typeName']?.toString().trim() ??
            'بدون نوع';

    final String unit =
        item['unit']?.toString().trim() ?? '';

    final double oldExecutedQuantity =
        _toDouble(
      item['executedQuantity'],
    );

    final int durationDays =
        int.tryParse(
              item['durationDays']?.toString() ?? '',
            ) ??
            0;

    // ============================================================
    // التاريخ الحالي
    // ============================================================

    final DateTime now = DateTime.now();

    final DateTime executionDate = DateTime(
      now.year,
      now.month,
      now.day,
    );

    // ============================================================
    // الكمية التراكمية
    // ============================================================

    final double newExecutedQuantity =
        oldExecutedQuantity + executionQuantity;

    // ============================================================
    // اسم المشروع
    // ============================================================

    final String projectName =
        await _getProjectName(projectId);

    // ============================================================
    // تحديد بداية التنفيذ
    // ============================================================

    DateTime executionStartDate;

    final dynamic oldStartDate =
        item['executionStartDate'];

    if (oldStartDate is Timestamp) {
      executionStartDate =
          _timestampToDate(oldStartDate) ??
              executionDate;
    } else {
      executionStartDate = executionDate;
    }

    // ============================================================
    // نهاية التنفيذ
    // ============================================================

    final DateTime executionEndDate =
        executionStartDate.add(
      Duration(days: durationDays),
    );

    setState(() {
      _saving = true;
    });

    try {
      final DocumentReference<Map<String, dynamic>>
          itemRef = _firestore
              .collection('items')
              .doc(widget.itemId);

      final DocumentReference<Map<String, dynamic>>
          executionRef = _firestore
              .collection('item_executions')
              .doc();

      // ============================================================
      // Batch
      // ============================================================

      final WriteBatch batch =
          _firestore.batch();

      // ============================================================
      // تحديث البند
      // ============================================================

      batch.update(
        itemRef,
        {
          'executedQuantity':
              newExecutedQuantity,
          'executionStartDate':
              oldStartDate is Timestamp
                  ? oldStartDate
                  : Timestamp.fromDate(
                      executionStartDate,
                    ),
          'executionEndDate':
              Timestamp.fromDate(
            executionEndDate,
          ),
          'updatedAt':
              FieldValue.serverTimestamp(),
        },
      );

      // ============================================================
      // تسجيل عملية التنفيذ
      // ============================================================

      batch.set(
        executionRef,
        {
          'itemId': widget.itemId,
          'projectId': projectId,
          'projectName': projectName,
          'itemName': itemName,
          'typeName': typeName,
          'executedQuantity':
              executionQuantity,
          'executionDate':
              Timestamp.fromDate(
            executionDate,
          ),
          'unit': unit,
          'createdBy': currentUser.uid,
          'createdAt':
              FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();

      // ============================================================
      // بيانات البند بعد التحديث
      // ============================================================

      final Map<String, dynamic> updatedItem =
          Map<String, dynamic>.from(item);

      updatedItem['executedQuantity'] =
          newExecutedQuantity;

      updatedItem['executionStartDate'] =
          Timestamp.fromDate(
        executionStartDate,
      );

      updatedItem['executionEndDate'] =
          Timestamp.fromDate(
        executionEndDate,
      );

      // ============================================================
      // إعادة فحص الأعمال الإضافية
      // ============================================================

      _lastCheckedSignature = null;

      await _checkAdditionalWorks(
        updatedItem,
      );

      _quantityController.clear();

      if (!mounted) {
        return;
      }

      AppWidgets.showSuccess(
        context,
        'تم حفظ التنفيذ بنجاح',
      );
    } catch (e) {
      debugPrint(
        'Error saving execution: $e',
      );

      if (!mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء حفظ التنفيذ:\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ============================================================
  // بناء واجهة الصفحة
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'تنفيذ البند',
      child: StreamBuilder<
          DocumentSnapshot<Map<String, dynamic>>>(
        stream: _firestore
            .collection('items')
            .doc(widget.itemId)
            .snapshots(),
        builder: (
          context,
          snapshot,
        ) {
          // ========================================================
          // تحميل
          // ========================================================

          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const AppLoading(
              message: 'جاري تحميل بيانات البند...',
            );
          }

          // ========================================================
          // خطأ
          // ========================================================

          if (snapshot.hasError) {
            return AppError(
              message:
                  'حدث خطأ أثناء تحميل البند:\n'
                  '${snapshot.error}',
            );
          }

          // ========================================================
          // غير موجود
          // ========================================================

          if (!snapshot.hasData ||
              !snapshot.data!.exists) {
            return const AppEmpty(
              icon: Icons.inventory_2_outlined,
              message: 'البند غير موجود',
            );
          }

          // ========================================================
          // بيانات البند
          // ========================================================

          final Map<String, dynamic> item =
              snapshot.data!.data()!;

          // ========================================================
          // فحص الأعمال الإضافية
          // ========================================================

          final String currentSignature =
              _buildCheckSignature(item);

          if (_lastCheckedSignature !=
                  currentSignature &&
              !_checkingAdditionalWorks) {
            WidgetsBinding.instance
                .addPostFrameCallback(
              (_) {
                if (mounted) {
                  _checkAdditionalWorks(item);
                }
              },
            );
          }

          // ========================================================
          // اسم البند
          // ========================================================

          String itemName =
              item['name']?.toString().trim() ?? '';

          if (itemName.isEmpty) {
            itemName =
                item['typeName']?.toString().trim() ??
                    '';
          }

          if (itemName.isEmpty) {
            itemName =
                item['itemDefinitionName']
                        ?.toString()
                        .trim() ??
                    '';
          }

          if (itemName.isEmpty) {
            itemName = 'بدون اسم';
          }

          // ========================================================
          // النوع
          // ========================================================

          final String rawTypeName =
              item['typeName']?.toString().trim() ?? '';

          final String typeName =
              rawTypeName.isNotEmpty
                  ? rawTypeName
                  : 'بدون نوع';

          // ========================================================
          // المشروع
          // ========================================================

          final String projectId =
              item['projectId']?.toString().trim() ?? '';

          // ========================================================
          // الكميات
          // ========================================================

          final double contractQuantity =
              _toDouble(
            item['contractQuantity'],
          );

          final double executedQuantity =
              _toDouble(
            item['executedQuantity'],
          );

          final double remainingQuantity =
              (contractQuantity -
                      executedQuantity)
                  .clamp(
            0.0,
            double.infinity,
          );

          final double progress =
              contractQuantity <= 0
                  ? 0
                  : (executedQuantity /
                          contractQuantity)
                      .clamp(
                      0.0,
                      1.0,
                    );

          final double extraQuantity =
              executedQuantity >
                      contractQuantity
                  ? executedQuantity -
                      contractQuantity
                  : 0;

          // ========================================================
          // الوحدة
          // ========================================================

          final String unit =
              item['unit']?.toString().trim() ?? '';

          // ========================================================
          // مدة التنفيذ
          // ========================================================

          final int durationDays =
              int.tryParse(
                    item['durationDays']?.toString() ?? '',
                  ) ??
                  0;

          // ========================================================
          // التواريخ
          // ========================================================

          final String executionStartDate =
              _formatDate(
            item['executionStartDate'],
          );

          final String executionEndDate =
              _formatDate(
            item['executionEndDate'],
          );

          final String todayText =
              _formatDate(
            Timestamp.fromDate(
              _today(),
            ),
          );

          return FutureBuilder<String>(
            future: _getProjectName(projectId),
            builder: (
              context,
              projectSnapshot,
            ) {
              final String projectName =
                  projectSnapshot.data ??
                      'جاري تحميل المشروع...';

              return AppPage(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      // ==================================================
                      // رأس البند
                      // ==================================================

                      AppPageHeader(
                        title: itemName,
                        subtitle: 'النوع: $typeName',
                        icon: Icons.construction,
                        trailing: AppStatusBadge(
                          text:
                              'منفذ ${(progress * 100).toStringAsFixed(1)}%',
                          color: progress >= 1
                              ? AppColors.success
                              : AppColors.primary,
                        ),
                      ),

                      AppSpacing.verticalLg,

                      // ==================================================
                      // معلومات البند
                      // ==================================================

                      AppCard(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            const AppSectionTitle(
                              title: 'بيانات البند',
                              icon: Icons.info_outline,
                            ),

                            AppSpacing.verticalMd,

                            AppResponsiveGrid(
                              children: [
                                AppInfoRow(
                                  icon: Icons.business,
                                  label: 'المشروع',
                                  value: projectName,
                                ),
                                AppInfoRow(
                                  icon: Icons.tag,
                                  label: 'كود البند',
                                  value:
                                      item['code']
                                                  ?.toString()
                                                  .trim()
                                                  .isNotEmpty ==
                                              true
                                          ? item['code']
                                              .toString()
                                              .trim()
                                          : '-',
                                ),
                                AppInfoRow(
                                  icon: Icons.assignment,
                                  label: 'الكمية التعاقدية',
                                  value:
                                      '${_formatQuantity(contractQuantity)} $unit',
                                ),
                                AppInfoRow(
                                  icon: Icons.done_all,
                                  label: 'الكمية المنفذة',
                                  value:
                                      '${_formatQuantity(executedQuantity)} $unit',
                                ),
                                AppInfoRow(
                                  icon:
                                      Icons.pending_actions,
                                  label: 'الكمية المتبقية',
                                  value:
                                      '${_formatQuantity(remainingQuantity)} $unit',
                                ),
                                AppInfoRow(
                                  icon: Icons.timelapse,
                                  label: 'مدة التنفيذ',
                                  value: '$durationDays يوم',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      AppSpacing.verticalLg,

                      // ==================================================
                      // نسبة الإنجاز
                      // ==================================================

                      AppCard(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'نسبة الإنجاز',
                                  style:
                                      AppTextStyles.sectionTitle,
                                ),
                                Text(
                                  '${(progress * 100).toStringAsFixed(1)}%',
                                  style:
                                      AppTextStyles.body.copyWith(
                                    color: progress >= 1
                                        ? AppColors.success
                                        : AppColors.primary,
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),

                            AppSpacing.verticalMd,

                            AppProgress(
                              value: progress,
                            ),

                            AppSpacing.verticalSm,

                            Text(
                              'تم تنفيذ ${_formatQuantity(executedQuantity)} من أصل ${_formatQuantity(contractQuantity)} $unit',
                              style:
                                  AppTextStyles.bodySecondary,
                            ),
                          ],
                        ),
                      ),

                      AppSpacing.verticalLg,

                      // ==================================================
                      // التواريخ
                      // ==================================================

                      AppCard(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            const AppSectionTitle(
                              title: 'تواريخ التنفيذ',
                              icon:
                                  Icons.calendar_month,
                            ),

                            AppSpacing.verticalMd,

                            AppResponsiveGrid(
                              children: [
                                AppInfoRow(
                                  icon: Icons.play_circle_outline,
                                  label: 'بداية التنفيذ',
                                  value:
                                      executionStartDate,
                                ),
                                AppInfoRow(
                                  icon:
                                      Icons.event_available,
                                  label: 'نهاية التنفيذ',
                                  value:
                                      executionEndDate,
                                ),
                                AppInfoRow(
                                  icon: Icons.today,
                                  label: 'تاريخ اليوم',
                                  value: todayText,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // ==================================================
                      // الأعمال الإضافية
                      // ==================================================

                      if (extraQuantity > 0) ...[
                        AppSpacing.verticalLg,

                        AppCard(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.warning
                                  .withValues(
                                alpha: 0.08,
                              ),
                              borderRadius:
                                  BorderRadius.circular(12),
                            ),
                            padding:
                                const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons
                                          .warning_amber_rounded,
                                      color:
                                          AppColors.warning,
                                    ),
                                    AppSpacing.horizontalSm,
                                    const Expanded(
                                      child: Text(
                                        'أعمال إضافية بسبب زيادة الكمية',
                                        style:
                                            AppTextStyles.sectionTitle,
                                      ),
                                    ),
                                  ],
                                ),

                                AppSpacing.verticalMd,

                                Text(
                                  'الكمية الإضافية: '
                                  '${_formatQuantity(extraQuantity)} $unit',
                                  style:
                                      AppTextStyles.body.copyWith(
                                    fontWeight:
                                        FontWeight.bold,
                                    color:
                                        AppColors.warning,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      // ==================================================
                      // فحص الأعمال الإضافية
                      // ==================================================

                      if (_checkingAdditionalWorks) ...[
                        AppSpacing.verticalMd,

                        AppCard(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.info
                                  .withValues(
                                alpha: 0.06,
                              ),
                              borderRadius:
                                  BorderRadius.circular(12),
                            ),
                            padding:
                                const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        AppColors.info,
                                  ),
                                ),

                                AppSpacing.horizontalMd,

                                const Expanded(
                                  child: Text(
                                    'جاري فحص الأعمال الإضافية...',
                                    style:
                                        AppTextStyles.body,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      AppSpacing.verticalLg,

                      // ==================================================
                      // إضافة تنفيذ
                      // ==================================================

                      const AppSectionTitle(
                        title: 'إضافة تنفيذ جديد',
                        icon: Icons.add_task,
                      ),

                      AppSpacing.verticalMd,

                      AppCard(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            // ==========================================
                            // تاريخ التنفيذ
                            // ==========================================

                            AppCard(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.primary
                                      .withValues(
                                    alpha: 0.06,
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                                padding:
                                    const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      color:
                                          AppColors.primary,
                                    ),
                                    AppSpacing.horizontalMd,
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'تاريخ التنفيذ',
                                            style:
                                                AppTextStyles.body,
                                          ),

                                          AppSpacing.verticalXs,

                                          Text(
                                            todayText,
                                            style:
                                                AppTextStyles.cardTitle,
                                          ),

                                          AppSpacing.verticalXs,

                                          const Text(
                                            'يتم أخذ التاريخ تلقائيًا من جهاز المهندس.',
                                            style:
                                                AppTextStyles.small,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            AppSpacing.verticalMd,

                            // ==========================================
                            // حقل الكمية
                            // ==========================================

                            AppNumberField(
                              controller:
                                  _quantityController,
                              label: 'الكمية المنفذة',
                              hint: 'أدخل الكمية',
                              suffixText:
                                  unit.isEmpty ? null : unit,
                              validator: (value) {
                                if (value == null ||
                                    value.trim().isEmpty) {
                                  return 'أدخل الكمية المنفذة';
                                }

                                final double? quantity =
                                    double.tryParse(
                                  value.trim(),
                                );

                                if (quantity == null ||
                                    quantity <= 0) {
                                  return 'أدخل كمية صحيحة أكبر من صفر';
                                }

                                return null;
                              },
                              enabled: !_saving,
                            ),

                            AppSpacing.verticalMd,

                            // ==========================================
                            // الكمية الحالية
                            // ==========================================

                            AppInfoRow(
                              icon: Icons.inventory_2,
                              label: 'الكمية الحالية',
                              value:
                                  '${_formatQuantity(executedQuantity)} $unit',
                            ),

                            AppSpacing.verticalLg,

                            // ==========================================
                            // زر الحفظ
                            // ==========================================

                            AppButton(
                              text: 'حفظ التنفيذ',
                              icon: Icons.save,
                              loading: _saving,
                              expanded: true,
                              onPressed: () =>
                                  _saveExecution(item),
                            ),
                          ],
                        ),
                      ),

                      AppSpacing.verticalLg,
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
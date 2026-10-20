import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

import 'engineer_item_page.dart';

class EngineerPage extends StatelessWidget {
  const EngineerPage({
    super.key,
  });

  // ============================================================
  // Firestore
  // ============================================================

  FirebaseFirestore get _firestore =>
      FirebaseFirestore.instance;

  // ============================================================
  // جلب البنود المسندة للمهندس الحالي
  // ============================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> itemsStream() {
    final User? currentUser =
        FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Stream.empty();
    }

    return _firestore
        .collection('items')
        .where(
          'engineerId',
          isEqualTo: currentUser.uid,
        )
        .where(
          'status',
          isEqualTo: 'active',
        )
        .snapshots();
  }

  // ============================================================
  // جلب اسم المشروع
  // ============================================================

  Future<String> getProjectName(
    String projectId,
  ) async {
    if (projectId.isEmpty) {
      return 'مشروع غير محدد';
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> projectDoc =
          await _firestore
              .collection('projects')
              .doc(projectId)
              .get();

      if (!projectDoc.exists) {
        return 'مشروع غير موجود';
      }

      final Map<String, dynamic> data =
          projectDoc.data() ?? {};

      final String projectName =
          (data['name'] ??
                  data['projectName'] ??
                  data['title'] ??
                  '')
              .toString()
              .trim();

      if (projectName.isEmpty) {
        return 'مشروع بدون اسم';
      }

      return projectName;
    } catch (e) {
      debugPrint(
        'Error loading project $projectId: $e',
      );

      return 'تعذر تحميل اسم المشروع';
    }
  }

  // ============================================================
  // تحويل الرقم إلى double
  // ============================================================

  double _toDouble(
    dynamic value,
  ) {
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

  String _formatQuantity(
    double value,
  ) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(2);
  }

  // ============================================================
  // تنسيق التاريخ
  // ============================================================

  String _formatDate(
    dynamic value,
  ) {
    if (value == null) {
      return 'غير محدد';
    }

    if (value is Timestamp) {
      final DateTime date = value.toDate();

      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    }

    return 'غير محدد';
  }

  // ============================================================
  // واجهة الصفحة
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final User? currentUser =
        FirebaseAuth.instance.currentUser;

    return AppScaffold(
      title: 'بنودي',
      child: currentUser == null
          ? const _NotLoggedInView()
          : StreamBuilder<
              QuerySnapshot<Map<String, dynamic>>>(
              stream: itemsStream(),
              builder: (
                context,
                snapshot,
              ) {
                // ==================================================
                // تحميل
                // ==================================================

                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const AppLoading(
                    message: 'جاري تحميل البنود...',
                  );
                }

                // ==================================================
                // خطأ
                // ==================================================

                if (snapshot.hasError) {
                  return AppError(
                    message:
                        'حدث خطأ أثناء تحميل البنود:\n'
                        '${snapshot.error}',
                  );
                }

                // ==================================================
                // البنود
                // ==================================================

                final List<
                        QueryDocumentSnapshot<
                            Map<String, dynamic>>>
                    documents =
                    snapshot.data?.docs ?? [];

                // ==================================================
                // لا توجد بنود
                // ==================================================

                if (documents.isEmpty) {
                  return const _EmptyEngineerItemsView();
                }

                // ==================================================
                // عرض البنود
                // ==================================================

                return AppPage(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      AppPageHeader(
                        title: 'البنود المسندة إليك',
                        subtitle:
                            'البنود التي تم تعيينك كمهندس مسؤول عنها',
                        icon: Icons.engineering,
                        trailing: AppStatusBadge(
                          text: '${documents.length} بند',
                          color: AppColors.primary,
                        ),
                      ),

                      AppSpacing.verticalLg,

                      ...documents.map(
                        (doc) {
                          final Map<String, dynamic> data =
                              doc.data();

                          // ==================================================
                          // المشروع
                          // ==================================================

                          final String projectId =
                              data['projectId']
                                      ?.toString()
                                      .trim() ??
                                  '';

                          // ==================================================
                          // اسم البند
                          // ==================================================

                          String itemName =
                              data['name']
                                      ?.toString()
                                      .trim() ??
                                  '';

                          if (itemName.isEmpty) {
                            itemName =
                                data['typeName']
                                        ?.toString()
                                        .trim() ??
                                    '';
                          }

                          if (itemName.isEmpty) {
                            itemName =
                                data['itemDefinitionName']
                                        ?.toString()
                                        .trim() ??
                                    '';
                          }

                          if (itemName.isEmpty) {
                            itemName = 'بدون اسم';
                          }

                          // ==================================================
                          // النوع
                          // ==================================================

                          final String rawTypeName =
                              data['typeName']
                                      ?.toString()
                                      .trim() ??
                                  '';

                          final String typeName =
                              rawTypeName.isNotEmpty
                                  ? rawTypeName
                                  : 'بدون نوع';

                          return _EngineerItemCard(
                            data: data,
                            itemId: doc.id,
                            itemName: itemName,
                            typeName: typeName,
                            projectNameFuture:
                                getProjectName(projectId),
                            toDouble: _toDouble,
                            formatQuantity:
                                _formatQuantity,
                            formatDate: _formatDate,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      EngineerItemPage(
                                    itemId: doc.id,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ============================================================
// بطاقة البند
// ============================================================

class _EngineerItemCard extends StatelessWidget {
  final Map<String, dynamic> data;

  final String itemId;

  final String itemName;

  final String typeName;

  final Future<String> projectNameFuture;

  final double Function(dynamic) toDouble;

  final String Function(double) formatQuantity;

  final String Function(dynamic) formatDate;

  final VoidCallback onTap;

  const _EngineerItemCard({
    required this.data,
    required this.itemId,
    required this.itemName,
    required this.typeName,
    required this.projectNameFuture,
    required this.toDouble,
    required this.formatQuantity,
    required this.formatDate,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    // ============================================================
    // البيانات
    // ============================================================

    final String code =
        data['code']
                ?.toString()
                .trim() ??
            '-';

    final String unit =
        data['unit']
                ?.toString()
                .trim() ??
            '';

    final double contractQuantity =
        toDouble(
      data['contractQuantity'],
    );

    final double executedQuantity =
        toDouble(
      data['executedQuantity'],
    );

    // ============================================================
    // الكمية المتبقية
    // ============================================================

    final double remaining =
        contractQuantity -
            executedQuantity;

    final double remainingQuantity =
        remaining > 0
            ? remaining
            : 0.0;

    // ============================================================
    // نسبة الإنجاز
    // ============================================================

    final double progress =
        contractQuantity <= 0
            ? 0.0
            : (executedQuantity /
                    contractQuantity)
                .clamp(
                  0.0,
                  1.0,
                )
                .toDouble();

    // ============================================================
    // الكمية الإضافية
    // ============================================================

    final double extraQuantity =
        executedQuantity >
                contractQuantity
            ? executedQuantity -
                contractQuantity
            : 0.0;

    // ============================================================
    // الحالة
    // ============================================================

    final String status =
        data['status']
                ?.toString() ??
            'active';

    final bool isActive =
        status == 'active';

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          // ========================================================
          // المشروع
          // ========================================================

          FutureBuilder<String>(
            future: projectNameFuture,
            builder: (
              context,
              snapshot,
            ) {
              final String projectName =
                  snapshot.data ??
                      'جاري تحميل المشروع...';

              return Row(
                children: [
                  const Icon(
                    Icons.business,
                    size: 20,
                    color: AppColors.primary,
                  ),

                  AppSpacing.horizontalSm,

                  Expanded(
                    child: Text(
                      projectName,
                      style:
                          AppTextStyles.bodySecondary
                              .copyWith(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          AppSpacing.verticalMd,

          const Divider(),

          AppSpacing.verticalMd,

          // ========================================================
          // اسم البند
          // ========================================================

          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.all(10),
                decoration:
                    BoxDecoration(
                  color: AppColors.primary
                      .withValues(
                    alpha: 0.08,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),
                ),
                child: const Icon(
                  Icons.construction,
                  size: 30,
                  color: AppColors.primary,
                ),
              ),

              AppSpacing.horizontalMd,

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemName,
                      style:
                          AppTextStyles.cardTitle
                              .copyWith(
                        fontSize: 19,
                      ),
                    ),

                    AppSpacing.verticalXs,

                    Row(
                      children: [
                        const Icon(
                          Icons.list_alt,
                          size: 17,
                          color:
                              AppColors.textSecondary,
                        ),

                        AppSpacing.horizontalXs,

                        Expanded(
                          child: Text(
                            'النوع: $typeName',
                            style:
                                AppTextStyles.bodySecondary
                                    .copyWith(
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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
            ],
          ),

          AppSpacing.verticalLg,

          // ========================================================
          // الحالة
          // ========================================================

          Row(
            children: [
              const Icon(
                Icons.info_outline,
                size: 20,
                color: AppColors.info,
              ),

              AppSpacing.horizontalSm,

              const Text(
                'الحالة:',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),

              AppSpacing.horizontalSm,

              AppStatusBadge(
                text: isActive
                    ? 'نشط'
                    : status,
                color: isActive
                    ? AppColors.success
                    : AppColors.warning,
              ),
            ],
          ),

          AppSpacing.verticalLg,

          // ========================================================
          // الكميات
          // ========================================================

          AppResponsiveGrid(
            children: [
              AppInfoRow(
                icon: Icons.assignment,
                label: 'الكمية التعاقدية',
                value:
                    '${formatQuantity(contractQuantity)} $unit',
              ),

              AppInfoRow(
                icon: Icons.done_all,
                label: 'الكمية المنفذة',
                value:
                    '${formatQuantity(executedQuantity)} $unit',
              ),

              AppInfoRow(
                icon: Icons.pending_actions,
                label: 'المتبقي',
                value:
                    '${formatQuantity(remainingQuantity)} $unit',
              ),

              AppInfoRow(
                icon: Icons.timelapse,
                label: 'مدة العقد',
                value:
                    data['durationDays'] == null
                        ? 'غير محددة'
                        : '${data['durationDays']} يوم',
              ),
            ],
          ),

          AppSpacing.verticalLg,

          // ========================================================
          // نسبة الإنجاز
          // ========================================================

          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'نسبة الإنجاز',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),

              Text(
                '${(progress * 100).toStringAsFixed(1)}%',
                style: AppTextStyles.body.copyWith(
                  color:
                      AppColors.primary,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ],
          ),

          AppSpacing.verticalSm,

          AppProgress(
            value: progress,
            color: progress >= 1
                ? AppColors.success
                : AppColors.primary,
            backgroundColor:
                AppColors.primary
                    .withValues(
              alpha: 0.10,
            ),
            height: 8,
          ),

          AppSpacing.verticalLg,

          // ========================================================
          // التواريخ
          // ========================================================

          const AppSectionTitle(
            title: 'تواريخ العقد والتنفيذ',
            icon: Icons.calendar_month,
          ),

          AppSpacing.verticalMd,

          AppResponsiveGrid(
            children: [
              AppInfoRow(
                icon: Icons.calendar_today,
                label: 'بداية العقد',
                value:
                    formatDate(
                  data['contractStartDate'],
                ),
              ),

              AppInfoRow(
                icon: Icons.event,
                label: 'نهاية العقد',
                value:
                    formatDate(
                  data['contractEndDate'],
                ),
              ),

              AppInfoRow(
                icon:
                    Icons.play_circle_outline,
                label: 'بداية التنفيذ',
                value:
                    formatDate(
                  data['executionStartDate'],
                ),
              ),

              AppInfoRow(
                icon:
                    Icons.event_available,
                label: 'نهاية التنفيذ',
                value:
                    formatDate(
                  data['executionEndDate'],
                ),
              ),
            ],
          ),

          // ========================================================
          // الأعمال الإضافية
          // ========================================================

          if (extraQuantity > 0) ...[
            AppSpacing.verticalLg,

            AppCard(
              color: AppColors.warning
                  .withValues(
                alpha: 0.08,
              ),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color:
                        AppColors.warning,
                  ),

                  AppSpacing.horizontalMd,

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'أعمال إضافية',
                          style:
                              AppTextStyles.sectionTitle,
                        ),

                        AppSpacing.verticalXs,

                        Text(
                          'الكمية الإضافية: '
                          '${formatQuantity(extraQuantity)} $unit',
                          style:
                              AppTextStyles.body.copyWith(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          AppSpacing.verticalLg,

          // ========================================================
          // فتح صفحة التنفيذ
          // ========================================================

          AppButton(
            label:
                'عرض البند وإضافة التنفيذ',
            icon: Icons.visibility,
            onPressed: onTap,
            expanded: true,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// لا يوجد بنود
// ============================================================

class _EmptyEngineerItemsView
    extends StatelessWidget {
  const _EmptyEngineerItemsView();

  @override
  Widget build(
    BuildContext context,
  ) {
    return AppPage(
      child: Center(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Container(
              padding:
                  const EdgeInsets.all(20),
              decoration:
                  BoxDecoration(
                color: AppColors.primary
                    .withValues(
                  alpha: 0.08,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.engineering,
                size: 70,
                color: AppColors.primary,
              ),
            ),

            AppSpacing.verticalLg,

            const Text(
              'لا توجد بنود مسجلة لك',
              textAlign:
                  TextAlign.center,
              style:
                  AppTextStyles.pageTitle,
            ),

            AppSpacing.verticalSm,

            const Text(
              'ستظهر هنا البنود التي تم تعيينك كمهندس مسؤول عنها.',
              textAlign:
                  TextAlign.center,
              style:
                  AppTextStyles.bodySecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// المستخدم غير مسجل الدخول
// ============================================================

class _NotLoggedInView
    extends StatelessWidget {
  const _NotLoggedInView();

  @override
  Widget build(
    BuildContext context,
  ) {
    return AppPage(
      child: Center(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock_outline,
              size: 70,
              color: AppColors.warning,
            ),

            AppSpacing.verticalLg,

            const Text(
              'المستخدم غير مسجل الدخول',
              textAlign:
                  TextAlign.center,
              style:
                  AppTextStyles.pageTitle,
            ),
          ],
        ),
      ),
    );
  }
}
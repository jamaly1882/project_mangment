
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/costs.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/cost_widgets.dart';
import 'items_page.dart';

// =============================================================
// لوحة مدير المشروع
// =============================================================
// صلاحيات مدير المشروع في هذه الصفحة:
// 1. بيانات المشروع
// 2. عدد البنود
// 3. صفحة البنود
//
// لا تظهر هنا:
// - الأعمال الإضافية
// - المهندسون
// - السائقون
//
// ويتم التعامل مع باقي الأقسام من خلال الأدوار المخصصة لها.
// =============================================================

class ProjectManagerDashboardPage extends StatelessWidget {
  final String projectId;

  const ProjectManagerDashboardPage({
    super.key,
    required this.projectId,
  });

  FirebaseFirestore get firestore => FirebaseFirestore.instance;

  // =============================================================
  // جلب بيانات المشروع
  // =============================================================

  Future<DocumentSnapshot<Map<String, dynamic>>> getProject() {
    return firestore.collection('projects').doc(projectId).get();
  }

  // =============================================================
  // حساب عدد البنود
  // =============================================================

  Future<int> countItems() async {
    final snapshot = await firestore
        .collection('items')
        .where(
          'projectId',
          isEqualTo: projectId,
        )
        .get();

    return snapshot.size;
  }

  // =============================================================
  // فتح صفحة البنود
  // =============================================================

  void openItemsPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemsPage(
          projectId: projectId,
        ),
      ),
    );
  }

  // =============================================================
  // تسجيل الخروج
  // =============================================================

  Future<void> logout(BuildContext context) async {
    final confirmed = await AppWidgets.showConfirmDialog(
      context: context,
      title: 'تسجيل الخروج',
      message: 'هل تريد تسجيل الخروج من النظام؟',
      confirmText: 'تسجيل الخروج',
      cancelText: 'إلغاء',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await FirebaseAuth.instance.signOut();

      if (!context.mounted) {
        return;
      }

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/',
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء تسجيل الخروج:\n$e',
      );
    }
  }

  // =============================================================
  // نص حالة المشروع
  // =============================================================

  String projectStatusText(dynamic status) {
    switch (status) {
      case 'active':
        return 'جاري';

      case 'completed':
        return 'مكتمل';

      case 'suspended':
        return 'متوقف';

      case 'cancelled':
        return 'ملغي';

      default:
        return status?.toString() ?? 'غير محدد';
    }
  }

  // =============================================================
  // لون حالة المشروع
  // =============================================================

  Color projectStatusColor(dynamic status) {
    switch (status) {
      case 'active':
        return AppColors.success;

      case 'completed':
        return AppColors.primary;

      case 'suspended':
        return AppColors.warning;

      case 'cancelled':
        return AppColors.danger;

      default:
        return AppColors.textSecondary;
    }
  }

  // =============================================================
  // القائمة الجانبية
  // =============================================================

  Widget _buildDrawer(BuildContext context) {
    return AppDrawer(
      userName: 'مدير المشروع',
      roleName: 'مدير المشروع',
      projectName: 'مشروع: $projectId',
      items: [
        // ---------------------------------------------------------
        // الرئيسية
        // ---------------------------------------------------------

        AppDrawerItem(
          icon: Icons.dashboard,
          title: 'الرئيسية',
          selected: true,
          onTap: () {},
        ),

        // ---------------------------------------------------------
        // البنود
        // ---------------------------------------------------------

        AppDrawerItem(
          icon: Icons.list_alt,
          title: 'البنود',
          onTap: () {
            openItemsPage(context);
          },
        ),
      ],
      onLogout: () {
        logout(context);
      },
    );
  }

  // =============================================================
  // معلومات المشروع
  // =============================================================

  Widget _buildProjectInfo({
    required String projectName,
    required String projectCode,
    required dynamic projectStatus,
    String? governorateName,
    String? districtName,
    String? managerName,
  }) {
    final statusColor = projectStatusColor(projectStatus);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // -------------------------------------------------------
          // اسم المشروع
          // -------------------------------------------------------

          Row(
            children: [
              Container(
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: AppColors.primary.withValues(
                    alpha: 0.10,
                  ),
                ),
                child: const Icon(
                  Icons.business,
                  size: 35,
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
                      projectName,
                      style: AppTextStyles.pageTitle,
                    ),

                    AppSpacing.verticalXs,

                    Text(
                      'كود المشروع: $projectCode',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ],
                ),
              ),
            ],
          ),

          AppSpacing.verticalMd,

          const Divider(),

          AppSpacing.verticalSm,

          // -------------------------------------------------------
          // حالة المشروع
          // -------------------------------------------------------

          Row(
            children: [
              const Icon(
                Icons.info_outline,
                size: 20,
                color: AppColors.textSecondary,
              ),

              AppSpacing.horizontalSm,

              const Text(
                'حالة المشروع:',
                style: AppTextStyles.body,
              ),

              AppSpacing.horizontalSm,

              AppStatusBadge(
                text: projectStatusText(projectStatus),
                color: statusColor,
              ),
            ],
          ),

          // -------------------------------------------------------
          // المحافظة
          // -------------------------------------------------------

          if (governorateName != null &&
              governorateName.isNotEmpty) ...[
            AppSpacing.verticalSm,

            AppInfoRow(
              icon: Icons.location_city,
              label: 'المحافظة',
              value: governorateName,
            ),
          ],

          // -------------------------------------------------------
          // المديرية
          // -------------------------------------------------------

          if (districtName != null &&
              districtName.isNotEmpty) ...[
            AppSpacing.verticalSm,

            AppInfoRow(
              icon: Icons.location_on,
              label: 'المديرية',
              value: districtName,
            ),
          ],

          // -------------------------------------------------------
          // مدير المشروع
          // -------------------------------------------------------

          if (managerName != null &&
              managerName.isNotEmpty) ...[
            AppSpacing.verticalSm,

            AppInfoRow(
              icon: Icons.person,
              label: 'مدير المشروع',
              value: managerName,
            ),
          ],
        ],
      ),
    );
  }

  // =============================================================
  // بطاقة تكاليف المشروع
  // =============================================================

  Widget _buildCostsSection(Map<String, dynamic> project) {
    final planned = ProjectCosts.breakdownOf(project);
    final plannedTotal = ProjectCosts.totalOf(project);

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: firestore
          .collection('items')
          .where(
            'projectId',
            isEqualTo: projectId,
          )
          .get(),
      builder: (context, snapshot) {
        final assigned = <String, double>{
          for (final category in ProjectCosts.categories)
            category.key: 0.0,
        };

        double assignedTotal = 0;

        for (final doc in snapshot.data?.docs ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
          final breakdown = ProjectCosts.breakdownOf(doc.data());

          for (final entry in breakdown.entries) {
            assigned[entry.key] =
                (assigned[entry.key] ?? 0) + entry.value;
            assignedTotal += entry.value;
          }
        }

        final remaining = plannedTotal - assignedTotal;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CostSummaryCard(
              title: 'تكاليف المشروع مقابل تكاليف البنود',
              breakdown: assigned,
              total: assignedTotal,
              reference: planned,
              referenceLabel: 'المخطط للمشروع',
              icon: Icons.payments_outlined,
            ),

            AppSpacing.verticalMd,

            AppCard(
              color: plannedTotal <= 0
                  ? AppColors.background
                  : (remaining < 0
                      ? AppColors.danger.withValues(alpha: 0.06)
                      : AppColors.success.withValues(alpha: 0.06)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppInfoRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'إجمالي مخطط للمشروع',
                    value: plannedTotal > 0
                        ? ProjectCosts.formatMoney(plannedTotal)
                        : 'لم يحدده مسؤول النظام بعد',
                  ),
                  AppSpacing.verticalXs,
                  AppInfoRow(
                    icon: Icons.assignment_outlined,
                    label: 'مجموع تكاليف البنود',
                    value: ProjectCosts.formatMoney(assignedTotal),
                  ),
                  AppSpacing.verticalXs,
                  if (plannedTotal > 0)
                    AppInfoRow(
                      icon: remaining < 0
                          ? Icons.warning_amber_rounded
                          : Icons.savings_outlined,
                      label: remaining < 0
                          ? 'تجاوز المخطط'
                          : 'المتبقي من المخطط',
                      value: ProjectCosts.formatMoney(
                        remaining.abs(),
                      ),
                    )
                  else
                    const Text(
                      'أضف تكاليف المشروع من صفحة المشاريع لدى مسؤول '
                      'النظام ليتم مقارنتها بتكاليف البنود.',
                      style: AppTextStyles.bodySecondary,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // =============================================================
  // بطاقة إحصائية: عدد البنود
  // =============================================================

  Widget _buildItemsStatisticCard(
    BuildContext context,
  ) {
    return FutureBuilder<int>(
      future: countItems(),
      builder: (
        context,
        snapshot,
      ) {
        final value = snapshot.hasData
            ? '${snapshot.data}'
            : snapshot.hasError
                ? '—'
                : '...';

        return AppStatCard(
          title: 'البنود',
          value: value,
          icon: Icons.list_alt,
          onTap: () {
            openItemsPage(context);
          },
        );
      },
    );
  }

  // =============================================================
  // بطاقة إدارة البنود
  // =============================================================

  Widget _buildItemsManagementCard(
    BuildContext context,
  ) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          openItemsPage(context);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // ---------------------------------------------------
              // الأيقونة
              // ---------------------------------------------------

              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.list_alt,
                  color: AppColors.primary,
                  size: 25,
                ),
              ),

              AppSpacing.horizontalMd,

              // ---------------------------------------------------
              // النص
              // ---------------------------------------------------

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'البنود',
                      style: AppTextStyles.cardTitle,
                    ),

                    AppSpacing.verticalXs,

                    Text(
                      'إضافة ومتابعة بنود المشروع',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ],
                ),
              ),

              // ---------------------------------------------------
              // السهم
              // ---------------------------------------------------

              const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =============================================================
  // بناء الصفحة
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'لوحة مدير المشروع',
      drawer: _buildDrawer(context),
      child: FutureBuilder<
          DocumentSnapshot<Map<String, dynamic>>>(
        future: getProject(),
        builder: (
          context,
          projectSnapshot,
        ) {
          // -------------------------------------------------------
          // جاري التحميل
          // -------------------------------------------------------

          if (projectSnapshot.connectionState ==
              ConnectionState.waiting) {
            return const SizedBox(
              height: 500,
              child: AppLoading(
                message: 'جاري تحميل بيانات المشروع...',
              ),
            );
          }

          // -------------------------------------------------------
          // حدث خطأ
          // -------------------------------------------------------

          if (projectSnapshot.hasError) {
            return SizedBox(
              height: 500,
              child: AppError(
                message:
                    'حدث خطأ أثناء تحميل المشروع:\n'
                    '${projectSnapshot.error}',
              ),
            );
          }

          // -------------------------------------------------------
          // المشروع غير موجود
          // -------------------------------------------------------

          if (!projectSnapshot.hasData ||
              !projectSnapshot.data!.exists) {
            return const SizedBox(
              height: 500,
              child: AppEmpty(
                icon: Icons.error_outline,
                message: 'المشروع غير موجود',
              ),
            );
          }

          // -------------------------------------------------------
          // بيانات المشروع
          // -------------------------------------------------------

          final project =
              projectSnapshot.data!.data() ?? {};

          final projectName =
              project['name']?.toString() ?? 'بدون اسم';

          final projectCode =
              project['code']?.toString() ?? '-';

          final projectStatus =
              project['status'];

          final governorateName =
              project['governorateName']?.toString();

          final districtName =
              project['districtName']?.toString();

          final managerName =
              project['managerName']?.toString();

          // -------------------------------------------------------
          // محتوى الصفحة
          // -------------------------------------------------------

          return RefreshIndicator(
            onRefresh: () async {
              await Future.delayed(
                const Duration(milliseconds: 300),
              );
            },
            child: SingleChildScrollView(
              physics:
                  const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  // =================================================
                  // 1. بيانات المشروع
                  // =================================================

                  _buildProjectInfo(
                    projectName: projectName,
                    projectCode: projectCode,
                    projectStatus: projectStatus,
                    governorateName:
                        governorateName,
                    districtName:
                        districtName,
                    managerName:
                        managerName,
                  ),

                  AppSpacing.verticalXl,

                  // =================================================
                  // 2. تكاليف المشروع
                  // =================================================

                  Text(
                    'تكاليف المشروع',
                    style: AppTextStyles.sectionTitle,
                  ),

                  AppSpacing.verticalMd,

                  _buildCostsSection(project),

                  AppSpacing.verticalXl,

                  // =================================================
                  // 3. عدد البنود
                  // =================================================

                  Text(
                    'إحصائيات المشروع',
                    style: AppTextStyles.sectionTitle,
                  ),

                  AppSpacing.verticalMd,

                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 300,
                      child: _buildItemsStatisticCard(
                        context,
                      ),
                    ),
                  ),

                  AppSpacing.verticalXl,

                  // =================================================
                  // 4. صفحة البنود
                  // =================================================

                  Text(
                    'إدارة المشروع',
                    style: AppTextStyles.sectionTitle,
                  ),

                  AppSpacing.verticalMd,

                  _buildItemsManagementCard(
                    context,
                  ),

                  AppSpacing.verticalLg,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}


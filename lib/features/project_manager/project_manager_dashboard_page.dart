
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/project_cost_sync.dart';
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
  // عرض بنود المشروع (قراءة وإحصاءات)
  //
  // إضافة البنود والكميات التعاقدية والتكاليف صلاحية مدير إدارة
  // الجودة، وتسجيل الكميات المنفذة صلاحية مشرف البند؛ فلا تُعرض
  // هنا أي أزرار إدخال.
  // =============================================================

  void openItemsPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        // مهندس المشروع للعرض والإحصاءات فقط: الإدخال صلاحية
        // مدير إدارة الجودة، وتسجيل الكميات صلاحية مشرف البند.
        builder: (_) => ItemsPage(
          projectId: projectId,
          readOnly: true,
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
  // بطاقة تكاليف المشروع (محسوبة من تكاليف البنود)
  // =============================================================

  Widget _buildCostsSection(Map<String, dynamic> project) {
    return FutureBuilder<ProjectCostTotals>(
      future: ProjectCostSync.totalsFor(projectId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppError(
            message:
                'تعذر حساب تكاليف المشروع من بنوده:\n${snapshot.error}',
          );
        }

        final totals =
            snapshot.data ?? ProjectCostTotals.empty();

        final storedTotal = ProjectCosts.totalOf(project);

        final plannedTotal = snapshot.hasData
            ? totals.total
            : storedTotal;

        // الإجمالي المعروض: الفعلي عند توفره، وإلا المخطط.
        final displayTotal = snapshot.hasData
            ? totals.displayTotal
            : storedTotal;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CostSummaryCard(
              title: totals.hasActual
                  ? 'تكاليف المشروع — الفعلي مقابل المخطط'
                  : 'تكاليف المشروع — محسوبة من بنوده',
              breakdown: !snapshot.hasData
                  ? ProjectCosts.breakdownOf(project)
                  : (totals.hasActual
                      ? totals.actualBreakdown
                      : totals.breakdown),
              reference: snapshot.hasData && totals.hasActual
                  ? totals.breakdown
                  : null,
              referenceLabel: 'المخطط',
              total: displayTotal,
              icon: Icons.payments_outlined,
            ),

            AppSpacing.verticalMd,

            AppCard(
              color: AppColors.background,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  AppInfoRow(
                    icon: Icons.list_alt,
                    label: 'بنود المشروع',
                    value: snapshot.hasData
                        ? '${totals.itemCount} بند، '
                            '${totals.costedItemCount} له تكلفة '
                            'مخططة، و${totals.actualItemCount} '
                            'له تكلفة فعلية'
                        : 'جاري الحساب...',
                  ),

                  AppSpacing.verticalXs,

                  AppInfoRow(
                    icon: Icons.timeline_outlined,
                    label: 'الإجمالي المخطط (إدخال مدير المشروع)',
                    value: ProjectCosts.formatMoney(plannedTotal),
                  ),

                  AppSpacing.verticalXs,

                  AppInfoRow(
                    icon: Icons.check_circle_outline,
                    label: 'الإجمالي الفعلي (تسجيل مشرف البند)',
                    value: ProjectCosts.formatMoney(
                      totals.actualTotal,
                    ),
                  ),

                  AppSpacing.verticalXs,

                  AppInfoRow(
                    icon: Icons.calculate_outlined,
                    label: 'إجمالي تكلفة المشروع المعتمد',
                    value: ProjectCosts.formatMoney(displayTotal),
                  ),

                  AppSpacing.verticalSm,

                  const Text(
                    'لا تُدخل تكاليف المشروع يدويًا: المخطط يدخله '
                    'مدير المشروع من صفحة تفاصيل البند، والفعلي يسجله '
                    'مشرف البند من صفحته، ويُعتمد الفعلي عند توفره.',
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}


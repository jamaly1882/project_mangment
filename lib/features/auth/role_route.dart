import 'package:flutter/material.dart';

import '../../core/constants/roles.dart';
import '../accountant/accountant_page.dart';
import '../admin/admin_page.dart';
import '../admin/org_chart_page.dart';
import '../admin/projects_page.dart';
import '../driver/driver_page.dart';
import '../engineer/engineer_page.dart';
import '../movement/diesel_dashboard_page.dart';
import '../movement/movement_dashboard_page.dart';
import '../movement/workshop_dashboard_page.dart';
import '../project_manager/project_manager_dashboard_page.dart';
import '../supervisor/supervisor_page.dart';

// ============================================================
// توجيه المستخدم بعد تسجيل الدخول حسب موقعه في الهيكل الإداري
// ============================================================
//
// يُستخدم من صفحة الدخول وصفحة البداية (Splash) حتى يبقى
// قرار «أي شاشة يفتحها هذا الدور» في مكان واحد.
// ============================================================

/// نتيجة التوجيه: إما شاشة تفتح، أو رسالة تمنع الدخول.
class RoleRoute {
  const RoleRoute.page(this.page) : error = null;

  const RoleRoute.error(this.error) : page = null;

  /// الشاشة التي تُفتح بعد تسجيل الدخول.
  final Widget? page;

  /// رسالة تمنع الدخول (مثل: الحساب غير مرتبط بمشروع).
  final String? error;

  bool get hasError => error != null;
}

/// يحدد الشاشة المناسبة للدور [role] استنادًا إلى بيانات
/// المستخدم [data] من وثيقة `users/{uid}`.
RoleRoute resolveRoleRoute({
  required String role,
  required Map<String, dynamic> data,
}) {
  final String raw = role.trim().toLowerCase();

  final List<String> projectIds = (data['projectIds'] as List?)
          ?.map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList() ??
      <String>[];

  final String projectId =
      (data['projectId'] ?? '').toString().trim();

  switch (raw) {
    // ==========================================================
    // المشرف الرئيسي
    // ==========================================================

    case AppRoles.admin:
    case AppRoles.generalManager:
      return const RoleRoute.page(AdminPage());

    // ==========================================================
    // مدير إدارة المشاريع — كل المشاريع
    // ==========================================================

    case AppRoles.projectsDeptManager:
      return const RoleRoute.page(ProjectsPage());

    // ==========================================================
    // مهندس المشروع (= مدير المشروع)
    //
    // يحدده مدير إدارة المشاريع عند بناء المشروع،
    // ويرتبط بمشروع واحد.
    // ==========================================================

    case AppRoles.projectManager:
    case AppRoles.projectEngineer:
      final String effectiveProjectId = projectId.isNotEmpty
          ? projectId
          : (projectIds.isNotEmpty ? projectIds.first : '');

      if (effectiveProjectId.isEmpty) {
        return const RoleRoute.error(
          'مهندس المشروع غير مرتبط بأي مشروع',
        );
      }

      return RoleRoute.page(
        ProjectManagerDashboardPage(
          projectId: effectiveProjectId,
        ),
      );

    // ==========================================================
    // مهندس البند (دور قديم)
    // ==========================================================

    case AppRoles.engineer:
      return const RoleRoute.page(EngineerPage());

    // ==========================================================
    // مشرف المشروع — ميداني
    // ==========================================================

    case AppRoles.supervisor:
    case AppRoles.projectSupervisor:
      if (projectIds.isEmpty) {
        return const RoleRoute.error(
          'مشرف المشروع غير مرتبط بأي مشروع',
        );
      }

      return RoleRoute.page(
        SupervisorPage(projectIds: projectIds),
      );

    // ==========================================================
    // السائق (دور قديم)
    // ==========================================================

    case AppRoles.driver:
      if (projectIds.isEmpty) {
        return const RoleRoute.error(
          'السائق غير مرتبط بأي مشروع',
        );
      }

      return RoleRoute.page(
        DriverPage(projectIds: projectIds),
      );

    // ==========================================================
    // الأدوار المالية
    // ==========================================================

    case AppRoles.accountant:
    case AppRoles.projectAccountant:
    case AppRoles.financialManager:
    case AppRoles.accountsManager:
      return const RoleRoute.page(AccountantPage());

    // ==========================================================
    // إدارة الحركة — يضيف المعدة وينقلها بين المشاريع،
    // فتنتقل بياناتها إلى إدارة الديزل والورشة والصيانة.
    // ==========================================================

    case AppRoles.movementDeptManager:
      return const RoleRoute.page(MovementDashboardPage());

    // ==========================================================
    // إدارة الديزل — نافذتا «استهلاك المعدات» (كل معدة بكودها
    // ورقم مشروعها) و«استهلاك الوقود» (كمية كل مشروع في اليوم).
    // مدير المحروقات ومراقب الحركة يعملان في اللوحة نفسها.
    // ==========================================================

    case AppRoles.fuelManager:
    case AppRoles.movementMonitor:
      return const RoleRoute.page(DieselDashboardPage());

    // ==========================================================
    // إدارة الورشة والصيانة — الأعطال وبدلات التواير وقطع
    // الغيار، وكلها تُضاف إلى ملف المعدة.
    // ==========================================================

    case AppRoles.workshopManager:
      return const RoleRoute.page(WorkshopDashboardPage());

    // ==========================================================
    // أدوار الهيكل التي لا تملك لوحة تنفيذية بعد
    //
    // تفتح لها صفحة الهيكل الإداري مع إبراز منصبها ومهامه.
    // ==========================================================

    case AppRoles.qualityCostManager:
      return RoleRoute.page(
        OrgChartPage(
          focusRole: AppRoles.normalize(raw),
          readOnly: true,
        ),
      );

    // ==========================================================
    // دور غير معروف
    // ==========================================================

    default:
      return RoleRoute.error(
        'دور المستخدم غير معروف: $role',
      );
  }
}

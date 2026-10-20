import '../assignment/assignment_details_page.dart';
import '../assignment/assignment_workspace_page.dart';

// =============================================================
// لوحة مشرف البند
// =============================================================

/// لوحة مشرف البند: تعرض البنود المسندة إليه من صفحة تفاصيل البند
/// لدى مدير المشروع، وتفتح شاشة تسجيل الاستهلاك الفعلي.
///
/// هذه اللوحة هي البديل المباشر للوحة السائق القديمة.
class SupervisorPage extends AssignmentWorkspacePage {
  const SupervisorPage({
    super.key,
    required List<String> projectIds,
  }) : super(
          projectIds: projectIds,
          supervisorMode: true,
        );
}

/// تفاصيل تكليف البند للمشرف وتسجيل الاستهلاك الفعلي.
class SupervisorItemDetailsPage extends AssignmentDetailsPage {
  const SupervisorItemDetailsPage({
    super.key,
    required String projectId,
    required String itemId,
  }) : super(
          projectId: projectId,
          itemId: itemId,
          supervisorMode: true,
        );
}

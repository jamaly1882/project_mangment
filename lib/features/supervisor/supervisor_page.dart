import '../assignment/assignment_details_page.dart';
import '../assignment/assignment_workspace_page.dart';

// =============================================================
// لوحة مشرف البند
// =============================================================

/// لوحة مشرف البند: تعرض البنود المسندة إليه من صفحة تفاصيل البند
/// لدى مدير المشروع بمعداتها ومتابعة تنفيذها، وتفتح صفحة البند التي
/// يسجّل فيها المشرف الكميات المنفذة والاستهلاك الفعلي والتكاليف.
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

/// صفحة البند للمشرف: الكميات المنفذة + الاستهلاك الفعلي +
/// التكاليف الفعلية، مع مقارنتها بما خططه مدير المشروع.
class SupervisorItemDetailsPage extends AssignmentDetailsPage {
  const SupervisorItemDetailsPage({
    super.key,
    required String projectId,
    required String itemId,
  }) : super(
          projectId: projectId,
          itemId: itemId,
        );
}

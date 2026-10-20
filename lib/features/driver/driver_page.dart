import '../assignment/assignment_workspace_page.dart';

// =============================================================
// لوحة السائق (قديمة)
// =============================================================

/// تم استبدال السائق بمشرف البند في إسناد البنود.
///
/// تُبقي هذه الصفحة حسابات السائقين القديمة تعمل على سجلات
/// `item_drivers` السابقة فقط، بينما الإسنادات الجديدة تكتب
/// في `item_supervisors` وتظهر في لوحة مشرف البند.
class DriverPage extends AssignmentWorkspacePage {
  const DriverPage({
    super.key,
    List<String> projectIds = const <String>[],
  }) : super(
          projectIds: projectIds,
          supervisorMode: false,
        );
}

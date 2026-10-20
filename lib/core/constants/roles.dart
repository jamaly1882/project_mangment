class AppRoles {
  static const admin = 'admin';
  static const projectManager = 'project_manager';
  static const engineer = 'engineer';

  /// مشرف البند: يحل محل السائق في إسناد البنود وتسجيل الاستهلاك.
  static const supervisor = 'supervisor';

  /// الدور القديم (السائق) — باقٍ فقط لقراءة البيانات السابقة.
  static const driver = 'driver';

  static const accountant = 'accountant';
  static const user = 'user';

  /// كل الأدوار التي يمكن لمسؤول النظام إنشاء حسابات لها.
  static const List<String> creatable = [
    projectManager,
    engineer,
    supervisor,
    accountant,
  ];

  /// اسم الدور بالعربية.
  static String label(String? role) {
    switch (role) {
      case admin:
        return 'مسؤول النظام';
      case projectManager:
        return 'مدير المشروع';
      case engineer:
        return 'مهندس';
      case supervisor:
        return 'مشرف بند';
      case driver:
        return 'سائق';
      case accountant:
        return 'محاسب';
      default:
        return role == null || role.isEmpty ? 'مستخدم' : role;
    }
  }
}

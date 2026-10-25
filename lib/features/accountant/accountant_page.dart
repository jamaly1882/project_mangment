import 'package:flutter/material.dart';

import '../accounting/accounting_dashboard_page.dart';
import '../accounting/accounting_service.dart';

// ============================================================
// لوحة الإدارة المالية — نقطة الدخول بعد تسجيل الدخول
// ============================================================
//
// كانت هذه الصفحة سابقًا لوحة عرض بلا وظائف. صارت الآن بوابة
// الوحدة المالية (accounting_dashboard_page.dart):
//
// • المدير المالي: ينشئ حساب المحاسب من قسم «مستخدمو الإدارة
//   المالية»، ويتابع السندات والصندوق والقيود والتقارير في وضع
//   إشراف (عرض فقط).
//
// • المحاسب (project_accountant / accountant / accounts_manager
//   بعد التطبيع): مسؤول عن كل أعمال الوحدة:
//   - سندات القبض وسندات الصرف (وتُرحَّل تلقائيًا إلى القيود).
//   - الصندوق: الرصيد الافتتاحي، الحركة، والرصيد الجاري.
//   - القيود اليومية اليدوية، والاطلاع على قيود السندات.
//   - التقارير المالية وميزان المراجعة.
//
// ربط المحاسب بالمشروع: [scope] يأتي من role_route بعد قراءة
// `users/{uid}` (projectId / projectIds). متى كان المحاسب مربوطًا
// بمشروع، تُقيَّد كل شاشات الوحدة (السندات والقيود والصندوق
// والتقارير والرصيد الافتتاحي) في ذلك المشروع فقط.
//
// يبقى اسم الصف [AccountantPage] لأن role_route.dart يوجّه إليه
// كل الأدوار المالية، فلا تتغير خريطة التوجيه.
// ============================================================

class AccountantPage extends StatelessWidget {
  const AccountantPage({
    super.key,
    this.scope = AccountingScope.none,
  });

  /// مشروع المحاسب (فارغ = كل مشاريع الوحدة).
  final AccountingScope scope;

  @override
  Widget build(BuildContext context) {
    return AccountingDashboardPage(scope: scope);
  }
}

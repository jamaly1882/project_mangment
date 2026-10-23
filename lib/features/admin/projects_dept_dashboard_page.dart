import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/roles.dart';
import 'department_users_page.dart';
import 'item_band_page.dart';
import 'material_page.dart' as materials;
import 'project_managers_page.dart';
import 'projects_page.dart';

// ============================================================
// لوحة مدير إدارة المشاريع
// ============================================================
//
// قاعدة النظام: المشرف الرئيسي ينشئ مدير إدارة المشاريع فقط،
// ومدير إدارة المشاريع من هنا:
// • ينشئ المشروع ويدير المشاريع (ProjectsPage).
// • ينشئ حسابات كل إدارته: مدير الجودة والتكلفة، مهندس
//   المشروع (= مدير المشروع، مرتبطًا بمشروعه)، ومشرف
//   المشروع — عبر صفحة «مستخدمي إدارة المشاريع»
//   (DepartmentUsersPage بأدوار creatableBy)، إضافة إلى
//   صفحة «مديرو المشاريع» التفصيلية الحالية لتعيين مدير
//   لكل مشروع.
// • يحدد البنود وأنواعها والمواد.
// ============================================================

class ProjectsDeptDashboardPage extends StatelessWidget {
  const ProjectsDeptDashboardPage({super.key});

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  void _push(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_back_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة المشاريع'),
          centerTitle: true,
          actions: <Widget>[
            IconButton(
              tooltip: 'تسجيل الخروج',
              icon: const Icon(Icons.logout),
              onPressed: () => _logout(context),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: <Widget>[
                    const CircleAvatar(
                      radius: 24,
                      child: Icon(Icons.apartment, size: 26),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'لوحة مدير إدارة المشاريع',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'تنشئ من هنا المشروع ومهندسه ومدير الجودة '
                            'ومشرفي المشروع، وتحدد البنود وأنواعها والمواد. '
                            'بقية الإدارات تنشئ مستخدميها من صفحاتها.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _section('المشاريع'),
            _tile(
              context,
              icon: Icons.apartment_outlined,
              title: 'المشاريع',
              subtitle: 'إنشاء المشاريع وإدارتها (رقم المشروع وبياناته)',
              onTap: () => _push(context, const ProjectsPage()),
            ),
            _section('مستخدمو إدارتك'),
            _tile(
              context,
              icon: Icons.group_outlined,
              title: 'مستخدمو إدارة المشاريع',
              subtitle:
                  'إنشاء مدير الجودة والتكلفة ومهندس المشروع ومشرف المشروع',
              onTap: () => _push(
                context,
                DepartmentUsersPage(
                  title: 'مستخدمو إدارة المشاريع',
                  subtitle:
                      'حسابات إدارتك فقط: كل دور بتبويبه، وربط المهندس '
                      'بمشروعه والمشرف بمشاريعه.',
                  roles: AppRoles.creatableBy(
                    AppRoles.projectsDeptManager,
                  ),
                ),
              ),
            ),
            _tile(
              context,
              icon: Icons.engineering_outlined,
              title: 'مديرو المشاريع (حسب المشروع)',
              subtitle: 'الشاشة التفصيلية لتعيين مهندس (مدير) لكل مشروع',
              onTap: () => _push(context, const ProjectManagersPage()),
            ),
            _section('البنود والمواد'),
            _tile(
              context,
              icon: Icons.list_alt_outlined,
              title: 'بنود العمل',
              subtitle: 'تعريف بنود الأعمال المستخدمة في المشاريع',
              onTap: () => _push(context, const ItemBandPage()),
            ),
            _tile(
              context,
              icon: Icons.category_outlined,
              title: 'أنواع البنود',
              subtitle: 'تصنيفات وأنواع البنود',
              onTap: () => _push(context, const ItemBandPage()),
            ),
            _tile(
              context,
              icon: Icons.inventory_2_outlined,
              title: 'المواد',
              subtitle: 'مواد البناء وأنواعها وأسعارها',
              onTap: () => _push(context, const materials.MaterialPage()),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/roles.dart';
import 'department_users_page.dart';
import 'districts_page.dart';
import 'governorates_page.dart';
import 'org_chart_page.dart';

// ============================================================
// لوحة المشرف الرئيسي (المدير) — صفحة نظيفة
// ============================================================
//
// قاعدة النظام المعتمدة: المشرف الرئيسي ينشئ فقط
// • البيانات الجغرافية: المحافظات والمديريات.
// • حسابات رؤساء الإدارات الثلاثة: مدير إدارة المشاريع،
//   مدير إدارة الحركة، والمدير المالي
//   (AppRoles.creatableBy(generalManager) = أبناؤه المباشرون).
//
// وبقية المستخدمين تنشئهم إداراتهم من صفحاتها:
// • مدير إدارة المشاريع: المشروع ومهندسه ومدير الجودة
//   ومشرف المشروع والبنود والمواد (ProjectsDeptDashboardPage).
// • مدير إدارة الحركة: المحروقات والورشة ومراقب الحركة
//   والمعدات (MovementDashboardPage).
// • المدير المالي: إدارة الحسابات ومحاسب المشروع
//   (AccountantPage).
//
// لذلك لا توجد هنا أدوات مشاريع أو مستخدمين عامين أو بنود
// أو مواد أو معدات — تبقى فقط: المحافظات والمديريات،
// إدارة المديرين الثلاثة، والهيكل الإداري (عرض فقط حتى لا
// يكون بابًا خلفيًا لإنشاء الحسابات)، وإحصائيات عامة.
// ============================================================

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late Map<String, Future<int>> _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats() {
    _stats = <String, Future<int>>{
      'governorates': _count('governorates'),
      'districts': _count('districts'),
      'projects': _count('projects'),
      'users': _count('users'),
    };
  }

  Future<int> _count(String collection) async {
    final snapshot = await _firestore.collection(collection).get();
    return snapshot.size;
  }

  Future<void> _refresh() async {
    setState(_loadStats);
    try {
      await Future.wait(_stats.values);
    } catch (_) {
      // تعرض كل بطاقة خطأها في مكانها.
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  void _push(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  // ==========================================================
  // عناصر الواجهة
  // ==========================================================

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

  Widget _tile({
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

  Widget _statCard({
    required IconData icon,
    required String label,
    required Future<int> future,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            FutureBuilder<int>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                    'خطأ',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.red),
                  );
                }
                return Text(
                  snapshot.hasData ? '${snapshot.data}' : '...',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                );
              },
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
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
          title: const Text('المشرف الرئيسي'),
          centerTitle: true,
          actions: <Widget>[
            IconButton(
              tooltip: 'تحديث الإحصائيات',
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
            ),
            IconButton(
              tooltip: 'تسجيل الخروج',
              icon: const Icon(Icons.logout),
              onPressed: _logout,
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
                      child: Icon(Icons.admin_panel_settings, size: 26),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'صفحة المشرف الرئيسي',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'تنشئ من هنا فقط: المحافظات والمديريات، '
                            'وحسابات مديري الإدارات الثلاثة. وكل إدارة '
                            'تنشئ بقية مستخدميها وأعمالها من صفحتها.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _section('إحصائيات عامة'),
            LayoutBuilder(
              builder: (context, constraints) {
                final double width = constraints.maxWidth > 520
                    ? (constraints.maxWidth - 24) / 4
                    : (constraints.maxWidth - 8) / 2;
                final List<Widget> cards = <Widget>[
                  _statCard(
                    icon: Icons.map_outlined,
                    label: 'المحافظات',
                    future: _stats['governorates']!,
                  ),
                  _statCard(
                    icon: Icons.location_city_outlined,
                    label: 'المديريات',
                    future: _stats['districts']!,
                  ),
                  _statCard(
                    icon: Icons.apartment_outlined,
                    label: 'المشاريع',
                    future: _stats['projects']!,
                  ),
                  _statCard(
                    icon: Icons.people_outline,
                    label: 'المستخدمون',
                    future: _stats['users']!,
                  ),
                ];
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: cards
                      .map((c) => SizedBox(width: width, child: c))
                      .toList(),
                );
              },
            ),
            _section('البيانات الجغرافية'),
            _tile(
              icon: Icons.map_outlined,
              title: 'المحافظات',
              subtitle: 'إنشاء المحافظات وإدارتها',
              onTap: () => _push(const GovernoratesPage()),
            ),
            _tile(
              icon: Icons.location_city_outlined,
              title: 'المديريات',
              subtitle: 'إنشاء المديريات وربطها بمحافظاتها',
              onTap: () => _push(const DistrictsPage()),
            ),
            _section('مديرو الإدارات'),
            _tile(
              icon: Icons.supervisor_account_outlined,
              title: 'مديرو الإدارات الثلاثة',
              subtitle:
                  'مدير إدارة المشاريع • مدير إدارة الحركة • المدير المالي\n'
                  'هؤلاء فقط من تنشئ حساباتهم — وبقية المستخدمين عند إداراتهم',
              onTap: () => _push(
                DepartmentUsersPage(
                  title: 'مديرو الإدارات',
                  subtitle:
                      'حسابات رؤساء الإدارات الثلاثة فقط. كل رئيس إدارة '
                      'بعدها ينشئ مستخدمي إدارته من صفحته.',
                  roles: AppRoles.creatableBy(AppRoles.generalManager),
                ),
              ),
            ),
            _section('الهيكل والتنظيم'),
            _tile(
              icon: Icons.account_tree_outlined,
              title: 'الهيكل الإداري',
              subtitle:
                  'عرض المناصب وشاغليها (إنشاء الحسابات من صفحات الإدارات)',
              onTap: () => _push(const OrgChartPage(readOnly: true)),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/app_widgets.dart';
import 'users_page.dart';
import 'governorates_page.dart';
import 'districts_page.dart';
import 'projects_page.dart';
import 'project_managers_page.dart';
import 'item_band_page.dart';
import 'item_types_page.dart';
import 'material_page.dart' as materials;
import 'equipment_management_pages.dart' as equipment_data;
import 'equipment_page.dart';

/// لوحة مسؤول النظام.
/// مقسمة إلى:
/// 1) عرض وإدارة البيانات الموجودة.
/// 2) إضافة بيانات جديدة.
/// 3) الإحصائيات والإجراءات السريعة.
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  late Map<String, Future<int>> _stats;

  @override
  void initState() {
    super.initState();
    _createStatFutures();
  }

  void _createStatFutures() {
    _stats = {
      'activeProjects': countActiveProjects(),
      'projectManagers': countRole('project_manager'),
      'users': countUsers(),
      'engineers': countRole('engineer'),
      'supervisors': countRole('supervisor'),
      'drivers': countRole('driver'),
      'accountants': countRole('accountant'),
      'itemBands': countCollection('item_definitions'),
      'materials': countCollection('materials'),
      'equipment': countCollection('equipment'),
      'consumables': countCollection('equipment_consumption_rules'),
      'dieselRules': countCollection('diesel_consumption_rules'),
      'equipmentCosts': countCollection('equipment_costs'),
      'referenceData': countCollection('reference_data'),
    };
  }

  Future<int> countCollection(String collection) async {
    final snapshot = await firestore.collection(collection).get();
    return snapshot.size;
  }

  Future<int> countActiveProjects() async {
    final snapshot = await firestore
        .collection('projects')
        .where('status', isEqualTo: 'active')
        .get();
    return snapshot.size;
  }

  Future<int> countRole(String role) async {
    final snapshot = await firestore
        .collection('users')
        .where('role', isEqualTo: role)
        .get();
    return snapshot.size;
  }

  Future<int> countUsers() async {
    final snapshot = await firestore.collection('users').get();
    return snapshot.size;
  }

  Future<void> _refresh() async {
    setState(_createStatFutures);
    try {
      await Future.wait(_stats.values);
    } catch (_) {
      // تعرض كل بطاقة الخطأ في مكانها عند اكتمال البناء.
    }
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/',
      (route) => false,
    );
  }

  // ============================================================
  // صفحات العرض والإدارة
  // ============================================================

  void openGovernorates() => _push(const GovernoratesPage());
  void openDistricts() => _push(const DistrictsPage());
  void openProjects() => _push(const ProjectsPage());
  void openProjectManagers() => _push(const ProjectManagersPage());
  void openUsers() => _push(const UsersPage());
  void openItemBands() => _push(const ItemBandPage());

  /// صفحة أنواع البنود تحتاج اختيار البند أولًا،
  /// لذلك نعرض قائمة البنود ثم نفتح صفحة أنواع البند المختار.
  Future<void> openItemTypes() async {
    try {
      final snapshot = await firestore
          .collection('item_definitions')
          .where('active', isEqualTo: true)
          .get();

      final docs = snapshot.docs;

      if (docs.isEmpty) {
        if (!mounted) return;

        AppWidgets.showWarning(
          context,
          'لا توجد بنود. أضف البند أولًا من «إضافة بند».',
        );
        return;
      }

      if (!mounted) return;

      final selected = await showDialog<List<String>>(
        context: context,
        builder: (dialogContext) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('اختر البند لعرض أنواعه'),
              content: SizedBox(
                width: 420,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final doc in docs)
                      ListTile(
                        leading: const Icon(Icons.category_outlined),
                        title: Text(
                          doc.data()['name']?.toString() ?? 'بدون اسم',
                        ),
                        onTap: () {
                          Navigator.of(dialogContext).pop(
                            <String>[
                              doc.id,
                              doc.data()['name']?.toString() ?? 'بدون اسم',
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('إلغاء'),
                ),
              ],
            ),
          );
        },
      );

      if (selected == null || selected.length < 2) return;

      _push(
        ItemTypesPage(
          itemDefinitionId: selected[0],
          itemDefinitionName: selected[1],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      AppWidgets.showError(
        context,
        'تعذر تحميل البنود:\n$e',
      );
    }
  }
  void openMaterials() => _push(const materials.MaterialPage());

  void openEquipment() => _push(const EquipmentPage());
  void openConsumables() =>
      _push(const equipment_data.EquipmentConsumablesPage());
  void openDieselConsumption() =>
      _push(const equipment_data.DieselConsumptionPage());
  void openEquipmentCosts() =>
      _push(const equipment_data.EquipmentCostsPage());
  void openReferenceData() =>
      _push(const equipment_data.ReferenceDataPage());

  void openReports() =>
      _push(const _ComingSoonPage(title: 'التقارير'));

  // ============================================================
  // صفحات الإضافة
  //
  // حاليًا الإضافة تفتح صفحة الإدارة نفسها، لأن صفحات المشروع
  // والمستخدمين والمواد والمعدات الموجودة في المشروع هي التي
  // تحتوي على نماذج وأزرار الإضافة الخاصة بها.
  // ============================================================

  void addGovernorate() => openGovernorates();
  void addDistrict() => openDistricts();
  void addProject() => openProjects();
  void addProjectManager() => openProjectManagers();
  void addUser() => openUsers();
  void addItemBand() => openItemBands();
  void addItemType() => openItemTypes();
  void addSupervisor() =>
      _push(const UsersPage(initialSupervisor: true));
  void addMaterial() => openMaterials();
  void addEquipment() => openEquipment();

  void _push(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  // ============================================================
  // عناصر الواجهة
  // ============================================================

  Widget _drawerItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 6),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            child: Icon(icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required String statKey,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return FutureBuilder<int>(
      future: _stats[statKey],
      builder: (context, snapshot) {
        final value = snapshot.hasError
            ? '—'
            : snapshot.connectionState == ConnectionState.waiting
                ? '…'
                : '${snapshot.data ?? 0}';

        return _DashboardCard(
          icon: icon,
          title: title,
          value: value,
          onTap: onTap,
        );
      },
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return _QuickActionCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }

  Widget _managementCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return _ManagementCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      actionText: 'عرض وإدارة',
      onTap: onTap,
    );
  }

  Widget _addCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return _AddCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }

  Widget buildDrawer() {
    return Drawer(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                child: const Column(
                  children: [
                    CircleAvatar(
                      radius: 38,
                      child: Icon(
                        Icons.admin_panel_settings,
                        size: 42,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'مسؤول النظام',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'إدارة النظام والبيانات الأساسية',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    _drawerItem(
                      icon: Icons.dashboard,
                      title: 'الرئيسية',
                      onTap: () {},
                    ),

                    _sectionLabel('العرض والإدارة'),

                    _drawerItem(
                      icon: Icons.business,
                      title: 'المشاريع',
                      subtitle: 'عرض وتعديل وحذف المشاريع',
                      onTap: openProjects,
                    ),
                    _drawerItem(
                      icon: Icons.people,
                      title: 'المستخدمون',
                      subtitle: 'المهندسون والمشرفون والمحاسبون وغيرهم',
                      onTap: openUsers,
                    ),
                    _drawerItem(
                      icon: Icons.manage_accounts,
                      title: 'مديرو المشاريع',
                      subtitle: 'عرض وتعيين مديري المشاريع',
                      onTap: openProjectManagers,
                    ),
                    _drawerItem(
                      icon: Icons.location_city,
                      title: 'المحافظات',
                      onTap: openGovernorates,
                    ),
                    _drawerItem(
                      icon: Icons.location_on,
                      title: 'المديريات',
                      onTap: openDistricts,
                    ),
                    _drawerItem(
                      icon: Icons.category,
                      title: 'تعريف البنود وأنواعها',
                      onTap: openItemBands,
                    ),
                    _drawerItem(
                      icon: Icons.list_alt,
                      title: 'أنواع البنود',
                      subtitle: 'اختيار بند ثم إدارة أنواعه',
                      onTap: openItemTypes,
                    ),
                    _drawerItem(
                      icon: Icons.inventory_2,
                      title: 'المواد',
                      onTap: openMaterials,
                    ),
                    _drawerItem(
                      icon: Icons.construction,
                      title: 'حصر المعدات',
                      onTap: openEquipment,
                    ),

                    const Divider(),

                    _sectionLabel('بيانات المعدات والاستهلاك'),

                    _drawerItem(
                      icon: Icons.oil_barrel,
                      title: 'الوحدات الاستهلاكية',
                      onTap: openConsumables,
                    ),
                    _drawerItem(
                      icon: Icons.local_gas_station,
                      title: 'استهلاك الديزل للمعدات',
                      onTap: openDieselConsumption,
                    ),
                    _drawerItem(
                      icon: Icons.calculate,
                      title: 'الإهلاك والإيجار والأعطال',
                      onTap: openEquipmentCosts,
                    ),
                    _drawerItem(
                      icon: Icons.tune,
                      title: 'البيانات والأسعار المرجعية',
                      onTap: openReferenceData,
                    ),

                    const Divider(),

                    _sectionLabel('التقارير'),

                    _drawerItem(
                      icon: Icons.assessment,
                      title: 'التقارير',
                      onTap: openReports,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.logout,
                  color: Colors.red,
                ),
                title: const Text(
                  'تسجيل الخروج',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: logout,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // قسم العرض والإدارة
  // ============================================================

  Widget _buildManagementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          icon: Icons.visibility,
          title: 'عرض وإدارة البيانات',
          subtitle: 'عرض البيانات الحالية والدخول إلى صفحات الإدارة والتعديل',
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 4
                : constraints.maxWidth >= 700
                    ? 3
                    : 2;

            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                _managementCard(
                  icon: Icons.business,
                  title: 'المشاريع',
                  subtitle: 'عرض وإدارة المشاريع',
                  onTap: openProjects,
                ),
                _managementCard(
                  icon: Icons.people,
                  title: 'المستخدمون',
                  subtitle: 'المهندسون والمشرفون والمحاسبون',
                  onTap: openUsers,
                ),
                _managementCard(
                  icon: Icons.manage_accounts,
                  title: 'مديرو المشاريع',
                  subtitle: 'عرض وإدارة المديرين',
                  onTap: openProjectManagers,
                ),
                _managementCard(
                  icon: Icons.location_city,
                  title: 'المحافظات',
                  subtitle: 'عرض وإدارة المحافظات',
                  onTap: openGovernorates,
                ),
                _managementCard(
                  icon: Icons.location_on,
                  title: 'المديريات',
                  subtitle: 'عرض وإدارة المديريات',
                  onTap: openDistricts,
                ),
                _managementCard(
                  icon: Icons.category,
                  title: 'البنود والأنواع',
                  subtitle: 'عرض وتعريف البنود وأنواعها',
                  onTap: openItemBands,
                ),
                _managementCard(
                  icon: Icons.list_alt,
                  title: 'أنواع البنود',
                  subtitle: 'إدارة أنواع كل بند',
                  onTap: openItemTypes,
                ),
                _managementCard(
                  icon: Icons.inventory_2,
                  title: 'المواد',
                  subtitle: 'عرض وإدارة المواد',
                  onTap: openMaterials,
                ),
                _managementCard(
                  icon: Icons.construction,
                  title: 'المعدات',
                  subtitle: 'عرض وإدارة المعدات',
                  onTap: openEquipment,
                ),
                _managementCard(
                  icon: Icons.oil_barrel,
                  title: 'الوحدات الاستهلاكية',
                  subtitle: 'عرض معدلات الاستهلاك',
                  onTap: openConsumables,
                ),
                _managementCard(
                  icon: Icons.local_gas_station,
                  title: 'استهلاك الديزل',
                  subtitle: 'عرض قواعد استهلاك الديزل',
                  onTap: openDieselConsumption,
                ),
                _managementCard(
                  icon: Icons.calculate,
                  title: 'تكاليف المعدات',
                  subtitle: 'الإهلاك والإيجار والأعطال',
                  onTap: openEquipmentCosts,
                ),
                _managementCard(
                  icon: Icons.tune,
                  title: 'البيانات المرجعية',
                  subtitle: 'عرض الأسعار والنسب والفترات',
                  onTap: openReferenceData,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // ============================================================
  // قسم الإضافة
  // ============================================================

  Widget _buildAddSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          icon: Icons.add_circle_outline,
          title: 'إضافة بيانات جديدة',
          subtitle: 'اختر نوع البيانات التي تريد إضافتها ثم استخدم نموذج الإضافة داخل الصفحة',
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 4
                : constraints.maxWidth >= 700
                    ? 3
                    : 2;

            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                _addCard(
                  icon: Icons.add_business,
                  title: 'إضافة مشروع',
                  subtitle: 'إنشاء مشروع جديد',
                  onTap: addProject,
                ),
                _addCard(
                  icon: Icons.person_add,
                  title: 'إضافة مستخدم',
                  subtitle: 'مهندس أو مشرف بند أو محاسب',
                  onTap: addUser,
                ),
                _addCard(
                  icon: Icons.supervisor_account,
                  title: 'إضافة مشرف بند',
                  subtitle: 'بديل السائق في إسناد البنود',
                  onTap: addSupervisor,
                ),
                _addCard(
                  icon: Icons.person_add_alt_1,
                  title: 'إضافة مدير مشروع',
                  subtitle: 'إنشاء مدير وربطه بالمشروع',
                  onTap: addProjectManager,
                ),
                _addCard(
                  icon: Icons.add_location_alt,
                  title: 'إضافة محافظة',
                  subtitle: 'إنشاء محافظة جديدة',
                  onTap: addGovernorate,
                ),
                _addCard(
                  icon: Icons.add_location,
                  title: 'إضافة مديرية',
                  subtitle: 'إضافة مديرية إلى محافظة',
                  onTap: addDistrict,
                ),
                _addCard(
                  icon: Icons.add_box,
                  title: 'إضافة بند',
                  subtitle: 'إنشاء بند أو نوع أو وحدة',
                  onTap: addItemBand,
                ),
                _addCard(
                  icon: Icons.playlist_add,
                  title: 'إضافة نوع',
                  subtitle: 'إضافة نوع لأحد البنود',
                  onTap: addItemType,
                ),
                _addCard(
                  icon: Icons.add_shopping_cart,
                  title: 'إضافة مادة',
                  subtitle: 'إضافة مادة أو نوع مادة',
                  onTap: addMaterial,
                ),
                _addCard(
                  icon: Icons.add_business,
                  title: 'إضافة معدة',
                  subtitle: 'إضافة معدة جديدة إلى النظام',
                  onTap: addEquipment,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // ============================================================
  // الإحصائيات
  // ============================================================

  Widget _buildStatisticsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'إحصائيات النظام',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1200
                ? 4
                : constraints.maxWidth >= 800
                    ? 3
                    : 2;

            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.55,
              children: [
                _statCard(
                  statKey: 'activeProjects',
                  icon: Icons.business,
                  title: 'المشاريع النشطة',
                  onTap: openProjects,
                ),
                _statCard(
                  statKey: 'projectManagers',
                  icon: Icons.manage_accounts,
                  title: 'مديرو المشاريع',
                  onTap: openProjectManagers,
                ),
                _statCard(
                  statKey: 'users',
                  icon: Icons.people,
                  title: 'كل المستخدمين',
                  onTap: openUsers,
                ),
                _statCard(
                  statKey: 'engineers',
                  icon: Icons.engineering,
                  title: 'المهندسون',
                  onTap: openUsers,
                ),
                _statCard(
                  statKey: 'supervisors',
                  icon: Icons.supervisor_account,
                  title: 'مشرفو البنود',
                  onTap: openUsers,
                ),
                _statCard(
                  statKey: 'drivers',
                  icon: Icons.local_shipping,
                  title: 'السائقون (قديم)',
                  onTap: openUsers,
                ),
                _statCard(
                  statKey: 'accountants',
                  icon: Icons.account_balance,
                  title: 'المحاسبون',
                  onTap: openUsers,
                ),
                _statCard(
                  statKey: 'itemBands',
                  icon: Icons.category,
                  title: 'تعريف البنود وأنواعها',
                  onTap: openItemBands,
                ),
                _statCard(
                  statKey: 'materials',
                  icon: Icons.inventory_2,
                  title: 'المواد',
                  onTap: openMaterials,
                ),
                _statCard(
                  statKey: 'equipment',
                  icon: Icons.construction,
                  title: 'المعدات',
                  onTap: openEquipment,
                ),
                _statCard(
                  statKey: 'consumables',
                  icon: Icons.oil_barrel,
                  title: 'الوحدات الاستهلاكية',
                  onTap: openConsumables,
                ),
                _statCard(
                  statKey: 'dieselRules',
                  icon: Icons.local_gas_station,
                  title: 'قواعد استهلاك الديزل',
                  onTap: openDieselConsumption,
                ),
                _statCard(
                  statKey: 'equipmentCosts',
                  icon: Icons.calculate,
                  title: 'الإهلاك والإيجار والأعطال',
                  onTap: openEquipmentCosts,
                ),
                _statCard(
                  statKey: 'referenceData',
                  icon: Icons.tune,
                  title: 'البيانات المرجعية',
                  onTap: openReferenceData,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الإجراءات السريعة',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 4
                : constraints.maxWidth >= 650
                    ? 3
                    : 2;

            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                _quickAction(
                  icon: Icons.business,
                  title: 'المشاريع',
                  subtitle: 'إدارة المشاريع',
                  onTap: openProjects,
                ),
                _quickAction(
                  icon: Icons.people,
                  title: 'المستخدمون',
                  subtitle: 'المهندسون والسائقون والمحاسبون',
                  onTap: openUsers,
                ),
                _quickAction(
                  icon: Icons.manage_accounts,
                  title: 'مديرو المشاريع',
                  subtitle: 'تعيين وإدارة المديرين',
                  onTap: openProjectManagers,
                ),
                _quickAction(
                  icon: Icons.construction,
                  title: 'حصر المعدات',
                  subtitle: 'بيانات المعدات وقراءة العداد الحالية',
                  onTap: openEquipment,
                ),
                _quickAction(
                  icon: Icons.oil_barrel,
                  title: 'الوحدات الاستهلاكية',
                  subtitle: 'المواد والمعدلات الاستهلاكية',
                  onTap: openConsumables,
                ),
                _quickAction(
                  icon: Icons.local_gas_station,
                  title: 'استهلاك الديزل',
                  subtitle: 'معدلات الديزل حسب المعدة',
                  onTap: openDieselConsumption,
                ),
                _quickAction(
                  icon: Icons.calculate,
                  title: 'تكاليف المعدات',
                  subtitle: 'الإهلاك والإيجار والأعطال',
                  onTap: openEquipmentCosts,
                ),
                _quickAction(
                  icon: Icons.tune,
                  title: 'البيانات المرجعية',
                  subtitle: 'الأسعار والنسب والفترات',
                  onTap: openReferenceData,
                ),
                _quickAction(
                  icon: Icons.category,
                  title: 'تعريف البنود وأنواعها',
                  subtitle: 'إنشاء وتعديل البنود والأنواع',
                  onTap: openItemBands,
                ),
                _quickAction(
                  icon: Icons.inventory_2,
                  title: 'المواد',
                  subtitle: 'إدارة المواد والأنواع',
                  onTap: openMaterials,
                ),
                _quickAction(
                  icon: Icons.location_city,
                  title: 'المحافظات',
                  subtitle: 'إدارة المحافظات',
                  onTap: openGovernorates,
                ),
                _quickAction(
                  icon: Icons.location_on,
                  title: 'المديريات',
                  subtitle: 'إدارة المديريات',
                  onTap: openDistricts,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildLatestProjects() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'آخر المشاريع',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: firestore.collection('projects').limit(10).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'حدث خطأ أثناء تحميل المشاريع. '
                    'تحقق من الاتصال والصلاحيات.',
                  ),
                ),
              );
            }

            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text('لا توجد مشاريع حتى الآن'),
                  ),
                ),
              );
            }

            return Column(
              children: docs.map((doc) {
                return _ProjectCard(
                  data: doc.data(),
                  onTap: openProjects,
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة تحكم مسؤول النظام'),
          centerTitle: true,
        ),
        drawer: buildDrawer(),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'مرحباً بك في لوحة التحكم',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'إدارة المشاريع والمستخدمين وبيانات المعدات '
                'والاستهلاك المرتبطة بملف الإكسل.',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 24),

              // ==================================================
              // 1. العرض والإدارة
              // ==================================================
              _buildManagementSection(),

              const SizedBox(height: 32),

              // ==================================================
              // 2. الإضافة
              // ==================================================
              _buildAddSection(),

              const SizedBox(height: 32),

              // ==================================================
              // 3. الإحصائيات
              // ==================================================
              _buildStatisticsSection(),

              const SizedBox(height: 32),

              // ==================================================
              // 4. الإجراءات السريعة
              // ==================================================
              _buildQuickActionsSection(),

              const SizedBox(height: 32),

              // ==================================================
              // 5. آخر المشاريع
              // ==================================================
              _buildLatestProjects(),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 30,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 7),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagementCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionText;
  final VoidCallback onTap;

  const _ManagementCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 34,
                color: color,
              ),
              const SizedBox(height: 9),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 9),
              OutlinedButton.icon(
                onPressed: onTap,
                icon: const Icon(
                  Icons.visibility,
                  size: 16,
                ),
                label: Text(actionText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AddCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 9),
              FilledButton.icon(
                onPressed: onTap,
                icon: const Icon(
                  Icons.add,
                  size: 17,
                ),
                label: const Text('إضافة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _ProjectCard({
    required this.data,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name']?.toString() ?? 'بدون اسم';
    final code = data['code']?.toString() ?? '';
    final status = data['status']?.toString() ?? 'active';
    final isActive = status == 'active';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        child: ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.business),
          ),
          title: Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            code.isEmpty ? 'مشروع' : 'رقم المشروع: $code',
          ),
          trailing: Icon(
            isActive ? Icons.check_circle : Icons.cancel,
            color: isActive ? Colors.green : Colors.red,
          ),
        ),
      ),
    );
  }
}

class _ComingSoonPage extends StatelessWidget {
  final String title;

  const _ComingSoonPage({
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
        ),
        body: const Center(
          child: Text(
            'هذه الصفحة ستكون متاحة لاحقاً',
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}

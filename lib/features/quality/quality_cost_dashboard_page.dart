import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/services/item_approvals.dart';
import '../project_manager/items_page.dart';
import 'approvals_page.dart';

// =============================================================
// لوحة مدير إدارة الجودة والتكلفة
// =============================================================
// مهامه حسب الهيكل الإداري:
//   • إدخال الكمية التعاقدية لكل بند.
//   • تحديد التكلفة التقديرية لكل بند.
//   • متابعة التكلفة الفعلية ومشرف كل بند.
//
// المشرف والمهندس مربوطان بالمشروع مسبقًا، فلا يُطلبان عند إدخال
// البند. هذه اللوحة تعرض مشاريع المدير (أو كل المشاريع إن لم يكن
// مربوطًا بمشروع) وتفتح صفحة بنود المشروع مباشرة.
// =============================================================

class QualityCostDashboardPage extends StatefulWidget {
  /// المشاريع المرتبطة بالمدير (فارغة = كل المشاريع).
  final List<String> projectIds;

  const QualityCostDashboardPage({
    super.key,
    this.projectIds = const <String>[],
  });

  @override
  State<QualityCostDashboardPage> createState() =>
      _QualityCostDashboardPageState();
}

class _QualityCostDashboardPageState extends State<QualityCostDashboardPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Future<void> _logout() async {
    final confirmed = await AppWidgets.showConfirmDialog(
      context: context,
      title: 'تسجيل الخروج',
      message: 'هل تريد تسجيل الخروج من الحساب؟',
      confirmText: 'خروج',
      danger: true,
    );

    if (!confirmed) return;

    await _auth.signOut();
  }

  void _openItems(String projectId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemsPage(projectId: projectId),
      ),
    );
  }

  bool _matches(Map<String, dynamic> data) {
    if (_search.isEmpty) return true;

    final name = _text(data['name']).toLowerCase();
    final code = _text(data['code']).toLowerCase();

    return name.contains(_search) || code.contains(_search);
  }

  @override
  Widget build(BuildContext context) {
    final linkedOnly = widget.projectIds.isNotEmpty;

    return AppScaffold(
      title: 'إدارة الجودة والتكلفة',
      actions: [
        IconButton(
          tooltip: 'تسجيل الخروج',
          onPressed: _logout,
          icon: const Icon(Icons.logout_outlined),
        ),
      ],
      // القائمة تستخدم Expanded فلا بد من تمرير scrollable: false.
      child: AppPage(
        scrollable: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPageHeader(
              title: 'بنود المشاريع',
              subtitle:
                  'أدخل الكمية التعاقدية والتكلفة التقديرية لكل بند. '
                  'مهندس المشروع ومشرفه مربوطان بالمشروع مسبقًا.',
              icon: Icons.fact_check_outlined,
            ),
            AppSpacing.verticalLg,
            AppTextField(
              controller: _searchController,
              label: 'البحث',
              hint: 'ابحث باسم المشروع أو بكوده',
              prefixIcon: Icons.search,
              onChanged: (value) {
                setState(() => _search = value.trim().toLowerCase());
              },
            ),
            AppSpacing.verticalLg,

            // أيقونتا الموافقات: الكميات الإضافية وتمديد الوقت.
            Row(
              children: [
                Expanded(
                  child: _ApprovalTile(
                    title: 'الكميات الإضافية',
                    icon: Icons.add_chart_outlined,
                    color: AppColors.warning,
                    stream: ItemApprovals.stream(
                      kind: ApprovalKind.extraQuantity,
                      status: ApprovalStatus.pending,
                    ),
                    projectIds: widget.projectIds,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ApprovalsPage(
                          kind: ApprovalKind.extraQuantity,
                          projectIds: widget.projectIds,
                        ),
                      ),
                    ),
                  ),
                ),
                AppSpacing.horizontalSm,
                Expanded(
                  child: _ApprovalTile(
                    title: 'تمديد الوقت',
                    icon: Icons.more_time_outlined,
                    color: AppColors.info,
                    stream: ItemApprovals.stream(
                      kind: ApprovalKind.timeExtension,
                      status: ApprovalStatus.pending,
                    ),
                    projectIds: widget.projectIds,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ApprovalsPage(
                          kind: ApprovalKind.timeExtension,
                          projectIds: widget.projectIds,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            AppSpacing.verticalLg,

            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _firestore.collection('projects').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return AppError(
                      message: 'تعذر تحميل المشاريع:\n${snapshot.error}',
                      onRetry: () => setState(() {}),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const AppLoading(message: 'جاري تحميل المشاريع...');
                  }

                  final docs = (snapshot.data?.docs ??
                          <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                      .where(
                        (doc) => linkedOnly
                            ? widget.projectIds.contains(doc.id)
                            : true,
                      )
                      .where((doc) => _matches(doc.data()))
                      .toList();

                  if (docs.isEmpty) {
                    return AppEmpty(
                      message: linkedOnly
                          ? 'لا توجد مشاريع مرتبطة بحسابك. '
                              'اطلب من مدير إدارة المشاريع ربطك بالمشروع.'
                          : 'لا توجد مشاريع حتى الآن.',
                      icon: Icons.business_outlined,
                    );
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => AppSpacing.verticalSm,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();

                      final name = _text(data['name'], fallback: 'مشروع');
                      final code = _text(data['code']);
                      final active = data['status'] != 'inactive';

                      return AppCard(
                        onTap: () => _openItems(doc.id),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.qualityCostManager
                                    .withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.business_outlined,
                                color: AppColors.qualityCostManager,
                              ),
                            ),
                            AppSpacing.horizontalMd,
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    code.isEmpty ? name : '$name — $code',
                                    style: AppTextStyles.cardTitle,
                                  ),
                                  AppSpacing.verticalXs,
                                  Text(
                                    'اضغط لعرض البنود وإدخال الكميات التعاقدية',
                                    style: AppTextStyles.bodySecondary,
                                  ),
                                ],
                              ),
                            ),
                            AppStatusBadge(
                              text: active ? 'نشط' : 'موقوف',
                              color: active
                                  ? AppColors.success
                                  : AppColors.danger,
                            ),
                            AppSpacing.horizontalSm,
                            const Icon(
                              Icons.arrow_back_ios_new,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// =============================================================
// بطاقة اختصار لطلبات الموافقة (كمية إضافية / تمديد وقت)
// =============================================================

class _ApprovalTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final List<String> projectIds;
  final VoidCallback onTap;

  const _ApprovalTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.stream,
    required this.projectIds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const Spacer(),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: stream,
                builder: (context, snapshot) {
                  final count = (snapshot.data?.docs ??
                          <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                      .where(
                        (doc) => projectIds.isEmpty ||
                            projectIds.contains(
                              (doc.data()['projectId'] ?? '').toString(),
                            ),
                      )
                      .length;

                  if (count == 0) return const SizedBox.shrink();

                  return AppStatusBadge(
                    text: '$count',
                    color: color,
                  );
                },
              ),
            ],
          ),
          AppSpacing.verticalSm,
          Text(
            title,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
          ),
          AppSpacing.verticalXs,
          Text(
            'طلبات بانتظار قرارك',
            style: AppTextStyles.small,
          ),
        ],
      ),
    );
  }
}

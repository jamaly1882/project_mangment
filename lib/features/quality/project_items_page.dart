import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

import '../project_manager/items_page.dart';

/// ============================================================
/// «إضافة ومتابعة بنود المشروع» — صلاحية مدير إدارة الجودة
/// ============================================================
///
/// نُقلت من لوحة مهندس المشروع: مدير الجودة هو من يضيف البنود
/// وكمياتها التعاقدية وتكاليفها. بعد اختيار المشروع تُفتح صفحة
/// بنوده كاملة الصلاحيات (إضافة بند، الكمية التعاقدية، التفاصيل،
/// التكاليف، الأسعار).
class ProjectItemsPage extends StatefulWidget {
  /// المشاريع المرتبطة بالمدير (فارغة = كل المشاريع).
  final List<String> projectIds;

  const ProjectItemsPage({
    super.key,
    this.projectIds = const <String>[],
  });

  @override
  State<ProjectItemsPage> createState() => _ProjectItemsPageState();
}

class _ProjectItemsPageState extends State<ProjectItemsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
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

  bool _matches(Map<String, dynamic> data) {
    if (_search.isEmpty) return true;

    return _text(data['name']).toLowerCase().contains(_search) ||
        _text(data['code']).toLowerCase().contains(_search);
  }

  @override
  Widget build(BuildContext context) {
    final linkedOnly = widget.projectIds.isNotEmpty;

    return AppScaffold(
      title: 'بنود المشاريع',
      showBackButton: true,
      child: AppPage(
        scrollable: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPageHeader(
              title: 'إضافة ومتابعة بنود المشروع',
              subtitle:
                  'اختر المشروع لإضافة بنوده وكمياتها التعاقدية وتكاليفها '
                  'وأسعارها. مهندس المشروع يرى البنود والإحصاءات فقط، '
                  'والمشرف يسجّل الكميات المنفذة.',
              icon: Icons.list_alt,
            ),
            AppSpacing.verticalMd,
            AppTextField(
              controller: _searchController,
              label: 'البحث',
              hint: 'اسم المشروع أو كوده',
              prefixIcon: Icons.search,
              onChanged: (value) {
                setState(() => _search = value.trim().toLowerCase());
              },
            ),
            AppSpacing.verticalMd,
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
                    return const AppEmpty(
                      message: 'لا توجد مشاريع مطابقة.',
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
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ItemsPage(projectId: doc.id),
                          ),
                        ),
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
                                Icons.list_alt,
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
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  AppSpacing.verticalXs,
                                  const Text(
                                    'اضغط لإضافة البنود ومتابعتها',
                                    style: AppTextStyles.bodySecondary,
                                  ),
                                ],
                              ),
                            ),
                            AppStatusBadge(
                              text: active ? 'نشط' : 'موقوف',
                              color: active
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                            ),
                            const Icon(
                              Icons.chevron_left,
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

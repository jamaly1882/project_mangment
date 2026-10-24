import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/costs.dart';
import '../../core/widgets/app_widgets.dart';

import 'item_prices_page.dart';

/// ============================================================
/// بنود المشروع — لاستيراد أسعار التكاليف إلى بند واحد
/// ============================================================
///
/// مدير إدارة الجودة: يختار المشروع ثم البند، فتُفتح صفحة أسعار البند
/// ونافذة لصق جدول التحليل تلقائيًا. الأسطر غير الموجودة في البند
/// تُضاف بلا كميات إلى أقسامها:
///   • المهنة + المصاريف        → العمالة
///   • نوع المعدة + الإهلاك     → المعدات
///   • ديزل/بترول/قاز/غاز/زيت  → المحروقات
///   • بقية المواد              → المواد
class ProjectItemsPricesPage extends StatefulWidget {
  final String projectId;
  final String projectName;

  const ProjectItemsPricesPage({
    super.key,
    required this.projectId,
    this.projectName = '',
  });

  @override
  State<ProjectItemsPricesPage> createState() =>
      _ProjectItemsPricesPageState();
}

class _ProjectItemsPricesPageState extends State<ProjectItemsPricesPage> {
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

    final name = _text(data['name']).toLowerCase();
    final type = _text(data['typeName']).toLowerCase();
    final code = _text(data['code']).toLowerCase();

    return name.contains(_search) ||
        type.contains(_search) ||
        code.contains(_search);
  }

  void _openItem(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemPriceEditorPage(
          itemId: doc.id,
          projectId: widget.projectId,
          itemName: _text(data['name'], fallback: _text(data['typeName'])),
          openImportOnLoad: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'أسعار التكاليف — بنود المشروع',
      showBackButton: true,
      child: AppPage(
        scrollable: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              title: widget.projectName.isEmpty
                  ? 'بنود المشروع'
                  : widget.projectName,
              subtitle:
                  'اختر البند ثم الصق جدول التحليل، فتُضاف أسطره إلى '
                  'تكاليف العمالة والمعدات والمحروقات والمواد.',
              icon: Icons.list_alt,
            ),
            AppSpacing.verticalMd,
            AppTextField(
              controller: _searchController,
              label: 'البحث',
              hint: 'اسم البند أو نوعه أو كوده',
              prefixIcon: Icons.search,
              onChanged: (value) {
                setState(() => _search = value.trim().toLowerCase());
              },
            ),
            AppSpacing.verticalMd,
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _firestore
                    .collection('items')
                    .where('projectId', isEqualTo: widget.projectId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return AppError(
                      message: 'تعذر تحميل البنود:\n${snapshot.error}',
                      onRetry: () => setState(() {}),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const AppLoading(message: 'جاري تحميل البنود...');
                  }

                  final docs = (snapshot.data?.docs ??
                          <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                      .where((doc) => _matches(doc.data()))
                      .toList();

                  if (docs.isEmpty) {
                    return const AppEmpty(
                      message: 'لا توجد بنود في هذا المشروع. '
                          'أضف بنود المشروع أولًا.',
                      icon: Icons.inventory_2_outlined,
                    );
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => AppSpacing.verticalSm,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();

                      final name = _text(
                        data['name'],
                        fallback: _text(data['typeName'], fallback: 'بند'),
                      );
                      final code = _text(data['code']);
                      final unit = _text(data['unit']);
                      final cost = ProjectCosts.totalOf(data);

                      return AppCard(
                        onTap: () => _openItem(doc),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.qualityCostManager
                                    .withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.price_change_outlined,
                                color: AppColors.qualityCostManager,
                              ),
                            ),
                            AppSpacing.horizontalMd,
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: AppTextStyles.cardTitle,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  AppSpacing.verticalXs,
                                  Text(
                                    <String>[
                                      if (code.isNotEmpty) code,
                                      if (unit.isNotEmpty) unit,
                                      'المخطط: ${ProjectCosts.formatMoney(cost)}',
                                    ].join(' — '),
                                    style: AppTextStyles.bodySecondary,
                                  ),
                                ],
                              ),
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

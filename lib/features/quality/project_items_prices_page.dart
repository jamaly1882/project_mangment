import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/unit_analysis_prices.dart';
import '../../core/services/project_cost_sync.dart';
import '../../core/services/unit_analysis_import.dart';
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
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();

  String _search = '';
  String? _importingItemId;

  /// استيراد جارٍ لكل بنود المشروع.
  bool _importingProject = false;

  /// تقدّم الاستيراد: «٣ / ١٢».
  String? _progress;

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

  /// استيراد أسعار التحليل إلى هذا البند بضغطة واحدة (بلا فتحه).
  Future<void> _importAnalysis(DocumentSnapshot<Map<String, dynamic>> doc) async {
    if (_importingItemId != null) return;

    final user = _auth.currentUser;
    if (user == null) {
      AppWidgets.showError(context, 'انتهت جلسة تسجيل الدخول.');
      return;
    }

    final data = doc.data() ?? <String, dynamic>{};
    final name = _text(
      data['name'],
      fallback: _text(data['typeName'], fallback: 'البند'),
    );

    final confirmed = await AppWidgets.showConfirmDialog(
      context: context,
      title: 'استيراد أسعار التحليل',
      message: 'سيُطبَّق جدول تحليل الوحدة ($unitAnalysisYear) على «$name»: '
          '${unitAnalysisLaborCount} مهنة، '
          '${unitAnalysisEquipmentCount} معدة، '
          '${unitAnalysisFuelCount} وقود، '
          '${unitAnalysisMaterialsCount} مادة.\n\n'
          'السطر الموجود يُحدَّث سعره، وغير الموجود يُضاف بلا كميات.',
      confirmText: 'استيراد',
    );

    if (!confirmed) return;

    setState(() => _importingItemId = doc.id);

    try {
      final result = await UnitAnalysisImporter.importToItem(
        itemId: doc.id,
        projectId: widget.projectId,
        userId: user.uid,
      );

      try {
        await ProjectCostSync.applyTotals(widget.projectId);
      } catch (e) {
        debugPrint('تعذرت مزامنة تكاليف المشروع: $e');
      }

      if (!mounted) return;
      setState(() => _importingItemId = null);

      AppWidgets.showSuccess(context, result.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _importingItemId = null);
      AppWidgets.showError(context, 'تعذر استيراد أسعار التحليل:\n$e');
    }
  }

  /// استيراد أسعار التحليل لكل بنود المشروع بضغطة واحدة.
  Future<void> _importProjectAnalysis() async {
    if (_importingProject || _importingItemId != null) return;

    final user = _auth.currentUser;
    if (user == null) {
      AppWidgets.showError(context, 'انتهت جلسة تسجيل الدخول.');
      return;
    }

    final confirmed = await AppWidgets.showConfirmDialog(
      context: context,
      title: 'استيراد التكاليف لكل بنود المشروع',
      message: 'سيُطبَّق جدول تحليل الوحدة ($unitAnalysisYear) على '
          'كل بنود هذا المشروع: '
          '${unitAnalysisLaborCount} مهنة، '
          '${unitAnalysisEquipmentCount} معدة، '
          '${unitAnalysisFuelCount} وقود، '
          '${unitAnalysisMaterialsCount} مادة.\n\n'
          'في كل بند: السطر الموجود يُحدَّث سعره، وغير الموجود يُضاف '
          'بلا كميات (التكلفة صفر حتى يدخل المشرف كمياته).\n'
          'إعادة الاستيراد لا تُكرر الأسطر. هل تريد المتابعة؟',
      confirmText: 'استيراد للكل',
    );

    if (!confirmed) return;

    setState(() {
      _importingProject = true;
      _progress = null;
    });

    try {
      final result = await UnitAnalysisImporter.importToProject(
        projectId: widget.projectId,
        userId: user.uid,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() => _progress = '$done / $total');
        },
      );

      ProjectCostTotals? totals;
      try {
        totals = await ProjectCostSync.applyTotals(widget.projectId);
      } catch (e) {
        debugPrint('تعذرت مزامنة تكاليف المشروع: $e');
      }

      if (!mounted) return;
      setState(() => _importingProject = false);

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('نتيجة استيراد التكاليف'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Text(
                <String>[
                  'حُدِّث ${result.itemsUpdated} بندًا من '
                      '${result.totalItems} في المشروع.',
                  if (result.updatedPrices > 0)
                    'أسعار محدَّثة: ${result.updatedPrices}',
                  if (result.addedLines > 0)
                    'أسطر مضافة بلا كميات: ${result.addedLines}',
                  if (result.itemsUpdated == 0)
                    'كل البنود كانت تحتوي أسطر التحليل بأسعارها.',
                  if (result.failedItems > 0)
                    'تعذر استيراد ${result.failedItems} بندًا؛ '
                        'أعد المحاولة له لاحقًا.',
                  if (totals != null)
                    'إجمالي تكلفة المشروع: '
                        '${ProjectCosts.formatMoney(totals.displayTotal)}',
                ].join('\n'),
                style: AppTextStyles.body,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _importingProject = false);
      AppWidgets.showError(
        context,
        'تعذر استيراد التكاليف لكل البنود:\n$e',
      );
    }
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
            AppSpacing.verticalSm,

            // استيراد التكاليف لكل بنود المشروع بضغطة واحدة.
            AppButton(
              label: _importingProject
                  ? 'جارٍ استيراد التكاليف لكل البنود...'
                  : 'استيراد التكاليف لكل بنود المشروع '
                      '($unitAnalysisRowCount سطرًا)',
              icon: Icons.download_for_offline_outlined,
              expanded: true,
              loading: _importingProject,
              onPressed: _importingProject || _importingItemId != null
                  ? null
                  : _importProjectAnalysis,
            ),

            if (_importingProject) ...[
              AppSpacing.verticalXs,
              Text(
                'جارٍ استيراد التكاليف: ${_progress ?? '...'} بندًا',
                style: AppTextStyles.small,
                textAlign: TextAlign.center,
              ),
            ],
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
                        onTap: _importingProject
                            ? null
                            : () => _openItem(doc),
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
                            if (_importingItemId == doc.id)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              IconButton(
                                tooltip: 'استيراد أسعار التحليل إلى هذا البند',
                                onPressed: _importingProject
                                    ? null
                                    : () => _importAnalysis(doc),
                                icon: const Icon(
                                  Icons.download_for_offline_outlined,
                                  color: AppColors.qualityCostManager,
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

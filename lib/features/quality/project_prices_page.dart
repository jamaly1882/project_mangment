import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/unit_analysis_prices.dart';
import '../../core/services/cost_prices.dart';
import '../../core/services/unit_analysis_import.dart';
import '../../core/services/project_cost_sync.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/cost_lines.dart';
import '../../core/utils/costs.dart';
import '../../core/widgets/app_widgets.dart';

import 'price_import_dialog.dart';
import 'project_items_prices_page.dart';

/// ============================================================
/// استيراد جدول أسعار التكاليف على مستوى المشروع
/// ============================================================
///
/// مدير إدارة الجودة يلصق جدول التحليل مرة واحدة، فيُوزَّع على بنود
/// المشروع كلها بحسب اسم كل سطر:
///   • المهنة + المصاريف        → العمالة
///   • المعدة + الإهلاك         → المعدات
///   • ديزل/بترول/غاز/قاز/زيت   → المحروقات
///   • بقية عمود المحروقات      → المواد
///
/// الأسطر التي لا يقابلها بند في المشروع تُعرض في نهاية الاستيراد
/// ليضيفها المدير يدويًا داخل بندها.
class ProjectPricesPage extends StatefulWidget {
  /// المشاريع المرتبطة بالمدير (فارغة = كل المشاريع).
  final List<String> projectIds;

  const ProjectPricesPage({
    super.key,
    this.projectIds = const <String>[],
  });

  @override
  State<ProjectPricesPage> createState() => _ProjectPricesPageState();
}

class _ProjectPricesPageState extends State<ProjectPricesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _tableController = TextEditingController();

  String _search = '';
  bool _applying = false;

  /// معرّف المشروع الجاري استيراد تكاليفه بضغطة واحدة.
  String? _importingProjectId;

  /// تقدّم الاستيراد: «٣ / ١٢».
  String? _progress;

  @override
  void dispose() {
    _searchController.dispose();
    _tableController.dispose();
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

  /// استيراد أسعار التحليل لكل بنود مشروع بضغطة واحدة (بلا لصق).
  Future<void> _importAnalysisForProject(
    Map<String, dynamic> project,
    String projectId,
  ) async {
    if (_applying || _importingProjectId != null) return;

    final user = _auth.currentUser;
    if (user == null) {
      AppWidgets.showError(context, 'انتهت جلسة تسجيل الدخول.');
      return;
    }

    final name = _text(project['name'], fallback: 'المشروع');

    final confirmed = await AppWidgets.showConfirmDialog(
      context: context,
      title: 'استيراد التكاليف لكل بنود المشروع',
      message: 'سيُطبَّق جدول تحليل الوحدة ($unitAnalysisYear) على '
          'كل بنود «$name»: '
          '${unitAnalysisLaborCount} مهنة، '
          '${unitAnalysisEquipmentCount} معدة، '
          '${unitAnalysisFuelCount} وقود، '
          '${unitAnalysisMaterialsCount} مادة.\n\n'
          'السطر الموجود يُحدَّث سعره، وغير الموجود يُضاف بلا كميات '
          '(التكلفة صفر حتى يدخل المشرف كمياته).',
      confirmText: 'استيراد للكل',
    );

    if (!confirmed) return;

    setState(() {
      _importingProjectId = projectId;
      _progress = null;
    });

    try {
      final result = await UnitAnalysisImporter.importToProject(
        projectId: projectId,
        userId: user.uid,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() => _progress = '$done / $total');
        },
      );

      ProjectCostTotals? totals;
      try {
        totals = await ProjectCostSync.applyTotals(projectId);
      } catch (e) {
        debugPrint('تعذرت مزامنة تكاليف المشروع: $e');
      }

      if (!mounted) return;
      setState(() => _importingProjectId = null);

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
      setState(() => _importingProjectId = null);
      AppWidgets.showError(
        context,
        'تعذر استيراد التكاليف لكل البنود:\n$e',
      );
    }
  }

  Future<void> _importFor(
    Map<String, dynamic> project,
    String projectId,
  ) async {
    if (_applying) return;

    final user = _auth.currentUser;
    if (user == null) {
      AppWidgets.showError(context, 'انتهت جلسة تسجيل الدخول.');
      return;
    }

    _tableController.clear();

    final entries = await showDialog<List<PriceEntry>>(
      context: context,
      builder: (_) => PriceImportDialog(
        controller: _tableController,
        title: 'استيراد أسعار المشروع',
        subtitle:
            'الصق جدول التحليل. تُوزَّع الأسعار على بنود المشروع كلها '
            'بحسب اسم كل سطر: المهنة ← العمالة، المعدة ← المعدات، '
            'ديزل/بترول/غاز/قاز/زيت ← المحروقات، وبقية المواد ← المواد.',
      ),
    );

    if (entries == null || entries.isEmpty) return;

    // معاينة سريعة للتوزيع قبل الحفظ.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد استيراد الأسعار'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'سيُطبَّق ${entries.length} سعرًا على كل بنود المشروع.'
                  '\nالأسعار القديمة تُستبدل، وتُعاد تكلفة البنود والمشروع.',
                  style: AppTextStyles.bodySecondary,
                ),
                AppSpacing.verticalSm,
                for (final kind in CostLineKind.values)
                  if (entries.any((entry) => entry.kind == kind))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${_kindLabel(kind)}: '
                        '${entries.where((e) => e.kind == kind).length} سطرًا',
                        style: AppTextStyles.small,
                      ),
                    ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _applying = true);

    try {
      final result = await CostPrices.applyToProject(
        projectId: projectId,
        entries: entries,
        userId: user.uid,
        projectName: _text(project['name']),
      );

      ProjectCostTotals? totals;
      try {
        totals = await ProjectCostSync.applyTotals(projectId);
      } catch (e) {
        debugPrint('تعذرت مزامنة تكاليف المشروع: $e');
      }

      if (!mounted) return;
      setState(() => _applying = false);

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('نتيجة الاستيراد'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Text(
                <String>[
                  'حُدِّث ${result.updatedLines} سعرًا في '
                      '${result.itemsTouched} بندًا من ${result.totalItems}.',
                  if (totals != null)
                    'إجمالي تكلفة المشروع: '
                        '${ProjectCosts.formatMoney(totals.displayTotal)}',
                  if (result.unmatched.isNotEmpty)
                    'أسطر بلا بند مطابق (${result.unmatched.length}):\n'
                        '${result.unmatched.take(12).join('، ')}',
                ].join('\n\n'),
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
      setState(() => _applying = false);
      AppWidgets.showError(context, 'تعذر استيراد الأسعار:\n$e');
    }
  }

  String _kindLabel(CostLineKind kind) {
    switch (kind) {
      case CostLineKind.material:
        return 'مواد';
      case CostLineKind.labor:
        return 'عمالة';
      case CostLineKind.equipment:
        return 'معدات';
      case CostLineKind.fuel:
        return 'محروقات';
    }
  }

  @override
  Widget build(BuildContext context) {
    final linkedOnly = widget.projectIds.isNotEmpty;

    return AppScaffold(
      title: 'أسعار التكاليف — مستوى المشروع',
      showBackButton: true,
      child: AppPage(
        scrollable: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPageHeader(
              title: 'استيراد جدول الأسعار',
              subtitle:
                  'اختر المشروع ثم البند، والصق جدول التحليل فتُضاف أسطره '
                  'إلى تكاليف العمالة والمعدات والمحروقات والمواد. '
                  'ولكل المشروع استخدم زر «تطبيق على كل بنود المشروع».',
              icon: Icons.table_chart_outlined,
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
            if (_applying)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: AppLoading(message: 'جاري تطبيق الأسعار على البنود...'),
              ),
            if (_importingProjectId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'جارٍ استيراد التكاليف لكل البنود: '
                  '${_progress ?? '...'}',
                  style: AppTextStyles.small,
                  textAlign: TextAlign.center,
                ),
              ),
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

                      return AppCard(
                        onTap: _applying
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProjectItemsPricesPage(
                                      projectId: doc.id,
                                      projectName: name,
                                    ),
                                  ),
                                ),
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
                                Icons.table_chart_outlined,
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
                                    'اضغط لاختيار بند، أو ⬇ لاستيراد '
                                    'التكاليف لكل بنوده',
                                    style: AppTextStyles.bodySecondary,
                                  ),
                                ],
                              ),
                            ),
                            if (_importingProjectId == doc.id)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              IconButton(
                                tooltip: 'استيراد التكاليف لكل بنود المشروع '
                                    '(133 سطرًا) بلا لصق',
                                onPressed: _applying
                                    ? null
                                    : () => _importAnalysisForProject(
                                          data,
                                          doc.id,
                                        ),
                                icon: const Icon(
                                  Icons.download_for_offline_outlined,
                                  color: AppColors.qualityCostManager,
                                ),
                              ),
                            IconButton(
                              tooltip: 'لصق جدول مختلف لكل بنود المشروع',
                              onPressed: _applying
                                  ? null
                                  : () => _importFor(data, doc.id),
                              icon: const Icon(
                                Icons.playlist_add_check_outlined,
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

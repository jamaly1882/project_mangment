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
import '../../core/widgets/cost_lines_editor.dart';
import '../../core/widgets/cost_table_editor.dart';

import 'price_import_dialog.dart';

/// ============================================================
/// نافذة أسعار التكاليف — صلاحية مدير إدارة الجودة
/// ============================================================
///
/// صفحة أولى: بنود المشاريع، ثم صفحة تحرير أسعار البند.
/// السعر الذي يحدّده المدير يحلّ محل القديم في مخطط البند وفعليه،
/// ويعيد حساب تكلفة كل سطر ومجاميع الأقسام وتكاليف المشروع.
///
/// المشرف يرى الأسعار في صفحته للقراءة فقط: يقفلها مدير الجودة.
class ItemPricesPage extends StatefulWidget {
  /// المشاريع المرتبطة بالمدير (فارغة = كل المشاريع).
  final List<String> projectIds;

  const ItemPricesPage({
    super.key,
    this.projectIds = const <String>[],
  });

  @override
  State<ItemPricesPage> createState() => _ItemPricesPageState();
}

class _ItemPricesPageState extends State<ItemPricesPage> {
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
    final project = _text(data['projectName']).toLowerCase();
    final code = _text(data['code']).toLowerCase();

    return name.contains(_search) ||
        type.contains(_search) ||
        project.contains(_search) ||
        code.contains(_search);
  }

  double _costOf(Map<String, dynamic> data) {
    final planned = ProjectCosts.totalOf(data);
    return planned > 0 ? planned : ProjectCosts.actualTotalOf(data);
  }

  @override
  Widget build(BuildContext context) {
    final linkedOnly = widget.projectIds.isNotEmpty;

    return AppScaffold(
      title: 'أسعار التكاليف',
      showBackButton: true,
      child: AppPage(
        scrollable: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPageHeader(
              title: 'تحديث أسعار التكاليف',
              subtitle:
                  'سعر المواد والعمالة والمعدات والمحروقات لكل بند. '
                  'السعر الجديد يحلّ محل القديم ويُعاد حساب تكاليف البند '
                  'والمشروع، ولا يظهر للمشرف.',
              icon: Icons.price_change_outlined,
            ),
            AppSpacing.verticalMd,
            AppTextField(
              controller: _searchController,
              label: 'البحث',
              hint: 'اسم البند أو نوعه أو المشروع',
              prefixIcon: Icons.search,
              onChanged: (value) {
                setState(() => _search = value.trim().toLowerCase());
              },
            ),
            AppSpacing.verticalMd,
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _firestore.collection('items').snapshots(),
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
                      .where(
                        (doc) => linkedOnly
                            ? widget.projectIds
                                .contains(_text(doc.data()['projectId']))
                            : true,
                      )
                      .where((doc) => _matches(doc.data()))
                      .toList();

                  if (docs.isEmpty) {
                    return const AppEmpty(
                      message: 'لا توجد بنود مطابقة.',
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
                      final projectId = _text(data['projectId']);
                      final projectName = _text(
                        data['projectName'],
                        fallback: projectId,
                      );
                      final unit = _text(data['unit']);
                      final cost = _costOf(data);

                      return AppCard(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ItemPriceEditorPage(
                              itemId: doc.id,
                              projectId: projectId,
                              itemName: name,
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
                                    '$projectName'
                                    '${unit.isEmpty ? '' : ' — $unit'}',
                                    style: AppTextStyles.bodySecondary,
                                  ),
                                ],
                              ),
                            ),
                            AppSpacing.horizontalSm,
                            Text(
                              ProjectCosts.formatMoney(cost),
                              style: AppTextStyles.bodySecondary,
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

// =============================================================
// تحرير أسعار بند واحد
// =============================================================

class ItemPriceEditorPage extends StatefulWidget {
  final String itemId;
  final String projectId;
  final String itemName;

  /// يفتح نافذة لصق جدول التحليل فور تحميل الأسطر.
  /// يُستخدم في مسار: المشروع ← البند ← استيراد.
  final bool openImportOnLoad;

  const ItemPriceEditorPage({
    super.key,
    required this.itemId,
    required this.projectId,
    this.itemName = '',
    this.openImportOnLoad = false,
  });

  @override
  State<ItemPriceEditorPage> createState() => _ItemPriceEditorPageState();
}

class _ItemPriceEditorPageState extends State<ItemPriceEditorPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  Map<String, dynamic> _item = <String, dynamic>{};

  /// الأسطر المخططة والفعلية بعد أي تعديل سعر.
  CostLines _planned = CostLines();
  CostLines _actual = CostLines();

  /// أسطر جديدة أضافها الاستيراد (نوع + فهرس في المخطط).
  final List<PriceEntry> _addedEntries = <PriceEntry>[];

  /// جداول الأسعار: متحكم لكل قسم (نفس جدول صفحة المشرف).
  final Map<CostLineKind, CostLinesEditorController> _priceEditors =
      <CostLineKind, CostLinesEditorController>{
    for (final schema in CostLineSchema.ordered)
      schema.kind: CostLinesEditorController(schema),
  };

  /// الأسعار وقت التحميل: لمقارنة ما غيّره المدير وتوثيقه.
  final Map<String, double> _originalPrices = <String, double>{};

  @override
  void dispose() {
    for (final editor in _priceEditors.values) {
      editor.dispose();
    }
    super.dispose();
  }

  /// يجمع الأسطر من الجداول إلى [planned].
  void _syncPlannedFromEditors() {
    _planned = CostLines(<CostLineKind, List<Map<String, dynamic>>>{
      for (final schema in CostLineSchema.ordered)
        schema.kind: _priceEditors[schema.kind]!.lines,
    });
  }

  /// يعيد تحميل الجداول من [planned] (بعد الاستيراد أو اللصق).
  void _reloadEditors() {
    for (final schema in CostLineSchema.ordered) {
      _priceEditors[schema.kind]!.applyLines(_planned[schema.kind]);
    }
  }

  String _priceKeyOf(CostLineKind kind, String label) =>
      '${kind.name}|${normalizedLineName(label)}';

  void _captureOriginalPrices() {
    _originalPrices.clear();

    for (final schema in CostLineSchema.ordered) {
      for (final line in _planned[schema.kind]) {
        final label = CostLineSchema.text(line, schema.titleKey);
        if (label.trim().isEmpty) continue;

        _originalPrices[_priceKeyOf(schema.kind, label)] =
            CostLineSchema.number(line, schema.priceKey);
      }
    }
  }

  /// الأسعار التي تغيّرت عن وقت التحميل (للتوثيق في السجل).
  List<PriceChange> _pendingPriceChanges() {
    final changes = <PriceChange>[];

    for (final schema in CostLineSchema.ordered) {
      for (final line in _planned[schema.kind]) {
        final label = CostLineSchema.text(line, schema.titleKey);
        if (label.trim().isEmpty) continue;

        final old = _originalPrices[_priceKeyOf(schema.kind, label)] ?? 0;

        final now = CostLineSchema.number(line, schema.priceKey);
        if ((old - now).abs() < 0.0001) continue;

        changes.add(
          PriceChange(
            kind: schema.kind,
            label: label,
            oldPrice: old,
            newPrice: now,
          ),
        );
      }
    }

    return changes;
  }

  double get _contractQuantity {
    final executed = ProjectCosts.nonNegative(_item['executedQuantity']);
    if (executed > 0) return executed;

    return ProjectCosts.nonNegative(_item['contractQuantity']);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final itemDoc =
          await _firestore.collection('items').doc(widget.itemId).get();
      if (!itemDoc.exists) throw Exception('البند غير موجود.');

      final item = itemDoc.data() ?? <String, dynamic>{};
      final detailsDoc = await _firestore
          .collection('item_details')
          .doc(widget.itemId)
          .get();
      final details = detailsDoc.data() ?? <String, dynamic>{};

      final quantity = ProjectCosts.nonNegative(item['executedQuantity']) > 0
          ? ProjectCosts.nonNegative(item['executedQuantity'])
          : ProjectCosts.nonNegative(item['contractQuantity']);

      // مصدر المخطط: تفاصيل البند إن كانت تحمل أسطرًا، وإلا وثيقة البند.
      final plannedSource =
          CostLines.fromData(details, contractQuantity: quantity).isNotEmpty
              ? details
              : item;

      final planned = CostLines.fromData(
        plannedSource,
        contractQuantity: quantity,
        unit: (item['unit'] ?? '').toString(),
      );

      final actual = CostLines.fromData(
        details.isNotEmpty ? details : item,
        actual: true,
        contractQuantity: quantity,
        unit: (item['unit'] ?? '').toString(),
      );

      // بعد أي تحميل تُعاد تعبئة الجداول لتظهر القيم المحفوظة.
      if (!mounted) return;
      setState(() {
        _item = item;
        _planned = planned;
        _actual = actual;
        _loading = false;
      });

      _reloadEditors();
      _captureOriginalPrices();

      if (widget.openImportOnLoad) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openImport();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ============================================================
  // تعديل الأسعار
  // ============================================================

  /// يطبّق السعر على أسطر المخطط والفعلي معًا، ويضيف غير الموجود.
  void _applyEntries(List<PriceEntry> entries) {
    final changes = <PriceChange>[];
    var added = 0;

    for (final entry in entries) {
      var matched = false;

      for (final target in <CostLines>[_planned, _actual]) {
        final lines = target[entry.kind];

        for (final line in lines) {
          final schema = CostLineSchema.of(entry.kind);
          final label = CostLineSchema.text(line, schema.titleKey);

          if (!CostPrices.matches(label, entry.label)) continue;

          matched = true;

          final oldPrice = CostPrices.priceOf(entry.kind, line);
          if (CostPrices.applyPriceToLine(schema, line, entry.price)) {
            final change = PriceChange(
              kind: entry.kind,
              label: label,
              oldPrice: oldPrice,
              newPrice: entry.price,
            );

            changes.add(change);
          }
        }
      }

      if (!matched) {
        _planned[entry.kind].add(
          CostPrices.newLine(entry.kind, entry),
        );
        _addedEntries.add(entry);
        added++;
      }
    }

    // نُعيد تعبئة الجداول لتظهر الأسعار المطبقة.
    _reloadEditors();

    if (!mounted) return;

    setState(() {});

    final parts = <String>[
      if (changes.isNotEmpty) 'تم تحديث ${changes.length} سعرًا',
      if (added > 0) 'أُضيف $added سطرًا جديدًا بلا كميات',
    ];

    if (parts.isEmpty) {
      AppWidgets.showWarning(
        context,
        'لم يتغير أي سعر؛ الأرقام المُلصقة تطابق الأسعار المحفوظة.',
      );
      return;
    }

    AppWidgets.showSuccess(context, '${parts.join('، ')}. راجع ثم احفظ.');
  }

  Future<void> _save() async {
    if (_saving) return;

    final user = _auth.currentUser;
    if (user == null) {
      AppWidgets.showError(context, 'انتهت جلسة تسجيل الدخول.');
      return;
    }

    // الأسعار من الجداول هي المصدر الأخير.
    _syncPlannedFromEditors();

    final planned = _planned;
    final changes = _pendingPriceChanges();

    // المشرف يقرأ الأسطر الفعلية: ننسخ إليها الأسعار ونضيف ما ينقصها.
    final actual = CostPrices.mirrorPlannedPrices(
      planned: planned,
      actual: _actual,
    );

    if (planned.isEmpty && actual.isEmpty) {
      AppWidgets.showWarning(context, 'لا توجد أسطر تكلفة في هذا البند.');
      return;
    }

    setState(() => _saving = true);

    try {
      await CostPrices.save(
        itemId: widget.itemId,
        projectId: widget.projectId,
        planned: planned,
        actual: actual,
        changes: changes,
        userId: user.uid,
        itemName: widget.itemName.isNotEmpty
            ? widget.itemName
            : (_item['name'] ?? '').toString(),
        contractQuantity: _contractQuantity,
      );

      ProjectCostTotals? totals;
      try {
        totals = await ProjectCostSync.applyTotals(widget.projectId);
      } catch (e) {
        debugPrint('تعذرت مزامنة تكاليف المشروع: $e');
      }

      if (!mounted) return;

      setState(() {
        _saving = false;
        _planned = planned;
        _actual = actual;
      });

      _captureOriginalPrices();

      AppWidgets.showSuccess(
        context,
        <String>[
          'تم حفظ الأسعار وتطبيقها على مخطط البند وفعليه.',
          if (_addedEntries.isNotEmpty)
            'أُضيف ${_addedEntries.length} سطرًا جديدًا بلا كميات؛ '
                'أكمل كمياتها من صفحة تفاصيل البند.',
          if (totals != null)
            'إجمالي تكلفة المشروع: '
                '${ProjectCosts.formatMoney(totals.displayTotal)}',
        ].join('\n'),
      );

      _addedEntries.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppWidgets.showError(context, 'تعذر حفظ الأسعار:\n$e');
    }
  }

  // ============================================================
  // استيراد جدول التحليل
  // ============================================================

  /// استيراد أسعار التحليل المضمّنة بضغطة واحدة.
  Future<void> _importUnitAnalysis() async {
    if (_saving) return;

    final user = _auth.currentUser;
    if (user == null) {
      AppWidgets.showError(context, 'انتهت جلسة تسجيل الدخول.');
      return;
    }

    final confirmed = await AppWidgets.showConfirmDialog(
      context: context,
      title: 'استيراد أسعار التحليل',
      message: 'سيُطبَّق جدول تحليل الوحدة ($unitAnalysisYear) على هذا البند: '
          '${unitAnalysisLaborCount} مهنة، '
          '${unitAnalysisEquipmentCount} معدة، '
          '${unitAnalysisFuelCount} وقود، '
          '${unitAnalysisMaterialsCount} مادة.\n\n'
          'السطر الموجود يُحدَّث سعره، وغير الموجود يُضاف بلا كميات '
          'حتى يدخلها المشرف. هل تريد المتابعة؟',
      confirmText: 'استيراد',
    );

    if (!confirmed) return;

    setState(() => _saving = true);

    try {
      final result = await UnitAnalysisImporter.importToItem(
        itemId: widget.itemId,
        projectId: widget.projectId,
        userId: user.uid,
      );

      ProjectCostTotals? totals;
      try {
        totals = await ProjectCostSync.applyTotals(widget.projectId);
      } catch (e) {
        debugPrint('تعذرت مزامنة تكاليف المشروع: $e');
      }

      await _load();

      if (!mounted) return;
      setState(() => _saving = false);

      AppWidgets.showSuccess(
        context,
        <String>[
          result.message,
          if (totals != null)
            'إجمالي تكلفة المشروع: '
                '${ProjectCosts.formatMoney(totals.displayTotal)}',
        ].join('\n'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppWidgets.showError(context, 'تعذر استيراد أسعار التحليل:\n$e');
    }
  }

  Future<void> _openImport() async {
    final controller = TextEditingController();
    final result = await showDialog<List<PriceEntry>>(
      context: context,
      builder: (dialogContext) => PriceImportDialog(controller: controller),
    );

    controller.dispose();

    if (result == null || result.isEmpty) return;

    _applyEntries(result);
  }

  // ============================================================
  // العرض
  // ============================================================

  double get _plannedTotal => _planned.grandTotal;

  double get _actualTotal => _actual.grandTotal;

  Widget _buildSection(CostLineKind kind, Color accent) {
    return CostTableEditor(
      schema: CostLineSchema.of(kind),
      controller: _priceEditors[kind]!,
      accent: accent,
      // مدير الجودة يعدّل السعر من الجدول مباشرة، والتعليم يعني
      // «السطر مُدرج» بلا كميات (الكميات يدخلها المشرف).
      priceEditable: true,
      quantitySelection: false,
      trailingNote: 'علّم ✓ على الأسطر التي يستخدمها البند، وعدّل '
          '${CostPrices.priceLabelOf(kind)}. إلغاء ✓ يصفّر الكمية فقط.',
      onChanged: () {
        if (!mounted) return;
        setState(_syncPlannedFromEditors);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (_item['name'] ?? widget.itemName).toString();
    final unit = (_item['unit'] ?? '').toString();
    final quantity = _contractQuantity;

    return AppScaffold(
      title: 'أسعار التكاليف',
      showBackButton: true,
      actions: [
        IconButton(
          tooltip: 'استيراد أسعار التحليل',
          onPressed: _loading || _error != null || _saving
              ? null
              : _importUnitAnalysis,
          icon: const Icon(Icons.download_for_offline_outlined),
        ),
        IconButton(
          tooltip: 'لصق جدول أسعار',
          onPressed: _loading || _error != null ? null : _openImport,
          icon: const Icon(Icons.upload_file_outlined),
        ),
      ],
      child: _loading
          ? const AppLoading(message: 'جاري تحميل أسطر التكلفة...')
          : _error != null
              ? AppPage(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          size: 56,
                          color: AppColors.warning,
                        ),
                        AppSpacing.verticalMd,
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body,
                        ),
                        AppSpacing.verticalLg,
                        AppButton(
                          label: 'إعادة المحاولة',
                          icon: Icons.refresh,
                          expanded: true,
                          onPressed: _load,
                        ),
                      ],
                    ),
                  ),
                )
              : AppPage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppPageHeader(
                        title: name.isEmpty ? 'بند' : name,
                        subtitle: 'السعر الجديد يحلّ محل القديم '
                            '${unit.isEmpty ? '' : '— الوحدة: $unit'}',
                        icon: Icons.price_change_outlined,
                      ),
                      AppSpacing.verticalMd,
                      AppInfoRow(
                        label: 'الكمية المحسوب عليها الإجمالي',
                        value: ProjectCosts.formatNumber(quantity),
                        icon: Icons.straighten,
                      ),
                      AppSpacing.verticalXs,
                      AppInfoRow(
                        label: 'إجمالي المخطط',
                        value: ProjectCosts.formatMoney(_plannedTotal),
                        icon: Icons.timeline_outlined,
                      ),
                      AppSpacing.verticalXs,
                      AppInfoRow(
                        label: 'إجمالي الفعلي المسجَّل',
                        value: ProjectCosts.formatMoney(_actualTotal),
                        icon: Icons.check_circle_outline,
                      ),
                      AppSpacing.verticalMd,
                      AppButton(
                        label: _saving
                            ? 'جارٍ الاستيراد...'
                            : 'استيراد أسعار التحليل ($unitAnalysisRowCount سطرًا)',
                        icon: Icons.download_for_offline_outlined,
                        expanded: true,
                        loading: _saving,
                        onPressed: _saving ? null : _importUnitAnalysis,
                      ),
                      AppSpacing.verticalSm,
                      AppOutlinedButton(
                        label: 'لصق جدول مختلف (متقدّم)',
                        icon: Icons.upload_file_outlined,
                        expanded: true,
                        onPressed: _saving ? null : _openImport,
                      ),
                      AppSpacing.verticalMd,
                      _buildSection(CostLineKind.material, AppColors.primary),
                      AppSpacing.verticalMd,
                      _buildSection(CostLineKind.labor, AppColors.engineer),
                      AppSpacing.verticalMd,
                      _buildSection(CostLineKind.equipment, AppColors.time),
                      AppSpacing.verticalMd,
                      _buildSection(CostLineKind.fuel, AppColors.driver),
                      AppSpacing.verticalLg,
                      AppButton(
                        label: _saving ? 'جارٍ الحفظ...' : 'حفظ الأسعار',
                        icon: Icons.save_outlined,
                        loading: _saving,
                        expanded: true,
                        onPressed: _saving ? null : _save,
                      ),
                      AppSpacing.verticalSm,
                      const Text(
                        'الحفظ يطبّق الأسعار على مخطط البند وفعليه، '
                        'ويعيد حساب تكلفة كل سطر ومجاميع الأقسام وتكاليف المشروع.',
                        style: AppTextStyles.small,
                        textAlign: TextAlign.center,
                      ),
                      AppSpacing.verticalXl,
                    ],
                  ),
                ),
    );
  }
}

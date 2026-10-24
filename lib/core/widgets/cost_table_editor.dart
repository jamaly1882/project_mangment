import 'package:flutter/material.dart';

import '../services/unit_analysis_seed.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/cost_lines.dart';
import '../utils/costs.dart';
import 'app_widgets.dart';
import 'cost_lines_editor.dart';

/// ============================================================
/// جدول اختيار أسطر التكلفة من جدول التحليل
/// ============================================================
///
/// بدل صفوف طويلة فيها كل سطر بحقوله، يعرض كل قسم **جدولًا**:
///   [✓] الاسم | الوحدة | السعر | الكمية/العدد والمدة | التكلفة
///
/// القواعد:
///   • ✓ يعني أن السطر داخل تكاليف البند، ووضعه كمية ابتدائية ١.
///   • إلغاء ✓ **يصفّر الكمية فقط** ويُبقي الاسم والسعر (لا حذف).
///   • السعر يُعدَّل من صفحة مدير الجودة فقط؛ عند المشرف يُقرأ فقط.
///   • يمكن إضافة سطر مخصص غير موجود في جدول التحليل.
class CostTableEditor extends StatefulWidget {
  const CostTableEditor({
    super.key,
    required this.schema,
    required this.controller,
    this.accent,
    this.priceEditable = false,
    this.trailingNote,
    this.onChanged,
    this.allowCustom = true,
    this.quantitySelection = true,
  });

  final CostLineSchema schema;
  final CostLinesEditorController controller;
  final Color? accent;

  /// هل يمكن تعديل السعر من الجدول (مدير الجودة)؟
  final bool priceEditable;

  final String? trailingNote;
  final VoidCallback? onChanged;
  final bool allowCustom;

  /// معنى ✓:
  ///   true  → السطر مستخدم وله كمية (صفحة المشرف).
  ///   false → السطر مُدرج في البند بالاسم والسعر فقط (صفحة الجودة).
  final bool quantitySelection;

  @override
  State<CostTableEditor> createState() => _CostTableEditorState();
}

class _CostTableEditorState extends State<CostTableEditor> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuilt);
    widget.controller.attachRows();
  }

  @override
  void didUpdateWidget(CostTableEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_rebuilt);
      oldWidget.controller.detachRows();

      widget.controller.addListener(_rebuilt);
      widget.controller.attachRows();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuilt);
    widget.controller.detachRows();
    _searchController.dispose();
    super.dispose();
  }

  void _rebuilt() {
    if (!mounted) return;
    setState(() {});
    widget.onChanged?.call();
  }

  CostLineSchema get _schema => widget.schema;
  CostLinesEditorController get _controller => widget.controller;

  String _normalize(String value) => value
      .trim()
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .toLowerCase();

  bool _matchesQuery(String label) {
    if (_query.trim().isEmpty) return true;
    return _normalize(label).contains(_normalize(_query));
  }

  /// أسطر جدول التحليل مع فهرسها في البند إن وُجد.
  List<_AnalysisLine> get _analysisLines {
    final lines = _controller.lines;

    return <_AnalysisLine>[
      for (final row in UnitAnalysisSeed.rowsOf(_schema.kind))
        () {
          final index = _controller.indexOfLabel(row.name);
          final price = index >= 0
              ? CostLineSchema.number(lines[index], _schema.priceKey)
              : row.amount;

          return _AnalysisLine(
            label: row.name,
            price: price > 0 ? price : row.amount,
            index: index,
            selected: _isSelected(index),
            cost: index >= 0 ? _schema.costOf(lines[index]) : 0,
          );
        }(),
    ];
  }

  /// فهارس الأسطر غير الموجودة في جدول التحليل (مخصصة أو فارغة).
  List<int> get _customIndexes {
    final labels = UnitAnalysisSeed.rowsOf(_schema.kind)
        .map((row) => row.name)
        .toList();

    final result = <int>[];

    for (var i = 0; i < _controller.count; i++) {
      final label = _controller.textOf(i, _schema.titleKey);

      if (label.trim().isEmpty) {
        result.add(i);
        continue;
      }

      if (!labels.any((name) => sameLineName(name, label))) {
        result.add(i);
      }
    }

    return result;
  }

  int get _selectedCount {
    var count = 0;
    final labels = UnitAnalysisSeed.rowsOf(_schema.kind)
        .where((row) => _matchesQuery(row.name));

    for (final row in labels) {
      if (_isSelected(_controller.indexOfLabel(row.name))) count++;
    }

    return count;
  }

  // ============================================================
  // العرض
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? AppColors.primary;
    final lines = _controller.lines;

    final analysis =
        _analysisLines.where((line) => _matchesQuery(line.label)).toList();
    final custom = _customIndexes;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionTitle(
            title: _schema.title,
            subtitle: <String>[
              if (_schema.note.isNotEmpty) _schema.note,
              '${UnitAnalysisSeed.rowsOf(_schema.kind).length} سطرًا · '
                  'المختار: $_selectedCount',
            ].join(' — '),
            icon: _schema.icon,
          ),
          AppSpacing.verticalSm,

          // ------- البحث وعدد المختار -------
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchController,
                    textAlign: TextAlign.right,
                    style: AppTextStyles.body,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'ابحث في ${_schema.rowTitle}…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              AppSpacing.horizontalSm,
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'المختار: $_selectedCount',
                  style: AppTextStyles.small.copyWith(
                    color: accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          AppSpacing.verticalSm,

          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!compact) _headerRow(),
                  if (!compact) const Divider(height: 12),

                  if (analysis.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'لا يوجد سطر مطابق لبحثك.',
                        style: AppTextStyles.small,
                      ),
                    ),

                  for (final line in analysis)
                    compact
                        ? _compactRow(line, lines, accent)
                        : _tableRow(line, lines, accent),
                ],
              );
            },
          ),

          if (custom.isNotEmpty) ...[
            AppSpacing.verticalMd,
            Text(
              'أسطر مخصصة',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
            ),
            for (final index in custom) _customRow(index, lines, accent),
          ],

          if (widget.allowCustom) ...[
            AppSpacing.verticalSm,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _controller.addRow(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إضافة سطر مخصص'),
              ),
            ),
          ],

          AppSpacing.verticalSm,

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'إجمالي ${_shortName(_schema.kind)}',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  ProjectCosts.formatMoney(_controller.total),
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),

          if (widget.trailingNote != null) ...[
            AppSpacing.verticalXs,
            Text(widget.trailingNote!, style: AppTextStyles.small),
          ],
        ],
      ),
    );
  }

  Widget _headerRow() {
    final cells = <Widget>[
      const SizedBox(width: 40),
      Expanded(flex: 4, child: _header('الاسم')),
      if (_showsUnit) Expanded(flex: 2, child: _header('الوحدة')),
      Expanded(flex: 2, child: _header(_priceLabel)),
      ..._quantityCells.map(
        (cell) => Expanded(flex: 2, child: _header(cell.label)),
      ),
      Expanded(flex: 2, child: _header('التكلفة')),
    ];

    return Row(children: _withSpacing(cells));
  }

  Widget _header(String text) => Text(
        text,
        style: AppTextStyles.small.copyWith(fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      );

  Widget _tableRow(
    _AnalysisLine line,
    List<Map<String, dynamic>> lines,
    Color accent,
  ) {
    final index = line.index;

    final cells = <Widget>[
      SizedBox(
        width: 40,
        child: Checkbox(
          value: line.selected,
          activeColor: accent,
          onChanged: (value) => _toggle(line, value == true),
        ),
      ),
      Expanded(
        flex: 4,
        child: Text(
          line.label,
          style: AppTextStyles.body,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (_showsUnit)
        Expanded(
          flex: 2,
          child: Text(
            index >= 0
                ? CostLineSchema.text(lines[index], _unitKey)
                : MaterialUnits.forName(line.label).first,
            style: AppTextStyles.small,
            textAlign: TextAlign.center,
          ),
        ),
      Expanded(
        flex: 2,
        child: _priceCell(line, lines),
      ),
      for (final cell in _quantityCells)
        Expanded(
          flex: 2,
          child: index >= 0
              ? _numberField(_controller.numberController(index, cell.key))
              : _addCell(line),
        ),
      Expanded(
        flex: 2,
        child: Text(
          line.cost > 0 ? ProjectCosts.formatNumber(line.cost) : '0',
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.bold,
            color: line.cost > 0 ? accent : AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: _withSpacing(cells),
      ),
    );
  }

  Widget _compactRow(
    _AnalysisLine line,
    List<Map<String, dynamic>> lines,
    Color accent,
  ) {
    final index = line.index;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: line.selected
            ? accent.withValues(alpha: 0.05)
            : AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: line.selected
              ? accent.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(
                value: line.selected,
                activeColor: accent,
                onChanged: (value) => _toggle(line, value == true),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.label,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$_priceLabel: ${ProjectCosts.formatMoney(line.price)}'
                      '${_showsUnit ? ' · ${MaterialUnits.forName(line.label).first}' : ''}',
                      style: AppTextStyles.small,
                    ),
                  ],
                ),
              ),
              Text(
                ProjectCosts.formatMoney(line.cost),
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.bold,
                  color: line.cost > 0 ? accent : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (index >= 0) ...[
            AppSpacing.verticalXs,
            Row(
              children: [
                for (final cell in _quantityCells) ...[
                  Expanded(
                    child: _labeledField(
                      cell.label,
                      _controller.numberController(index, cell.key),
                    ),
                  ),
                  AppSpacing.horizontalSm,
                ],
                Expanded(
                  flex: 2,
                  child: widget.priceEditable
                      ? _labeledField(
                          _priceLabel,
                          _controller.numberController(index, _schema.priceKey),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// خلية سطر غير مُعلَّم: زر إضافة يعلّمه ويُظهر حقول الكمية.
  Widget _addCell(_AnalysisLine line) {
    return Center(
      child: IconButton(
        tooltip: 'إضافة السطر',
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.add_circle_outline),
        onPressed: () => _toggle(line, true),
      ),
    );
  }

  Widget _priceCell(_AnalysisLine line, List<Map<String, dynamic>> lines) {
    final index = line.index;
    final price = index >= 0
        ? CostLineSchema.number(lines[index], _schema.priceKey)
        : line.price;

    if (widget.priceEditable && index >= 0) {
      return _numberField(
        _controller.numberController(index, _schema.priceKey),
      );
    }

    return Text(
      ProjectCosts.formatNumber(price),
      style: AppTextStyles.small.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _customRow(
    int index,
    List<Map<String, dynamic>> lines,
    Color accent,
  ) {
    final schema = _schema;
    final cost = schema.costOf(lines[index]);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller:
                        _controller.textController(index, schema.titleKey),
                    style: AppTextStyles.body,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'اسم ${schema.rowTitle}',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              AppSpacing.horizontalSm,
              Expanded(
                flex: 2,
                child: widget.priceEditable
                    ? _numberField(
                        _controller.numberController(index, schema.priceKey),
                      )
                    : Text(
                        ProjectCosts.formatNumber(
                          CostLineSchema.number(lines[index], schema.priceKey),
                        ),
                        style: AppTextStyles.small,
                        textAlign: TextAlign.center,
                      ),
              ),
              IconButton(
                tooltip: 'حذف السطر',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _controller.removeAt(index),
              ),
            ],
          ),
          AppSpacing.verticalXs,
          Row(
            children: [
              for (final cell in _quantityCells) ...[
                Expanded(
                  child: _labeledField(
                    cell.label,
                    _controller.numberController(index, cell.key),
                  ),
                ),
                AppSpacing.horizontalSm,
              ],
              Expanded(
                flex: 2,
                child: Text(
                  'التكلفة: ${ProjectCosts.formatNumber(cost)}',
                  style: AppTextStyles.small.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numberField(TextEditingController controller) {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: AppTextStyles.body,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _labeledField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTextStyles.small, textAlign: TextAlign.center),
        const SizedBox(height: 2),
        _numberField(controller),
      ],
    );
  }

  /// هل السطر «مختار» حسب وضع الصفحة؟
  bool _isSelected(int index) {
    if (index < 0) return false;
    if (!widget.quantitySelection) return true;

    return _controller.hasQuantity(index);
  }

  void _toggle(_AnalysisLine line, bool selected) {
    if (selected) {
      if (widget.quantitySelection) {
        // المشرف: السطر يبدأ بكمية ١ فتظهر تكلفته.
        _controller.selectLabel(line.label, line.price);
      } else {
        // الجودة: سطر بالسعر فقط، بلا كميات (المشرف يدخلها).
        _controller.ensureLabel(line.label, line.price);
      }
    } else if (widget.quantitySelection) {
      // إلغاء ✓ يصفّر الكمية ويُبقي الاسم والسعر.
      _controller.deselectLabel(line.label);
    } else {
      final index = _controller.indexOfLabel(line.label);
      if (index >= 0) _controller.removeAt(index);
    }

    widget.onChanged?.call();
  }

  // ============================================================
  // تفاصيل الأعمدة حسب القسم
  // ============================================================

  bool get _showsUnit => _schema.kind == CostLineKind.material;

  String get _unitKey => 'unit';

  String get _priceLabel {
    switch (_schema.kind) {
      case CostLineKind.material:
        return 'السعر';
      case CostLineKind.labor:
        return 'الأجرة';
      case CostLineKind.equipment:
        return 'الإهلاك';
      case CostLineKind.fuel:
        return 'سعر اللتر';
    }
  }

  List<_QuantityCell> get _quantityCells {
    switch (_schema.kind) {
      case CostLineKind.material:
        return const <_QuantityCell>[
          _QuantityCell(key: 'quantity', label: 'الكمية'),
        ];
      case CostLineKind.fuel:
        return const <_QuantityCell>[
          _QuantityCell(key: 'quantity', label: 'اللترات'),
        ];
      case CostLineKind.equipment:
        return const <_QuantityCell>[
          _QuantityCell(key: 'count', label: 'العدد'),
          _QuantityCell(key: 'quantity', label: 'الساعات'),
        ];
      case CostLineKind.labor:
        return const <_QuantityCell>[
          _QuantityCell(key: 'count', label: 'العدد'),
          _QuantityCell(key: 'duration', label: 'المدة'),
        ];
    }
  }

  List<Widget> _withSpacing(List<Widget> cells) {
    final result = <Widget>[];

    for (var i = 0; i < cells.length; i++) {
      result.add(cells[i]);
      if (i != cells.length - 1) result.add(AppSpacing.horizontalSm);
    }

    return result;
  }

  static String _shortName(CostLineKind kind) {
    switch (kind) {
      case CostLineKind.material:
        return 'المواد';
      case CostLineKind.labor:
        return 'أجور العمالة';
      case CostLineKind.equipment:
        return 'المعدات';
      case CostLineKind.fuel:
        return 'المحروقات';
    }
  }
}

class _AnalysisLine {
  const _AnalysisLine({
    required this.label,
    required this.price,
    required this.index,
    required this.selected,
    required this.cost,
  });

  final String label;
  final double price;
  final int index;
  final bool selected;
  final double cost;
}

class _QuantityCell {
  const _QuantityCell({required this.key, required this.label});

  final String key;
  final String label;
}

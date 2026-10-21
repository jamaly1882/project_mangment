import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/cost_lines.dart';
import '../utils/costs.dart';
import 'app_widgets.dart';

// ============================================================
// خيار من بيانات النظام (المواد أو حصر المعدات)
// ============================================================

class CostPickerOption {
  const CostPickerOption({required this.id, required this.label});

  final String id;
  final String label;
}

// ============================================================
// حالة سطر واحد
// ============================================================

class _CostLineRow {
  _CostLineRow({
    required CostLineSchema schema,
    Map<String, dynamic>? data,
  })  : controllers = <String, TextEditingController>{
          for (final field in schema.fields)
            field.key: TextEditingController(
              text: _initialText(schema, field, data),
            ),
        },
        costController = TextEditingController(
          text: _costText(data),
        ),
        manual = data?[CostLineSchema.manualKey] == true,
        legacy = data?[CostLineSchema.legacyKey] == true,
        id = data == null ? null : _idOf(schema, data);

  final Map<String, TextEditingController> controllers;
  final TextEditingController costController;

  bool manual;
  bool legacy;
  String? id;

  static String _costText(Map<String, dynamic>? data) {
    final cost = data?[CostLineSchema.costKey];

    if (cost == null) return '';

    final number = ProjectCosts.nonNegative(cost);

    return number > 0 ? ProjectCosts.toEditText(number) : '';
  }

  static String? _idOf(CostLineSchema schema, Map<String, dynamic> data) {
    final key = schema.pickerIdKey;
    if (key == null) return null;

    final value = data[key];
    if (value == null) return null;

    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static String _initialText(
    CostLineSchema schema,
    CostLineField field,
    Map<String, dynamic>? data,
  ) {
    final raw = data?[field.key];

    if (raw != null) {
      if (field.isNumber) {
        final number = ProjectCosts.nonNegative(raw);
        return number > 0 ? ProjectCosts.toEditText(number) : '';
      }

      return raw.toString().trim();
    }

    return field.defaultValue ?? '';
  }

  void attach(void Function() onChange) {
    for (final controller in controllers.values) {
      controller.addListener(onChange);
    }

    costController.addListener(onChange);
  }

  void detach(void Function() onChange) {
    for (final controller in controllers.values) {
      controller.removeListener(onChange);
    }

    costController.removeListener(onChange);
  }

  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }

    costController.dispose();
  }

  double computed(CostLineSchema schema) =>
      schema.computedCost(toMap(schema));

  bool get hasInput {
    if (controllers.values
        .any((c) => c.text.trim().isNotEmpty)) {
      return true;
    }

    return costController.text.trim().isNotEmpty;
  }

  Map<String, dynamic> toMap(CostLineSchema schema) {
    final map = <String, dynamic>{};

    for (final field in schema.fields) {
      final text = controllers[field.key]!.text.trim();

      if (field.isNumber) {
        map[field.key] = ProjectCosts.parseNumber(text);
      } else {
        map[field.key] = text;
      }
    }

    final typed = ProjectCosts.parseOptional(
      costController.text.trim(),
    );

    final auto = schema.computedCost(map);

    final isManual = manual &&
        typed != null &&
        (typed - auto).abs() >= 0.01;

    map[CostLineSchema.costKey] =
        isManual ? ProjectCosts.nonNegative(typed) : auto;
    map[CostLineSchema.manualKey] = isManual;

    if (legacy) map[CostLineSchema.legacyKey] = true;

    final idKey = schema.pickerIdKey;

    if (idKey != null) map[idKey] = id;

    return map;
  }

  /// يحدّث خانة التكلفة من المحسوب ما لم يثبّتها المستخدم يدويًا.
  void syncCost(CostLineSchema schema) {
    final auto = computed(schema);
    final typed = ProjectCosts.parseOptional(
      costController.text.trim(),
    );

    if (typed != null && (typed - auto).abs() >= 0.01) {
      manual = true;
      return;
    }

    manual = false;

    final wanted = ProjectCosts.toEditText(auto);

    if (costController.text != wanted) {
      costController.value = TextEditingValue(
        text: wanted,
        selection: TextSelection.collapsed(offset: wanted.length),
      );
    }
  }
}

// ============================================================
// متحكم المحرر: يملك الأسطر ويطلع المنادى عليها عند التغيير
// ============================================================

class CostLinesEditorController extends ChangeNotifier {
  CostLinesEditorController(this.schema);

  final CostLineSchema schema;

  final List<_CostLineRow> _rows = <_CostLineRow>[];

  List<Map<String, dynamic>> get lines =>
      _rows.map((row) => row.toMap(schema)).toList();

  double get total {
    double sum = 0;

    for (final line in lines) {
      sum += schema.costOf(line);
    }

    return sum;
  }

  int get count => _rows.length;

  bool get hasInput => _rows.any((row) => row.hasInput);

  List<String> validate() =>
      CostLines(<CostLineKind, List<Map<String, dynamic>>>{
        schema.kind: lines,
      }).validate();

  void addRow([Map<String, dynamic>? data]) {
    final row = _CostLineRow(schema: schema, data: data);

    row.syncCost(schema);
    _rows.add(row);

    if (_attached) row.attach(_onChange);

    notifyListeners();
  }

  void removeAt(int index) {
    if (index < 0 || index >= _rows.length) return;

    final row = _rows.removeAt(index);

    if (_attached) {
      row.detach(_onChange);
    }

    row.dispose();
    notifyListeners();
  }

  void duplicate(int index) {
    if (index < 0 || index >= _rows.length) return;

    _rows.insert(index + 1, _CostLineRow(
      schema: schema,
      data: _rows[index].toMap(schema),
    ));

    if (_attached) _rows[index + 1].attach(_onChange);

    notifyListeners();
  }

  /// يستبدل الأسطر الحالية بأخرى محفوظة (عند تحميل البند).
  void applyLines(Iterable<Map<String, dynamic>>? data) {
    _clearRows();

    for (final line in data ?? const <Map<String, dynamic>>[]) {
      _rows.add(_CostLineRow(
        schema: schema,
        data: Map<String, dynamic>.from(line),
      ));
    }

    if (_attached) {
      for (final row in _rows) {
        row.attach(_onChange);
      }
    }

    notifyListeners();
  }

  // ==========================================================
  // وصول الواجهة إلى خانات السطر
  // ==========================================================

  _CostLineRow? _row(int index) {
    if (index < 0 || index >= _rows.length) return null;
    return _rows[index];
  }

  String textOf(int index, String key) =>
      _row(index)?.controllers[key]?.text.trim() ?? '';

  void setText(int index, String key, String value) {
    final row = _row(index);
    if (row == null) return;

    row.controllers[key]?.text = value;
    _onChange();
  }

  TextEditingController numberController(int index, String key) =>
      _row(index)!.controllers[key]!;

  TextEditingController textController(int index, String key) =>
      _row(index)!.controllers[key]!;

  TextEditingController costControllerOf(int index) =>
      _row(index)!.costController;

  String? idOf(int index) => _row(index)?.id;

  bool isManual(int index) => _row(index)?.manual ?? false;

  bool isLegacy(int index) => _row(index)?.legacy ?? false;

  /// تثبيت التكلفة المكتوبة يدويًا أو إعادة حسابها تلقائيًا.
  void toggleManual(int index) {
    final row = _row(index);
    if (row == null) return;

    if (row.manual) {
      row.manual = false;
      row.syncCost(schema);
    } else {
      final typed = ProjectCosts.parseOptional(
        row.costController.text.trim(),
      );

      if (typed == null) {
        row.costController.text =
            ProjectCosts.toEditText(row.computed(schema));
      }

      row.manual = true;
    }

    notifyListeners();
  }

  /// اختيار مادة/معدة من بيانات النظام: يعبّئ الاسم ويحفظ المعرّف.
  void pickOption(
    int index, {
    required String? id,
    required String? nameKey,
    required String name,
  }) {
    final row = _row(index);
    if (row == null) return;

    row.id = id;

    if (nameKey != null) {
      row.controllers[nameKey]?.text = name;
    }

    _onChange();
  }

  void _clearRows() {
    for (final row in _rows) {
      if (_attached) row.detach(_onChange);
      row.dispose();
    }

    _rows.clear();
  }

  bool _attached = false;
  bool _syncing = false;

  void _onChange() {
    if (_syncing) return;

    _syncing = true;

    for (final row in _rows) {
      row.syncCost(schema);
    }

    _syncing = false;

    notifyListeners();
  }

  void attachRows() {
    _attached = true;

    for (final row in _rows) {
      row.attach(_onChange);
    }
  }

  void detachRows() {
    _attached = false;

    for (final row in _rows) {
      row.detach(_onChange);
    }
  }

  @override
  void dispose() {
    _clearRows();
    super.dispose();
  }
}

// ============================================================
// بطاقة محرر أسطر قسم تكلفة
// ============================================================

class CostLinesEditor extends StatefulWidget {
  const CostLinesEditor({
    super.key,
    required this.schema,
    required this.controller,
    this.options = const <CostPickerOption>[],
    this.accent,
    this.onChanged,
    this.trailingNote,
  });

  final CostLineSchema schema;
  final CostLinesEditorController controller;
  final List<CostPickerOption> options;
  final Color? accent;
  final VoidCallback? onChanged;

  /// سطر إرشادي داخل البطاقة (مثل تلميح الكمية المحسوب عليها).
  final String? trailingNote;

  @override
  State<CostLinesEditor> createState() => _CostLinesEditorState();
}

class _CostLinesEditorState extends State<CostLinesEditor> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuilt);
    widget.controller.attachRows();
  }

  @override
  void didUpdateWidget(CostLinesEditor oldWidget) {
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
    super.dispose();
  }

  void _rebuilt() {
    if (!mounted) return;

    setState(() {});
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final schema = widget.schema;
    final accent = widget.accent ?? AppColors.primary;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionTitle(
            title: schema.title,
            subtitle: schema.note.isEmpty ? null : schema.note,
            icon: schema.icon,
          ),
          AppSpacing.verticalSm,

          if (controller.count == 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'لا توجد بنود في هذا القسم بعد. '
                'اضغط «إضافة سطر» لإدخال بند واحد لكل مادة أو مهنة أو معدة.',
                style: AppTextStyles.bodySecondary,
              ),
            )
          else
            for (var i = 0; i < controller.count; i++) ...[
              _buildRow(context, controller, schema, i, accent),
              AppSpacing.verticalSm,
            ],

          AppSpacing.verticalSm,

          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => controller.addRow(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة سطر'),
            ),
          ),

          AppSpacing.verticalMd,

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
                    'إجمالي ${_shortName(schema.kind)}',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  ProjectCosts.formatMoney(controller.total),
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
            Text(
              widget.trailingNote!,
              style: AppTextStyles.small,
            ),
          ],
        ],
      ),
    );
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

  Widget _buildRow(
    BuildContext context,
    CostLinesEditorController controller,
    CostLineSchema schema,
    int index,
    Color accent,
  ) {
    final rows = _fieldRows(schema);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(schema.icon, size: 18, color: accent),
              const SizedBox(width: 6),
              Text(
                '${schema.rowTitle} ${index + 1}',
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (controller.isLegacy(index))
                _chip('إدخال قديم', AppColors.info),
              if (controller.isManual(index))
                _chip('يدوي', AppColors.warning),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'تكرار السطر',
                onPressed: () => controller.duplicate(index),
                icon: const Icon(Icons.copy_all_outlined, size: 18),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'حذف السطر',
                onPressed: () => controller.removeAt(index),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),

          if (widget.options.isNotEmpty && schema.pickerIdKey != null) ...[
            const SizedBox(height: 4),
            _buildPicker(controller, schema, index),
          ],

          const SizedBox(height: 6),

          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final field in row) ...[
                    Expanded(
                      flex: field.flex,
                      child: _buildField(
                        controller,
                        schema,
                        index,
                        field,
                      ),
                    ),
                    if (field != row.last) AppSpacing.horizontalMd,
                  ],
                ],
              ),
            ),

          _buildCostField(controller, schema, index, accent),
        ],
      ),
    );
  }

  /// تقسيم الحقول إلى صفوف حتى لا تتزاحم على الشاشة.
  static List<List<CostLineField>> _fieldRows(CostLineSchema schema) {
    final rows = <List<CostLineField>>[];
    var current = <CostLineField>[];
    var flex = 0;

    for (final field in schema.fields) {
      if (flex + field.flex > 4 && current.isNotEmpty) {
        rows.add(current);
        current = <CostLineField>[];
        flex = 0;
      }

      current.add(field);
      flex += field.flex;
    }

    if (current.isNotEmpty) rows.add(current);

    return rows;
  }

  Widget _buildField(
    CostLinesEditorController controller,
    CostLineSchema schema,
    int index,
    CostLineField field,
  ) {
    if (field.kind == CostFieldKind.choice) {
      return AppDropdown<String>(
        label: field.label,
        value: field.choices.contains(controller.textOf(index, field.key))
            ? controller.textOf(index, field.key)
            : (field.choices.isEmpty ? null : field.choices.first),
        items: [
          for (final choice in field.choices)
            DropdownMenuItem<String>(
              value: choice,
              child: Text(choice),
            ),
        ],
        onChanged: (value) =>
            controller.setText(index, field.key, value ?? ''),
      );
    }

    if (field.isNumber) {
      return AppNumberField(
        controller: controller.numberController(index, field.key),
        label: field.label,
        hint: field.hint ?? '0',
        suffixText: field.suffix,
        onChanged: (_) {},
      );
    }

    return AppTextField(
      controller: controller.textController(index, field.key),
      label: field.label,
      hint: field.hint,
      onChanged: (_) {},
    );
  }

  Widget _buildCostField(
    CostLinesEditorController controller,
    CostLineSchema schema,
    int index,
    Color accent,
  ) {

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 3,
          child: AppNumberField(
            controller: controller.costControllerOf(index),
            label: 'التكلفة (محسوبة تلقائيًا)',
            hint: 'يمكنك تثبيتها يدويًا',
            suffixText: ProjectCosts.currency,
            onChanged: (_) {},
          ),
        ),
        AppSpacing.horizontalSm,
        Expanded(
          child: Text(
            controller.isManual(index) ? 'مثبّتة' : 'تلقائية',
            textAlign: TextAlign.center,
            style: AppTextStyles.small.copyWith(
              color: controller.isManual(index)
                  ? AppColors.warning
                  : AppColors.textSecondary,
            ),
          ),
        ),
        AppSpacing.horizontalSm,
        Expanded(
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => controller.toggleManual(index),
            icon: Icon(
              controller.isManual(index)
                  ? Icons.autorenew
                  : Icons.push_pin_outlined,
              size: 16,
            ),
            label: Text(
              controller.isManual(index)
                  ? 'إلغاء'
                  : 'تثبيت يدوي',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPicker(
    CostLinesEditorController controller,
    CostLineSchema schema,
    int index,
  ) {
    final selected = controller.idOf(index);

    return AppDropdown<String>(
      label: schema.pickerLabel!,
      value: selected != null &&
              widget.options.any((o) => o.id == selected)
          ? selected
          : null,
      hint: 'بدون اختيار (إدخال يدوي)',
      items: [
        for (final option in widget.options)
          DropdownMenuItem<String>(
            value: option.id,
            child: Text(
              option.label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value == null) return;

        final option = widget.options.firstWhere((o) => o.id == value);

        controller.pickOption(
          index,
          id: option.id,
          nameKey: schema.pickerNameKey,
          name: option.label,
        );
      },
    );
  }

  static Widget _chip(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTextStyles.small.copyWith(color: color),
      ),
    );
  }
}

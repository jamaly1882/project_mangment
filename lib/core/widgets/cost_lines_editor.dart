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
        excluded = data?[CostLineSchema.excludedKey] == true,
        picked = data?[CostLineSchema.pickedKey] == true,
        id = data == null ? null : _idOf(schema, data);

  final Map<String, TextEditingController> controllers;
  final TextEditingController costController;

  bool manual;
  bool legacy;

  /// سطر أضافه المستخدم من جدول التحليل (يظهر في الجداول).
  bool picked;

  /// سطر مستبعد: يختفي إدخاله ولا يدخل في الإجمالي، دون أن يمسح
  /// المستخدم ما كتبه بنفسه.
  bool excluded;

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

  VoidCallback? _costListener;

  void attach(void Function() onChange) {
    for (final controller in controllers.values) {
      controller.addListener(onChange);
    }

    _costListener = () {
      manual = true;
      onChange();
    };
    costController.addListener(_costListener!);
  }

  void detach(void Function() onChange) {
    for (final controller in controllers.values) {
      controller.removeListener(onChange);
    }

    if (_costListener != null) costController.removeListener(_costListener!);
    _costListener = null;
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
      final text = excluded ? '' : controllers[field.key]!.text.trim();

      if (field.isNumber) {
        map[field.key] = ProjectCosts.parseNumber(text);
      } else {
        map[field.key] = text;
      }
    }

    map[CostLineSchema.excludedKey] = excluded;

    if (picked) map[CostLineSchema.pickedKey] = true;

    // السطر المستبعد لا يحمل تكلفة.
    if (excluded) {
      map[CostLineSchema.costKey] = 0.0;
      map[CostLineSchema.manualKey] = false;
      return map;
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
    if (manual) return;

    final wanted = ProjectCosts.toEditText(auto);

    if (costController.text != wanted) {
      if (_costListener != null) costController.removeListener(_costListener!);
      costController.value = TextEditingValue(
        text: wanted,
        selection: TextSelection.collapsed(offset: wanted.length),
      );
      if (_costListener != null) costController.addListener(_costListener!);
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
      if (line[CostLineSchema.excludedKey] == true) continue;
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
    if (schema.kind == CostLineKind.material && key == 'materialName') {
      row.controllers['unit']?.text = MaterialUnits.forName(value).first;
    }
    _onChange();
  }

  TextEditingController numberController(int index, String key) =>
      _row(index)!.controllers[key]!;

  TextEditingController textController(int index, String key) =>
      _row(index)!.controllers[key]!;

  TextEditingController costControllerOf(int index) =>
      _row(index)!.costController;

  // ==========================================================
  // جداول الاختيار: مطابقة أسماء الجدول بالأسطر المحفوظة
  // ==========================================================

  /// فهرس السطر المطابق لاسم في جدول التحليل، أو -1.
  ///
  /// نفضّل التساوي التام أولًا، ثم المطابقة المرنة، حتى لا يُطابق
  /// «أسمنت» سطر «خالطة أسمنتية» عند وجودهما معًا.
  int indexOfLabel(String label) {
    final titleKey = schema.titleKey;
    final wanted = normalizedLineName(label);

    for (var i = 0; i < _rows.length; i++) {
      if (normalizedLineName(textOf(i, titleKey)) == wanted) return i;
    }

    for (var i = 0; i < _rows.length; i++) {
      if (sameLineName(textOf(i, titleKey), label)) return i;
    }

    return -1;
  }

  bool hasLabel(String label) => indexOfLabel(label) >= 0;

  /// يضمن وجود سطر باسم من الجدول: يُضاف بالسعر إن لم يكن، ويُعاد فهرسه.
  int ensureLabel(String label, double price) {
    final existing = indexOfLabel(label);

    if (existing >= 0) return existing;

    addRow(buildCostLine(kind: schema.kind, label: label, price: price));

    return _rows.length - 1;
  }

  /// مفاتيح الكميات في القسم (التي منها تُحسب التكلفة).
  static List<String> quantityKeysOf(CostLineKind kind) =>
      CostLineSchema.of(kind).quantityKeys;

  bool hasQuantity(int index) {
    if (index < 0 || index >= _rows.length) return false;

    for (final key in quantityKeysOf(schema.kind)) {
      if (ProjectCosts.parseNumber(textOf(index, key)) > 0) return true;
    }

    return false;
  }

  /// تصفير كميات السطر مع بقاء الاسم والسعر (إلغاء ✓ في الجدول).
  void zeroQuantities(int index) {
    final row = _row(index);
    if (row == null) return;

    for (final key in quantityKeysOf(schema.kind)) {
      row.controllers[key]?.text = '0';
    }

    _onChange();
  }

  /// تعليم سطر في الجدول: يضمن وجوده ويضع كمية ابتدائية ١.
  int selectLabel(String label, double price) {
    final index = ensureLabel(label, price);

    _rows[index].picked = true;

    for (final key in quantityKeysOf(schema.kind)) {
      if (ProjectCosts.parseNumber(textOf(index, key)) <= 0) {
        setText(index, key, '1');
      }
    }

    return index;
  }

  /// إلغاء تعليم سطر: يبقى السطر ويُصفَّر (لا يُحذف).
  void deselectLabel(String label) {
    final index = indexOfLabel(label);
    if (index < 0) return;

    zeroQuantities(index);
  }

  String? idOf(int index) => _row(index)?.id;

  bool isManual(int index) => _row(index)?.manual ?? false;

  /// هل السطر مستبعد (إدخاله مخفي ولا يدخل في الإجمالي)؟
  bool isExcluded(int index) => _row(index)?.excluded ?? false;

  /// استبعاد/إرجاع السطر: يخفي الإدخال بدل أن يمسحه المستخدم.
  void toggleExcluded(int index) {
    final row = _row(index);
    if (row == null) return;

    row.excluded = !row.excluded;

    if (!row.excluded) row.syncCost(schema);

    _onChange();
  }

  bool isLegacy(int index) => _row(index)?.legacy ?? false;

  /// هل السطر أضافه المستخدم بنفسه (ظاهر في الجداول)؟
  bool isPicked(int index) => _row(index)?.picked ?? false;

  void markPicked(int index, bool value) {
    final row = _row(index);
    if (row == null) return;

    row.picked = value;
    notifyListeners();
  }

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
      setText(index, nameKey, name);
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
    this.hiddenKeys = const <String>{},
    this.readOnlyKeys = const <String>{},
  });

  final CostLineSchema schema;

  /// حقول تُخفى من الإدخال مع بقاء قيمها محفوظة عند الحفظ.
  /// تُستخدم لإخفاء الأسعار عن المشرف؛ السعر يحدّده مدير الجودة فقط.
  final Set<String> hiddenKeys;

  /// حقول تظهر للقراءة فقط: قيمتها منقولة من إدارة الجودة ولا تُعدَّل هنا.
  final Set<String> readOnlyKeys;
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
    final rows = _fieldRowsFor(_visibleFields(schema));

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
              if (controller.isExcluded(index))
                _chip('مستبعد', AppColors.danger),
              if (controller.isLegacy(index))
                _chip('إدخال قديم', AppColors.info),
              if (controller.isManual(index))
                _chip('يدوي', AppColors.warning),
              // استبعاد السطر: عند التأشير يختفي الإدخال ولا يدخل في
              // الإجمالي، بدل أن يمسح المستخدم ما كتبه بيده.
              Checkbox(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize:
                    MaterialTapTargetSize.shrinkWrap,
                value: controller.isExcluded(index),
                onChanged: (_) => controller.toggleExcluded(index),
              ),
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

          if (controller.isExcluded(index)) ...[
            const SizedBox(height: 4),
            Text(
              'السطر مستبعد: لا يظهر إدخاله ولا يدخل في إجمالي القسم. '
              'أزل التأشير لإرجاعه كما كان (البيانات لم تُمحَ).',
              style: AppTextStyles.small.copyWith(
                color: AppColors.danger,
              ),
            ),
          ] else ...[
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
        ],
      ),
    );
  }

  /// الحقول الظاهرة: نستثني الأسعار المخفية، والقيم تبقى في المتحكم.
  List<CostLineField> _visibleFields(CostLineSchema schema) => [
        for (final field in schema.fields)
          if (!widget.hiddenKeys.contains(field.key)) field,
      ];

  /// تقسيم الحقول إلى صفوف حتى لا تتزاحم على الشاشة.
  static List<List<CostLineField>> _fieldRowsFor(
    List<CostLineField> fields,
  ) {
    final rows = <List<CostLineField>>[];
    var current = <CostLineField>[];
    var flex = 0;

    for (final field in fields) {
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
    final locked = widget.readOnlyKeys.contains(field.key);

    if (field.kind == CostFieldKind.choice) {
      final current = controller.textOf(index, field.key);
      final suggested = schema.kind == CostLineKind.material && field.key == 'unit'
          ? MaterialUnits.forName(controller.textOf(index, 'materialName'))
          : field.choices;
      // نعرض الوحدة القديمة كما هي دون تحويل كمياتها ضمنيًا.
      final choices = <String>{...suggested, if (current.isNotEmpty) current}.toList();
      return AppDropdown<String>(
        label: field.label,
        value: current.isEmpty ? null : current,
        items: [
          for (final choice in choices)
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
        // سعر منقول من إدارة الجودة: يُقرأ ولا يُعدَّل، ويُحفظ كما هو.
        readOnly: locked,
        prefixIcon: locked ? Icons.lock_outline : null,
        onChanged: (_) {},
      );
    }

    return AppTextField(
      controller: controller.textController(index, field.key),
      label: field.label,
      hint: field.hint,
      readOnly: locked,
      onChanged: (value) {
        if (schema.kind == CostLineKind.material && field.key == 'materialName') {
          controller.setText(index, 'unit', MaterialUnits.forName(value).first);
        }
      },
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

// ============================================================
// بطاقة مقارنة سطر بسطر: المخطط مقابل الفعلي
// ============================================================

class CostLinesComparison extends StatelessWidget {
  const CostLinesComparison({
    super.key,
    required this.planned,
    required this.actual,
    this.title = 'مقارنة الأسطر: المخطط مقابل المسجّل فعليًا',
    this.plannedLabel = 'المخطط',
    this.actualLabel = 'الفعلي',
    this.accent,
  });

  final CostLines planned;
  final CostLines actual;

  final String title;
  final String plannedLabel;
  final String actualLabel;

  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final diff = planned.diff(actual);

    if (!diff.hasAny) {
      return const SizedBox.shrink();
    }

    final tone = accent ?? AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionTitle(
            title: title,
            subtitle: diff.summaryLabel(),
            icon: Icons.compare_arrows,
          ),
          AppSpacing.verticalSm,
          _headCell(tone),
          const Divider(height: 1),
          for (final row in diff.rows) _bodyRow(row),
          const Divider(height: 1),
          _totalRow(diff, tone),
          AppSpacing.verticalXs,
          Text(
            'الفروق على مستوى السطر تقريبية: كل سطر يُقارن بالسطر '
            'الذي بنفس ترتيبه لدى الطرف الآخر داخل القسم، '
            'والاعتبار الأول لمجموع القسم.',
            style: AppTextStyles.small.copyWith(
              color: AppColors.textLight,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headCell(Color tone) {
    return Container(
      color: tone.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _cell('البيان', flex: 4, style: _headStyle),
          _cell(plannedLabel, flex: 2, style: _headStyle, end: true),
          _cell(actualLabel, flex: 2, style: _headStyle, end: true),
          _cell('الفرق', flex: 2, style: _headStyle, end: true),
        ],
      ),
    );
  }

  static TextStyle get _headStyle => AppTextStyles.small.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      );

  Widget _bodyRow(CostDiffRow row) {
    final Color deltaColor;

    if (row.overBudget) {
      deltaColor = AppColors.danger;
    } else if (row.hasDelta) {
      deltaColor = AppColors.success;
    } else {
      deltaColor = AppColors.textLight;
    }

    final labelStyle = row.isCategorySummary
        ? AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)
        : AppTextStyles.bodySecondary;

    return Container(
      color: row.isCategorySummary
          ? AppColors.background.withValues(alpha: 0.6)
          : null,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _cell(
                row.isCategorySummary
                    ? row.label
                    : '   ${row.index + 1}. ${row.label}',
                flex: 4,
                style: labelStyle,
              ),
              _cell(
                ProjectCosts.formatMoney(row.planned),
                flex: 2,
                style: AppTextStyles.small,
                end: true,
              ),
              _cell(
                ProjectCosts.formatMoney(row.actual),
                flex: 2,
                style: AppTextStyles.small,
                end: true,
              ),
              _cell(
                _signed(row.delta),
                flex: 2,
                style: AppTextStyles.small.copyWith(color: deltaColor),
                end: true,
              ),
            ],
          ),
          if (!row.isCategorySummary && row.note != 'مطابق')
            Padding(
              padding: const EdgeInsets.only(right: 4, top: 2),
              child: Text(
                row.note,
                style: AppTextStyles.small.copyWith(
                  color: deltaColor,
                  fontSize: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _totalRow(CostLinesDiff diff, Color tone) {
    final Color deltaColor = diff.overBudget
        ? AppColors.danger
        : (diff.hasDifference ? AppColors.success : tone);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          _cell(
            'الإجمالي',
            flex: 4,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          _cell(
            ProjectCosts.formatMoney(diff.plannedTotal),
            flex: 2,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w700,
            ),
            end: true,
          ),
          _cell(
            ProjectCosts.formatMoney(diff.actualTotal),
            flex: 2,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w700,
            ),
            end: true,
          ),
          _cell(
            _signed(diff.delta),
            flex: 2,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w700,
              color: deltaColor,
            ),
            end: true,
          ),
        ],
      ),
    );
  }

  Widget _cell(
    String text, {
    required int flex,
    required TextStyle style,
    bool end = false,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: end ? TextAlign.end : TextAlign.start,
        style: style,
        maxLines: end ? 1 : 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static String _signed(double value) {
    if (value.abs() < 0.0001) return '—';

    final text = ProjectCosts.formatMoney(value.abs());

    return value > 0 ? '+$text' : '-$text';
  }
}

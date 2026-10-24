import 'package:flutter/material.dart';

import 'costs.dart';

// ============================================================
// بنود التكلفة المفصّلة (أسطر لكل قسم)
// ============================================================
//
// كل قسم من أقسام التكلفة الأربعة صار جدول أسطر بدل رقم واحد:
//
// • المواد     : نوع المادة · الوحدة · سعر الوحدة · الكمية · التكلفة
// • العمالة    : المهنة · العدد · أساس الأجرة · الأجرة · المدة · التكلفة
// • المعدات     : نوع المعدة · العدد · الوحدة · سعر الوحدة · الكمية · التكلفة
// • المحروقات  : نوع الوقود · الكمية · الوحدة · سعر اللتر · التكلفة
//
// التكلفة تُحسب تلقائيًا من معادلة القسم، ويمكن كتابة التكلفة يدويًا
// فيُعلَّم السطر manual=true فلا تُعاد حسبته.
//
// مجاميع الأقسام تُكتب في نفس الحقول القديمة (materialsCost ... totalCost)
// حتى تستمر قائمة البنود واللوحة وتقرير المحاسب ومجاميع المشروع بدون تعديل.

/// وحدات المواد المقترحة، مستقلة عن وحدة البند التعاقدية.
class MaterialUnits {
  static const all = ['كيس', 'م³', 'لتر', 'طن', 'كجم', 'متر طولي',
    'قطعة', 'م²', 'كرتون', 'جالون', 'متر', 'علبة'];

  static List<String> forName(String name) {
    final normalized = name.trim().replaceAll('أ', 'ا').replaceAll('إ', 'ا');
    const groups = <String, List<String>>{
      'اسمنت': ['كيس'],
      'رمل': ['م³'], 'نيسة': ['م³'], 'حصى': ['م³'], 'بحص': ['م³'],
      'ماء': ['لتر', 'م³'],
      'الواح': ['قطعة'],
      'زوايا': ['متر', 'قطعة'],
      'حديد': ['طن', 'كجم'], 'خشب': ['م³', 'متر طولي'],
      'طوب': ['قطعة'], 'بلك': ['قطعة'],
      'بلاط': ['م²', 'كرتون'], 'دهان': ['لتر', 'جالون'],
      'انابيب': ['متر طولي', 'قطعة'],
      'اسلاك': ['متر'], 'كابل': ['متر'], 'كابلات': ['متر'],
      'مسامير': ['كجم', 'علبة'], 'حجر': ['م³', 'م²'],
      'خرسانة': ['م³'],
    };
    for (final entry in groups.entries) {
      if (normalized.contains(entry.key)) return entry.value;
    }
    return all;
  }
}

/// أقسام جداول التكلفة.
enum CostLineKind { material, labor, equipment, fuel }

/// نوع حقل السطر في الواجهة.
enum CostFieldKind { text, number, choice }

/// وصف حقل واحد داخل سطر التكلفة.
class CostLineField {
  const CostLineField({
    required this.key,
    required this.label,
    required this.kind,
    this.required = false,
    this.suffix,
    this.hint,
    this.choices = const <String>[],
    this.defaultValue,
    this.flex = 1,
  });

  final String key;
  final String label;
  final CostFieldKind kind;
  final bool required;
  final String? suffix;
  final String? hint;
  final List<String> choices;

  /// قيمة تُكتب عند إنشاء سطر جديد (مثل وحدة «لتر» في المحروقات).
  final String? defaultValue;

  /// وزن الحقل في صف الإدخال.
  final int flex;

  bool get isNumber => kind == CostFieldKind.number;
}

/// مخطط قسم تكلفة: حقوله، معادلته، وحقول الحفظ الخاصة به.
class CostLineSchema {
  const CostLineSchema({
    required this.kind,
    required this.title,
    required this.rowTitle,
    required this.fields,
    required this.linesField,
    required this.actualLinesField,
    required this.totalField,
    required this.unitField,
    required this.actualField,
    required this.actualUnitField,
    required this.icon,
    this.pickerLabel,
    this.pickerIdKey,
    this.pickerNameKey,
    this.note = '',
  });

  final CostLineKind kind;

  /// عنوان البطاقة، مثل: «تكلفة المواد».
  final String title;

  /// عنوان السطر، مثل: «مادة».
  final String rowTitle;

  final List<CostLineField> fields;

  /// اسم حقل المصفوفة في Firestore (مخطط).
  final String linesField;

  /// اسم حقل المصفوفة في Firestore (فعلي).
  final String actualLinesField;

  // حقول المجاميع (المخطط والفعلي) في وثيقة البند.
  final String totalField;
  final String unitField;
  final String actualField;
  final String actualUnitField;

  final IconData icon;

  /// اختيار من بيانات النظام (المواد أو حصر المعدات) — اختياري.
  final String? pickerLabel;
  final String? pickerIdKey;
  final String? pickerNameKey;

  /// شرح قصير أسفل البطاقة.
  final String note;

  static const String manualKey = 'manual';

  /// علامة السطر المستبعد: يختفي إدخاله ولا يدخل في إجمالي القسم.
  static const String excludedKey = 'excluded';
  static const String costKey = 'cost';
  static const String legacyKey = 'legacy';

  /// مخططات الأقسام الأربعة.
  static const Map<CostLineKind, CostLineSchema> all = {
    CostLineKind.material: CostLineSchema(
      kind: CostLineKind.material,
      title: 'تكلفة المواد',
      rowTitle: 'مادة',
      linesField: 'materialLines',
      actualLinesField: 'materialActualLines',
      totalField: 'materialsCost',
      unitField: 'materialsUnitCost',
      actualField: 'materialsActualCost',
      actualUnitField: 'materialsActualUnitCost',
      icon: Icons.inventory_2_outlined,
      pickerLabel: 'اختيار المادة من صفحة المواد (اختياري)',
      pickerIdKey: 'materialId',
      pickerNameKey: 'materialName',
      note: 'التكلفة = سعر الوحدة × الكمية. '
          'اختر المادة ليعبّأ اسمها، والسعر يُدخل في كل سطر.',
      fields: [
        CostLineField(
          key: 'materialName',
          label: 'نوع المادة *',
          kind: CostFieldKind.text,
          required: true,
          flex: 3,
        ),
        CostLineField(
          key: 'unit',
          label: 'الوحدة *',
          kind: CostFieldKind.choice,
          choices: MaterialUnits.all,
          required: true,
          flex: 1,
        ),
        CostLineField(
          key: 'unitPrice',
          label: 'سعر الوحدة',
          kind: CostFieldKind.number,
          suffix: 'ريال',
          flex: 2,
        ),
        CostLineField(
          key: 'quantity',
          label: 'الكمية / العدد',
          kind: CostFieldKind.number,
          flex: 1,
        ),
      ],
    ),

    CostLineKind.labor: CostLineSchema(
      kind: CostLineKind.labor,
      title: 'تكلفة أجور العمالة',
      rowTitle: 'مهنة',
      linesField: 'laborLines',
      actualLinesField: 'laborActualLines',
      totalField: 'laborCost',
      unitField: 'laborUnitCost',
      actualField: 'laborActualCost',
      actualUnitField: 'laborActualUnitCost',
      icon: Icons.engineering_outlined,
      note: 'التكلفة = العدد × الأجرة × المدة. '
          'أساس الأجرة يغيّر معنى الأجرة والمدة فقط.',
      fields: [
        CostLineField(
          key: 'job',
          label: 'المهنة *',
          kind: CostFieldKind.text,
          required: true,
          flex: 3,
        ),
        CostLineField(
          key: 'wageBasis',
          label: 'أساس الأجرة',
          kind: CostFieldKind.choice,
          choices: ['يومي', 'ساعي', 'للوحدة'],
          defaultValue: 'يومي',
          flex: 2,
        ),
        CostLineField(
          key: 'count',
          label: 'العدد',
          kind: CostFieldKind.number,
          flex: 1,
        ),
        CostLineField(
          key: 'wage',
          label: 'الأجرة',
          kind: CostFieldKind.number,
          suffix: 'ريال',
          flex: 2,
        ),
        CostLineField(
          key: 'duration',
          label: 'المدة (أيام/ساعات/كمية)',
          kind: CostFieldKind.number,
          flex: 2,
        ),
      ],
    ),

    CostLineKind.equipment: CostLineSchema(
      kind: CostLineKind.equipment,
      title: 'تكلفة استهلاك المعدات',
      rowTitle: 'معدة',
      linesField: 'equipmentLines',
      actualLinesField: 'equipmentActualLines',
      totalField: 'equipmentCost',
      unitField: 'equipmentUnitCost',
      actualField: 'equipmentActualCost',
      actualUnitField: 'equipmentActualUnitCost',
      icon: Icons.precision_manufacturing_outlined,
      pickerLabel: 'اختيار المعدة من حصر المعدات (اختياري)',
      pickerIdKey: 'equipmentId',
      pickerNameKey: 'equipmentType',
      note: 'التكلفة = العدد × سعر الوحدة × الكمية، '
          'وسعر الوحدة يُدخل في كل سطر.',
      fields: [
        CostLineField(
          key: 'equipmentType',
          label: 'نوع المعدة *',
          kind: CostFieldKind.text,
          required: true,
          flex: 3,
        ),
        CostLineField(
          key: 'count',
          label: 'العدد',
          kind: CostFieldKind.number,
          flex: 1,
        ),
        CostLineField(
          key: 'unit',
          label: 'الوحدة *',
          kind: CostFieldKind.text,
          required: true,
          defaultValue: 'ساعة',
          flex: 1,
        ),
        CostLineField(
          key: 'unitPrice',
          label: 'سعر الوحدة',
          kind: CostFieldKind.number,
          suffix: 'ريال',
          flex: 2,
        ),
        CostLineField(
          key: 'quantity',
          label: 'الكمية',
          kind: CostFieldKind.number,
          flex: 1,
        ),
      ],
    ),

    CostLineKind.fuel: CostLineSchema(
      kind: CostLineKind.fuel,
      title: 'تكلفة استهلاك المحروقات',
      rowTitle: 'وقود',
      linesField: 'fuelLines',
      actualLinesField: 'fuelActualLines',
      totalField: 'fuelCost',
      unitField: 'fuelUnitCost',
      actualField: 'fuelActualCost',
      actualUnitField: 'fuelActualUnitCost',
      icon: Icons.local_gas_station_outlined,
      note: 'التكلفة = الكمية × سعر اللتر.',
      fields: [
        CostLineField(
          key: 'fuelType',
          label: 'نوع الوقود *',
          kind: CostFieldKind.choice,
          required: true,
          choices: ['ديزل', 'بترول', 'بنزين', 'غاز', 'قاز', 'زيت'],
          defaultValue: 'ديزل',
          flex: 2,
        ),
        CostLineField(
          key: 'quantity',
          label: 'الكمية',
          kind: CostFieldKind.number,
          flex: 2,
        ),
        CostLineField(
          key: 'unit',
          label: 'الوحدة',
          kind: CostFieldKind.choice,
          choices: ['لتر'],
          defaultValue: 'لتر',
          flex: 1,
        ),
        CostLineField(
          key: 'pricePerLiter',
          label: 'سعر اللتر',
          kind: CostFieldKind.number,
          suffix: 'ريال',
          flex: 2,
        ),
      ],
    ),
  };

  static CostLineSchema of(CostLineKind kind) => all[kind]!;

  static List<CostLineSchema> get ordered => [
        all[CostLineKind.material]!,
        all[CostLineKind.labor]!,
        all[CostLineKind.equipment]!,
        all[CostLineKind.fuel]!,
      ];

  /// مفتاح السعر في هذا القسم (سعر الوحدة / الأجرة / سعر اللتر).
  String get priceKey {
    switch (kind) {
      case CostLineKind.material:
      case CostLineKind.equipment:
        return 'unitPrice';
      case CostLineKind.labor:
        return 'wage';
      case CostLineKind.fuel:
        return 'pricePerLiter';
    }
  }

  String linesFieldFor({required bool actual}) =>
      actual ? actualLinesField : linesField;

  String totalFieldFor({required bool actual}) =>
      actual ? actualField : totalField;

  String unitFieldFor({required bool actual}) =>
      actual ? actualUnitField : unitField;

  /// قراءة حقل رقمي من سطر.
  static double number(Map<String, dynamic> line, String key) {
    final value = line[key];

    if (value is num) return value.toDouble();
    if (value is String) return ProjectCosts.parseNumber(value);

    return 0;
  }

  static String text(Map<String, dynamic> line, String key) {
    final value = line[key];
    if (value == null) return '';
    return value.toString().trim();
  }

  /// معادلة التكلفة لهذا القسم.
  double computedCost(Map<String, dynamic> line) {
    switch (kind) {
      case CostLineKind.material:
        return number(line, 'unitPrice') * number(line, 'quantity');
      case CostLineKind.labor:
        return number(line, 'count') *
            number(line, 'wage') *
            number(line, 'duration');
      case CostLineKind.equipment:
        return number(line, 'count') *
            number(line, 'unitPrice') *
            number(line, 'quantity');
      case CostLineKind.fuel:
        return number(line, 'quantity') * number(line, 'pricePerLiter');
    }
  }

  /// التكلفة المعتمدة للسطر: اليدوية إن وُجدت، وإلا المحسوبة.
  double costOf(Map<String, dynamic> line) {
    if (line[excludedKey] == true) return 0;

    final isManual = line[manualKey] == true;
    final manual = line[costKey];

    if (isManual && manual != null) {
      return ProjectCosts.nonNegative(manual);
    }

    return ProjectCosts.nonNegative(computedCost(line));
  }

  /// الحقل الذي يسمّي السطر (الاسم/المهنة/نوع الوقود).
  /// أي حقل غير رقمي من الأعلى: نص أو قائمة قيم،
  /// لأن نوع الوقود في المحروقات حقل اختيار لا نص.
  String get titleKey {
    for (final field in fields) {
      if (field.kind != CostFieldKind.number) return field.key;
    }

    return fields.isEmpty ? '' : fields.first.key;
  }

  /// نص مختصر للسطر يُستخدم في المقارنات والتقارير.
  String describe(Map<String, dynamic> line) {
    final name = text(line, titleKey).trim();

    final unitKey =
        kind == CostLineKind.labor ? 'wageBasis' : 'unit';
    final unit = text(line, unitKey).trim();

    if (name.isEmpty && unit.isEmpty) return '$rowTitle بدون اسم';
    if (unit.isEmpty) return name;

    return '$name ($unit)';
  }

  /// تحقق من سطر واحد؛ يعيد قائمة رسائل (فارغة = سليم).
  List<String> validateLine(Map<String, dynamic> line, int index) {
    final errors = <String>[];

    // السطر المستبعد لا يُدقَّق ولا يدخل في الإجمالي.
    if (line[excludedKey] == true) return errors;

    final label = 'السطر ${index + 1} ($rowTitle)';

    for (final field in fields) {
      if (!field.required) continue;

      if (field.isNumber) {
        if (number(line, field.key) <= 0) {
          errors.add('$label: ${field.label} مطلوب أن يكون أكبر من صفر');
        }
      } else if (text(line, field.key).isEmpty) {
        errors.add('$label: ${field.label} مطلوب');
      }
    }

    for (final field in fields.where((f) => f.isNumber)) {
      final value = number(line, field.key);

      if (value < 0) {
        errors.add('$label: ${field.label} لا يكون سالبًا');
      }
    }

    // سطر مستورد بسعر فقط وبلا كميات: مسموح، فالكمية يدخلها المشرف.
    final pricedOnly = number(line, priceKey) > 0;

    if (costOf(line) <= 0 && !pricedOnly) {
      errors.add('$label: أدخل الكميات والسعر أو تكلفة يدوية');
    }

    return errors;
  }
}

// ============================================================
// حزمة أسطر لأقسام البند الأربعة
// ============================================================

class CostLines {
  CostLines([Map<CostLineKind, List<Map<String, dynamic>>>? lines])
      : byKind = <CostLineKind, List<Map<String, dynamic>>>{
          for (final schema in CostLineSchema.ordered)
            schema.kind: List<Map<String, dynamic>>.from(
              lines?[schema.kind] ?? const <Map<String, dynamic>>[],
            ),
        };

  final Map<CostLineKind, List<Map<String, dynamic>>> byKind;

  List<Map<String, dynamic>> operator [](CostLineKind kind) =>
      byKind[kind] ?? const <Map<String, dynamic>>[];

  bool get isEmpty =>
      CostLineSchema.ordered.every((s) => this[s.kind].isEmpty);

  bool get isNotEmpty => !isEmpty;

  int get lineCount => CostLineSchema.ordered
      .map((s) => this[s.kind].length)
      .fold<int>(0, (sum, n) => sum + n);

  /// وصف مختصر: «3 مواد، 2 مهن...»
  String summaryLabel() {
    final parts = <String>[
      for (final schema in CostLineSchema.ordered)
        if (this[schema.kind].isNotEmpty)
          '${this[schema.kind].length} ${_countNoun(schema.kind)}',
    ];

    return parts.isEmpty ? 'بدون بنود' : parts.join('، ');
  }

  static String _countNoun(CostLineKind kind) {
    switch (kind) {
      case CostLineKind.material:
        return 'مواد';
      case CostLineKind.labor:
        return 'مهن';
      case CostLineKind.equipment:
        return 'معدات';
      case CostLineKind.fuel:
        return 'محروقات';
    }
  }

  double totalOf(CostLineKind kind) {
    final schema = CostLineSchema.of(kind);

    double sum = 0;

    for (final line in this[kind]) {
      sum += schema.costOf(line);
    }

    return sum;
  }

  /// مجاميع الأقسام بمفاتيحها القديمة (materials / labor / ...).
  Map<String, double> categoryTotals() {
    return <String, double>{
      'materials': totalOf(CostLineKind.material),
      'labor': totalOf(CostLineKind.labor),
      'equipment': totalOf(CostLineKind.equipment),
      'fuel': totalOf(CostLineKind.fuel),
    };
  }

  double get grandTotal {
    double sum = 0;

    for (final schema in CostLineSchema.ordered) {
      sum += totalOf(schema.kind);
    }

    return sum;
  }

  /// كل أخطاء التحقق.
  List<String> validate() {
    final errors = <String>[];

    for (final schema in CostLineSchema.ordered) {
      final lines = this[schema.kind];

      for (var i = 0; i < lines.length; i++) {
        errors.addAll(schema.validateLine(lines[i], i));
      }
    }

    return errors;
  }

  /// بيانات الحفظ في Firestore: الأسطر + مجاميع الأقسام + مرايا تكلفة الوحدة.
  /// مقارنة سطرًا بسطر مع حزمة أخرى (المخطط مقابل الفعلي).
  /// السطر رقم i في قسم يقابل السطر رقم i في الحزمة الأخرى،
  /// وللقسم سطر ملخّص بمجموعه.
  CostLinesDiff diff(CostLines? other) {
    final counterpart = other ?? CostLines();

    final rows = <CostDiffRow>[];

    final plannedByKind = <CostLineKind, double>{};
    final actualByKind = <CostLineKind, double>{};

    for (final schema in CostLineSchema.ordered) {
      final plannedLines = this[schema.kind];
      final actualLines = counterpart[schema.kind];

      if (plannedLines.isEmpty && actualLines.isEmpty) continue;

      final plannedTotal = totalOf(schema.kind);
      final actualTotal = counterpart.totalOf(schema.kind);

      plannedByKind[schema.kind] = plannedTotal;
      actualByKind[schema.kind] = actualTotal;

      rows.add(
        CostDiffRow(
          kind: schema.kind,
          index: -1,
          label: schema.title,
          planned: plannedTotal,
          actual: actualTotal,
          isSummary: true,
        ),
      );

      final count = plannedLines.length > actualLines.length
          ? plannedLines.length
          : actualLines.length;

      for (int i = 0; i < count; i++) {
        final plannedLine = i < plannedLines.length ? plannedLines[i] : null;
        final actualLine = i < actualLines.length ? actualLines[i] : null;

        rows.add(
          CostDiffRow(
            kind: schema.kind,
            index: i,
            label: schema.describe(plannedLine ?? actualLine!),
            planned: plannedLine == null ? 0 : schema.costOf(plannedLine),
            actual: actualLine == null ? 0 : schema.costOf(actualLine),
          ),
        );
      }
    }

    return CostLinesDiff(
      rows: rows,
      plannedTotal: grandTotal,
      actualTotal: counterpart.grandTotal,
      plannedByKind: plannedByKind,
      actualByKind: actualByKind,
    );
  }

  Map<String, dynamic> toSaveData({
    bool actual = false,
    double contractQuantity = 0,
  }) {
    final data = <String, dynamic>{};

    double grand = 0;

    for (final schema in CostLineSchema.ordered) {
      final lines = this[schema.kind];

      data[schema.linesFieldFor(actual: actual)] = lines;

      final total = totalOf(schema.kind);

      data[schema.totalFieldFor(actual: actual)] = total;

      // مرايا تكلفة الوحدة حتى تستمر حسابات «تكلفة المنفذ» والعرض القديم.
      data[schema.unitFieldFor(actual: actual)] = contractQuantity > 0
          ? total / contractQuantity
          : total;

      grand += total;
    }

    data[actual
        ? ProjectCosts.actualTotalField
        : ProjectCosts.totalField] = grand;

    data[actual ? 'actualCostsModel' : 'costsModel'] = 'lines';
    data[actual ? 'actualCostsLineCount' : 'costsLineCount'] = lineCount;

    return data;
  }

  /// قراءة الأسطر المحفوظة، مع ترحيل الإدخال القديم (رقم واحد لكل قسم).
  static CostLines fromData(
    Map<String, dynamic>? data, {
    bool actual = false,
    double contractQuantity = 0,
    String unit = '',
  }) {
    final lines = <CostLineKind, List<Map<String, dynamic>>>{};

    for (final schema in CostLineSchema.ordered) {
      final stored = data?[schema.linesFieldFor(actual: actual)];

      if (stored is List) {
        lines[schema.kind] = stored
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        continue;
      }

      // لا أسطر محفوظة: نحوّل الإجمالي القديم إلى سطر واحد إن وُجد.
      final legacyTotal = data == null
          ? 0.0
          : ProjectCosts.nonNegative(
              data[schema.totalFieldFor(actual: actual)],
            );

      if (legacyTotal <= 0) {
        lines[schema.kind] = <Map<String, dynamic>>[];
        continue;
      }

      lines[schema.kind] = <Map<String, dynamic>>[
        _legacyLine(
          schema: schema,
          data: data!,
          total: legacyTotal,
          contractQuantity: contractQuantity,
          unit: unit,
        ),
      ];
    }

    return CostLines(lines);
  }

  static Map<String, dynamic> _legacyLine({
    required CostLineSchema schema,
    required Map<String, dynamic> data,
    required double total,
    required double contractQuantity,
    required String unit,
  }) {
    final quantity = contractQuantity > 0 ? contractQuantity : 1.0;

    switch (schema.kind) {
      case CostLineKind.material:
        return <String, dynamic>{
          'materialName': 'تكلفة مواد محفوظة مسبقًا',
          'unit': unit.isEmpty ? 'وحدة' : unit,
          'unitPrice': total / quantity,
          'quantity': quantity,
          CostLineSchema.costKey: total,
          CostLineSchema.manualKey: true,
          CostLineSchema.legacyKey: true,
        };
      case CostLineKind.labor:
        return <String, dynamic>{
          'job': 'عمالة محفوظة مسبقًا',
          'wageBasis': 'يومي',
          'count': 1,
          'wage': total / quantity,
          'duration': quantity,
          CostLineSchema.costKey: total,
          CostLineSchema.manualKey: true,
          CostLineSchema.legacyKey: true,
        };
      case CostLineKind.equipment:
        return <String, dynamic>{
          'equipmentType': 'معدة محفوظة مسبقًا',
          'count': 1,
          'unit': unit.isEmpty ? 'ساعة' : unit,
          'unitPrice': total / quantity,
          'quantity': quantity,
          CostLineSchema.costKey: total,
          CostLineSchema.manualKey: true,
          CostLineSchema.legacyKey: true,
        };
      case CostLineKind.fuel:
        return <String, dynamic>{
          'fuelType': 'ديزل',
          'quantity': quantity,
          'unit': 'لتر',
          'pricePerLiter': total / quantity,
          CostLineSchema.costKey: total,
          CostLineSchema.manualKey: true,
          CostLineSchema.legacyKey: true,
        };
    }
  }
}

// ============================================================
// فرق سطر بسطر بين حزمتي أسطر (مخطط / فعلي)
// ============================================================

/// صف واحد في جدول المقارنة.
class CostDiffRow {
  const CostDiffRow({
    required this.kind,
    required this.index,
    required this.label,
    required this.planned,
    required this.actual,
    this.isSummary = false,
  });

  final CostLineKind kind;

  /// رقم السطر في قسمه، أو -1 لسطر ملخّص القسم.
  final int index;

  final String label;
  final double planned;
  final double actual;
  final bool isSummary;

  bool get isCategorySummary => isSummary;

  /// موجب = تجاوز المخطط، سالب = أقل منه.
  double get delta => actual - planned;

  bool get hasDelta => delta.abs() > 0.0001;

  bool get overBudget => hasDelta && delta > 0;

  /// سطر لم يُدخل في المخطط لكنه سُجّل فعليًا.
  bool get onlyActual => planned <= 0 && actual > 0;

  /// سطر مخطط لم يسجل المشرف شيئًا له.
  bool get notConsumed => actual <= 0 && planned > 0;

  String get note {
    if (onlyActual) return 'غير مخطط';
    if (notConsumed) return 'لم يُستهلك';
    if (overBudget) return 'تجاوز';
    if (hasDelta) return 'أقل من المخطط';

    return 'مطابق';
  }
}

/// نتيجة مقارنة حزمتي أسطر.
class CostLinesDiff {
  const CostLinesDiff({
    required this.rows,
    required this.plannedTotal,
    required this.actualTotal,
    required this.plannedByKind,
    required this.actualByKind,
  });

  final List<CostDiffRow> rows;

  final double plannedTotal;
  final double actualTotal;

  final Map<CostLineKind, double> plannedByKind;
  final Map<CostLineKind, double> actualByKind;

  bool get hasAny => rows.isNotEmpty;

  double get delta => actualTotal - plannedTotal;

  bool get hasDifference => delta.abs() > 0.0001;

  /// الفعلي تجاوز الإجمالي المخطط.
  bool get overBudget => delta > 0.0001;

  /// مقدار الزيادة فقط (لتفادي إطفاء النقصان للزيادة).
  double get overrun {
    double sum = 0;

    for (final row in rows) {
      if (row.isCategorySummary) continue;
      if (row.delta > 0) sum += row.delta;
    }

    return sum;
  }

  /// نسبة الاستهلاك من المخطط (0..1 وما فوق عند التجاوز).
  double get ratio =>
      plannedTotal > 0 ? actualTotal / plannedTotal : (actualTotal > 0 ? 1 : 0);

  List<CostDiffRow> linesOf(CostLineKind kind) {
    return rows
        .where((r) => r.kind == kind && !r.isCategorySummary)
        .toList();
  }

  /// نص مختصر للعناوين: «الفعلي أقل بـ ...» ونحوها.
  String summaryLabel() {
    if (!hasAny) return 'لا توجد أسطر للمقارنة';

    if (!hasDifference) {
      return actualTotal > 0
          ? 'مطابق للمخطط'
          : 'لم تُسجّل تكلفة فعلية بعد';
    }

    final text = ProjectCosts.formatMoney(delta.abs());

    return delta > 0 ? 'تجاوز المخطط بمقدار $text' : 'أقل من المخطط بمقدار $text';
  }
}

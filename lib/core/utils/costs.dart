import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

// ============================================================
// وصف بند من بنود التكلفة
// ============================================================

/// يمثل قسمًا واحدًا من أقسام التكلفة الأربعة:
/// المواد، أجور العمالة، المعدات، المحروقات.
///
/// - [totalField]: اسم الحقل الذي يحفظ الإجمالي في Firestore.
/// - [unitField]: اسم الحقل الذي يحفظ تكلفة الوحدة (يُستخدم في البنود).
class CostCategory {
  const CostCategory({
    required this.key,
    required this.totalField,
    required this.unitField,
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.color,
  });

  final String key;

  /// مثال: materialsCost
  final String totalField;

  /// مثال: materialsUnitCost
  final String unitField;

  final String label;

  final String shortLabel;

  final IconData icon;

  final Color color;
}

// ============================================================
// أدوات التكلفة الموحدة
// ============================================================

/// نموذج موحد لتكاليف المشروع وتكاليف البند.
///
/// المشروع يحفظ الإجماليات فقط:
/// materialsCost / laborCost / equipmentCost / fuelCost / totalCost
///
/// البند يحفظ تكلفة الوحدة والإجمالي المتوقع لكل قسم:
/// materialsUnitCost + materialsCost ... إلخ،
/// ويُحسب الإجمالي تلقائيًا من (تكلفة الوحدة × الكمية التعاقدية)
/// ما لم يُدخل المستخدم إجماليًا يدويًا.
class ProjectCosts {
  ProjectCosts._();

  // ==========================================================
  // أسماء الحقول المشتركة
  // ==========================================================

  static const String totalField = 'totalCost';

  static const String executedCostField = 'executedCost';

  /// العملة المستخدمة في العرض.
  static const String currency = 'ريال';

  // ==========================================================
  // أقسام التكلفة
  // ==========================================================

  static const List<CostCategory> categories = [
    CostCategory(
      key: 'materials',
      totalField: 'materialsCost',
      unitField: 'materialsUnitCost',
      label: 'تكلفة المواد',
      shortLabel: 'المواد',
      icon: Icons.inventory_2_outlined,
      color: AppColors.primary,
    ),
    CostCategory(
      key: 'labor',
      totalField: 'laborCost',
      unitField: 'laborUnitCost',
      label: 'تكلفة أجور العمالة',
      shortLabel: 'أجور العمالة',
      icon: Icons.engineering_outlined,
      color: AppColors.engineer,
    ),
    CostCategory(
      key: 'equipment',
      totalField: 'equipmentCost',
      unitField: 'equipmentUnitCost',
      label: 'تكلفة المعدات',
      shortLabel: 'المعدات',
      icon: Icons.precision_manufacturing_outlined,
      color: AppColors.time,
    ),
    CostCategory(
      key: 'fuel',
      totalField: 'fuelCost',
      unitField: 'fuelUnitCost',
      label: 'تكلفة المحروقات',
      shortLabel: 'المحروقات',
      icon: Icons.local_gas_station_outlined,
      color: AppColors.driver,
    ),
  ];

  // ==========================================================
  // قراءة الأرقام
  // ==========================================================

  /// يحول النص إلى رقم مع دعم الأرقام العربية والفواصل.
  /// يعيد 0 إذا كان النص فارغًا أو غير صالح.
  static double parseNumber(String value) {
    return parseOptional(value) ?? 0;
  }

  /// يحول النص إلى رقم، ويعيد null إذا كان فارغًا أو غير صالح.
  static double? parseOptional(String value) {
    String text = value
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9')
        .replaceAll('٫', '.')
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .replaceAll('ر.ي', '')
        .replaceAll('ريال', '')
        .trim();

    if (text.isEmpty || text == '.' || text == '-') {
      return null;
    }

    // الفاصلة العشرية الوحيدة تبقى كما هي.
    final int firstDot = text.indexOf('.');
    if (firstDot != -1) {
      final String head = text.substring(0, firstDot);
      final String tail =
          text.substring(firstDot + 1).replaceAll('.', '');
      text = '$head.$tail';
    }

    final double? parsed = double.tryParse(text);

    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return null;
    }

    return parsed;
  }

  /// قراءة قيمة رقمية محفوظة في Firestore.
  static double toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return parseNumber(value);
    }

    return 0;
  }

  /// قيمة موجبة أو 0 (لا نسمح بالتكاليف السالبة).
  static double nonNegative(dynamic value) {
    final number = toDouble(value);
    return number < 0 ? 0 : number;
  }

  // ==========================================================
  // حساب الإجماليات
  // ==========================================================

  /// إجمالي محفوظ أو محسوب من أقسام التكلفة.
  static double totalOf(Map<String, dynamic>? data) {
    if (data == null) return 0;

    double sum = 0;

    for (final category in categories) {
      sum += nonNegative(data[category.totalField]);
    }

    return sum;
  }

  /// خريطة أقسام التكلفة لمشروع أو بند.
  static Map<String, double> breakdownOf(Map<String, dynamic>? data) {
    final result = <String, double>{};

    for (final category in categories) {
      result[category.key] =
          data == null ? 0 : nonNegative(data[category.totalField]);
    }

    return result;
  }

  /// خريطة تكلفة الوحدة لبنُد المشروع.
  static Map<String, double> unitBreakdownOf(Map<String, dynamic>? data) {
    final result = <String, double>{};

    for (final category in categories) {
      result[category.key] =
          data == null ? 0 : nonNegative(data[category.unitField]);
    }

    return result;
  }

  static double totalUnitCost(Map<String, dynamic>? data) {
    double sum = 0;

    for (final value in unitBreakdownOf(data).values) {
      sum += value;
    }

    return sum;
  }

  /// هل أدخل المستخدم أي تكلفة من أقسام التكلفة؟
  static bool hasAnyValue(
    Map<String, TextEditingController> totalControllers,
  ) {
    for (final category in categories) {
      final controller = totalControllers[category.key];

      if (controller == null) continue;

      if (controller.text.trim().isNotEmpty) {
        return true;
      }
    }

    return false;
  }

  /// بيانات الحفظ الصالحة لمجموعة Firestore.
  ///
  /// نرسل الحقول التي لها قيمة فقط حتى لا نكتب 0 فوق بيانات موجودة
  /// في حال ترك المستخدم الحقل فارغًا أثناء التعديل.
  static Map<String, dynamic> buildSaveData({
    required Map<String, String> totalTexts,
    Map<String, String>? unitTexts,
    double contractQuantity = 0,
    bool includeZeros = false,
  }) {
    final data = <String, dynamic>{};

    double total = 0;

    for (final category in categories) {
      double? unitValue;

      if (unitTexts != null) {
        final parsed =
            parseOptional(unitTexts[category.key] ?? '');
        unitValue = parsed == null ? null : (parsed < 0 ? 0 : parsed);
      }

      double? value = parseOptional(totalTexts[category.key] ?? '');

      // الإجمالي المتوقع = تكلفة الوحدة × الكمية التعاقدية
      // عندما لا يدخل المستخدم إجماليًا يدويًا.
      if (value == null && unitValue != null) {
        value = contractQuantity > 0
            ? unitValue * contractQuantity
            : 0;
      }

      if (value == null) {
        if (includeZeros) {
          data[category.totalField] = 0;

          if (unitTexts != null) {
            data[category.unitField] = 0;
          }
        }

        continue;
      }

      final double stored = value < 0 ? 0 : value;

      data[category.totalField] = stored;
      total += stored;

      if (unitTexts != null) {
        data[category.unitField] = unitValue ?? 0;
      }
    }

    data[totalField] = total < 0 ? 0 : total;

    return data;
  }

  // ==========================================================
  // العرض
  // ==========================================================

  /// تنسيق رقم بدون كسور زائدة.
  static String formatNumber(double value) {
    final rounded = (value * 100).roundToDouble() / 100;

    final String sign = rounded < 0 ? '-' : '';

    final double abs = rounded.abs();

    if (rounded == rounded.roundToDouble()) {
      return '$sign${_groupDigits(abs.round().toString())}';
    }

    final int whole = abs.truncate();
    final int fraction =
        ((abs - whole) * 100).round();

    final String text = fraction == 0
        ? _groupDigits(whole.toString())
        : '${_groupDigits(whole.toString())}.'
            '${fraction.toString().padLeft(2, '0')}';

    return rounded < 0 ? '-$text' : text;
  }

  /// نص جاهز لوضعه في TextEditingController عند التعديل.
  static String toEditText(double value) {
    if (value <= 0) return '';

    if (value == value.roundToDouble()) {
      return value.round().toString();
    }

    return value.toStringAsFixed(2);
  }

  /// تنسيق مبلغ مع اسم العملة.
  static String formatMoney(double value, {bool withCurrency = true}) {
    final text = formatNumber(value);

    if (!withCurrency) return text;

    return '$text $currency';
  }

  /// نص مختصر للأرقام الكبيرة (استخدام بطاقات العرض).
  static String formatCompactMoney(double value) {
    final double abs = value.abs();

    if (abs >= 1000000000) {
      return '${formatNumber(value / 1000000000)} مليار $currency';
    }

    if (abs >= 1000000) {
      return '${formatNumber(value / 1000000)} مليون $currency';
    }

    return formatMoney(value);
  }

  static String _groupDigits(String digits) {
    final buffer = StringBuffer();

    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }

      buffer.write(digits[i]);
    }

    return buffer.toString();
  }
}

// ============================================================
// وحدة الحسابات — أدوات التنسيق والتواريخ
// ============================================================
//
// دوال نقية (بدون Flutter) حتى يمكن اختبارها مباشرة، وتُستخدم
// في كل صفحات الوحدة المالية: السندات والصندوق والقيود
// والتقارير.
// ============================================================

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// ينسّق المبلغ بفواصل الآلاف.
///
/// أمثلة:
/// 0        → 0.00
/// 1234.5   → 1,234.50
/// -1250000 → -1,250,000.00
String formatMoney(
  double value, {
  int decimals = 2,
  bool withSeparators = true,
}) {
  final bool negative = value < 0;
  final String fixed = value.abs().toStringAsFixed(decimals);
  final List<String> parts = fixed.split('.');
  final String digits = parts.first;
  final StringBuffer buffer = StringBuffer();

  if (withSeparators) {
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
  } else {
    buffer.write(digits);
  }

  final String decimalPart = parts.length > 1
      ? parts[1]
      : '0'.padRight(decimals, '0');

  final String result = decimals > 0
      ? '${buffer.toString()}.$decimalPart'
      : buffer.toString();

  return negative ? '-$result' : result;
}

/// المبلغ مع لاحقة العملة.
String formatMoneyWithCurrency(
  double value, {
  String currency = 'ريال',
  int decimals = 2,
}) {
  return '${formatMoney(value, decimals: decimals)} $currency';
}

/// تاريخ بصيغة يوم/شهر/سنة.
String formatDate(DateTime date) {
  return '${_twoDigits(date.day)}/${_twoDigits(date.month)}/${date.year}';
}

/// تاريخ ووقت.
String formatDateTime(DateTime? date) {
  if (date == null) return '—';
  return '${formatDate(date)}  ${_twoDigits(date.hour)}:${_twoDigits(date.minute)}';
}

/// يحوّل الأرقام العربية والفارسية إلى أرقام إنجليزية ويفك
/// فواصل الآلاف قبل التحويل إلى double.
String normalizeAmountText(String? text) {
  final String input = (text ?? '').trim();
  const String arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const String easternDigits = '۰۱۲۳۴۵۶۷۸۹';
  final StringBuffer buffer = StringBuffer();

  for (final int rune in input.runes) {
    final String char = String.fromCharCode(rune);
    final int arabicIndex = arabicDigits.indexOf(char);
    final int easternIndex = easternDigits.indexOf(char);

    if (arabicIndex >= 0) {
      buffer.write(arabicIndex);
    } else if (easternIndex >= 0) {
      buffer.write(easternIndex);
    } else if (char == '٫') {
      buffer.write('.');
    } else if (char == ',' || char == ' ') {
      // فواصل الآلاف والمسافات لا تدخل في الرقم.
      continue;
    } else {
      buffer.write(char);
    }
  }

  return buffer.toString();
}

/// يحوّل نصًا إلى مبلغ، ويعيد صفرًا إن كان النص غير صالح.
double parseAmount(String? text) {
  final String normalized = normalizeAmountText(text);
  if (normalized.isEmpty) return 0;
  return double.tryParse(normalized) ?? 0;
}

/// هل النص المدخل مبلغ موجب صالح؟
bool isValidAmount(String? text) {
  final double value = parseAmount(text);
  return value > 0;
}

// ============================================================
// حدود الفترات
// ============================================================

DateTime startOfDay(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

DateTime endOfDay(DateTime date) {
  return DateTime(
    date.year,
    date.month,
    date.day,
    23,
    59,
    59,
    999,
  );
}

DateTime startOfMonth(DateTime date) {
  return DateTime(date.year, date.month, 1);
}

DateTime endOfMonth(DateTime date) {
  return DateTime(date.year, date.month + 1, 0, 23, 59, 59, 999);
}

DateTime startOfYear(DateTime date) {
  return DateTime(date.year, 1, 1);
}

DateTime endOfYear(DateTime date) {
  return DateTime(date.year, 12, 31, 23, 59, 59, 999);
}

/// هل التاريخ داخل الفترة؟ (الحدان اختياريان)
bool inPeriod(DateTime date, DateTime? start, DateTime? end) {
  if (start != null && date.isBefore(start)) return false;
  if (end != null && date.isAfter(end)) return false;
  return true;
}

/// اسم الشهر بالعربية.
String arabicMonthName(int month) {
  const List<String> names = <String>[
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  if (month < 1 || month > 12) return '';
  return names[month - 1];
}

/// «أكتوبر 2026».
String formatMonthYear(DateTime date) {
  return '${arabicMonthName(date.month)} ${date.year}';
}

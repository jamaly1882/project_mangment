import 'package:azal/features/accounting/accounting_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('تنسيق المبالغ', () {
    test('فواصل الآلاف والمنازل العشرية', () {
      expect(formatMoney(0), '0.00');
      expect(formatMoney(1234.5), '1,234.50');
      expect(formatMoney(1000000), '1,000,000.00');
      expect(formatMoney(1234567.891), '1,234,567.89');
      expect(formatMoney(-1250000), '-1,250,000.00');
      expect(formatMoney(1500, decimals: 0), '1,500');
      expect(formatMoney(1500, withSeparators: false), '1500.00');
    });

    test('العملة مع المبلغ', () {
      expect(formatMoneyWithCurrency(2500), '2,500.00 ريال');
      expect(
        formatMoneyWithCurrency(2500, currency: 'دولار', decimals: 0),
        '2,500 دولار',
      );
    });
  });

  group('قراءة المبالغ المدخلة', () {
    test('أرقام إنجليزية وفواصل آلاف', () {
      expect(parseAmount('1,234.50'), 1234.5);
      expect(parseAmount(' 1500 '), 1500);
      expect(parseAmount(''), 0);
      expect(parseAmount(null), 0);
      expect(parseAmount('غير رقم'), 0);
    });

    test('أرقام عربية وفارسية وفاصلة عشرية عربية', () {
      expect(parseAmount('١٢٣٤'), 1234);
      expect(parseAmount('١٢٣٤٫٥'), 1234.5);
      expect(parseAmount('۱۲۳'), 123);
      expect(normalizeAmountText('١,٢٣٤'), '1234');
    });

    test('المبلغ الموجب', () {
      expect(isValidAmount('0'), isFalse);
      expect(isValidAmount('-5'), isFalse);
      expect(isValidAmount('10'), isTrue);
    });
  });

  group('التواريخ والفترات', () {
    test('تنسيق التاريخ', () {
      expect(formatDate(DateTime(2026, 1, 5)), '05/01/2026');
      expect(
        formatDateTime(DateTime(2026, 10, 25, 8, 7)),
        '25/10/2026  08:07',
      );
      expect(formatDateTime(null), '—');
    });

    test('حدود الشهر والسنة', () {
      expect(startOfMonth(DateTime(2026, 10, 25)), DateTime(2026, 10, 1));
      expect(
        endOfMonth(DateTime(2026, 10, 25)),
        DateTime(2026, 10, 31, 23, 59, 59, 999),
      );
      expect(startOfYear(DateTime(2026, 10, 25)), DateTime(2026, 1, 1));
      expect(
        endOfYear(DateTime(2026, 10, 25)),
        DateTime(2026, 12, 31, 23, 59, 59, 999),
      );
    });

    test('هل التاريخ داخل الفترة', () {
      final DateTime start = DateTime(2026, 10, 1);
      final DateTime end = DateTime(2026, 10, 31, 23, 59);

      expect(inPeriod(DateTime(2026, 10, 15), start, end), isTrue);
      expect(inPeriod(DateTime(2026, 9, 30), start, end), isFalse);
      expect(inPeriod(DateTime(2026, 11, 1), start, end), isFalse);
      expect(inPeriod(DateTime(2026, 11, 1), null, null), isTrue);
    });

    test('اسم الشهر', () {
      expect(arabicMonthName(1), 'يناير');
      expect(arabicMonthName(10), 'أكتوبر');
      expect(arabicMonthName(13), '');
      expect(formatMonthYear(DateTime(2026, 10, 1)), 'أكتوبر 2026');
    });
  });
}

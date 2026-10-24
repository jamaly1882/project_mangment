import 'package:flutter_test/flutter_test.dart';

import 'package:azal/core/services/cost_prices.dart';
import 'package:azal/core/utils/cost_lines.dart';

// ============================================================
// أسعار التكاليف: تصنيف أسطر التحليل وقراءة أرقام الجدول
// ============================================================

void main() {
  group('CostPrices.classify — توزيع بنود التحليل على الأقسام', () {
    test('الوقود: بترول، ديزل، غاز، قاز، زيت', () {
      for (final label in const <String>[
        'بترول',
        'ديزل',
        'غاز',
        'قاز',
        'زيت',
      ]) {
        expect(
          CostPrices.classify(label),
          CostLineKind.fuel,
          reason: label,
        );
      }
    });

    test('المهنة مع المصاريف تُصنَّف عمالة', () {
      for (final label in const <String>[
        'سائق حفارة D155',
        'مشرف',
        'غرابيل',
        'مساعد مشغل',
        'مفرزة',
      ]) {
        expect(
          CostPrices.classify(label),
          CostLineKind.labor,
          reason: label,
        );
      }
    });

    test('المعدات تبقى في قسم المعدات', () {
      for (final label in const <String>[
        'حفارة D155',
        'قلاب 20 طن',
        'دكاكة ترابية',
        'بوكات',
        'كمبريش هواء',
        'دينا',
      ]) {
        expect(
          CostPrices.classify(label),
          CostLineKind.equipment,
          reason: label,
        );
      }
    });

    test('المواد الواردة في عمود المحروقات تُضاف إلى المواد', () {
      for (final label in const <String>[
        'ماء زجاجة',
        'ماء متر',
        'خطة إستنكية',
        'حجر جدران',
        'رصيف 25 سم',
        'حديد حماية',
        'أجرة قلعقة',
      ]) {
        expect(
          CostPrices.classify(label),
          CostLineKind.material,
          reason: label,
        );
      }
    });

    test('سائق حفارة: العمالة تتقدم على المعدات', () {
      expect(
        CostPrices.classify('سائق حفارة D155'),
        CostLineKind.labor,
      );
    });
  });

  group('CostPrices.parseTable — التوزيع بموضع العمود', () {
    test('ما سوى الوقود في عمود المحروقات يُضاف إلى المواد', () {
      final entries = CostPrices.parseTable(
        'مشرف | 12,000 | دكاكة صغيرة | 2,360 | ماء زجاجة | 15,000',
      );

      expect(
        entries.map((e) => e.kind).toList(),
        <CostLineKind>[
          CostLineKind.labor,
          CostLineKind.equipment,
          CostLineKind.material,
        ],
      );
    });

    test('الوقود داخل عمود المحروقات يُصنَّف محروقات', () {
      final entries = CostPrices.parseTable(
        'عمال | 8,500 | فيكسس | 2,310 | غاز | 325',
      );

      expect(entries.last.kind, CostLineKind.fuel);
      expect(entries.last.label, 'غاز');
      expect(entries.last.price, 325);
    });

    test('كل سطر في عمود المهنة عمالة حتى بلا كلمات مفتاحية', () {
      final entries = CostPrices.parseTable(
        'مستخلص أعمال | 5,000 | قلاب 6 طن | 9,000 | قاز | 500',
      );

      expect(entries[0].kind, CostLineKind.labor);
      expect(entries[1].kind, CostLineKind.equipment);
      expect(entries[2].kind, CostLineKind.fuel);
    });

    test('isFuel يميز الوقود عن بقية المواد', () {
      for (final fuel in const <String>[
        'ديزل',
        'بترول',
        'غاز',
        'قاز',
        'زيت',
      ]) {
        expect(CostPrices.isFuel(fuel), isTrue, reason: fuel);
      }

      for (final material in const <String>[
        'ماء زجاجة',
        'حجر جدران',
        'رصيف 25 سم',
        'حديد حماية',
      ]) {
        expect(CostPrices.isFuel(material), isFalse, reason: material);
      }
    });
  });

  group('CostPrices.parsePrice — أرقام الجدول', () {
    test('يقبل الفواصل والأرقام العربية', () {
      expect(CostPrices.parsePrice('11,500'), 11500);
      expect(CostPrices.parsePrice('٤٧٥'), 475);
      expect(CostPrices.parsePrice('420,000'), 420000);
    });

    test('يرفض خلايا الخطأ والنصوص', () {
      expect(CostPrices.parsePrice('#REF!'), isNull);
      expect(CostPrices.parsePrice('البريموث'), isNull);
      expect(CostPrices.parsePrice(''), isNull);
    });
  });

  group('CostPrices.parseTable — قراءة جدول التحليل', () {
    test('ست قيم: مهنة ومعدة ومحروقات', () {
      final entries = CostPrices.parseTable(
        'سائق حفارة D155 | 11,500 | حفارة D155 | 23,100 | ديزل | 475',
      );

      expect(entries.length, 3);
      expect(entries[0].kind, CostLineKind.labor);
      expect(entries[0].price, 11500);
      expect(entries[1].kind, CostLineKind.equipment);
      expect(entries[1].price, 23100);
      expect(entries[2].kind, CostLineKind.fuel);
      expect(entries[2].price, 475);
    });

    test('قيمتان: اسم وسعر فقط', () {
      final entries = CostPrices.parseTable('حديد حماية | 620');

      expect(entries.length, 1);
      expect(entries.single.kind, CostLineKind.material);
      expect(entries.single.price, 620);
    });

    test('خلايا #REF! لا توقف القراءة', () {
      final entries = CostPrices.parseTable(
        'دكاكة ترابية | 9,000 | دكاكة ترابية | #REF!',
      );

      expect(entries.length, 1);
      expect(entries.single.kind, CostLineKind.equipment);
    });
  });

  group('CostPrices.applyPriceToLine — استبدال السعر', () {
    test('السعر الجديد يحل محل القديم وتُعاد التكلفة', () {
      final schema = CostLineSchema.of(CostLineKind.material);
      final line = <String, dynamic>{
        'materialName': 'أسمنت',
        'unit': 'طن',
        'unitPrice': 100.0,
        'quantity': 10.0,
      };

      expect(schema.costOf(line), 1000);

      final changed = CostPrices.applyPriceToLine(schema, line, 200);

      expect(changed, isTrue);
      expect(CostPrices.priceOf(CostLineKind.material, line), 200);
      expect(schema.costOf(line), 2000);
    });

    test('لا يتغير شيء عند نفس السعر', () {
      final schema = CostLineSchema.of(CostLineKind.fuel);
      final line = <String, dynamic>{
        'fuelType': 'ديزل',
        'quantity': 10.0,
        'pricePerLiter': 475.0,
      };

      expect(CostPrices.applyPriceToLine(schema, line, 475), isFalse);
    });
  });

  group('CostPrices.matches — مطابقة سطر التحليل بسطر البند', () {
    test('مطابقة تامة أو احتواء', () {
      expect(CostPrices.matches('أسمنت', 'أسمنت'), isTrue);
      expect(CostPrices.matches('سائق حفارة', 'سائق'), isTrue);
      expect(CostPrices.matches('حديد', 'حديد حماية'), isTrue);
      expect(CostPrices.matches('أسمنت', 'رمل'), isFalse);
    });
  });
}

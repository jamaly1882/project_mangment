import 'package:flutter_test/flutter_test.dart';

import 'package:azal/core/constants/previous_prices.dart';

// ============================================================
// خلاصة أسعار 1447هـ: تحقق من سلامة البيانات المستوردة
// ============================================================

void main() {
  group('بنية أسعار 1447هـ', () {
    test('ثلاثة بنود (أقسام أعمال) و 71 نوعًا', () {
      expect(PreviousPrices.bandsCount, 3);
      expect(PreviousPrices.typesCount, 71);
      expect(previousPriceBands.map((band) => band.key).toList(), <String>[
        'terrain',
        'asphalt',
        'structural',
      ]);
    });

    test('أكواد الأنواع من 1 إلى 71 بلا تكرار أو فراغ', () {
      final codes = PreviousPrices.allTypes.map((type) => type.code).toList();

      expect(codes.toSet().length, codes.length);
      expect(codes.toSet(), Set<int>.from(List<int>.generate(71, (i) => i + 1)));

      for (var code = 1; code <= 71; code++) {
        expect(PreviousPrices.findByCode(code), isNotNull, reason: 'كود $code');
      }
    });

    test('كل نوع له بند ووحدة واسم غير فارغ', () {
      for (final type in PreviousPrices.allTypes) {
        expect(PreviousPrices.bandOfCode(type.code), isNotNull);
        expect(type.unit.trim(), isNotEmpty, reason: 'كود ${type.code}');
        expect(type.name.trim(), isNotEmpty, reason: 'كود ${type.code}');
      }
    });

    test('الوحدات المركبة محفوظة كما في الملف', () {
      expect(PreviousPrices.findByCode(19)!.unit, 'م3*كم');
      expect(PreviousPrices.findByCode(31)!.unit, 'طن*كم');
      expect(PreviousPrices.findByCode(70)!.unit, 'طن*كم');
      expect(PreviousPrices.findByCode(17)!.unit, 'م.ط');
      expect(PreviousPrices.findByCode(42)!.unit, 'عدد');
      expect(PreviousPrices.findByCode(13)!.unit, 'كم');
    });

    test('السعران المفقودان (#REF!) محفوظان كـ null لا صفر', () {
      for (final code in <int>[12, 21]) {
        final type = PreviousPrices.findByCode(code)!;
        expect(type.price, isNull, reason: 'كود $code');
        expect(type.hasPrice, isFalse);
        expect(type.priceNote, previousPriceMissing);
      }
    });

    test('عدد الأنواع المسعّرة 69', () {
      expect(PreviousPrices.pricedTypesCount, 69);
      expect(
        PreviousPrices.allTypes.where((type) => !type.hasPrice).length,
        2,
      );
    });

    test('نطاقات الأسعار داخل كل بند غير فارغة', () {
      for (final band in previousPriceBands) {
        expect(band.typesCount, greaterThan(0));
        expect(band.pricedTypesCount, greaterThan(0));
        expect(band.priceRange, isNotNull);
      }
    });

    test('كل الوحدات في قائمة وحدات التطبيق', () {
      for (final unit in PreviousPrices.units) {
        expect(
          previousTypeUnits,
          contains(unit),
          reason: 'الوحدة $unit غير موجودة في قائمة الوحدات',
        );
      }
    });
  });

  group('الوحدات في التطبيق', () {
    test('عدد يقابله قطعة، والبقية كما هي', () {
      expect(PreviousPrices.findByCode(42)!.appUnit, 'قطعة');
      expect(PreviousPrices.findByCode(19)!.appUnit, 'م3*كم');
      expect(PreviousPrices.findByCode(17)!.appUnit, 'م.ط');
      expect(PreviousPrices.findByCode(1)!.appUnit, 'م3');
    });
  });
}

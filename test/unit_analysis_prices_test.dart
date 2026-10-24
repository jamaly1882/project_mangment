import 'package:flutter_test/flutter_test.dart';

import 'package:azal/core/constants/unit_analysis_prices.dart';
import 'package:azal/core/services/cost_prices.dart';
import 'package:azal/core/services/unit_analysis_seed.dart';
import 'package:azal/core/utils/cost_lines.dart';

// ============================================================
// جدول تحليل الوحدة المضمّن: اكتمال البيانات وصحة التصنيف
// ============================================================

void main() {
  group('unitAnalysis — اكتمال الجدول', () {
    test('العدد الكلي 133 سطرًا', () {
      expect(unitAnalysisRowCount, 133);
      expect(unitAnalysisAll.length, 133);
    });

    test('عدد أسطر كل قسم', () {
      expect(unitAnalysisLabor.length, unitAnalysisLaborCount);
      expect(unitAnalysisEquipment.length, unitAnalysisEquipmentCount);
      expect(unitAnalysisFuel.length, unitAnalysisFuelCount);
      expect(unitAnalysisMaterials.length, unitAnalysisMaterialsCount);
    });

    test('كل سطر له اسم ومبلغ موجب', () {
      for (final row in unitAnalysisAll) {
        expect(row.name.trim(), isNotEmpty);
        expect(row.amount, greaterThan(0), reason: row.name);
      }
    });

    test('لا أسطر مكررة داخل القسم نفسه', () {
      for (final rows in <List<UnitAnalysisRow>>[
        unitAnalysisLabor,
        unitAnalysisEquipment,
        unitAnalysisFuel,
        unitAnalysisMaterials,
      ]) {
        final names = rows.map((row) => row.name).toList();
        expect(names.toSet().length, names.length);
      }
    });
  });

  group('unitAnalysis — الأسعار المطابقة للملف', () {
    test('الوقود: ديزل 475 وبترول 475 وقاز 500 وغاز 325', () {
      Map<String, double> prices = <String, double>{
        for (final row in unitAnalysisFuel) row.name: row.amount,
      };

      expect(prices['ديزل'], 475);
      expect(prices['بترول'], 475);
      expect(prices['قاز'], 500);
      expect(prices['غاز'], 325);
    });

    test('العمالة: سائق حرارة D155 = 11,500', () {
      final row = unitAnalysisLabor.firstWhere(
        (item) => item.name.contains('D155'),
      );

      expect(row.amount, 11500);
    });

    test('المعدات: حرارة D155 = 23,100', () {
      final row = unitAnalysisEquipment.firstWhere(
        (item) => item.name.contains('D155'),
      );

      expect(row.amount, 23100);
    });

    test('المواد: أسمنت وحديد G40 موجودة بأسعارها', () {
      final materials = <String, double>{
        for (final row in unitAnalysisMaterials) row.name: row.amount,
      };

      expect(materials.containsKey('أسمنت'), isTrue);
      expect(materials['أسمنت'], 4000);
      expect(materials['حديد G40'], 400000);
    });
  });

  group('unitAnalysis — بناء أسطر التكاليف', () {
    test('كل سطر عمالة يبني سطر أجور بسعر وبلا مدة', () {
      final schema = CostLineSchema.of(CostLineKind.labor);
      final row = unitAnalysisLabor.first;
      final entry = PriceEntry(
        label: row.name,
        kind: CostLineKind.labor,
        price: row.amount,
      );

      final line = CostPrices.newLine(CostLineKind.labor, entry);

      expect(line['job'], row.name);
      expect(line['wage'], row.amount);
      expect(line['duration'], 0);
      expect(schema.costOf(line), 0);
    });

    test('كل سطر معدات يبني سطر إهلاك بسعر وبلا كمية', () {
      final schema = CostLineSchema.of(CostLineKind.equipment);
      final row = unitAnalysisEquipment.first;
      final entry = PriceEntry(
        label: row.name,
        kind: CostLineKind.equipment,
        price: row.amount,
      );

      final line = CostPrices.newLine(CostLineKind.equipment, entry);

      expect(line['equipmentType'], row.name);
      expect(line['unitPrice'], row.amount);
      expect(line['quantity'], 0);
      expect(schema.costOf(line), 0);
    });

    test('المحروقات تُبنى بسعر اللتر', () {
      final entry = PriceEntry(
        label: 'ديزل',
        kind: CostLineKind.fuel,
        price: 475,
      );

      final line = CostPrices.newLine(CostLineKind.fuel, entry);

      expect(line['fuelType'], 'ديزل');
      expect(line['pricePerLiter'], 475);
    });

    test('المواد تُبنى بسعر الوحدة ووحدة مناسبة', () {
      final entry = PriceEntry(
        label: 'أسمنت',
        kind: CostLineKind.material,
        price: 4000,
      );

      final line = CostPrices.newLine(CostLineKind.material, entry);

      expect(line['materialName'], 'أسمنت');
      expect(line['unitPrice'], 4000);
      expect((line['unit'] as String).isNotEmpty, isTrue);
    });
  });

  // ============================================================
  // بذور البند الجديد: الأسعار تُحفظ مع الإنشاء وبلا كميات
  // ============================================================

  group('UnitAnalysisSeed — بند جديد', () {
    test('كل الأقسام تُبنى بعدد أسطرها وبلا كميات', () {
      final lines = UnitAnalysisSeed.lines;

      expect(lines[CostLineKind.labor]!.length, unitAnalysisLaborCount);
      expect(
        lines[CostLineKind.equipment]!.length,
        unitAnalysisEquipmentCount,
      );
      expect(lines[CostLineKind.fuel]!.length, unitAnalysisFuelCount);
      expect(lines[CostLineKind.material]!.length, unitAnalysisMaterialsCount);
      expect(UnitAnalysisSeed.lineCount, unitAnalysisRowCount);

      // لا كميات: تكلفة البند صفر عند الإنشاء.
      for (final line in lines[CostLineKind.material]!) {
        expect(line['quantity'], 0);
      }
      for (final line in lines[CostLineKind.fuel]!) {
        expect(line['quantity'], 0);
      }
      for (final line in lines[CostLineKind.equipment]!) {
        expect(line['quantity'], 0);
      }
      for (final line in lines[CostLineKind.labor]!) {
        expect(line['duration'], 0);
      }
    });

    test('الأسعار مكتوبة في أسطر البذور', () {
      final material = UnitAnalysisSeed.lines[CostLineKind.material]!
          .firstWhere((line) => line['materialName'] == 'أسمنت');
      expect(material['unitPrice'], 4000);

      final fuel = UnitAnalysisSeed.lines[CostLineKind.fuel]!
          .firstWhere((line) => line['fuelType'] == 'ديزل');
      expect(fuel['pricePerLiter'], 475);

      final labor = UnitAnalysisSeed.lines[CostLineKind.labor]!
          .firstWhere((line) => line['job'] == 'عمال');
      expect(labor['wage'], 8500);
    });

    test('بيانات الحفظ تحمل الأسطر والمجاميع الصفرية', () {
      final data = UnitAnalysisSeed.saveData(contractQuantity: 10);

      final planned =
          CostLines.fromData(data, contractQuantity: 10, unit: 'م3');

      expect(planned.lineCount, unitAnalysisRowCount);

      // الأسطر الفعلية مكتوبة أيضًا، وهي ما تقرأه صفحة المشرف.
      final material = CostLineSchema.of(CostLineKind.material);
      expect(
        data.containsKey(material.linesFieldFor(actual: true)),
        isTrue,
      );
      final actualLines =
          CostLines.fromData(data, actual: true, contractQuantity: 10);
      expect(actualLines.lineCount, unitAnalysisRowCount);
      expect(
        CostLineKind.values.fold<double>(
          0,
          (sum, kind) => sum + actualLines.totalOf(kind),
        ),
        0,
      );
      expect(
        CostLineKind.values.fold<double>(
          0,
          (sum, kind) => sum + planned.totalOf(kind),
        ),
        0,
      );
      expect(planned[CostLineKind.material].first['unitPrice'], isPositive);
    });

    test('إعادة الاستيراد لا تُكرر أسطر البذور', () {
      final planned = CostLines(UnitAnalysisSeed.lines);
      final schema = CostLineSchema.of(CostLineKind.material);
      final before = planned[CostLineKind.material].length;

      // كل أسماء البذور موجودة أصلًا ⇒ لا سطر جديد.
      for (final line in planned[CostLineKind.material]) {
        final label = CostLineSchema.text(line, schema.titleKey);
        expect(
          unitAnalysisMaterials.any(
            (row) => CostPrices.matches(label, row.name),
          ),
          isTrue,
        );
      }

      expect(planned[CostLineKind.material].length, before);
      expect(UnitAnalysisSeed.lines[CostLineKind.material]!.length, before);
    });
  });
}

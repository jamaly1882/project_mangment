import 'package:flutter_test/flutter_test.dart';

import 'package:azal/core/utils/cost_lines.dart';
import 'package:azal/core/utils/costs.dart';

// ============================================================
// جداول أسطر التكلفة: المعادلات، التثبيت اليدوي،
// المجاميع، الحفظ، والترحيل من الإدخال القديم
// ============================================================

Map<String, dynamic> materialLine({
  String name = 'إسمنت',
  String unit = 'كيس',
  double unitPrice = 15000,
  double quantity = 40,
  double? cost,
  bool manual = false,
}) {
  return <String, dynamic>{
    'materialName': name,
    'unit': unit,
    'unitPrice': unitPrice,
    'quantity': quantity,
    if (cost != null) CostLineSchema.costKey: cost,
    if (manual) CostLineSchema.manualKey: true,
  };
}

void main() {
  group('معادلات الأقسام', () {
    test('المواد: سعر الوحدة × الكمية', () {
      final schema = CostLineSchema.of(CostLineKind.material);

      expect(schema.computedCost(materialLine(unitPrice: 100, quantity: 3)),
          300);
    });

    test('العمالة: العدد × الأجرة × المدة', () {
      final schema = CostLineSchema.of(CostLineKind.labor);

      expect(
        schema.computedCost(<String, dynamic>{
          'job': 'نجار',
          'wageBasis': 'يومي',
          'count': 2,
          'wage': 12000,
          'duration': 5,
        }),
        120000,
      );
    });

    test('المعدات: العدد × سعر الوحدة × الكمية', () {
      final schema = CostLineSchema.of(CostLineKind.equipment);

      expect(
        schema.computedCost(<String, dynamic>{
          'equipmentType': 'حفار',
          'count': 1,
          'unit': 'ساعة',
          'unitPrice': 25000,
          'quantity': 8,
        }),
        200000,
      );
    });

    test('المحروقات: الكمية × سعر اللتر', () {
      final schema = CostLineSchema.of(CostLineKind.fuel);

      expect(
        schema.computedCost(<String, dynamic>{
          'fuelType': 'ديزل',
          'quantity': 100,
          'unit': 'لتر',
          'pricePerLiter': 180,
        }),
        18000,
      );
    });

    test('التكلفة المثبتة يدويًا تتقدم على المحسوبة', () {
      final schema = CostLineSchema.of(CostLineKind.material);

      final line = materialLine(
        unitPrice: 100,
        quantity: 3,
        cost: 999,
        manual: true,
      );

      expect(schema.costOf(line), 999);
      expect(schema.computedCost(line), 300);
    });

    test('بدون تثبيت يدوي تُستخدم القيمة المحسوبة', () {
      final schema = CostLineSchema.of(CostLineKind.material);

      // cost موجود لكن manual غير مضبوط => يبقى الحساب هو المعتمد.
      final line = materialLine(unitPrice: 100, quantity: 3, cost: 999);

      expect(schema.costOf(line), 300);
    });

    test('لا يقبل قيما سالبة', () {
      final schema = CostLineSchema.of(CostLineKind.material);

      final line = materialLine(
        unitPrice: -100,
        quantity: 3,
        cost: -50,
        manual: true,
      );

      expect(schema.costOf(line), 0);
    });
  });

  group('CostLines', () {
    CostLines sample() {
      return CostLines(<CostLineKind, List<Map<String, dynamic>>>{
        CostLineKind.material: [
          materialLine(unitPrice: 15000, quantity: 40),
        ],
        CostLineKind.labor: [
          <String, dynamic>{
            'job': 'نجار',
            'wageBasis': 'يومي',
            'count': 2,
            'wage': 12000,
            'duration': 5,
          },
        ],
        CostLineKind.equipment: [
          <String, dynamic>{
            'equipmentType': 'حفار',
            'count': 1,
            'unit': 'ساعة',
            'unitPrice': 25000,
            'quantity': 8,
          },
        ],
        CostLineKind.fuel: [
          <String, dynamic>{
            'fuelType': 'ديزل',
            'quantity': 100,
            'unit': 'لتر',
            'pricePerLiter': 180,
          },
        ],
      });
    }

    test('مجاميع الأقسام والإجمالي العام', () {
      final lines = sample();

      expect(lines.totalOf(CostLineKind.material), 600000);
      expect(lines.totalOf(CostLineKind.labor), 120000);
      expect(lines.totalOf(CostLineKind.equipment), 200000);
      expect(lines.totalOf(CostLineKind.fuel), 18000);
      expect(lines.grandTotal, 938000);
      expect(lines.lineCount, 4);
    });

    test('categoryTotals يستخدم مفاتيح الحقول القديمة', () {
      final totals = sample().categoryTotals();

      expect(totals['materials'], 600000);
      expect(totals['labor'], 120000);
      expect(totals['equipment'], 200000);
      expect(totals['fuel'], 18000);
    });

    test('toSaveData يكتب الأسطر والمجاميع ومرايا تكلفة الوحدة', () {
      final data = sample().toSaveData(contractQuantity: 100);

      expect(data['materialLines'], hasLength(1));
      expect(data['materialsCost'], 600000);
      expect(data['materialsUnitCost'], 6000);
      expect(data['laborCost'], 120000);
      expect(data['equipmentCost'], 200000);
      expect(data['fuelCost'], 18000);
      expect(data[ProjectCosts.totalField], 938000);
      expect(data['costsModel'], 'lines');
      expect(data['costsLineCount'], 4);
    });

    test('toSaveData بوضع الفعلي يكتب حقول Actual', () {
      final data = sample().toSaveData(actual: true, contractQuantity: 10);

      expect(data['materialActualLines'], isNotNull);
      expect(data['materialsActualCost'], 600000);
      expect(data['materialsActualUnitCost'], 60000);
      expect(data[ProjectCosts.actualTotalField], 938000);
      expect(data['materialsCost'], isNull);
      expect(data['actualCostsModel'], 'lines');
    });

    test('التحقق: وحدة فارغة تُرفض، وسطر سليم يمر', () {
      final bad = CostLines(<CostLineKind, List<Map<String, dynamic>>>{
        CostLineKind.material: [materialLine(unit: '')],
      });

      expect(bad.validate(), isNotEmpty);
      expect(bad.validate().first, contains('الوحدة'));

      final good = CostLines(<CostLineKind, List<Map<String, dynamic>>>{
        CostLineKind.material: [materialLine()],
      });

      expect(good.validate(), isEmpty);
    });

    test('سطر بلا كمية ولا سعر يعطي تكلفة صفرًا', () {
      final lines = CostLines(<CostLineKind, List<Map<String, dynamic>>>{
        CostLineKind.material: [
          <String, dynamic>{
            'materialName': 'حديد',
            'unit': 'طن',
            'unitPrice': 0,
            'quantity': 0,
          },
        ],
      });

      expect(lines.totalOf(CostLineKind.material), 0);
      expect(lines.validate(), isNotEmpty);
    });

    test('summaryLabel يصف عدد الأسطر لكل قسم', () {
      expect(sample().summaryLabel(),
          '1 مواد، 1 مهن، 1 معدات، 1 محروقات');
      expect(CostLines().summaryLabel(), 'بدون بنود');
    });
  });

  group('الترحيل من الإدخال القديم', () {
    test('رقم مفرد لقسم يتحول إلى سطر واحد مثبّت', () {
      final lines = CostLines.fromData(
        <String, dynamic>{'materialsCost': 5000},
        contractQuantity: 10,
        unit: 'م3',
      );

      final materialLines = lines[CostLineKind.material];

      expect(materialLines, hasLength(1));
      expect(lines.totalOf(CostLineKind.material), 5000);

      final line = materialLines.first;

      expect(line[CostLineSchema.legacyKey], true);
      expect(line[CostLineSchema.manualKey], true);
      expect(CostLineSchema.number(line, 'unitPrice'), 500);
      expect(CostLineSchema.number(line, 'quantity'), 10);
      expect(CostLineSchema.text(line, 'unit'), 'م3');
    });

    test('الأسطر المحفوظة تُقرأ كما هي ولها الأولوية', () {
      final lines = CostLines.fromData(<String, dynamic>{
        'materialLines': [
          materialLine(unitPrice: 100, quantity: 2),
        ],
        'materialsCost': 999999,
      });

      expect(lines.totalOf(CostLineKind.material), 200);
    });

    test('الفعلي يقرأ من حقول Actual وأسطرها', () {
      final lines = CostLines.fromData(
        <String, dynamic>{
          'fuelActualCost': 36000,
        },
        actual: true,
        contractQuantity: 200,
      );

      expect(lines.totalOf(CostLineKind.fuel), 36000);
      expect(lines[CostLineKind.fuel].single['fuelType'], 'ديزل');
    });

    test('وثيقة بلا تكاليف تعيد حزمة فارغة', () {
      final lines = CostLines.fromData(<String, dynamic>{});

      expect(lines.isEmpty, isTrue);
      expect(lines.grandTotal, 0);
      expect(lines.validate(), isEmpty);
    });
  });

  group('التوافق مع دوال التكلفة القديمة', () {
    test('مجاميع الأسطر تساوي ما تقرأه ProjectCosts من الوثيقة', () {
      final lines = CostLines(<CostLineKind, List<Map<String, dynamic>>>{
        CostLineKind.material: [materialLine(unitPrice: 100, quantity: 5)],
        CostLineKind.fuel: [
          <String, dynamic>{
            'fuelType': 'ديزل',
            'quantity': 10,
            'unit': 'لتر',
            'pricePerLiter': 180,
          },
        ],
      });

      final data = lines.toSaveData(contractQuantity: 5);

      expect(ProjectCosts.totalOf(data), lines.grandTotal);
      expect(ProjectCosts.breakdownOf(data)['materials'], 500);
      expect(ProjectCosts.breakdownOf(data)['fuel'], 1800);
      expect(ProjectCosts.totalUnitCost(data),
          ProjectCosts.totalOf(data) / 5);
    });

    test('formatNumber وformatMoney يعملان مع المجاميع', () {
      expect(ProjectCosts.formatNumber(1234.5), '1,234.50');
      expect(ProjectCosts.formatMoney(0), contains('0'));
    });
  });
}

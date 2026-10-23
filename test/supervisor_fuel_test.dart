import 'package:azal/core/utils/equipment_calculations.dart';
import 'package:flutter_test/flutter_test.dart';

// ============================================================
// اختبارات «استهلاك المشرفين»: قراءة محروقات مشرف المشروع
// من وثيقة البند وتجميعها لكل مشروع لمقارنتها عند مدير
// المحروقات بسجلات صرف الديزل الرسمية.
// ============================================================

void main() {
  group('SupervisorFuel.fromItemDoc', () {
    test('يقرأ أسطر المحروقات الفعلية ويفصل الديزل عن باقي الأنواع', () {
      final SupervisorItemFuel? fuel = SupervisorFuel.fromItemDoc('item1', {
        'projectId': 'p1',
        'itemDefinitionName': 'أعمال حفر',
        'typeName': 'حفر عميق',
        'code': 'B-01',
        'actualCostsBy': 'sup1',
        'fuelActualLines': [
          {
            'fuelType': 'ديزل',
            'quantity': 100,
            'pricePerLiter': 2,
            'cost': 200,
          },
          // بدون تكلفة محفوظة: تُحسب الكمية × سعر اللتر
          {'fuelType': 'بترول', 'quantity': 10, 'pricePerLiter': 3},
        ],
      });

      expect(fuel, isNotNull);
      expect(fuel!.totalLiters, 110);
      expect(fuel.dieselLiters, 100);
      expect(fuel.cost, 230);
      expect(fuel.litersByType['ديزل'], 100);
      expect(fuel.litersByType['بترول'], 10);
      expect(fuel.supervisorId, 'sup1');
      expect(fuel.itemName, contains('أعمال حفر'));
      expect(fuel.linesCount, 2);
    });

    test('يستخدم fuelActualCost عند غياب الأسطر المفصلة', () {
      final SupervisorItemFuel? fuel = SupervisorFuel.fromItemDoc('item2', {
        'projectId': 'p1',
        'itemDefinitionName': 'ردم',
        'fuelActualCost': 500,
      });

      expect(fuel, isNotNull);
      expect(fuel!.totalLiters, 0);
      expect(fuel.cost, 500);
      expect(fuel.hasFuel, isTrue);
    });

    test('يعيد null عند غياب المحروقات أو رقم المشروع', () {
      expect(
        SupervisorFuel.fromItemDoc('item3', {'projectId': 'p1'}),
        isNull,
      );
      expect(
        SupervisorFuel.fromItemDoc('item4', {
          'fuelActualLines': [
            {'fuelType': 'ديزل', 'quantity': 50, 'pricePerLiter': 2},
          ],
        }),
        isNull,
      );
    });

    test('يتجاهل الأسطر الصفرية ويعتبر النوع الفارغ ديزلًا', () {
      final SupervisorItemFuel? fuel = SupervisorFuel.fromItemDoc('item5', {
        'projectId': 'p2',
        'fuelActualLines': [
          {'fuelType': '', 'quantity': 40, 'pricePerLiter': 2.5},
          {'fuelType': 'زيت', 'quantity': 0, 'pricePerLiter': 5},
        ],
      });
      expect(fuel, isNotNull);
      expect(fuel!.dieselLiters, 40);
      expect(fuel.cost, 100);
      expect(fuel.linesCount, 1);
    });
  });

  group('SupervisorFuel.compare', () {
    test('يحسب الفرق بين المشرفين وسجلات الديزل ويضم المشاريع كلها', () {
      final List<ProjectFuelComparison> comparisons =
          SupervisorFuel.compare(
        supervisorItems: [
          const SupervisorItemFuel(
            itemId: 'i1',
            itemName: 'بند أ',
            code: 'A',
            projectId: 'p1',
            supervisorId: 'sup1',
            totalLiters: 160,
            dieselLiters: 150,
            cost: 300,
            litersByType: {'ديزل': 150, 'بترول': 10},
            linesCount: 3,
          ),
          const SupervisorItemFuel(
            itemId: 'i2',
            itemName: 'بند ج',
            code: 'C',
            projectId: 'p3',
            supervisorId: 'sup2',
            totalLiters: 20,
            dieselLiters: 20,
            cost: 40,
            litersByType: {'ديزل': 20},
            linesCount: 1,
          ),
        ],
        dieselLitersByProject: {'p1': 120, 'p2': 80},
        dieselCostByProject: {'p1': 240, 'p2': 160},
      );

      // ثلاث مشروعات: p1 مكتملة الجانبين، p2 ديزل رسمي فقط، p3 مشرف فقط
      expect(comparisons.length, 3);

      final ProjectFuelComparison p1 = comparisons[0];
      expect(p1.projectId, 'p1');
      expect(p1.supervisorDieselLiters, 150);
      expect(p1.supervisorTotalLiters, 160);
      expect(p1.dieselLiters, 120);
      expect(p1.litersDiff, 30);
      expect(p1.costDiff, 60);
      expect(p1.litersDiffPercent, closeTo(25, 0.001));
      expect(p1.hasSupervisorInput, isTrue);
      expect(p1.hasDieselLogs, isTrue);

      final ProjectFuelComparison p2 = comparisons[1];
      expect(p2.hasSupervisorInput, isFalse);
      expect(p2.hasDieselLogs, isTrue);
      expect(p2.litersDiff, -80);

      final ProjectFuelComparison p3 = comparisons[2];
      expect(p3.hasSupervisorInput, isTrue);
      expect(p3.hasDieselLogs, isFalse);
      expect(p3.litersDiffPercent, 0);
    });

    test('قائمة فارغة عند غياب أي إدخال', () {
      expect(
        SupervisorFuel.compare(
          supervisorItems: const [],
          dieselLitersByProject: const {},
          dieselCostByProject: const {},
        ),
        isEmpty,
      );
    });
  });
}

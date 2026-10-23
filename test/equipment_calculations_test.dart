import 'package:flutter_test/flutter_test.dart';

import 'package:azal/core/utils/equipment_calculations.dart';

// ============================================================
// حسابات الحركة والديزل والورشة:
// تكلفة الديزل، تكاليف الصيانة (أعطال/تواير/قطع)،
// الإهلاك وبدل الأعطال، ملف المعدة، واستهلاك المشروع اليومي.
// ============================================================

Map<String, dynamic> dieselLog({
  String equipmentId = 'eq1',
  String projectId = 'p1',
  String projectCode = 'PRJ-1',
  String dayKey = '2026-10-23',
  double liters = 100,
  double pricePerLiter = 500,
  double? totalCost,
  double workUnits = 8,
  double meterReading = 1000,
}) {
  return <String, dynamic>{
    'equipmentId': equipmentId,
    'projectId': projectId,
    'projectCode': projectCode,
    'projectName': 'مشروع الطريق',
    'dayKey': dayKey,
    'liters': liters,
    'pricePerLiter': pricePerLiter,
    if (totalCost != null) 'totalCost': totalCost,
    'workUnits': workUnits,
    'meterReading': meterReading,
  };
}

Map<String, dynamic> maintenanceLog({
  String type = MaintenanceTypes.breakdown,
  String status = MaintenanceTypes.statusDone,
  double quantity = 1,
  double unitCost = 10000,
  double? totalCost,
  double downtimeHours = 2,
}) {
  return <String, dynamic>{
    'type': type,
    'status': status,
    'quantity': quantity,
    'unitCost': unitCost,
    if (totalCost != null) 'totalCost': totalCost,
    'downtimeHours': downtimeHours,
  };
}

void main() {
  group('الديزل', () {
    test('تكلفة الصرف = اللترات × سعر اللتر', () {
      expect(
        EquipmentCalc.dieselCost(liters: 120, pricePerLiter: 550),
        66000,
      );
    });

    test('القيم السالبة تُصفَّر', () {
      expect(EquipmentCalc.dieselCost(liters: -5, pricePerLiter: 100), 0);
    });

    test('تكلفة الديزل لكل وحدة عمل', () {
      expect(
        EquipmentCalc.dieselCostPerWorkUnit(
          totalFuelCost: 80000,
          totalWorkUnits: 40,
        ),
        2000,
      );
      // بدون وحدات عمل لا قسمة على صفر.
      expect(
        EquipmentCalc.dieselCostPerWorkUnit(
          totalFuelCost: 80000,
          totalWorkUnits: 0,
        ),
        0,
      );
    });

    test('مفتاح اليوم yyyy-MM-dd', () {
      expect(EquipmentCalc.dayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(EquipmentCalc.dayKey(DateTime(2026, 10, 23)), '2026-10-23');
    });
  });

  group('الورشة والصيانة', () {
    test('تكلفة القطع/التواير = الكمية × سعر الوحدة', () {
      // 4 تواير × 45000
      expect(
        EquipmentCalc.maintenanceCost(quantity: 4, unitCost: 45000),
        180000,
      );
    });

    test('أسماء الأنواع بالعربية', () {
      expect(MaintenanceTypes.label(MaintenanceTypes.breakdown), 'عطل');
      expect(MaintenanceTypes.label(MaintenanceTypes.tire), 'بدل تواير');
      expect(MaintenanceTypes.label(MaintenanceTypes.part), 'قطع غيار');
      expect(
        MaintenanceTypes.statusLabel(MaintenanceTypes.statusOpen),
        'قيد الإصلاح',
      );
    });
  });

  group('الإهلاك وبدل الأعطال', () {
    test('إهلاك وحدة العمل بالقيمة', () {
      // (10,000,000 - 1,000,000) / 9,000 ساعة = 1,000 لكل ساعة
      expect(
        EquipmentCalc.depreciationPerWorkUnit(
          currentValue: 10000000,
          salvageValue: 1000000,
          expectedWorkUnits: 9000,
        ),
        1000,
      );
    });

    test('بدون وحدات متوقعة أو قيمة قابلة للإهلاك فالإهلاك صفر', () {
      expect(
        EquipmentCalc.depreciationPerWorkUnit(
          currentValue: 10000000,
          salvageValue: 1000000,
          expectedWorkUnits: 0,
        ),
        0,
      );
      expect(
        EquipmentCalc.depreciationPerWorkUnit(
          currentValue: 1000000,
          salvageValue: 1000000,
          expectedWorkUnits: 9000,
        ),
        0,
      );
    });

    test('المتراكم لا يتجاوز القيمة القابلة للإهلاك', () {
      // 1000/ساعة × 20,000 ساعة = 20,000,000 لكن السقف 9,000,000
      expect(
        EquipmentCalc.accumulatedDepreciation(
          perWorkUnit: 1000,
          workedUnits: 20000,
          currentValue: 10000000,
          salvageValue: 1000000,
        ),
        9000000,
      );
      expect(
        EquipmentCalc.accumulatedDepreciation(
          perWorkUnit: 1000,
          workedUnits: 3000,
          currentValue: 10000000,
          salvageValue: 1000000,
        ),
        3000000,
      );
    });

    test('القيمة الدفترية ونسبة استهلاك العمر', () {
      expect(
        EquipmentCalc.bookValue(currentValue: 10000000, accumulated: 3000000),
        7000000,
      );
      expect(
        EquipmentCalc.consumedLifeRatio(
          workedUnits: 4500,
          expectedWorkUnits: 9000,
        ),
        0.5,
      );
      expect(
        EquipmentCalc.consumedLifeRatio(
          workedUnits: 20000,
          expectedWorkUnits: 9000,
        ),
        1,
      );
    });

    test('طريقة الإكسل: الإهلاك 50% من تكلفة الديزل وبدل الأعطال 5%', () {
      final double dep = EquipmentCalc.depreciationFromDieselCost(
        dieselCostPerWorkUnit: 2000,
      );
      expect(dep, 1000);
      expect(
        EquipmentCalc.breakdownAllowancePerWorkUnit(
          depreciationPerWorkUnit: dep,
        ),
        50,
      );
    });
  });

  group('ملف المعدة', () {
    test('يتجمع الديزل والأعطال والتواير والقطع في ملف واحد', () {
      final EquipmentFileTotals totals = EquipmentFileTotals.fromLogs(
        dieselLogs: <Map<String, dynamic>>[
          dieselLog(liters: 100, pricePerLiter: 500, workUnits: 8, meterReading: 1000),
          dieselLog(liters: 50, pricePerLiter: 500, workUnits: 4, meterReading: 1100),
        ],
        maintenanceLogs: <Map<String, dynamic>>[
          maintenanceLog(
            type: MaintenanceTypes.breakdown,
            status: MaintenanceTypes.statusOpen,
            quantity: 1,
            unitCost: 30000,
            downtimeHours: 5,
          ),
          maintenanceLog(
            type: MaintenanceTypes.tire,
            quantity: 2,
            unitCost: 45000,
            downtimeHours: 1,
          ),
          maintenanceLog(
            type: MaintenanceTypes.part,
            quantity: 3,
            unitCost: 7000,
            downtimeHours: 0,
          ),
        ],
      );

      expect(totals.totalLiters, 150);
      expect(totals.totalFuelCost, 75000);
      expect(totals.totalWorkUnits, 12);
      expect(totals.lastMeter, 1100);
      expect(totals.dieselRecords, 2);

      expect(totals.breakdownCount, 1);
      expect(totals.openBreakdownCount, 1);
      expect(totals.breakdownCost, 30000);
      expect(totals.tiresCost, 90000);
      expect(totals.partsCost, 21000);
      expect(totals.totalMaintenanceCost, 141000);
      expect(totals.totalDowntimeHours, 6);

      expect(totals.totalOperatingCost, 75000 + 141000);
      expect(totals.dieselCostPerWorkUnit, closeTo(6250, 0.001));
    });

    test('التكلفة المحفوظة في السجل تسبق إعادة الحساب', () {
      final EquipmentFileTotals totals = EquipmentFileTotals.fromLogs(
        dieselLogs: <Map<String, dynamic>>[
          dieselLog(liters: 100, pricePerLiter: 500, totalCost: 48000),
        ],
        maintenanceLogs: <Map<String, dynamic>>[
          maintenanceLog(quantity: 2, unitCost: 10000, totalCost: 19000),
        ],
      );
      expect(totals.totalFuelCost, 48000);
      expect(totals.breakdownCost, 19000);
    });
  });

  group('استهلاك الوقود: رقم المشروع وكمية اليوم', () {
    test('يُجمَّع حسب المشروع واليوم ومرتب بالأحدث', () {
      final List<ProjectDayFuel> days = dailyFuelTotals(
        <Map<String, dynamic>>[
          dieselLog(equipmentId: 'eq1', liters: 100, dayKey: '2026-10-22'),
          dieselLog(equipmentId: 'eq2', liters: 80, dayKey: '2026-10-23'),
          dieselLog(equipmentId: 'eq1', liters: 60, dayKey: '2026-10-23'),
          dieselLog(
            equipmentId: 'eq9',
            projectId: 'p2',
            projectCode: 'PRJ-2',
            liters: 200,
            dayKey: '2026-10-23',
          ),
        ],
      );

      expect(days.length, 3);

      // الأحدث أولًا.
      expect(days.first.dayKey, '2026-10-23');

      final ProjectDayFuel p1Today = days.firstWhere(
        (ProjectDayFuel d) => d.projectCode == 'PRJ-1' && d.dayKey == '2026-10-23',
      );
      expect(p1Today.liters, 140); // 80 + 60 في نفس اليوم
      expect(p1Today.cost, 140 * 500);
      expect(p1Today.records, 2);
      expect(p1Today.equipmentCount, 2); // معدتان مختلفتان

      final ProjectDayFuel p2Today = days.firstWhere(
        (ProjectDayFuel d) => d.projectCode == 'PRJ-2',
      );
      expect(p2Today.liters, 200);
      expect(p2Today.equipmentCount, 1);
    });

    test('السجلات بدون مشروع أو يوم تُتجاهل', () {
      final List<ProjectDayFuel> days = dailyFuelTotals(
        <Map<String, dynamic>>[
          dieselLog(projectId: ''),
          <String, dynamic>{'projectId': 'p1', 'liters': 10},
        ],
      );
      expect(days, isEmpty);
    });
  });

  group('قراءة الأرقام', () {
    test('تدعم الأرقام العربية والنصوص', () {
      expect(EquipmentCalc.numOf('١٢٣'), 123);
      expect(EquipmentCalc.numOf(42), 42);
      expect(EquipmentCalc.numOf(null), 0);
      expect(EquipmentCalc.numOf(''), 0);
    });
  });
}

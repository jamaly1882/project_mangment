import 'package:flutter_test/flutter_test.dart';

import 'package:azal/core/services/cost_prices.dart';
import 'package:azal/core/utils/cost_lines.dart';

// ============================================================
// مزامنة أسعار المخطط إلى الأسطر الفعلية (صفحة مدير الجودة)
// ============================================================

void main() {
  CostLines planned() => CostLines(<CostLineKind, List<Map<String, dynamic>>>{
        CostLineKind.material: <Map<String, dynamic>>[
          <String, dynamic>{
            'materialName': 'أسمنت',
            'unit': 'كيس',
            'unitPrice': 5000.0,
            'quantity': 0,
            CostLineSchema.excludedKey: false,
          },
          <String, dynamic>{
            'materialName': 'حديد G40',
            'unit': 'طن',
            'unitPrice': 420000.0,
            'quantity': 0,
            CostLineSchema.excludedKey: false,
          },
        ],
        CostLineKind.labor: <Map<String, dynamic>>[
          <String, dynamic>{
            'job': 'عمال',
            'wageBasis': 'للوحدة',
            'count': 1,
            'wage': 9000.0,
            'duration': 0,
            CostLineSchema.excludedKey: false,
          },
        ],
      });

  CostLines actual() => CostLines(<CostLineKind, List<Map<String, dynamic>>>{
        CostLineKind.material: <Map<String, dynamic>>[
          <String, dynamic>{
            'materialName': 'الإسمنت',
            'unit': 'كيس',
            'unitPrice': 4000.0,
            'quantity': 7,
            CostLineSchema.excludedKey: false,
          },
        ],
      });

  test('سعر السطر الفعلي يُحدَّث مع بقاء كميته', () {
    final mirrored = CostPrices.mirrorPlannedPrices(
      planned: planned(),
      actual: actual(),
    );

    final cement = mirrored[CostLineKind.material].first;

    expect(cement['unitPrice'], 5000);
    expect(cement['quantity'], 7, reason: 'كمية المشرف لا تُمسّ');
    expect(cement[CostLineSchema.costKey], 35000);
  });

  test('السطر الجديد يُضاف فعليًا بلا كميات', () {
    final mirrored = CostPrices.mirrorPlannedPrices(
      planned: planned(),
      actual: actual(),
    );

    final iron = mirrored[CostLineKind.material]
        .firstWhere((line) => line['materialName'] == 'حديد G40');

    expect(iron['unitPrice'], 420000);
    expect(iron['quantity'], 0);
    expect(iron[CostLineSchema.costKey], 0);

    final labor = mirrored[CostLineKind.labor].single;

    expect(labor['job'], 'عمال');
    expect(labor['wage'], 9000);
    expect(labor['count'], 0);
    expect(labor['duration'], 0);
    expect(labor[CostLineSchema.costKey], 0);
  });

  test('لا يُكرر السطر الفعلي عند إعادة المزامنة', () {
    final first = CostPrices.mirrorPlannedPrices(
      planned: planned(),
      actual: actual(),
    );

    final second = CostPrices.mirrorPlannedPrices(
      planned: planned(),
      actual: first,
    );

    expect(second[CostLineKind.material].length, 2);
    expect(second[CostLineKind.labor].length, 1);
    expect(second[CostLineKind.material].first['quantity'], 7);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:azal/core/services/project_cost_sync.dart';

// ============================================================
// تجميع تكاليف المشروع من بنوده:
// مخطط (إدخال مدير المشروع) / فعلي (تسجيل مشرف البند) / معتمد
// ============================================================

void main() {
  group('ProjectCostTotals.fromItems', () {
    test('يجمع التكاليف المخططة من البنود', () {
      final totals = ProjectCostTotals.fromItems([
        <String, dynamic>{'materialsCost': 100.0, 'laborCost': 50.0},
        <String, dynamic>{'equipmentCost': 200.0, 'fuelCost': 25.0},
      ]);

      expect(totals.total, 375.0);
      expect(totals.breakdown['materials'], 100.0);
      expect(totals.breakdown['fuel'], 25.0);
      expect(totals.itemCount, 2);
      expect(totals.costedItemCount, 2);
      expect(totals.hasActual, isFalse);
      expect(totals.displayTotal, 375.0);
    });

    test('الفعلي يعتمَد قسمًا قسمًا والإجمالي يتبعه', () {
      final totals = ProjectCostTotals.fromItems([
        <String, dynamic>{
          'materialsCost': 100.0,
          'materialsActualCost': 120.0,
          'laborCost': 10.0,
        },
        <String, dynamic>{'fuelCost': 40.0},
      ]);

      expect(totals.total, 150.0);
      expect(totals.actualTotal, 120.0);
      // 120 (فعلي بدل مخططها) + 10 (لا فعلي لها) + 40
      expect(totals.effectiveTotal, 170.0);
      expect(totals.actualItemCount, 1);
      expect(totals.displayTotal, 170.0);
      expect(totals.hasActual, isTrue);
    });

    test('بند بلا تكلفة لا يدخل ضمن البنود المكلفة', () {
      final totals = ProjectCostTotals.fromItems([
        <String, dynamic>{'materialsCost': 0.0},
        <String, dynamic>{'materialsCost': 5.0},
      ]);

      expect(totals.itemCount, 2);
      expect(totals.costedItemCount, 1);
      expect(totals.total, 5.0);
    });

    test('أسطر التكلفة لا تغيّر المجاميع (تُقرأ من الحقول المجمّعة)', () {
      final totals = ProjectCostTotals.fromItems([
        <String, dynamic>{
          'materialsCost': 600.0,
          'materialLines': [
            <String, dynamic>{
              'materialName': 'إسمنت',
              'unit': 'كيس',
              'unitPrice': 15000,
              'quantity': 40,
              'cost': 600000,
            },
          ],
        },
      ]);

      expect(totals.total, 600.0);
      expect(totals.itemCount, 1);
    });

    test('قائمة فارغة تعيد أصفارًا آمنة', () {
      final totals = ProjectCostTotals.fromItems(const <Map<String, dynamic>>[]);

      expect(totals.total, 0);
      expect(totals.actualTotal, 0);
      expect(totals.itemCount, 0);
      expect(totals.hasCosts, isFalse);
      expect(totals.displayTotal, 0);
    });

    test('empty() آمن قبل وصول البيانات', () {
      final totals = ProjectCostTotals.empty();

      expect(totals.total, 0);
      expect(totals.displayTotal, 0);
      expect(totals.hasCosts, isFalse);
      expect(totals.breakdown['labor'], 0.0);
    });

    test('يجمع عدد أسطر التكلفة المخططة والفعلية', () {
      final totals = ProjectCostTotals.fromItems([
        <String, dynamic>{'materialsCost': 10.0, 'costsLineCount': 3},
        <String, dynamic>{
          'laborCost': 20.0,
          'costsLineCount': 2,
          'actualCostsLineCount': 4,
        },
        <String, dynamic>{'fuelCost': 5.0},
      ]);

      expect(totals.lineCount, 5);
      expect(totals.actualLineCount, 4);
      expect(totals.hasLines, isTrue);
    });

    test('بند بلا أسطر لا يضيف عددًا', () {
      final totals = ProjectCostTotals.fromItems([
        <String, dynamic>{'materialsCost': 10.0, 'costsLineCount': null},
        <String, dynamic>{'materialsCost': 1.0, 'costsLineCount': '2'},
      ]);

      expect(totals.lineCount, 0);
      expect(totals.hasLines, isFalse);
    });

    test('toFields يحتوي مجاميع المخطط والفعلي والمعتمد والعدّادات', () {
      final totals = ProjectCostTotals.fromItems([
        <String, dynamic>{
          'materialsCost': 100.0,
          'materialsActualCost': 120.0,
        },
      ]);

      final fields = totals.toFields();

      expect(fields.containsKey('materialsCost'), isTrue);
      expect(fields.containsKey('materialsActualCost'), isTrue);
      expect(fields.containsKey('totalCost'), isTrue);
      expect(fields.containsKey('actualTotalCost'), isTrue);
      expect(fields.containsKey('effectiveTotalCost'), isTrue);
      expect(fields['costsSource'], 'auto_from_items');
      expect(fields['costsItemCount'], 1);
      expect(fields['costsActualItemCount'], 1);
      expect(fields['costsProjectItemCount'], 1);
      expect(fields['costsLineCount'], 0);
      expect(fields['actualCostsLineCount'], 0);
      expect(fields['materialsCost'], 100.0);
      expect(fields['materialsActualCost'], 120.0);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:azal/core/services/item_approvals.dart';
import 'package:azal/core/utils/cost_lines.dart';

// ============================================================
// قواعد الكميات الإضافية والزمن + استبعاد أسطر التكلفة
// ============================================================

void main() {
  group('ItemAllowance — الكمية القصوى', () {
    test('بدون موافقة: الحد هو الكمية التعاقدية', () {
      const allowance = ItemAllowance(
        contractQuantity: 1000,
        executedQuantity: 400,
        extraPercent: 0,
        extraApproved: false,
        contractStart: null,
        contractEnd: null,
        extensionDays: 0,
        extensionUntil: null,
      );

      expect(allowance.maxQuantity, 1000);
      expect(allowance.remaining, 600);
      expect(allowance.extraAllowance, 0);
      expect(allowance.isOverContract, isFalse);
    });

    test('بموافقة 20%: الحد 1200 والزيادة 200', () {
      const allowance = ItemAllowance(
        contractQuantity: 1000,
        executedQuantity: 1000,
        extraPercent: 20,
        extraApproved: true,
        contractStart: null,
        contractEnd: null,
        extensionDays: 0,
        extensionUntil: null,
      );

      expect(allowance.maxQuantity, 1200);
      expect(allowance.remaining, 200);
      expect(allowance.extraAllowance, 200);
    });

    test('النسبة لا تتجاوز 20% حتى لو حُفظت أكبر', () {
      const allowance = ItemAllowance(
        contractQuantity: 1000,
        executedQuantity: 0,
        extraPercent: 60,
        extraApproved: true,
        contractStart: null,
        contractEnd: null,
        extensionDays: 0,
        extensionUntil: null,
      );

      expect(allowance.maxQuantity, 1200);
    });

    test('الموافقة على 0% لا تمنح زيادة', () {
      const allowance = ItemAllowance(
        contractQuantity: 500,
        executedQuantity: 500,
        extraPercent: 0,
        extraApproved: true,
        contractStart: null,
        contractEnd: null,
        extensionDays: 0,
        extensionUntil: null,
      );

      expect(allowance.maxQuantity, 500);
      expect(allowance.isOverContract, isFalse);
    });

    test('قراءة الحقول من وثيقة البند', () {
      final allowance = ItemAllowance.fromData(<String, dynamic>{
        'contractQuantity': 200,
        'executedQuantity': 210,
        'extraQuantityApproved': true,
        'extraQuantityPercent': 20,
      });

      expect(allowance.maxQuantity, 240);
      expect(allowance.isOverContract, isTrue);
      expect(allowance.remaining, 30);
    });
  });

  group('ItemAllowance — الزمن', () {
    test('بلا تواريخ: لا انتهاء', () {
      final allowance = ItemAllowance.fromData(<String, dynamic>{
        'contractQuantity': 100,
      });

      expect(allowance.effectiveEnd, isNull);
      expect(allowance.isTimeExpired, isFalse);
    });

    test('نهاية في الماضي = منتهٍ، وفي المستقبل = ساري', () {
      final expired = ItemAllowance.fromData(<String, dynamic>{
        'contractQuantity': 100,
        'contractEndDate': DateTime.now().subtract(const Duration(days: 2)),
      });

      final running = ItemAllowance.fromData(<String, dynamic>{
        'contractQuantity': 100,
        'contractEndDate': DateTime.now().add(const Duration(days: 5)),
      });

      expect(expired.isTimeExpired, isTrue);
      expect(running.isTimeExpired, isFalse);
    });

    test('التمديد يمدّ النهاية المعتمدة', () {
      final base = DateTime.now().add(const Duration(days: 1));

      final allowance = ItemAllowance.fromData(<String, dynamic>{
        'contractQuantity': 100,
        'contractEndDate': base,
        'timeExtensionDays': 30,
      });

      expect(
        allowance.effectiveEnd!.difference(base).inDays,
        30,
      );
      expect(allowance.isTimeExpired, isFalse);
    });

    test('timeExtensionUntil يتقدّم على المدة المحسوبة', () {
      final until = DateTime.now().add(const Duration(days: 10));

      final allowance = ItemAllowance.fromData(<String, dynamic>{
        'contractQuantity': 100,
        'contractEndDate': DateTime.now().subtract(const Duration(days: 30)),
        'timeExtensionDays': 5,
        'timeExtensionUntil': until,
      });

      expect(allowance.effectiveEnd, until);
      expect(allowance.isTimeExpired, isFalse);
    });
  });

  group('استبعاد سطر التكلفة', () {
    test('السطر المستبعد تكلفته صفر ولا يُدقَّق', () {
      final schema = CostLineSchema.all[CostLineKind.material]!;

      final line = <String, dynamic>{
        'materialName': 'حديد',
        'unit': 'طن',
        'unitPrice': 1000.0,
        'quantity': 5.0,
        CostLineSchema.excludedKey: true,
      };

      expect(schema.costOf(line), 0);
      expect(schema.validateLine(line, 0), isEmpty);
    });

    test('السطر غير المستبعد يُحسب طبيعيًا', () {
      final schema = CostLineSchema.all[CostLineKind.material]!;

      final line = <String, dynamic>{
        'materialName': 'حديد',
        'unit': 'طن',
        'unitPrice': 1000.0,
        'quantity': 5.0,
      };

      expect(schema.costOf(line), 5000);
    });
  });

  group('نسبة الكمية الإضافية', () {
    test('الحد الأقصى 20%', () {
      expect(maxExtraQuantityPercent, 20);
    });
  });

  // ============================================================
  // قرار «الكمية الإضافية» قبل إدخال الكمية المنفذة
  // ============================================================
  group('ExtraQuantityPlan — قرار الكمية الإضافية', () {
    test('إدخال داخل الكمية التعاقدية: لا يحتاج طلبًا', () {
      final plan = ExtraQuantityPlan.of(
        contractQuantity: 700,
        executedQuantity: 100,
        enteredQuantity: 50,
      );

      expect(plan.totalAfter, 150);
      expect(plan.needsRequest, isFalse);
      expect(plan.exceedsCap, isFalse);
      expect(plan.excessQuantity, 0);
      expect(plan.requestedPercent, 0);
    });

    test('تراكم الكميات: 50 ثم 100 على عقد 700 = 150', () {
      final plan = ExtraQuantityPlan.of(
        contractQuantity: 700,
        executedQuantity: 50,
        enteredQuantity: 100,
      );

      expect(plan.totalAfter, 150);
      expect(plan.needsRequest, isFalse);
    });

    test('تجاوز التعاقدية: يُحسب الفائض والنسبة المطلوبة', () {
      final plan = ExtraQuantityPlan.of(
        contractQuantity: 700,
        executedQuantity: 650,
        enteredQuantity: 100,
      );

      expect(plan.totalAfter, 750);
      expect(plan.needsRequest, isTrue);
      expect(plan.exceedsCap, isFalse);
      expect(plan.excessQuantity, 50);
      expect(plan.requestedPercent, closeTo(7.1428, 0.001));
      expect(plan.requestedQuantity, closeTo(50, 0.001));
      expect(plan.requestedTotal, closeTo(750, 0.001));
      expect(plan.maxEnterableNow, 190);
    });

    test('تجاوز سقف 20%: النسبة تُقيَّد بالسقف ويُعلَم التجاوز', () {
      final plan = ExtraQuantityPlan.of(
        contractQuantity: 700,
        executedQuantity: 700,
        enteredQuantity: 200,
      );

      expect(plan.totalAfter, 900);
      expect(plan.maxAllowedQuantity, 840);
      expect(plan.needsRequest, isTrue);
      expect(plan.exceedsCap, isTrue);
      expect(plan.requestedPercent, maxExtraQuantityPercent);
      expect(plan.requestedQuantity, closeTo(140, 0.001));
      expect(plan.requestedTotal, closeTo(840, 0.001));
    });

    test('بعد موافقة 10%: الحد يرتفع إلى 110% من التعاقدية', () {
      final plan = ExtraQuantityPlan.of(
        contractQuantity: 1000,
        executedQuantity: 1090,
        enteredQuantity: 30,
        approvedPercent: 10,
        extraApproved: true,
      );

      expect(plan.allowedQuantity, 1100);
      expect(plan.totalAfter, 1120);
      expect(plan.needsRequest, isTrue);
      expect(plan.approvedPercent, 10);
      expect(plan.requestedPercent, closeTo(12, 0.001));
    });

    test('بعد موافقة 10%: إدخال داخل الحد المعتمد لا يحتاج طلبًا', () {
      final plan = ExtraQuantityPlan.of(
        contractQuantity: 1000,
        executedQuantity: 1050,
        enteredQuantity: 40,
        approvedPercent: 10,
        extraApproved: true,
      );

      expect(plan.totalAfter, 1090);
      expect(plan.allowedQuantity, 1100);
      expect(plan.needsRequest, isFalse);
      expect(plan.excessQuantity, 50);
    });

    test('بلا كمية تعاقدية: لا طلب ولا سقف', () {
      final plan = ExtraQuantityPlan.of(
        contractQuantity: 0,
        executedQuantity: 10,
        enteredQuantity: 5,
      );

      expect(plan.needsRequest, isFalse);
      expect(plan.exceedsCap, isFalse);
      expect(plan.requestedPercent, 0);
      expect(plan.allowedQuantity, double.infinity);
    });

    test('قيم سالبة تُعامل كصفر', () {
      final plan = ExtraQuantityPlan.of(
        contractQuantity: 100,
        executedQuantity: -20,
        enteredQuantity: -5,
      );

      expect(plan.executedQuantity, 0);
      expect(plan.enteredQuantity, 0);
      expect(plan.totalAfter, 0);
      expect(plan.needsRequest, isFalse);
    });
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/costs.dart';

// ============================================================
// نتيجة تجميع تكاليف بنود المشروع
// ============================================================

/// تكلفة المشروع ليست إدخالًا يدويًا،
/// بل مجموع تكاليف بنوده (مواد / عمالة / معدات / محروقات).
class ProjectCostTotals {
  const ProjectCostTotals({
    required this.breakdown,
    required this.total,
    required this.itemCount,
    required this.costedItemCount,
  });

  /// مبالغ كل قسم: materials / labor / equipment / fuel
  final Map<String, double> breakdown;

  /// إجمالي تكلفة المشروع = مجموع أقسام كل البنود.
  final double total;

  /// عدد بنود المشروع كلها.
  final int itemCount;

  /// عدد البنود التي لها تكلفة مسجلة.
  final int costedItemCount;

  bool get hasCosts => costedItemCount > 0 && total > 0;

  /// حقل واحد لكل قسم + الإجمالي، جاهز للكتابة في Firestore.
  Map<String, dynamic> toFields() {
    final fields = <String, dynamic>{
      for (final category in ProjectCosts.categories)
        category.totalField: breakdown[category.key] ?? 0,
      ProjectCosts.totalField: total,
      'costsSource': 'auto_from_items',
      'costsItemCount': costedItemCount,
      'costsProjectItemCount': itemCount,
      'costsUpdatedAt': FieldValue.serverTimestamp(),
    };

    return fields;
  }

  static ProjectCostTotals empty() {
    return ProjectCostTotals(
      breakdown: {
        for (final category in ProjectCosts.categories) category.key: 0.0,
      },
      total: 0,
      itemCount: 0,
      costedItemCount: 0,
    );
  }

  /// تجميع التكاليف من قائمة بنود (خرائط بيانات).
  static ProjectCostTotals fromItems(
    Iterable<Map<String, dynamic>> items,
  ) {
    final breakdown = <String, double>{
      for (final category in ProjectCosts.categories) category.key: 0.0,
    };

    double total = 0;
    int costed = 0;
    int count = 0;

    for (final item in items) {
      count++;

      final itemBreakdown = ProjectCosts.breakdownOf(item);
      final itemTotal = ProjectCosts.totalOf(item);

      if (itemTotal > 0) costed++;

      for (final entry in itemBreakdown.entries) {
        breakdown[entry.key] =
            (breakdown[entry.key] ?? 0) + entry.value;
        total += entry.value;
      }
    }

    return ProjectCostTotals(
      breakdown: breakdown,
      total: total,
      itemCount: count,
      costedItemCount: costed,
    );
  }
}

// ============================================================
// مزامنة تكاليف المشروع مع بنوده
// ============================================================

class ProjectCostSync {
  ProjectCostSync._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// قراءة بنود المشروع وحساب تكاليفه.
  static Future<ProjectCostTotals> totalsFor(String projectId) async {
    final items = await _firestore
        .collection('items')
        .where('projectId', isEqualTo: projectId)
        .get();

    return ProjectCostTotals.fromItems(
      items.docs.map((doc) => doc.data()),
    );
  }

  /// حساب تكاليف المشروع وكتابتها في وثيقة المشروع.
  ///
  /// تُستدعى بعد أي حفظ يغيّر تكاليف البنود
  /// (إنشاء بند، حفظ تفاصيل/تكاليف بند، تعديل كمية).
  static Future<ProjectCostTotals> applyTotals(
    String projectId, {
    WriteBatch? batch,
  }) async {
    final totals = await totalsFor(projectId);

    final fields = totals.toFields();

    if (batch != null) {
      batch.set(
        _firestore.collection('projects').doc(projectId),
        fields,
        SetOptions(merge: true),
      );
    } else {
      await _firestore
          .collection('projects')
          .doc(projectId)
          .set(fields, SetOptions(merge: true));
    }

    return totals;
  }
}

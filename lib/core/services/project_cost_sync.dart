import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/costs.dart';

// ============================================================
// نتيجة تجميع تكاليف بنود المشروع
// ============================================================

/// تكلفة المشروع ليست إدخالًا يدويًا،
/// بل مجموع تكاليف بنوده (مواد / عمالة / معدات / محروقات).
///
/// يفرّق الحساب بين:
/// • المخطط: ما يدخله مدير المشروع في صفحة تفاصيل البند.
/// • الفعلي: ما يسجله مشرف البند في صفحته.
/// • المعتمد: الفعلي لقسم البند إن وُجد، وإلا المخطط.
class ProjectCostTotals {
  const ProjectCostTotals({
    required this.breakdown,
    required this.total,
    required this.itemCount,
    required this.costedItemCount,
    this.actualBreakdown = const <String, double>{},
    this.actualTotal = 0,
    this.effectiveBreakdown = const <String, double>{},
    this.effectiveTotal = 0,
    this.actualItemCount = 0,
  });

  /// مبالغ كل قسم المخططة: materials / labor / equipment / fuel
  final Map<String, double> breakdown;

  /// إجمالي التكلفة المخططة للمشروع.
  final double total;

  /// عدد بنود المشروع كلها.
  final int itemCount;

  /// عدد البنود التي لها تكلفة مخططة مسجلة.
  final int costedItemCount;

  /// مبالغ كل قسم الفعلية (ما سجله مشرف البند).
  final Map<String, double> actualBreakdown;

  /// إجمالي التكلفة الفعلية للمشروع.
  final double actualTotal;

  /// الفعلي عند توفره وإلا المخطط، قسمًا قسمًا.
  final Map<String, double> effectiveBreakdown;

  /// الإجمالي المعتمد للمشروع.
  final double effectiveTotal;

  /// عدد البنود التي سجل مشرفها تكلفة فعلية.
  final int actualItemCount;

  bool get hasCosts => costedItemCount > 0 && total > 0;

  bool get hasActual => actualItemCount > 0 && actualTotal > 0;

  /// المبلغ الذي يُعرض على أنه «إجمالي تكلفة المشروع»:
  /// الفعلي عند توفره، وإلا المخطط.
  double get displayTotal => effectiveTotal > 0 ? effectiveTotal : total;

  Map<String, double> get displayBreakdown =>
      hasActual ? actualBreakdown : breakdown;

  /// حقول جاهزة للكتابة في وثيقة المشروع.
  Map<String, dynamic> toFields() {
    final fields = <String, dynamic>{
      // المخطط (ما يدخله مدير المشروع).
      for (final category in ProjectCosts.categories)
        category.totalField: breakdown[category.key] ?? 0,
      ProjectCosts.totalField: total,

      // الفعلي (ما يسجله مشرف البند).
      for (final category in ProjectCosts.categories)
        category.actualField: actualBreakdown[category.key] ?? 0,
      ProjectCosts.actualTotalField: actualTotal,

      // المعتمد: الفعلي عند توفره وإلا المخطط.
      ProjectCosts.effectiveTotalField: effectiveTotal > 0
          ? effectiveTotal
          : total,

      'costsSource': 'auto_from_items',
      'costsItemCount': costedItemCount,
      'costsActualItemCount': actualItemCount,
      'costsProjectItemCount': itemCount,
      'costsUpdatedAt': FieldValue.serverTimestamp(),
    };

    return fields;
  }

  static ProjectCostTotals empty() {
    const zero = <String, double>{
      'materials': 0.0,
      'labor': 0.0,
      'equipment': 0.0,
      'fuel': 0.0,
    };

    return ProjectCostTotals(
      breakdown: zero,
      total: 0,
      itemCount: 0,
      costedItemCount: 0,
      actualBreakdown: zero,
      effectiveBreakdown: zero,
    );
  }

  /// تجميع التكاليف من قائمة بنود (خرائط بيانات).
  static ProjectCostTotals fromItems(
    Iterable<Map<String, dynamic>> items,
  ) {
    final breakdown = _zeroBreakdown();
    final actualBreakdown = _zeroBreakdown();
    final effectiveBreakdown = _zeroBreakdown();

    double total = 0;
    double actualTotal = 0;
    double effectiveTotal = 0;

    int costed = 0;
    int actuals = 0;
    int count = 0;

    for (final item in items) {
      count++;

      final planned = ProjectCosts.breakdownOf(item);
      final actual = ProjectCosts.actualBreakdownOf(item);
      final effective = ProjectCosts.effectiveBreakdownOf(item);

      if (ProjectCosts.totalOf(item) > 0) costed++;
      if (ProjectCosts.hasActualValues(item)) actuals++;

      for (final category in ProjectCosts.categories) {
        final key = category.key;

        breakdown[key] = (breakdown[key] ?? 0) + (planned[key] ?? 0);
        actualBreakdown[key] =
            (actualBreakdown[key] ?? 0) + (actual[key] ?? 0);
        effectiveBreakdown[key] =
            (effectiveBreakdown[key] ?? 0) + (effective[key] ?? 0);

        total += planned[key] ?? 0;
        actualTotal += actual[key] ?? 0;
        effectiveTotal += effective[key] ?? 0;
      }
    }

    return ProjectCostTotals(
      breakdown: breakdown,
      total: total,
      itemCount: count,
      costedItemCount: costed,
      actualBreakdown: actualBreakdown,
      actualTotal: actualTotal,
      effectiveBreakdown: effectiveBreakdown,
      effectiveTotal: effectiveTotal,
      actualItemCount: actuals,
    );
  }

  static Map<String, double> _zeroBreakdown() {
    return <String, double>{
      for (final category in ProjectCosts.categories) category.key: 0.0,
    };
  }
}

// ============================================================
// مزامنة تكاليف المشروع مع بنوده
// ============================================================

class ProjectCostSync {
  ProjectCostSync._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// قراءة بنود المشروع وحساب تكاليفه (المخطط والفعلي).
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
  /// تُستدعى بعد أي حفظ يغيّر تكاليف البنود:
  /// إنشاء بند، حفظ تفاصيل/تكاليف بند (مدير المشروع)،
  /// تسجيل استهلاك أو تكاليف فعلية (مشرف البند)، تعديل كمية.
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

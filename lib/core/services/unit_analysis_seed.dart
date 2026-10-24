import '../constants/unit_analysis_prices.dart';
import '../utils/cost_lines.dart';

/// ============================================================
/// بذور أسعار التحليل للبند الجديد
/// ============================================================
///
/// البند الجديد كان يُنشأ بلا تكاليف، فيفتح المشرف تكليفه فلا يجد سعرًا.
/// هنا نبني أسطر التحليل الأربعة **مسبقًا** لحظة إنشاء البند:
///   • العمالة: المهنة + الأجرة (بلا مدة ⇒ تكلفة صفر)
///   • المعدات: نوع المعدة + الإهلاك (بلا كمية)
///   • المحروقات: نوع الوقود + سعر اللتر (بلا كمية)
///   • المواد: الاسم + سعر الوحدة (بلا كمية)
///
/// الأسعار تُحفظ مع البند فورًا، والكميات تبقى صفرًا حتى يدخلها المشرف،
/// فلا تتأثر تكلفة المشروع بمجرد الإنشاء.
class UnitAnalysisSeed {
  UnitAnalysisSeed._();

  /// الأسطر المجمّعة حسب القسم.
  static Map<CostLineKind, List<Map<String, dynamic>>> get lines =>
      <CostLineKind, List<Map<String, dynamic>>>{
        CostLineKind.labor: _build(CostLineKind.labor, unitAnalysisLabor),
        CostLineKind.equipment:
            _build(CostLineKind.equipment, unitAnalysisEquipment),
        CostLineKind.fuel: _build(CostLineKind.fuel, unitAnalysisFuel),
        CostLineKind.material:
            _build(CostLineKind.material, unitAnalysisMaterials),
      };

  /// نفس الأسطر جاهزة للحفظ داخل وثيقة البند مباشرة.
  ///
  /// تُدمج في بيانات الإنشاء فلا نحتاج كتابة إضافية على Firestore،
  /// وتُحسب مجاميع الأقسام (وهي صفر بلا كميات).
  /// تشمل الأسطر **الفعلية** أيضًا، لأن صفحة المشرف (تكليف البند)
  /// تقرأ الأسطر الفعلية، فبدونها لا يرى السعر في تكليفه.
  static Map<String, dynamic> saveData({double contractQuantity = 0}) {
    final seeded = CostLines(lines);

    return <String, dynamic>{
      ...seeded.toSaveData(contractQuantity: contractQuantity),
      ...seeded.toSaveData(actual: true, contractQuantity: contractQuantity),
    };
  }

  /// عدد الأسطر التي ستُضاف للبند الجديد.
  static int get lineCount => unitAnalysisRowCount;

  /// وصف مختصر لعدد الأسطر لكل قسم (يُعرض في نموذج الإضافة).
  static String get summary =>
      'عمالة ${unitAnalysisLaborCount} · '
      'معدات ${unitAnalysisEquipmentCount} · '
      'وقود ${unitAnalysisFuelCount} · '
      'مواد ${unitAnalysisMaterialsCount}';

  /// أسطر التحليل الخام لقسم واحد (تُستخدم في جداول الاختيار).
  static List<UnitAnalysisRow> rowsOf(CostLineKind kind) {
    switch (kind) {
      case CostLineKind.labor:
        return unitAnalysisLabor;
      case CostLineKind.equipment:
        return unitAnalysisEquipment;
      case CostLineKind.fuel:
        return unitAnalysisFuel;
      case CostLineKind.material:
        return unitAnalysisMaterials;
    }
  }

  static List<Map<String, dynamic>> _build(
    CostLineKind kind,
    List<UnitAnalysisRow> rows,
  ) {
    return <Map<String, dynamic>>[
      for (final row in rows)
        buildCostLine(kind: kind, label: row.name, price: row.amount),
    ];
  }
}

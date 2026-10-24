import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/unit_analysis_prices.dart';
import '../utils/cost_lines.dart';
import '../utils/costs.dart';
import 'cost_prices.dart';

/// ============================================================
/// استيراد أسعار التحليل بضغطة واحدة
/// ============================================================
///
/// نفس فكرة «استيراد البنود والأنواع»: لا ملف ولا لصق. يقرأ الجدول
/// المضمّن في [unitAnalysisPrices] ويُملأ به تكاليف البند:
///   • العمالة: المهنة + المصاريف
///   • المعدات: نوع المعدة + الإهلاك
///   • المحروقات: ديزل/بترول/غاز/قاز/زيت + سعر اللتر
///   • المواد: بقية الأسماء + أسعارها
///
/// القواعد:
///   • السطر الموجود في البند (بمطابقة الاسم) يُحدَّث سعره فقط.
///   • السطر غير الموجود يُضاف بلا كميات: العدد ١ والمدة ٠ للعمالة،
///     والكمية ٠ لبقية الأقسام، فتبقى التكلفة صفرًا حتى يدخل المشرف
///     كمياته.
///   • لا يتكرر أي سطر عند إعادة الاستيراد.
class UnitAnalysisImporter {
  UnitAnalysisImporter._();

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// يطبّق جدول التحليل على بند واحد.
  static Future<UnitAnalysisImportResult> importToItem({
    required String itemId,
    required String projectId,
    required String userId,
    bool actualToo = true,
  }) async {
    final itemRef = _firestore.collection('items').doc(itemId);
    final itemDoc = await itemRef.get();

    if (!itemDoc.exists) {
      throw Exception('البند غير موجود.');
    }

    final item = itemDoc.data() ?? <String, dynamic>{};
    if (ProjectCosts.nonNegative(item['contractQuantity']) < 0) {
      throw Exception('بيانات الكمية التعاقدية غير صالحة.');
    }

    final detailsDoc =
        await _firestore.collection('item_details').doc(itemId).get();
    final details = detailsDoc.data() ?? <String, dynamic>{};

    final executed = ProjectCosts.nonNegative(item['executedQuantity']);
    final quantity = executed > 0
        ? executed
        : ProjectCosts.nonNegative(item['contractQuantity']);
    final unit = (item['unit'] ?? '').toString();

    final plannedSource =
        CostLines.fromData(details, contractQuantity: quantity, unit: unit)
                .isNotEmpty
            ? details
            : item;

    final planned = CostLines.fromData(
      plannedSource,
      contractQuantity: quantity,
      unit: unit,
    );

    final actual = CostLines.fromData(
      details.isNotEmpty ? details : item,
      actual: true,
      contractQuantity: quantity,
      unit: unit,
    );

    final changes = <PriceChange>[];
    var applied = 0;
    var added = 0;

    void run(
      CostLineKind kind,
      List<UnitAnalysisRow> rows, {
      required bool addMissing,
    }) {
      final schema = CostLineSchema.of(kind);

      for (final row in rows) {
        final entry = PriceEntry(
          label: row.name,
          kind: kind,
          price: row.amount,
        );

        var matched = false;

        for (final target in <CostLines>[
          planned,
          if (actualToo) actual,
        ]) {
          for (final line in target[kind]) {
            final label = CostLineSchema.text(line, schema.titleKey);

            if (!CostPrices.matches(label, row.name)) continue;

            matched = true;

            final oldPrice = CostPrices.priceOf(kind, line);

            if (!CostPrices.applyPriceToLine(schema, line, row.amount)) {
              continue;
            }

            applied++;
            changes.add(
              PriceChange(
                kind: kind,
                label: label,
                oldPrice: oldPrice,
                newPrice: row.amount,
              ),
            );
          }
        }

        if (matched || !addMissing) continue;

        planned[kind].add(CostPrices.newLine(kind, entry));
        added++;
      }
    }

    run(CostLineKind.labor, unitAnalysisLabor, addMissing: true);
    run(CostLineKind.equipment, unitAnalysisEquipment, addMissing: true);
    run(CostLineKind.fuel, unitAnalysisFuel, addMissing: true);
    run(CostLineKind.material, unitAnalysisMaterials, addMissing: true);

    if (applied == 0 && added == 0) {
      return const UnitAnalysisImportResult(
        updatedPrices: 0,
        addedLines: 0,
        message: 'كل أسطر التحليل موجودة بأسعارها؛ لم يتغير شيء.',
      );
    }

    await CostPrices.save(
      itemId: itemId,
      projectId: projectId,
      planned: planned,
      actual: actual,
      changes: changes,
      userId: userId,
      itemName: (item['name'] ?? '').toString(),
      contractQuantity: quantity,
    );

    return UnitAnalysisImportResult(
      updatedPrices: applied,
      addedLines: added,
      message: 'تم استيراد أسعار التحليل: '
          '${applied > 0 ? 'حُدِّث $applied سعرًا' : ''}'
          '${applied > 0 && added > 0 ? '، و' : ''}'
          '${added > 0 ? 'أُضيف $added سطرًا' : ''}.',
    );
  }

  /// يطبّق الجدول على كل بنود المشروع.
  static Future<ProjectUnitAnalysisResult> importToProject({
    required String projectId,
    required String userId,
  }) async {
    final snapshot = await _firestore
        .collection('items')
        .where('projectId', isEqualTo: projectId)
        .get();

    if (snapshot.docs.isEmpty) {
      throw Exception('لا توجد بنود في هذا المشروع بعد.');
    }

    var items = 0;
    var prices = 0;
    var lines = 0;

    for (final doc in snapshot.docs) {
      final result = await importToItem(
        itemId: doc.id,
        projectId: projectId,
        userId: userId,
        actualToo: false,
      );

      if (result.updatedPrices == 0 && result.addedLines == 0) continue;

      items++;
      prices += result.updatedPrices;
      lines += result.addedLines;
    }

    return ProjectUnitAnalysisResult(
      itemsUpdated: items,
      totalItems: snapshot.docs.length,
      updatedPrices: prices,
      addedLines: lines,
    );
  }
}

/// نتيجة استيراد أسعار التحليل على بند.
class UnitAnalysisImportResult {
  const UnitAnalysisImportResult({
    required this.updatedPrices,
    required this.addedLines,
    required this.message,
  });

  final int updatedPrices;
  final int addedLines;
  final String message;
}

/// نتيجة استيراد أسعار التحليل على مشروع.
class ProjectUnitAnalysisResult {
  const ProjectUnitAnalysisResult({
    required this.itemsUpdated,
    required this.totalItems,
    required this.updatedPrices,
    required this.addedLines,
  });

  final int itemsUpdated;
  final int totalItems;
  final int updatedPrices;
  final int addedLines;
}

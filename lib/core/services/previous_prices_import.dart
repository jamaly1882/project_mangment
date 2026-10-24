import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/previous_prices.dart';

// ============================================================
// استيراد أسعار 1447هـ إلى البنود والأنواع
// ============================================================
//
// يقرأ القائمة الثابتة [previousPriceBands] ويكتبها في:
//   item_definitions/{band}            → بند لكل قسم أعمال
//   item_definitions/{band}/types/{id} → نوع لكل سطر مسعّر
//
// قواعد الأمان:
//   • لا يحذف ولا يعدّل شيئًا موجودًا؛ يضيف الناقص فقط.
//   • لا يكرر: يقارن بكود البند (code) ثم باسم النوع.
//   • يعمل على دفعات (batch) صغيرة ليظل التقدم ظاهرًا.
// ============================================================

/// نتيجة عملية استيراد واحدة.
class PreviousPricesImportResult {
  const PreviousPricesImportResult({
    this.bandsCreated = 0,
    this.bandsExisting = 0,
    this.typesCreated = 0,
    this.typesSkipped = 0,
    this.failed = 0,
    this.errors = const <String>[],
  });

  /// بنود أُنشئت في هذه العملية.
  final int bandsCreated;

  /// بنود كانت موجودة مسبقًا (أُضيفت إليها الأنواع الناقصة فقط).
  final int bandsExisting;

  /// أنواع أُنشئت.
  final int typesCreated;

  /// أنواع موجودة مسبقًا فتم تخطيها.
  final int typesSkipped;

  /// عمليات فشلت.
  final int failed;

  /// رسائل الأخطاء المختصرة.
  final List<String> errors;

  bool get hasChanges => bandsCreated > 0 || typesCreated > 0;

  String get summary {
    final lines = <String>[
      'البنود: ${bandsCreated + bandsExisting} '
          '(جديد $bandsCreated، موجود $bandsExisting)',
      'الأنواع: ${typesCreated + typesSkipped} '
          '(جديد $typesCreated، موجود $typesSkipped)',
      if (failed > 0) 'فشل: $failed',
    ];

    return lines.join('\n');
  }
}

class PreviousPricesImporter {
  PreviousPricesImporter._();

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _bands =>
      _firestore.collection('item_definitions');

  /// يستورد أقسام الأعمال وأنواعها المسعّرة.
  ///
  /// [onProgress] يُستدعى بعد كل قسم: (المنجز، الإجمالي).
  /// [overwritePrices] إن كانت true تُحدَّث أسعار الأنواع الموجودة
  /// (تحديث السعر السابق فقط، دون المساس بالاسم أو التفعيل).
  static Future<PreviousPricesImportResult> import({
    void Function(int done, int total)? onProgress,
    bool overwritePrices = false,
  }) async {
    var bandsCreated = 0;
    var bandsExisting = 0;
    var typesCreated = 0;
    var typesSkipped = 0;
    var failed = 0;
    final errors = <String>[];

    final total = previousPriceBands.length;
    var done = 0;

    for (final band in previousPriceBands) {
      try {
        // البحث عن البند بالاسم أو بمفتاح القسم المحفوظ سابقًا.
        DocumentSnapshot<Map<String, dynamic>>? existingDoc;

        final byKey = await _bands
            .where('previousPriceBandKey', isEqualTo: band.key)
            .limit(1)
            .get();
        if (byKey.docs.isNotEmpty) {
          existingDoc = byKey.docs.first;
        } else {
          final byName =
              await _bands.where('name', isEqualTo: band.name).limit(1).get();
          if (byName.docs.isNotEmpty) {
            existingDoc = byName.docs.first;
          }
        }

        DocumentReference<Map<String, dynamic>> bandRef;

        if (existingDoc == null) {
          bandRef = await _bands.add(<String, dynamic>{
            'name': band.name,
            'description': band.description,
            'active': true,
            'previousPriceBandKey': band.key,
            'previousPriceYear': previousPricesYear,
            'previousPriceSource': previousPricesSource,
            'previousPriceTypesCount': band.typesCount,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          bandsCreated++;
        } else {
          bandRef = existingDoc.reference;
          bandsExisting++;
          // إكمال الحقول التعريفية دون المساس بالاسم.
          await bandRef.set(
            <String, dynamic>{
              'previousPriceBandKey': band.key,
              'previousPriceYear': previousPricesYear,
              'previousPriceSource': previousPricesSource,
              'previousPriceTypesCount': band.typesCount,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        // الأنواع الحالية لهذا البند.
        final typesRef = bandRef.collection('types');
        final current = await typesRef.get();

        final existingCodes = <int>{};
        final existingNames = <String>{};
        final docByCode = <int, DocumentReference<Map<String, dynamic>>>{};

        for (final doc in current.docs) {
          final data = doc.data();
          final rawCode = data['code'] ?? data['previousPriceCode'];
          final code = rawCode is num
              ? rawCode.toInt()
              : int.tryParse(rawCode?.toString() ?? '');
          if (code != null) {
            existingCodes.add(code);
            docByCode[code] = doc.reference;
          }
          final name = (data['name'] ?? '').toString().trim();
          if (name.isNotEmpty) existingNames.add(name);
        }

        final batch = _firestore.batch();
        var batchCount = 0;

        for (final type in band.types) {
          if (existingCodes.contains(type.code)) {
            typesSkipped++;
            if (overwritePrices && type.hasPrice) {
              batch.set(
                docByCode[type.code]!,
                <String, dynamic>{
                  'previousPrice': type.price,
                  'previousPriceYear': previousPricesYear,
                  'unit': type.unit,
                  'updatedAt': FieldValue.serverTimestamp(),
                },
                SetOptions(merge: true),
              );
              batchCount++;
            }
            continue;
          }

          if (existingNames.contains(type.name)) {
            typesSkipped++;
            continue;
          }

          final newRef = typesRef.doc();
          batch.set(newRef, <String, dynamic>{
            'name': type.name,
            'code': type.code,
            'previousPriceCode': type.code,
            'unit': type.unit,
            'previousPrice': type.price,
            'previousPriceYear': previousPricesYear,
            'previousPriceSource': previousPricesSource,
            if (!type.hasPrice) 'previousPriceNote': previousPriceMissing,
            'active': true,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          batchCount++;
          typesCreated++;
        }

        if (batchCount > 0) {
          await batch.commit();
        }
      } catch (e) {
        failed++;
        errors.add('${band.name}: $e');
      }

      done++;
      onProgress?.call(done, total);
    }

    return PreviousPricesImportResult(
      bandsCreated: bandsCreated,
      bandsExisting: bandsExisting,
      typesCreated: typesCreated,
      typesSkipped: typesSkipped,
      failed: failed,
      errors: errors,
    );
  }
}

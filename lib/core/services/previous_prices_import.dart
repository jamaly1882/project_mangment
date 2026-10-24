import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/previous_prices.dart';

// ============================================================
// استيراد أسعار 1447هـ إلى البنود والأنواع (مع الترميز الهرمي)
// ============================================================
//
// يقرأ القائمة الثابتة [previousPriceBands] ويكتبها في:
//   item_definitions/{band}            → بند لكل قسم أعمال  (code = rd_01 …)
//   item_definitions/{band}/types/{id} → نوع لكل سطر مسعّر (code = rd_0101 …)
//
// قواعد الأمان:
//   • لا يحذف شيئًا ولا يغيّر الأسماء أو الأسعار المدخلة يدويًا.
//   • لا يكرر: يطابق النوع بالكود الجديد، ثم بالكود القديم، ثم بالاسم.
//   • الأنواع المستوردة سابقًا بأكواد رقمية (1–71) تُعاد ترميزها إلى
//     الصيغة الجديدة (rd_0101 …) مع حفظ الكود القديم في previousPriceCode.
//   • يعمل على دفعات (batch) صغيرة ليظل التقدم ظاهرًا.
// ============================================================

/// نتيجة عملية استيراد واحدة.
class PreviousPricesImportResult {
  const PreviousPricesImportResult({
    this.bandsCreated = 0,
    this.bandsExisting = 0,
    this.typesCreated = 0,
    this.typesSkipped = 0,
    this.typesRenumbered = 0,
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

  /// أنواع موجودة أُعيد ترميزها إلى الصيغة الجديدة (rd_0101).
  final int typesRenumbered;

  /// عمليات فشلت.
  final int failed;

  /// رسائل الأخطاء المختصرة.
  final List<String> errors;

  bool get hasChanges =>
      bandsCreated > 0 || typesCreated > 0 || typesRenumbered > 0;

  String get summary {
    final lines = <String>[
      'البنود: ${bandsCreated + bandsExisting} '
          '(جديد $bandsCreated، موجود $bandsExisting)',
      'الأنواع: ${typesCreated + typesSkipped} '
          '(جديد $typesCreated، موجود $typesSkipped)',
      if (typesRenumbered > 0) 'أُعيد ترميزه: $typesRenumbered',
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

  /// هل الكود نصي بالصيغة الهرمية (rd_0101) وليس رقمًا قديمًا؟
  static bool isHierarchicalCode(Object? value) {
    final text = value?.toString().trim() ?? '';
    return RegExp(r'^[a-z]{2}_\d{2,}$').hasMatch(text);
  }

  /// يستورد أقسام الأعمال وأنواعها ويكمل الترميز الهرمي.
  ///
  /// [onProgress] يُستدعى بعد كل قسم: (المنجز، الإجمالي).
  static Future<PreviousPricesImportResult> import({
    void Function(int done, int total)? onProgress,
  }) async {
    var bandsCreated = 0;
    var bandsExisting = 0;
    var typesCreated = 0;
    var typesSkipped = 0;
    var typesRenumbered = 0;
    var failed = 0;
    final errors = <String>[];

    final total = previousPriceBands.length;
    var done = 0;

    for (final band in previousPriceBands) {
      try {
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
          } else {
            final byCode =
                await _bands.where('code', isEqualTo: band.code).limit(1).get();
            if (byCode.docs.isNotEmpty) {
              existingDoc = byCode.docs.first;
            }
          }
        }

        DocumentReference<Map<String, dynamic>> bandRef;

        if (existingDoc == null) {
          bandRef = await _bands.add(<String, dynamic>{
            'name': band.name,
            'code': band.code,
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

          // إكمال الحقول التعريفية وكود البند دون المساس بالاسم.
          await bandRef.set(
            <String, dynamic>{
              'code': band.code,
              'previousPriceBandKey': band.key,
              'previousPriceYear': previousPricesYear,
              'previousPriceSource': previousPricesSource,
              'previousPriceTypesCount': band.typesCount,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        final typesRef = bandRef.collection('types');
        final current = await typesRef.get();

        // فهرسة الموجود: بالكود النصي، بالكود القديم، وبالاسم.
        final byCode = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        final byLegacyCode =
            <int, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        final byName = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

        for (final doc in current.docs) {
          final data = doc.data();
          final code = (data['code'] ?? '').toString().trim();
          if (code.isNotEmpty) byCode[code] = doc;

          final legacy = data['previousPriceCode'];
          final legacyInt = legacy is num
              ? legacy.toInt()
              : int.tryParse(legacy?.toString() ?? '');
          if (legacyInt != null) byLegacyCode[legacyInt] = doc;

          // كود رقمي محفوظ في code من نسخة سابقة (قبل الترميز).
          final numericCode = int.tryParse(code);
          if (numericCode != null) byLegacyCode[numericCode] = doc;

          final name = (data['name'] ?? '').toString().trim();
          if (name.isNotEmpty) byName[name] = doc;
        }

        final batch = _firestore.batch();
        var batchCount = 0;

        for (var index = 0; index < band.types.length; index++) {
          final type = band.types[index];
          final newCode = band.typeCodeAt(index);

          final existing = byCode[newCode] ??
              byLegacyCode[type.code] ??
              byName[type.name];

          if (existing == null) {
            final ref = typesRef.doc();
            batch.set(ref, <String, dynamic>{
              'name': type.name,
              'code': newCode,
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
            continue;
          }

          // موجود: نكمل الترميز فقط إن كان قديمًا أو ناقصًا.
          final currentCode = (existing.data()['code'] ?? '').toString().trim();

          if (!isHierarchicalCode(currentCode)) {
            // لا نلمس سعرًا عدّله المستخدم؛ نكمله فقط إن كان ناقصًا.
            final hasPrice = existing.data()['previousPrice'] is num;

            batch.set(
              existing.reference,
              <String, dynamic>{
                'code': newCode,
                'previousPriceCode': type.code,
                if (!hasPrice && type.hasPrice) 'previousPrice': type.price,
                'previousPriceYear': previousPricesYear,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
            batchCount++;
            typesRenumbered++;
          } else {
            typesSkipped++;
          }
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
      typesRenumbered: typesRenumbered,
      failed: failed,
      errors: errors,
    );
  }
}

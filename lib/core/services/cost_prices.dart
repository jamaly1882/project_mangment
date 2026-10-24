import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/cost_lines.dart';
import '../utils/costs.dart';

/// ============================================================
/// أسعار التكاليف: صلاحية مدير إدارة الجودة.
/// ============================================================
///
/// مدير الجودة يحدّد سعر كل سطر داخل البند (مادة / مهنة / معدة / وقود)،
/// والسعر الجديد يحلّ محل القديم في مخطط البند وفعليه معًا، ثم تُعاد
/// حساب مجاميع الأقسام وتكلفة البند وتكاليف المشروع.
///
/// صفحة المشرف لا تعرض الأسعار؛ يبقى السعر محفوظًا ويُستخدم في حساب
/// التكلفة فقط.
///
/// قاعدة التوزيع المعتمدة (من جدول تحليل الأسعار):
///   • المهنة + المصاريف            → العمالة
///   • المعدة + الإهلاك             → المعدات
///   • بترول/ديزل/غاز/قاز/زيت       → المحروقات
///   • بقية المواد وأسعارها         → المواد
///
/// التنبيه المهم: القسم يُستنتج من اسم السطر لا من العمود الذي ورد فيه؛
/// لذلك «ماء زجاجة» و«حجر جدران» و«رصيف 25 سم» الواردة في عمود
/// المحروقات تُضاف إلى المواد.
class CostPrices {
  CostPrices._();

  /// مجموعة سجل تعديلات الأسعار.
  static const String logCollection = 'quality_price_updates';

  /// حقل مفتاح السعر في كل قسم.
  static String priceKeyOf(CostLineKind kind) =>
      CostLineSchema.of(kind).priceKey;

  /// اسم السعر كما يظهر في الواجهة.
  static String priceLabelOf(CostLineKind kind) {
    switch (kind) {
      case CostLineKind.material:
        return 'سعر الوحدة';
      case CostLineKind.labor:
        return 'الأجرة / المصاريف';
      case CostLineKind.equipment:
        return 'إهلاك الوحدة';
      case CostLineKind.fuel:
        return 'سعر اللتر';
    }
  }

  // ============================================================
  // التصنيف
  // ============================================================

  static const List<String> _fuelWords = <String>[
    'بترول', 'بنزين', 'ديزل', 'غاز', 'قاز', 'كاز', 'زيت', 'وقود',
    'محروقات', 'سولار', 'مازوت',
  ];

  static const List<String> _laborWords = <String>[
    'سائق', 'مشرف', 'مساعد', 'مهنة', 'مهنه', 'عامل', 'عمال', 'فني',
    'مشغل', 'مراقب', 'غرابيل', 'مفرزة', 'نجارة', 'حداد', 'ميكانيكي',
    'كهربائي', 'سباك', 'بناء', 'حارس', 'عامل يومية',
  ];

  static const List<String> _equipmentWords = <String>[
    'حفار', 'قلاب', 'شيول', 'بوكات', 'بوكالن', 'دكاك', 'كمبريش',
    'دينا', 'جريدر', 'لوري', 'قاطر', 'قاطرة', 'بلدوزر', 'رافعة',
    'ونش', 'هزاز', 'خلاطة', 'سيارة', 'معدة', 'معده', 'مضخة',
  ];

  static const List<String> _materialWords = <String>[
    'ماء', 'مياه', 'حجر', 'رصيف', 'حديد', 'اسمنت', 'أسمنت', 'رمل',
    'بحص', 'خشب', 'بلوك', 'طوب', 'صلب', 'استنكية', 'إستنكية',
    'قلعقة', 'دهان', 'مسامير', 'انابيب', 'أنابيب', 'مواسير', 'كيبل',
    'اسلاك', 'أسلاك', 'خرطوم', 'طين', 'تراب', 'حصى', 'زجاجة',
  ];

  /// تصنيف سطر تحليل إلى قسم تكلفة، بالاعتماد على كلماته.
  static CostLineKind classify(String label) {
    final text = _normalize(label);
    if (text.isEmpty) return CostLineKind.material;

    // الأولوية: وقود ← عمالة ← معدات ← مواد.
    if (_containsAny(text, _fuelWords)) return CostLineKind.fuel;
    if (_containsAny(text, _laborWords)) return CostLineKind.labor;
    if (_containsAny(text, _equipmentWords)) return CostLineKind.equipment;
    if (_containsAny(text, _materialWords)) return CostLineKind.material;

    return CostLineKind.material;
  }

  static bool _containsAny(String text, List<String> words) {
    for (final word in words) {
      if (text.contains(_normalize(word))) return true;
    }
    return false;
  }

  /// تطبيع النص العربي: إزالة التشكيل وتوحيد الألف والهمزة والياء.
  static String _normalize(String value) {
    var text = value.toLowerCase();

    const diacritics = <String>[
      '\u064B', '\u064C', '\u064D', '\u064E', '\u064F', '\u0650',
      '\u0651', '\u0652', '\u0653', '\u0654', '\u0655', '\u0640',
    ];

    for (final mark in diacritics) {
      text = text.replaceAll(mark, '');
    }

    text = text
        .replaceAll(RegExp('[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي');

    return text.trim();
  }

  // ============================================================
  // قراءة جدول التحليل (لصق من PDF)
  // ============================================================

  /// سطر تحليل مقروء من جدول الأسعار قبل التطبيق.
  static List<PriceEntry> parseTable(String rawText) {
    final entries = <PriceEntry>[];

    for (final rawLine in rawText.split(RegExp(r'[\r\n]+'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final cells = _splitCells(line);
      if (cells.isEmpty) continue;

      if (cells.length >= 6) {
        // الترتيب في جدول التحليل:
        // المهنة | المصاريف | المعدة | الإهلاك | المحروقات/المادة | السعر
        // القسم هنا يُؤخذ من العمود نفسه، لا من الكلمات:
        //   • العمود الأول مهنة  → العمالة
        //   • العمود الثالث معدة → المعدات
        //   • العمود الخامس: الوقود فقط (ديزل/بترول/غاز/قاز/زيت) محروقات،
        //     وكل ما سواه (ماء، حجر، رصيف، حديد، أسمنت…) مواد.
        _addPair(entries, cells[0], cells[1], force: CostLineKind.labor);
        _addPair(entries, cells[2], cells[3], force: CostLineKind.equipment);
        _addPair(entries, cells[4], cells[5], fuelOrMaterial: true);
        continue;
      }

      if (cells.length >= 4) {
        _addPair(entries, cells[0], cells[1]);
        _addPair(entries, cells[2], cells[3]);
        continue;
      }

      if (cells.length == 2) {
        _addPair(entries, cells[0], cells[1]);
        continue;
      }

      // سطر بلا فواصل: نحاول التقاط «اسم … رقم» في آخره.
      final match = RegExp(r'^(.+?)\s+([\d٠-٩][\d٠-٩.,٫]*)$').firstMatch(line);
      if (match != null) {
        _addPair(entries, match.group(1) ?? '', match.group(2) ?? '');
      }
    }

    return entries;
  }

  static List<String> _splitCells(String line) {
    if (line.contains('\t')) {
      return line
          .split('\t')
          .map((cell) => cell.trim())
          .where((cell) => cell.isNotEmpty)
          .toList();
    }

    if (line.contains('|')) {
      return line
          .split('|')
          .map((cell) => cell.trim())
          .where((cell) => cell.isNotEmpty)
          .toList();
    }

    final parts = line
        .split(RegExp(r'\s{2,}'))
        .map((cell) => cell.trim())
        .where((cell) => cell.isNotEmpty)
        .toList();

    if (parts.length > 1) return parts;

    return <String>[line];
  }

  static void _addPair(
    List<PriceEntry> entries,
    String name,
    String price, {
    CostLineKind? force,
    bool fuelOrMaterial = false,
  }) {
    final label = name.trim();
    if (label.isEmpty) return;

    // عناوين الأعمدة أو خلايا غير صالحة.
    if (_isHeader(label)) return;

    final value = parsePrice(price);
    if (value == null) return;

    final CostLineKind kind = force ??
        (fuelOrMaterial
            ? (isFuel(label) ? CostLineKind.fuel : CostLineKind.material)
            : classify(label));

    entries.add(
      PriceEntry(
        label: label,
        kind: kind,
        price: value,
      ),
    );
  }

  /// هل الاسم وقود؟ (ديزل / بترول / غاز / قاز / زيت)
  ///
  /// هذا هو الفاصل الوحيد داخل عمود «بيان المحروقات»: ما سواه مواد.
  static bool isFuel(String label) =>
      _containsAny(_normalize(label), _fuelWords);

  static bool _isHeader(String label) {
    final text = _normalize(label);
    return text == 'المهنه' ||
        text == 'بيان' ||
        text == 'البيان' ||
        text == 'المبلغ' ||
        text == 'السعر' ||
        text == 'سعر اللتر' ||
        text == 'سعر الوحده';
  }

  /// قراءة رقم مالي عربي أو لاتيني؛ `#REF!` و«البريموث» تعيد null.
  static double? parsePrice(String value) {
    var text = value.trim();
    if (text.isEmpty) return null;

    const arabicDigits = <String>[
      '٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩',
    ];

    for (var i = 0; i < arabicDigits.length; i++) {
      text = text.replaceAll(arabicDigits[i], i.toString());
    }

    text = text
        .replaceAll('٫', '.')
        .replaceAll('٬', '')
        .replaceAll(',', '')
        .replaceAll(' ', '');

    // خلايا الخطأ في Excel أو نصوص غير رقمية.
    if (!RegExp(r'^[+-]?\d+(\.\d+)?$').hasMatch(text)) return null;

    final parsed = double.tryParse(text);
    if (parsed == null || parsed < 0) return null;

    return parsed;
  }

  // ============================================================
  // تطبيق الأسعار على أسطر البند
  // ============================================================

  /// يضبط السعر في السطر ويعيد حالة «هل تغيّر شيء».
  ///
  /// يمسح تثبيت التكلفة اليدوي حتى يُعاد حسابها بالسعر الجديد.
  static bool applyPriceToLine(
    CostLineSchema schema,
    Map<String, dynamic> line,
    double price,
  ) {
    final key = priceKeyOf(schema.kind);
    final current = CostLineSchema.number(line, key);

    if ((current - price).abs() < 0.0001) return false;

    line[key] = price;
    line[CostLineSchema.manualKey] = false;
    line[CostLineSchema.costKey] = schema.computedCost(line);

    return true;
  }

  /// سطر جديد من مخطط التحليل: السعر فقط، والكمية صفر، والتكلفة صفر.
  /// يدخل المشرف الكميات لاحقًا من صفحة البند.
  static Map<String, dynamic> newLine(CostLineKind kind, PriceEntry entry) {
    switch (kind) {
      case CostLineKind.material:
        return <String, dynamic>{
          'materialName': entry.label,
          // الوحدة مطلوبة في السطر: نأخذ أول وحدة مناسبة لاسم المادة.
          'unit': MaterialUnits.forName(entry.label).first,
          'unitPrice': entry.price,
          'quantity': 0,
          CostLineSchema.excludedKey: false,
        };
      case CostLineKind.labor:
        // العدد ١ بلا مدة: يظهر السطر بالسعر، وتكلفته صفر حتى يدخل
        // المشرف المدة (أو العدد) الفعلية.
        return <String, dynamic>{
          'job': entry.label,
          'wageBasis': 'للوحدة',
          'count': 1,
          'wage': entry.price,
          'duration': 0,
          CostLineSchema.excludedKey: false,
        };
      case CostLineKind.equipment:
        return <String, dynamic>{
          'equipmentType': entry.label,
          'count': 1,
          'unit': 'ساعة',
          'unitPrice': entry.price,
          'quantity': 0,
          CostLineSchema.excludedKey: false,
        };
      case CostLineKind.fuel:
        return <String, dynamic>{
          'fuelType': entry.label,
          'quantity': 0,
          'unit': 'لتر',
          'pricePerLiter': entry.price,
          CostLineSchema.excludedKey: false,
        };
    }
  }

  /// هل يطابق السطر اسم سطر التحليل؟
  static bool matches(String lineLabel, String entryLabel) {
    final line = _normalize(lineLabel);
    final entry = _normalize(entryLabel);

    if (line.isEmpty || entry.isEmpty) return false;
    if (line == entry) return true;

    return line.contains(entry) || entry.contains(line);
  }

  // ============================================================
  // حفظ أسعار البند
  // ============================================================

  /// يحفظ الأسعار الجديدة على مخطط البند وفعليه، ثم يعيد حساب المجاميع.
  ///
  /// [planned] و[actual] هي الأسطر بعد تعديل الأسعار.
  /// [changes] تُسجَّل في مجموعة `quality_price_updates` للتوثيق.
  static Future<void> save({
    required String itemId,
    required String projectId,
    required CostLines planned,
    required CostLines actual,
    required List<PriceChange> changes,
    required String userId,
    String itemName = '',
    double contractQuantity = 0,
  }) async {
    final firestore = FirebaseFirestore.instance;

    final itemRef = firestore.collection('items').doc(itemId);
    final detailsRef = firestore.collection('item_details').doc(itemId);

    final itemDoc = await itemRef.get();
    if (!itemDoc.exists) {
      throw Exception('البند غير موجود.');
    }

    final item = itemDoc.data() ?? <String, dynamic>{};

    // الكمية المحسوب عليها الإجمالي: المنفذة إن وُجدت، وإلا التعاقدية.
    final executed = ProjectCosts.nonNegative(item['executedQuantity']);
    final quantity = executed > 0
        ? executed
        : (contractQuantity > 0
            ? contractQuantity
            : ProjectCosts.nonNegative(item['contractQuantity']));

    final plannedData = planned.toSaveData(
      contractQuantity: quantity,
    );
    final actualData = actual.toSaveData(
      actual: true,
      contractQuantity: quantity,
    );

    final stamp = <String, dynamic>{
      'priceUpdatedBy': userId,
      'priceUpdatedAt': FieldValue.serverTimestamp(),
      'priceUpdatedCount': changes.length,
      'priceUpdatedItemName': itemName,
    };

    final batch = firestore.batch();

    batch.set(
      itemRef,
      <String, dynamic>{
        ...plannedData,
        ...actualData,
        ...stamp,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    batch.set(
      detailsRef,
      <String, dynamic>{
        ...plannedData,
        ...actualData,
        ...stamp,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    for (final change in changes.take(200)) {
      batch.set(
        firestore.collection(logCollection).doc(),
        <String, dynamic>{
          'itemId': itemId,
          'projectId': projectId,
          'itemName': itemName,
          'kind': change.kind.name,
          'label': change.label,
          'oldPrice': change.oldPrice,
          'newPrice': change.newPrice,
          'updatedBy': userId,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
    }

    await batch.commit();
  }

  /// قراءة السعر الحالي لسطر.
  static double priceOf(CostLineKind kind, Map<String, dynamic> line) =>
      CostLineSchema.number(line, priceKeyOf(kind));

  // ============================================================
  // استيراد أسعار على مستوى المشروع
  // ============================================================

  /// يطبّق جدول أسعار واحدًا على **كل بنود المشروع**.
  ///
  /// يبحث عن كل سطر تحليل في أسطر البنود (المخطط والفعلي) بمطابقة الاسم،
  /// ويستبدل سعره. الأسطر التي لا مثيل لها تُرجَع في [unmatched] ليُضيفها
  /// المدير يدويًا في بندها، لأن الجدول لا يحدد البند الذي تنتمي إليه.
  static Future<ProjectPriceResult> applyToProject({
    required String projectId,
    required List<PriceEntry> entries,
    required String userId,
    String projectName = '',
  }) async {
    final firestore = FirebaseFirestore.instance;

    final itemsSnapshot = await firestore
        .collection('items')
        .where('projectId', isEqualTo: projectId)
        .get();

    if (itemsSnapshot.docs.isEmpty) {
      throw Exception('لا توجد بنود في هذا المشروع بعد.');
    }

    final batch = firestore.batch();
    final matchedLabels = <String>{};
    final logs = <Map<String, dynamic>>[];

    var updatedLines = 0;
    var itemsTouched = 0;

    for (final doc in itemsSnapshot.docs) {
      final item = doc.data();

      final detailsDoc = await firestore
          .collection('item_details')
          .doc(doc.id)
          .get();
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

      var itemUpdated = false;

      for (final entry in entries) {
        final schema = CostLineSchema.of(entry.kind);

        for (final target in <CostLines>[planned, actual]) {
          for (final line in target[entry.kind]) {
            final label = CostLineSchema.text(line, schema.titleKey);

            if (!matches(label, entry.label)) continue;

            matchedLabels.add(entry.label);

            final oldPrice = priceOf(entry.kind, line);

            if (!applyPriceToLine(schema, line, entry.price)) continue;

            updatedLines++;
            itemUpdated = true;

            if (logs.length < 120) {
              logs.add(<String, dynamic>{
                'itemId': doc.id,
                'projectId': projectId,
                'itemName': (item['name'] ?? '').toString(),
                'kind': entry.kind.name,
                'label': label,
                'oldPrice': oldPrice,
                'newPrice': entry.price,
                'updatedBy': userId,
                'createdAt': FieldValue.serverTimestamp(),
              });
            }
          }
        }
      }

      if (!itemUpdated) continue;

      itemsTouched++;

      final stamp = <String, dynamic>{
        'priceUpdatedBy': userId,
        'priceUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final plannedData = planned.toSaveData(contractQuantity: quantity);
      final actualData = actual.toSaveData(
        actual: true,
        contractQuantity: quantity,
      );

      batch.set(
        doc.reference,
        <String, dynamic>{...plannedData, ...actualData, ...stamp},
        SetOptions(merge: true),
      );

      batch.set(
        firestore.collection('item_details').doc(doc.id),
        <String, dynamic>{...plannedData, ...actualData, ...stamp},
        SetOptions(merge: true),
      );
    }

    for (final log in logs) {
      batch.set(firestore.collection(logCollection).doc(), <String, dynamic>{
        ...log,
        if (projectName.isNotEmpty) 'projectName': projectName,
      });
    }

    if (itemsTouched > 0) await batch.commit();

    final unmatched = <String>[
      for (final entry in entries)
        if (!matchedLabels.contains(entry.label)) entry.label,
    ];

    return ProjectPriceResult(
      updatedLines: updatedLines,
      itemsTouched: itemsTouched,
      totalItems: itemsSnapshot.docs.length,
      unmatched: unmatched,
    );
  }
}

/// سطر مقروء من جدول التحليل مع القسم المستنتج.
class PriceEntry {
  PriceEntry({
    required this.label,
    required this.kind,
    required this.price,
  });

  final String label;
  CostLineKind kind;
  double price;
}

/// تغيير سعر سطر واحد (للتوثيق).
class PriceChange {
  const PriceChange({
    required this.kind,
    required this.label,
    required this.oldPrice,
    required this.newPrice,
  });

  final CostLineKind kind;
  final String label;
  final double oldPrice;
  final double newPrice;
}

/// نتيجة استيراد أسعار على مستوى المشروع.
class ProjectPriceResult {
  const ProjectPriceResult({
    required this.updatedLines,
    required this.itemsTouched,
    required this.totalItems,
    required this.unmatched,
  });

  final int updatedLines;
  final int itemsTouched;
  final int totalItems;

  /// أسطر التحليل التي لم يُعثر لها على بند مطابق في المشروع.
  final List<String> unmatched;
}

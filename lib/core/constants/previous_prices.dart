import 'package:flutter/material.dart';

// ============================================================
// أسعار سابقة — خلاصة أسعار بنود أعمال مشاريع الطرق 1447هـ
// ============================================================
//
// المصدر: «خلاصة أسعار بنود أعمال مشاريع الطرق لمكتب النقل
// والأشغال العامة م/ صنعاء لعام 1447هـ» — صفحات 121 إلى 125
// من ملف: الانتاجية اليومية والانتاجية لكل وحدة عمل - الاحتياطية.
//
// التقسيم المتفق عليه:
//   • البند (item_definitions) = قسم الأعمال (ترابية / إسفلتية / إنشائية)
//   • النوع (item_definitions/{band}/types) = سطر مرقّم بسعره ووحدته
//
// كل نوع يحمل:
//   code            كود البند في خلاصة 1447هـ
//   unit            الوحدة (م3 / م2 / م.ط / طن / عدد / كم / م3*كم / طن*كم)
//   previousPrice   سعر الوحدة لعام 1447هـ (ريال) — «سعر سابق»
//   priceNote       ملاحظة إن كان السعر غير محدد في الملف (#REF!)
//
// هذه القائمة مرجع للعرض وللاستيراد من صفحة البنود، ولا تُقرأ
// تلقائيًا من Firestore؛ الاستيراد يكتبها في قاعدة البيانات مرة واحدة.
// ============================================================

/// سنة الأسعار السابقة المرجعية.
const String previousPricesYear = '1447هـ';

/// وصف المصدر كما هو في الملف.
const String previousPricesSource =
    'خلاصة أسعار بنود أعمال مشاريع الطرق — مكتب النقل والأشغال العامة م/ صنعاء لعام 1447هـ';

/// ملاحظة السعر المفقود في الملف.
const String previousPriceMissing = 'غير محدد في الملف (خطأ #REF!)';

/// الوحدات المستخدمة في خلاصة أسعار 1447هـ، تصلح لقائمة الوحدة
/// في أنواع البنود.
const List<String> previousTypeUnits = <String>[
  'م3',
  'م2',
  'م.ط',
  'طن',
  'عدد',
  'كم',
  'م3*كم',
  'طن*كم',
];

/// نوع بند واحد من خلاصة أسعار 1447هـ.
class PreviousPriceType {
  const PreviousPriceType({
    required this.code,
    required this.name,
    required this.unit,
    this.price,
  });

  /// كود البند في الخلاصة (1 … 71).
  final int code;

  /// وصف النوع.
  final String name;

  /// وحدة القياس كما وردت في الملف.
  final String unit;

  /// سعر الوحدة لعام 1447هـ، أو null إن كان التسعير مفقودًا في الملف.
  final double? price;

  bool get hasPrice => price != null && price! > 0;

  /// اسم يصلح لعرضه داخل التطبيق (الكود + أول جزء من الوصف).
  String get displayName => 'بند $code — $name';

  /// ملاحظة السعر إن كان مفقودًا.
  String? get priceNote => hasPrice ? null : previousPriceMissing;

  /// الوحدة بصيغة التطبيق (قائمة وحدات البند).
  String get appUnit {
    switch (unit) {
      // «عدد» هو اسم الوحدة في قائمة الأسعار، ويقابله «قطعة» في التطبيق.
      case 'عدد':
        return 'قطعة';
      // م3، م2، م.ط، طن، كم، م3*كم، طن*كم تُستخدم كما هي.
      default:
        return unit;
    }
  }
}

/// قسم أعمال واحد يحتوي أنواع بنوده المسعّرة.
class PreviousPriceBand {
  const PreviousPriceBand({
    required this.key,
    required this.name,
    required this.description,
    required this.icon,
    required this.types,
  });

  /// معرّف ثابت يُخزَّن في وثيقة البند باسم previousPriceBandKey.
  final String key;

  /// اسم القسم، ويُكتب كاسم البند في item_definitions عند الاستيراد.
  final String name;

  final String description;

  final IconData icon;

  final List<PreviousPriceType> types;

  int get typesCount => types.length;

  int get pricedTypesCount => types.where((type) => type.hasPrice).length;

  /// أقل وأعلى سعر في القسم (للعرض المختصر).
  (double, double)? get priceRange {
    final prices = types
        .where((type) => type.hasPrice)
        .map((type) => type.price!)
        .toList()
      ..sort();

    if (prices.isEmpty) return null;

    return (prices.first, prices.last);
  }
}

/// أقسام خلاصة أسعار 1447هـ.
const List<PreviousPriceBand> previousPriceBands = <PreviousPriceBand>[
  PreviousPriceBand(
    key: 'terrain',
    name: 'الأعمال الترابية',
    description: 'أعمال القطع والردم والمسح وتسوية الشوارع والبردورات',
    icon: Icons.landscape_outlined,
    types: <PreviousPriceType>[
      PreviousPriceType(
        code: 1,
        name: 'القطع العادي المستفاد منه شاملًا الاستفادة من ناتج القطع في الردم والتسوية على طبقات',
        unit: 'م3',
        price: 1235,
      ),
      PreviousPriceType(
        code: 2,
        name: 'القطع العادي المستفاد منه شاملًا الاستفادة من ناتج القطع في الردم على طبقات كل طبقة بسماكة 20 سم مع الرش والدك',
        unit: 'م3',
        price: 2125,
      ),
      PreviousPriceType(
        code: 3,
        name: 'القطع العادي غير المستفاد منه شاملًا (الترحيل الجانبي للطرق الخارجية) أو (تكويم القطعيات للطرق الداخلية)',
        unit: 'م3',
        price: 1000,
      ),
      PreviousPriceType(
        code: 4,
        name: 'القطع العادي غير المستفاد منه شاملًا ترحيل ناتج القطع (للطرق الداخلية)',
        unit: 'م3',
        price: 850,
      ),
      PreviousPriceType(
        code: 5,
        name: 'القطع الصخري بالدقاق شاملًا (الاستفادة من الصخور لجوانب الطرق الخارجية) أو (تكويم الصخور في الطرق الداخلية)',
        unit: 'م3',
        price: 5045,
      ),
      PreviousPriceType(
        code: 6,
        name: 'قطع غير مصنف في جميع أنواع التربة والصخور شاملًا الاستفادة من ناتج القطع في الردم وكذلك ترحيل المواد غير الصالحة للردم باستخدام الغرافة',
        unit: 'م3',
        price: 3500,
      ),
      PreviousPriceType(
        code: 7,
        name: 'قطع غير مصنف في جميع أنواع التربة والصخور شاملًا الاستفادة من ناتج القطع في الردم مع الرش والدك على طبقات',
        unit: 'م3',
        price: 4250,
      ),
      PreviousPriceType(
        code: 8,
        name: 'ترحيل المخلفات إلى مكان مناسب لمسافة أكبر من 6 كم',
        unit: 'م3',
        price: 2000,
      ),
      PreviousPriceType(
        code: 9,
        name: 'ترحيل المخلفات إلى مكان مناسب لمسافة لا تتجاوز 6 كم',
        unit: 'م3',
        price: 1160,
      ),
      PreviousPriceType(
        code: 10,
        name: 'أعمال فتح ومسح وتسوية الشوارع الداخلية (الترابية) شامل تنفيذ مصارف جانبية وميول جانبية ومطبات ترابية',
        unit: 'م2',
        price: 75,
      ),
      PreviousPriceType(
        code: 11,
        name: 'أعمال فتح ومسح وتسوية الشوارع الداخلية (الصخرية) شامل تنفيذ مصارف جانبية وميول جانبية ومطبات ترابية',
        unit: 'م2',
        price: 120,
      ),
      PreviousPriceType(
        code: 12,
        name: 'أعمال المسح والتسوية للطرق الخارجية (الترابية) شاملًا فتح المصارف الجانبية وتنفيذ الميول الجانبية',
        unit: 'م2',
        price: null,
      ),
      PreviousPriceType(
        code: 13,
        name: 'أعمال المسح والتسوية للطرق الترابية شاملًا فتح المصارف الجانبية وقطع وردم في جسم الطريق بسماكة لا تقل عن 20 سم',
        unit: 'كم',
        price: 440000,
      ),
      PreviousPriceType(
        code: 14,
        name: 'أعمال تسوية سرير الطريق في أماكن القطع شامل الرش والدك',
        unit: 'م2',
        price: 220,
      ),
      PreviousPriceType(
        code: 15,
        name: 'ردم مواد مستعارة مناسبة (G.S) على طبقات سماكة كل طبقة 20 سم مع الرش والدك حتى نسبة دك لا تقل عن 95%',
        unit: 'م3',
        price: 2780,
      ),
      PreviousPriceType(
        code: 16,
        name: 'توريد وفرش طبقة الأساس المساعد مواد طبيعية شامل الرش والدك ونسبة دك لا تقل عن 97%',
        unit: 'م2',
        price: 4840,
      ),
      PreviousPriceType(
        code: 17,
        name: 'توريد وتركيب بردورات خرسانية مقاس (60×15×25) سم شامل الحفر وتنفيذ خرسانة عادية تحت البردورات',
        unit: 'م.ط',
        price: 5000,
      ),
      PreviousPriceType(
        code: 18,
        name: 'توريد وتركيب بردورات خرسانية مقاس (60×15×35) سم شامل الحفر وتنفيذ خرسانة عادية تحت البردورات',
        unit: 'م.ط',
        price: 6250,
      ),
      PreviousPriceType(
        code: 19,
        name: 'أجور نقل مواد الأساس والأساس المساعد والردميات',
        unit: 'م3*كم',
        price: 205,
      ),
    ],
  ),
  PreviousPriceBand(
    key: 'asphalt',
    name: 'الأعمال الإسفلتية',
    description: 'القص والقشط والخلطات الإسفلتية والمعالجة والترميم واللوحات التعريفية',
    icon: Icons.route_outlined,
    types: <PreviousPriceType>[
      PreviousPriceType(
        code: 20,
        name: 'أعمال قص وقطع طبقة الأسفلت القديم مع النقل والترحيل',
        unit: 'م2',
        price: 330,
      ),
      PreviousPriceType(
        code: 21,
        name: 'أعمال قص وقطع طبقة الأسفلت القديم غير شامل النقل والترحيل',
        unit: 'م2',
        price: null,
      ),
      PreviousPriceType(
        code: 22,
        name: 'تجهيز وفرش طبقة الأساس (B.C) مواد طبيعية شاملًا الرش والدك ونسبة دك لا تقل عن 98%',
        unit: 'م3',
        price: 5050,
      ),
      PreviousPriceType(
        code: 23,
        name: 'تجهيز وفرش طبقة الأساس (B.C) مكسر آليًا شاملًا الرش والدك ونسبة دك لا تقل عن 98%',
        unit: 'م3',
        price: 9340,
      ),
      PreviousPriceType(
        code: 24,
        name: 'أعمال قشط الطبقة الإسفلتية سماكة لا تزيد عن 10 سم شامل نقل وترحيل المخلفات',
        unit: 'م2',
        price: 1160,
      ),
      PreviousPriceType(
        code: 25,
        name: 'أعمال قشط الطبقة الإسفلتية سماكة (10 - 15) سم شاملًا نقل وترحيل المخلفات',
        unit: 'م2',
        price: 1450,
      ),
      PreviousPriceType(
        code: 26,
        name: 'أعمال رش الطبقة اللاصقة R.C بعد تنظيف السطح الإسفلتي',
        unit: 'م2',
        price: 250,
      ),
      PreviousPriceType(
        code: 27,
        name: 'أعمال رش طبقة التشرب البيتومينية M.C',
        unit: 'م2',
        price: 630,
      ),
      PreviousPriceType(
        code: 28,
        name: 'إنتاج خلطة إسفلتية ساخنة خشنة',
        unit: 'طن',
        price: 48650,
      ),
      PreviousPriceType(
        code: 29,
        name: 'إنتاج خلطة إسفلتية ساخنة ناعمة',
        unit: 'طن',
        price: 51850,
      ),
      PreviousPriceType(
        code: 30,
        name: 'إنتاج خلطة إسفلتية رملية ساخنة',
        unit: 'طن',
        price: 60700,
      ),
      PreviousPriceType(
        code: 31,
        name: 'أجور نقل الخلطة الإسفلتية',
        unit: 'طن*كم',
        price: 100,
      ),
      PreviousPriceType(
        code: 32,
        name: 'أعمال الفرش والدك لطبقة الإسفلت الساخنة الخشنة سماكة من 4 إلى 6 سم باستخدام الفرادة',
        unit: 'م3',
        price: 12300,
      ),
      PreviousPriceType(
        code: 33,
        name: 'أعمال الفرش والدك لطبقة الإسفلت الساخنة الناعمة سماكة من 1.5 إلى 3 سم باستخدام الفرادة',
        unit: 'م3',
        price: 13000,
      ),
      PreviousPriceType(
        code: 34,
        name: 'أعمال فرش ودك طبقة تسوية إسفلتية بالجريدر بخلطة ناعمة أو رملية بمتوسط سماكة 1.5 سم (السعر لا يشمل الخلطة والنقل)',
        unit: 'طن',
        price: 6650,
      ),
      PreviousPriceType(
        code: 35,
        name: 'المعالجة والترميم للحفر والهبوط والتموج والشقوق الشبكية — للطرق الخارجية (مساحات لا تزيد عن 70 م2)',
        unit: 'م2',
        price: 14500,
      ),
      PreviousPriceType(
        code: 36,
        name: 'المعالجة والترميم للحفر والهبوط والتموج والشقوق الشبكية — للشوارع الداخلية',
        unit: 'م2',
        price: 16000,
      ),
      PreviousPriceType(
        code: 37,
        name: 'المعالجة والترميم للحفر والهبوط والتموج والشقوق الشبكية للمقاطع الكبيرة (إعادة إنشاء)',
        unit: 'م2',
        price: 12050,
      ),
      PreviousPriceType(
        code: 38,
        name: 'المعالجة والترميم للحفر السطحية بدون القاعدة',
        unit: 'م2',
        price: 13050,
      ),
      PreviousPriceType(
        code: 39,
        name: 'حقن وتعبئة الشقوق الطولية والعرضية بالبيتومين السائل المخلوط بالهلسن بعد نفخ وتنظيف الشقوق',
        unit: 'م.ط',
        price: 460,
      ),
      PreviousPriceType(
        code: 40,
        name: 'قلع وحفر البردورات القديمة لأي نوع مع الترحيل',
        unit: 'م.ط',
        price: 1160,
      ),
      PreviousPriceType(
        code: 41,
        name: 'أعمال تكسير الإسفلت القديم وخلطه مع طبقة الأساس القديمة وإعادة فرش الخليط كطبقة أساس مساعد بسماكة لا تقل عن 20 سم',
        unit: 'م2',
        price: 920,
      ),
      PreviousPriceType(
        code: 42,
        name: 'تنفيذ أعمال رفع أو خفض غرف التفتيش للمجاري والمواصلات بحلوق خرسانية',
        unit: 'عدد',
        price: 50200,
      ),
      PreviousPriceType(
        code: 43,
        name: 'توريد وتركيب مواسير بلاستيكية زراعية قطر 12 هنش ضغط عالي شاملًا الحفر',
        unit: 'م.ط',
        price: 31390,
      ),
      PreviousPriceType(
        code: 44,
        name: 'توريد وتركيب مواسير بلاستيكية زراعية قطر 16 هنش ضغط عالي شاملًا الحفر',
        unit: 'م.ط',
        price: 55130,
      ),
      PreviousPriceType(
        code: 45,
        name: 'توريد وتركيب لوحة تعريفية بالمشروع بأبعاد (1×2) موالف من 4 شرائح حديد بوجهين',
        unit: 'عدد',
        price: 272530,
      ),
      PreviousPriceType(
        code: 46,
        name: 'توريد وتركيب لوحة تعريفية بالمشروع وجهين ألومنيوم بعمودين 6 هنش ارتفاع صافي 2 متر',
        unit: 'عدد',
        price: 993510,
      ),
      PreviousPriceType(
        code: 47,
        name: 'توريد وتركيب لوحة تعريفية بالمشروع وجه واحد حديد بعمودين 6 هنش ارتفاع صافي 2 متر',
        unit: 'عدد',
        price: 554570,
      ),
      PreviousPriceType(
        code: 48,
        name: 'توريد وتركيب لوحة تعريفية بالمشروع وجهين حديد بعمودين 6 هنش ارتفاع صافي 2 متر',
        unit: 'عدد',
        price: 762820,
      ),
      PreviousPriceType(
        code: 49,
        name: 'أعمال الردم خلف الجدران',
        unit: 'م3',
        price: 2110,
      ),
      PreviousPriceType(
        code: 50,
        name: 'توريد وتركيب مواسير حديدية زراعية قطر 18 هنش شاملًا الحفر',
        unit: 'م.ط',
        price: 114560,
      ),
      PreviousPriceType(
        code: 51,
        name: 'أعمال توريد وفرش طبقة الهلسن فوق مادة (M.C)',
        unit: 'م2',
        price: 170,
      ),
    ],
  ),
  PreviousPriceBand(
    key: 'structural',
    name: 'الأعمال الإنشائية',
    description: 'الحفر الإنشائي والبناء بالحجر والخرسانة المسلحة وحديد التسليح',
    icon: Icons.foundation_outlined,
    types: <PreviousPriceType>[
      PreviousPriceType(
        code: 52,
        name: 'أعمال الحفر الإنشائي في التربة العادية شامل ردم الجوانب من ناتج الحفر مع الرش والدك والإزاحة الجانبية للمواد الزائدة',
        unit: 'م3',
        price: 2320,
      ),
      PreviousPriceType(
        code: 53,
        name: 'أعمال الحفر الإنشائي الصخري مع الترحيل',
        unit: 'م3',
        price: 4420,
      ),
      PreviousPriceType(
        code: 54,
        name: 'أعمال البناء بالحجر الجعم مع المونة الإسمنتية',
        unit: 'م3',
        price: 26370,
      ),
      PreviousPriceType(
        code: 55,
        name: 'أعمال البناء بالحجر المقلفع للعبارات مع المونة الإسمنتية شاملًا التكحيل (سماكة الجدران لا تزيد عن 80 سم والارتفاع أقل من 2 متر)',
        unit: 'م3',
        price: 44550,
      ),
      PreviousPriceType(
        code: 56,
        name: 'أعمال البناء بالحجر المقلفع للجدران الساندة مع المونة الإسمنتية شاملًا التكحيل',
        unit: 'م3',
        price: 42110,
      ),
      PreviousPriceType(
        code: 57,
        name: 'أعمال البناء بسالل الجابيون بأحجار مربوعة للواجهة وتعبئة باقي السلة بأحجار جيدة',
        unit: 'م3',
        price: 41450,
      ),
      PreviousPriceType(
        code: 58,
        name: 'أعمال البناء بالحجر الجعم المغمور بالخرسانة (Cyclopean) بنسبة 50% خرسانة نوع (ب) 300 كجم/م3 شاملًا الشدة الخشبية',
        unit: 'م3',
        price: 56540,
      ),
      PreviousPriceType(
        code: 59,
        name: 'أعمال البناء بالحجر الجعم المغمور بالخرسانة (Cyclopean) بنسبة 50% خرسانة نوع (ب) 300 كجم/م3 بدون تخشيبة',
        unit: 'م3',
        price: 46220,
      ),
      PreviousPriceType(
        code: 60,
        name: 'أعمال البناء بالحجر الربراب بسماكة 25 سم بإستخدام أحجار المنطقة مع المونة الأسمنتية',
        unit: 'م2',
        price: 8420,
      ),
      PreviousPriceType(
        code: 61,
        name: 'أعمال الرصف بالحجر الشبامي المنشور والمرقوم سماكة 15 سم مع المونة الإسمنتية',
        unit: 'م2',
        price: 17100,
      ),
      PreviousPriceType(
        code: 62,
        name: 'أعمال الرصف بالحجر المقلفع سماكة 25 سم شاملًا تسوية قاعدة الرصف وفرشة بالمونة الأسمنتية',
        unit: 'م2',
        price: 16530,
      ),
      PreviousPriceType(
        code: 63,
        name: 'أعمال تنفيذ الخرسانة المسلحة نوع (أ) بدون حديد لأسقف العبارات (إسمنت بورتلاندي لا يقل عن 350 كجم/م3)',
        unit: 'م3',
        price: 103650,
      ),
      PreviousPriceType(
        code: 64,
        name: 'أعمال تنفيذ الخرسانة المسلحة نوع (أ) بدون حديد للجسور السطحية',
        unit: 'م3',
        price: 77000,
      ),
      PreviousPriceType(
        code: 65,
        name: 'أعمال تنفيذ الخرسانة المسلحة نوع (ب) بدون حديد (إسمنت بورتلاندي لا يقل عن 300 كجم/م3)',
        unit: 'م3',
        price: 73000,
      ),
      PreviousPriceType(
        code: 66,
        name: 'أعمال تنفيذ الخرسانة الإسمنتية العادية نوع (ج) بإستخدام الإسمنت البورتلاندي بكمية لا تقل عن 250 كجم/م3',
        unit: 'م3',
        price: 63550,
      ),
      PreviousPriceType(
        code: 67,
        name: 'أعمال توريد وتجهيز حديد التسليح (G40) للعبارات والجسور العلوية',
        unit: 'طن',
        price: 626490,
      ),
      PreviousPriceType(
        code: 68,
        name: 'أعمال توريد وتجهيز حديد التسليح (G40) للجسور السطحية',
        unit: 'طن',
        price: 605360,
      ),
      PreviousPriceType(
        code: 69,
        name: 'أعمال توريد وتجهيز حديد التسليح (G60) للعبارات والجسور العلوية',
        unit: 'طن',
        price: 653850,
      ),
      PreviousPriceType(
        code: 70,
        name: 'فارق نقل حديد التسليح لما بعد مسافة 100 كم',
        unit: 'طن*كم',
        price: 100,
      ),
      PreviousPriceType(
        code: 71,
        name: 'الأعمال المساحية للدراسات والتصاميم للطرق الخارجية (تحديد مسار ورفع الإحداثيات للمسار والمقاطع العرضية)',
        unit: 'كم',
        price: 410790,
      ),
    ],
  ),
];

/// أدوات مساعدة على قائمة الأسعار السابقة.
class PreviousPrices {
  PreviousPrices._();

  static int get bandsCount => previousPriceBands.length;

  static List<PreviousPriceType> get allTypes => <PreviousPriceType>[
        for (final band in previousPriceBands) ...band.types,
      ];

  static int get typesCount => allTypes.length;

  static int get pricedTypesCount =>
      allTypes.where((type) => type.hasPrice).length;

  /// البحث عن نوع بكوده.
  static PreviousPriceType? findByCode(int code) {
    for (final type in allTypes) {
      if (type.code == code) return type;
    }
    return null;
  }

  /// البحث عن قسم بمفتاحه (terrain / asphalt / structural).
  static PreviousPriceBand? bandByKey(String key) {
    for (final band in previousPriceBands) {
      if (band.key == key) return band;
    }
    return null;
  }

  /// القسم الذي يتبع له الكود.
  static PreviousPriceBand? bandOfCode(int code) {
    for (final band in previousPriceBands) {
      if (band.types.any((type) => type.code == code)) return band;
    }
    return null;
  }

  /// الوحدات المستخدمة في الخلاصة (لإضافتها إلى قوائم الوحدات).
  static List<String> get units {
    final values = <String>[];
    for (final type in allTypes) {
      if (!values.contains(type.unit)) values.add(type.unit);
    }
    return values;
  }
}

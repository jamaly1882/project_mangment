// ============================================================
// أسعار تحليل التكاليف — جدول «تحليل الوحدة» 1448هـ
// ============================================================
//
// المصدر: صفحة «تحليل الوحدة» في ملف:
//   الانتاجية اليومية والانتاجية لكل وحدة عمل - الاحتياطية.pdf
//   (تحليل الوحدة 1448هـ / التعليل 1447هـ)
//
// أعمدة الجدول الستة:
//   المهنة | مبلغ المصاريف | بيان المعدات | مبلغ الإهلاك |
//   بيان المحروقات | سعر اللتر
//
// التوزيع على أقسام التكلفة الأربعة:
//   • المهنة + المصاريف            → تكاليف العمالة (job + wage)
//   • بيان المعدات + الإهلاك       → تكاليف المعدات
//                                    (equipmentType + إهلاك الوحدة)
//   • ديزل/بترول/غاز/قاز/زيت      → تكاليف المحروقات (pricePerLiter)
//   • بقية المواد وأسعارها         → تكاليف المواد (materialName + سعر)
//
// هذه القوائم مضمّنة في التطبيق مثل أسعار 1447هـ، فلا يحتاج المدير
// إلى ملف ولا إلى لصق جدول: يضغط «استيراد أسعار التحليل» فتُملأ تكاليف
// البند تلقائيًا. الكميات تبقى صفرًا حتى يدخلها المشرف.
//
// الخلايا غير الرقمية في الملف (#REF! مثلًا) استُبعدت.
// ============================================================

/// سطر واحد من جدول تحليل الوحدة: اسم البند ومبلغه.
class UnitAnalysisRow {
  const UnitAnalysisRow(this.name, this.amount);

  final String name;
  final double amount;
}

/// أسطر العمالة: المهنة ومبلغ مصاريفها.
const List<UnitAnalysisRow> unitAnalysisLabor = <UnitAnalysisRow>[
  UnitAnalysisRow('سائق حرارة D155', 11500),
  UnitAnalysisRow('سائق حرارة D85', 11500),
  UnitAnalysisRow('سائق غرافة', 10900),
  UnitAnalysisRow('سائق قالب 20 طن', 10900),
  UnitAnalysisRow('سائق قالب 6 طن', 9000),
  UnitAnalysisRow('سائق جريدر', 11500),
  UnitAnalysisRow('سائق دكاكة', 9000),
  UnitAnalysisRow('سائق وايت ماء', 9000),
  UnitAnalysisRow('سائق سيارة', 7600),
  UnitAnalysisRow('مشرف', 12000),
  UnitAnalysisRow('عمال', 8500),
  UnitAnalysisRow('سائق كناسة', 9000),
  UnitAnalysisRow('سائق وايت M.C', 9000),
  UnitAnalysisRow('مشغل غربال', 9600),
  UnitAnalysisRow('مساعد مشغل غربال', 8300),
  UnitAnalysisRow('مشغل كسارة', 10200),
  UnitAnalysisRow('مشغل كمبريش هواء', 9000),
  UnitAnalysisRow('معلم ديناميت', 10200),
  UnitAnalysisRow('سائق بوكلين', 10900),
  UnitAnalysisRow('سائق دقاق', 10900),
  UnitAnalysisRow('معلم بناء', 10900),
  UnitAnalysisRow('معلم نجارة', 10900),
  UnitAnalysisRow('مساعد معلم نجارة', 8300),
  UnitAnalysisRow('معلم فرمجة', 9000),
  UnitAnalysisRow('مساعد معلم بناء', 8300),
  UnitAnalysisRow('معلم حدادة', 10900),
  UnitAnalysisRow('مساعد معلم حدادة', 8300),
  UnitAnalysisRow('مؤشر', 7600),
  UnitAnalysisRow('مشغل منشار إسفلت', 9000),
  UnitAnalysisRow('مشغل خالطة إسفلت', 10200),
  UnitAnalysisRow('مساعد مشغل خالطة', 9000),
  UnitAnalysisRow('مسخن', 9000),
  UnitAnalysisRow('ملحم', 8300),
  UnitAnalysisRow('ميكانيك', 8700),
  UnitAnalysisRow('كهربائي', 8700),
  UnitAnalysisRow('بنشري', 8300),
  UnitAnalysisRow('سائق فراشة', 10900),
  UnitAnalysisRow('سائق دكاكة حديد', 9000),
  UnitAnalysisRow('سائق دكاكة ربل', 9000),
  UnitAnalysisRow('شواك', 9000),
  UnitAnalysisRow('مشغل خالطة إسمنت', 9000),
  UnitAnalysisRow('مهندس', 13500),
  UnitAnalysisRow('مساح', 9000),
  UnitAnalysisRow('فني مساحة', 8200),
  UnitAnalysisRow('سائق مكينة الرنج', 9000),
  UnitAnalysisRow('مسخن طالء', 9000),
  UnitAnalysisRow('سائق قشاطة إسفلت', 10200),
  UnitAnalysisRow('س / قاطرة', 12400),
  UnitAnalysisRow('مشغل الة حقن', 10200),
  UnitAnalysisRow('فني مختبر', 9000),
];

/// أسطر المعدات: نوع المعدة ومبلغ إهلاكها.
const List<UnitAnalysisRow> unitAnalysisEquipment = <UnitAnalysisRow>[
  UnitAnalysisRow('حرارة D155', 23100),
  UnitAnalysisRow('حرارة D85', 13860),
  UnitAnalysisRow('غرافة 950', 12270),
  UnitAnalysisRow('قالب 20 طن', 350),
  UnitAnalysisRow('قالب 6 طن', 230),
  UnitAnalysisRow('جريدر', 18230),
  UnitAnalysisRow('دكاكة ترابية', 6240),
  UnitAnalysisRow('وايت ماء', 260),
  UnitAnalysisRow('سيارة', 115),
  UnitAnalysisRow('دكاكة صغيرة', 2360),
  UnitAnalysisRow('فينكس', 2310),
  UnitAnalysisRow('كناسة', 6160),
  UnitAnalysisRow('وايت M.C', 310),
  UnitAnalysisRow('غرافة 966', 14370),
  UnitAnalysisRow('غربالي آلي', 5700),
  UnitAnalysisRow('قاطرة', 435),
  UnitAnalysisRow('كسارة', 25670),
  UnitAnalysisRow('كمبريش هواء', 1850),
  UnitAnalysisRow('بوكلين', 12320),
  UnitAnalysisRow('دقاق', 12320),
  UnitAnalysisRow('بوكلين JCP', 5400),
  UnitAnalysisRow('خالطة أسمنتية', 2930),
  UnitAnalysisRow('إهالك خشب', 300000),
  UnitAnalysisRow('إهالك مسامير وقمط', 367),
  UnitAnalysisRow('هزاز الصب', 239),
  UnitAnalysisRow('إهالك فورمة حواجز السالمة', 20000),
  UnitAnalysisRow('منشار إسفلت', 665),
  UnitAnalysisRow('خالطة إسفلت', 25670),
  UnitAnalysisRow('مولد كهرباء', 3600),
  UnitAnalysisRow('فراشة', 18480),
  UnitAnalysisRow('دكاكة حديد', 4110),
  UnitAnalysisRow('دكاكة ربل', 4110),
  UnitAnalysisRow('سخان رنج', 1930),
  UnitAnalysisRow('مكينة طالء', 2850),
  UnitAnalysisRow('مكنسة شفط', 285),
  UnitAnalysisRow('قشاطة إسفلت', 26080),
  UnitAnalysisRow('الة حقن الشقوق االسفلتية', 240),
];

/// أسطر المحروقات: نوع الوقود وسعر اللتر.
const List<UnitAnalysisRow> unitAnalysisFuel = <UnitAnalysisRow>[
  UnitAnalysisRow('ديزل', 475),
  UnitAnalysisRow('بترول', 475),
  UnitAnalysisRow('قاز', 500),
  UnitAnalysisRow('غاز', 325),
];

/// أسطر المواد: اسم المادة وسعرها (بقية عمود المحروقات).
const List<UnitAnalysisRow> unitAnalysisMaterials = <UnitAnalysisRow>[
  UnitAnalysisRow('بيتومين خام', 420000),
  UnitAnalysisRow('نقل البيتومين', 40),
  UnitAnalysisRow('B.C', 6330),
  UnitAnalysisRow('M.C', 620),
  UnitAnalysisRow('ماء زفة', 15000),
  UnitAnalysisRow('ماء لتر', 5),
  UnitAnalysisRow('خلطة إسفلتية', 41490),
  UnitAnalysisRow('ديناميت', 3000),
  UnitAnalysisRow('ديناكورد', 451),
  UnitAnalysisRow('صاعق', 900),
  UnitAnalysisRow('حجر ربراب', 250),
  UnitAnalysisRow('حجر جعم زفة', 30000),
  UnitAnalysisRow('حجر مثاني', 11100),
  UnitAnalysisRow('حجر جدران', 500),
  UnitAnalysisRow('حجر رصف 25 سم', 550),
  UnitAnalysisRow('حجر منشار', 500),
  UnitAnalysisRow('أسمنت', 4000),
  UnitAnalysisRow('نيسة', 10000),
  UnitAnalysisRow('كري', 12000),
  UnitAnalysisRow('هلسن', 6000),
  UnitAnalysisRow('أجور قلفعة', 200),
  UnitAnalysisRow('حديد أسوار الحماية', 47500),
  UnitAnalysisRow('حديد G40', 400000),
  UnitAnalysisRow('حديد G60', 430000),
  UnitAnalysisRow('سلك', 1500),
  UnitAnalysisRow('نقل الحديد', 20000),
  UnitAnalysisRow('سلة جابيون', 15000),
  UnitAnalysisRow('أحجار جابيون م 3', 11100),
  UnitAnalysisRow('حجر سكروبين م3', 10000),
  UnitAnalysisRow('بردورات 35 سم', 2800),
  UnitAnalysisRow('بردورات 25 سم', 2170),
  UnitAnalysisRow('أعمال الحفر م . ط', 60),
  UnitAnalysisRow('طالء حراري أبيض', 1260000),
  UnitAnalysisRow('طالء حراري أصفر', 1200000),
  UnitAnalysisRow('زجاج عاكس', 840000),
  UnitAnalysisRow('لوح ألومونيوم', 114000),
  UnitAnalysisRow('الصق عاكس', 18600),
  UnitAnalysisRow('عمود مجلفن', 7467),
  UnitAnalysisRow('ورق قص ولصق', 2000),
  UnitAnalysisRow('اسفلت سائل مع المواد المضافة', 1250),
  UnitAnalysisRow('خلطة إسفلتة ناعمة', 41500),
  UnitAnalysisRow('خلطة إسفلتية خشنة', 40000),
];

/// كل أسطر التحليل (١٣٣ سطرًا).
List<UnitAnalysisRow> get unitAnalysisAll => <UnitAnalysisRow>[
      ...unitAnalysisLabor,
      ...unitAnalysisEquipment,
      ...unitAnalysisFuel,
      ...unitAnalysisMaterials,
    ];

/// سنة التحليل المرجعية.
const String unitAnalysisYear = '1448هـ';

/// عدد أسطر العمالة.
const int unitAnalysisLaborCount = 50;

/// عدد أسطر المعدات.
const int unitAnalysisEquipmentCount = 37;

/// عدد أسطر المحروقات.
const int unitAnalysisFuelCount = 4;

/// عدد أسطر المواد.
const int unitAnalysisMaterialsCount = 42;

/// عدد أسطر التحليل الإجمالي.
const int unitAnalysisRowCount =
    unitAnalysisLaborCount +
        unitAnalysisEquipmentCount +
        unitAnalysisFuelCount +
        unitAnalysisMaterialsCount;

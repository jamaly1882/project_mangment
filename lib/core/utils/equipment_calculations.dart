// ============================================================
// حسابات المعدات النقية — إدارة الحركة / الديزل / الورشة
// ============================================================
//
// هذا الملف لا يعتمد على Flutter ولا Firebase إطلاقًا،
// حتى تبقى معادلات الديزل والصيانة والإهلاك قابلة للاختبار
// الآلي (test/equipment_calculations_test.dart) ولإعادة
// الاستخدام من أي شاشة.
//
// تدفق البيانات الذي تخدمه هذه الحسابات:
//
//   مدير إدارة الحركة يضيف المعدة (بكودها) ويربطها بمشروع
//   (برقم المشروع) ──► تظهر بياناتها مباشرة في:
//     • إدارة الديزل: نافذة «استهلاك المعدات» (كل معدة بكودها
//       ورقم مشروعها) ونافذة «استهلاك الوقود» (كمية كل مشروع
//       في اليوم).
//     • إدارة الورشة والصيانة: الأعطال وبدلات التواير وقطع
//       الغيار.
//   وكل سجل من الإدارتين يُضاف إلى «ملف المعدة»، ومنه يُحتسب
//   الإهلاك وبدل الأعطال تلقائيًا.
//
// معادلات الإهلاك المعتمدة (نفس معادلات ملف الإكسل في صفحة
// «الإهلاك والإيجار والأعطال»):
//
//   1) إهلاك وحدة العمل بالقيمة:
//        (القيمة الحالية للمعدة − القيمة التخريدية)
//        ÷ عدد وحدات العمل المتوقعة
//      والإهلاك المتراكم = إهلاك الوحدة × وحدات العمل المنفذة
//      (بسقف: القيمة الحالية − التخريدية)،
//      والقيمة الدفترية = القيمة الحالية − المتراكم.
//
//   2) إهلاك وحدة العمل من تكلفة الديزل (طريقة الإكسل):
//        تكلفة الديزل لكل وحدة عمل × نسبة الإهلاك (50%)
//      وبدل مواجهة الأعطال لكل وحدة عمل:
//        إهلاك الوحدة × نسبة الأعطال (5%)
// ============================================================

/// أنواع سجلات الورشة والصيانة المحفوظة في `maintenance_logs`.
class MaintenanceTypes {
  MaintenanceTypes._();

  /// عطل.
  static const String breakdown = 'breakdown';

  /// بدل تواير (إطارات).
  static const String tire = 'tire';

  /// قطع غيار.
  static const String part = 'part';

  /// صيانة دورية / أخرى.
  static const String service = 'service';

  /// حالتا سجل الصيانة: قيد الإصلاح / تم.
  static const String statusOpen = 'open';
  static const String statusDone = 'done';

  static const List<String> all = <String>[breakdown, tire, part, service];

  static String label(String? type) {
    switch (type) {
      case breakdown:
        return 'عطل';
      case tire:
        return 'بدل تواير';
      case part:
        return 'قطع غيار';
      case service:
        return 'صيانة';
      default:
        return 'صيانة';
    }
  }

  static String statusLabel(String? status) {
    return status == statusOpen ? 'قيد الإصلاح' : 'تم الإصلاح';
  }
}

/// معادلات المعدات: الديزل، والصيانة، والإهلاك، وتجميع ملف المعدة.
class EquipmentCalc {
  EquipmentCalc._();

  /// نسبة الإهلاك الافتراضية من تكلفة الديزل (ملف الإكسل: 50%).
  static const double defaultDepreciationRate = 0.5;

  /// نسبة بدل مواجهة الأعطال الافتراضية (ملف الإكسل: 5%).
  static const double defaultBreakdownRate = 0.05;

  // ==========================================================
  // أدوات عامة
  // ==========================================================

  /// مفتاح اليوم بصيغة `yyyy-MM-dd` — يُستخدم لتجميع استهلاك
  /// الوقود اليومي لكل مشروع.
  static String dayKey(DateTime date) {
    final String y = date.year.toString().padLeft(4, '0');
    final String m = date.month.toString().padLeft(2, '0');
    final String d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// قراءة رقم من قيمة محفوظة في Firestore (num أو نص).
  static double numOf(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final String text = value
          .replaceAll('٠', '0')
          .replaceAll('١', '1')
          .replaceAll('٢', '2')
          .replaceAll('٣', '3')
          .replaceAll('٤', '4')
          .replaceAll('٥', '5')
          .replaceAll('٦', '6')
          .replaceAll('٧', '7')
          .replaceAll('٨', '8')
          .replaceAll('٩', '9')
          .replaceAll('٫', '.')
          .replaceAll(',', '')
          .trim();
      return double.tryParse(text) ?? 0;
    }
    return 0;
  }

  /// قيمة غير سالبة (لا تكاليف ولا كميات سالبة).
  static double nonNegative(double value) {
    if (value.isNaN || value.isInfinite || value < 0) return 0;
    return value;
  }

  // ==========================================================
  // الديزل والوقود
  // ==========================================================

  /// تكلفة صرف الديزل = اللترات × سعر اللتر.
  static double dieselCost({
    required double liters,
    required double pricePerLiter,
  }) {
    return nonNegative(liters) * nonNegative(pricePerLiter);
  }

  /// تكلفة الديزل لكل وحدة عمل = إجمالي تكلفة الديزل ÷ وحدات
  /// العمل المنفذة (0 إذا لم تُسجَّل وحدات عمل بعد).
  static double dieselCostPerWorkUnit({
    required double totalFuelCost,
    required double totalWorkUnits,
  }) {
    if (totalWorkUnits <= 0) return 0;
    return nonNegative(totalFuelCost) / totalWorkUnits;
  }

  // ==========================================================
  // الورشة والصيانة
  // ==========================================================

  /// تكلفة بند صيانة (قطعة / تاير / إصلاح) = الكمية × سعر الوحدة.
  static double maintenanceCost({
    required double quantity,
    required double unitCost,
  }) {
    return nonNegative(quantity) * nonNegative(unitCost);
  }

  // ==========================================================
  // الإهلاك وبدل الأعطال
  // ==========================================================

  /// إهلاك وحدة العمل الواحدة بطريقة القيمة:
  /// (القيمة الحالية − التخريدية) ÷ وحدات العمل المتوقعة.
  static double depreciationPerWorkUnit({
    required double currentValue,
    required double salvageValue,
    required double expectedWorkUnits,
  }) {
    if (expectedWorkUnits <= 0) return 0;
    final double depreciable =
        nonNegative(currentValue) - nonNegative(salvageValue);
    if (depreciable <= 0) return 0;
    return depreciable / expectedWorkUnits;
  }

  /// الإهلاك المتراكم حتى الآن = إهلاك الوحدة × الوحدات المنفذة،
  /// بسقف (القيمة الحالية − التخريدية) فلا تتجاوزه أبدًا.
  static double accumulatedDepreciation({
    required double perWorkUnit,
    required double workedUnits,
    required double currentValue,
    required double salvageValue,
  }) {
    final double raw = nonNegative(perWorkUnit) * nonNegative(workedUnits);
    final double cap =
        nonNegative(currentValue) - nonNegative(salvageValue);
    if (cap <= 0) return 0;
    return raw > cap ? cap : raw;
  }

  /// القيمة الدفترية الحالية = القيمة الحالية − الإهلاك المتراكم.
  static double bookValue({
    required double currentValue,
    required double accumulated,
  }) {
    final double value = nonNegative(currentValue) - nonNegative(accumulated);
    return value < 0 ? 0 : value;
  }

  /// نسبة ما استُهلك من عمر المعدة الافتراضي (0..1):
  /// الوحدات المنفذة ÷ الوحدات المتوقعة.
  static double consumedLifeRatio({
    required double workedUnits,
    required double expectedWorkUnits,
  }) {
    if (expectedWorkUnits <= 0) return 0;
    final double ratio = nonNegative(workedUnits) / expectedWorkUnits;
    return ratio > 1 ? 1 : ratio;
  }

  /// إهلاك وحدة العمل بطريقة الإكسل:
  /// تكلفة الديزل لكل وحدة عمل × نسبة الإهلاك (افتراضي 50%).
  static double depreciationFromDieselCost({
    required double dieselCostPerWorkUnit,
    double rate = defaultDepreciationRate,
  }) {
    return nonNegative(dieselCostPerWorkUnit) * nonNegative(rate);
  }

  /// بدل مواجهة الأعطال لكل وحدة عمل:
  /// إهلاك الوحدة × نسبة الأعطال (افتراضي 5%).
  static double breakdownAllowancePerWorkUnit({
    required double depreciationPerWorkUnit,
    double rate = defaultBreakdownRate,
  }) {
    return nonNegative(depreciationPerWorkUnit) * nonNegative(rate);
  }
}

// ============================================================
// مجاميع ملف المعدة (من سجلات الديزل والورشة)
// ============================================================

/// إجماليات «ملف المعدة» محسوبة من سجلاتها الخام.
///
/// تُستخدم في صفحة ملف المعدة للتحقق والعرض الدقيق، بينما
/// تحمل وثيقة المعدة نفسها مجاميع متراكمة (increments)
/// للعرض السريع في القوائم — انظر EquipmentService.
class EquipmentFileTotals {
  const EquipmentFileTotals({
    this.totalLiters = 0,
    this.totalFuelCost = 0,
    this.totalWorkUnits = 0,
    this.dieselRecords = 0,
    this.lastMeter = 0,
    this.breakdownCount = 0,
    this.openBreakdownCount = 0,
    this.breakdownCost = 0,
    this.tiresCost = 0,
    this.partsCost = 0,
    this.serviceCost = 0,
    this.totalMaintenanceCost = 0,
    this.maintenanceRecords = 0,
    this.totalDowntimeHours = 0,
  });

  /// إجمالي لترات الديزل المصروفة للمعدة.
  final double totalLiters;

  /// إجمالي تكلفة الديزل.
  final double totalFuelCost;

  /// إجمالي وحدات العمل التي اشتغلتها المعدة (ساعة/كم/...).
  final double totalWorkUnits;

  /// عدد سجلات صرف الديزل.
  final int dieselRecords;

  /// أعلى قراءة عداد وردت في سجلات الديزل.
  final double lastMeter;

  /// عدد الأعطال المسجلة.
  final int breakdownCount;

  /// عدد الأعطال التي ما زالت قيد الإصلاح.
  final int openBreakdownCount;

  /// تكلفة الأعطال.
  final double breakdownCost;

  /// تكلفة بدلات التواير.
  final double tiresCost;

  /// تكلفة قطع الغيار.
  final double partsCost;

  /// تكلفة الصيانة الأخرى.
  final double serviceCost;

  /// إجمالي تكلفة الورشة والصيانة (أعطال + تواير + قطع + صيانة).
  final double totalMaintenanceCost;

  /// عدد سجلات الورشة والصيانة.
  final int maintenanceRecords;

  /// إجمالي ساعات التوقف بسبب الصيانة/الأعطال.
  final double totalDowntimeHours;

  /// تكلفة الديزل لكل وحدة عمل (مدخل معادلات الإهلاك).
  double get dieselCostPerWorkUnit => EquipmentCalc.dieselCostPerWorkUnit(
        totalFuelCost: totalFuelCost,
        totalWorkUnits: totalWorkUnits,
      );

  /// إجمالي ما كلّفته المعدة تشغيليًا: ديزل + صيانة.
  double get totalOperatingCost => totalFuelCost + totalMaintenanceCost;

  /// تجميع الملف من سجلات `diesel_consumption_logs`
  /// وسجلات `maintenance_logs` الخاصة بمعدة واحدة.
  factory EquipmentFileTotals.fromLogs({
    required List<Map<String, dynamic>> dieselLogs,
    required List<Map<String, dynamic>> maintenanceLogs,
  }) {
    double liters = 0;
    double fuelCost = 0;
    double workUnits = 0;
    double meter = 0;

    for (final Map<String, dynamic> log in dieselLogs) {
      final double logLiters = EquipmentCalc.numOf(log['liters']);
      liters += logLiters;

      // التكلفة المحفوظة أولًا، وإلا تُحسب من اللترات × السعر.
      final double savedCost = EquipmentCalc.numOf(log['totalCost']);
      fuelCost += savedCost > 0
          ? savedCost
          : EquipmentCalc.dieselCost(
              liters: logLiters,
              pricePerLiter: EquipmentCalc.numOf(log['pricePerLiter']),
            );

      workUnits += EquipmentCalc.numOf(log['workUnits']);

      final double reading = EquipmentCalc.numOf(log['meterReading']);
      if (reading > meter) meter = reading;
    }

    int breakdowns = 0;
    int openBreakdowns = 0;
    double breakdownCost = 0;
    double tires = 0;
    double parts = 0;
    double service = 0;
    double downtime = 0;

    for (final Map<String, dynamic> log in maintenanceLogs) {
      final String type = (log['type'] ?? '').toString();

      final double savedCost = EquipmentCalc.numOf(log['totalCost']);
      final double cost = savedCost > 0
          ? savedCost
          : EquipmentCalc.maintenanceCost(
              quantity: EquipmentCalc.numOf(log['quantity']),
              unitCost: EquipmentCalc.numOf(log['unitCost']),
            );

      downtime += EquipmentCalc.numOf(log['downtimeHours']);

      switch (type) {
        case MaintenanceTypes.breakdown:
          breakdowns++;
          if ((log['status'] ?? '').toString() ==
              MaintenanceTypes.statusOpen) {
            openBreakdowns++;
          }
          breakdownCost += cost;
          break;
        case MaintenanceTypes.tire:
          tires += cost;
          break;
        case MaintenanceTypes.part:
          parts += cost;
          break;
        default:
          service += cost;
      }
    }

    return EquipmentFileTotals(
      totalLiters: liters,
      totalFuelCost: fuelCost,
      totalWorkUnits: workUnits,
      dieselRecords: dieselLogs.length,
      lastMeter: meter,
      breakdownCount: breakdowns,
      openBreakdownCount: openBreakdowns,
      breakdownCost: breakdownCost,
      tiresCost: tires,
      partsCost: parts,
      serviceCost: service,
      totalMaintenanceCost: breakdownCost + tires + parts + service,
      maintenanceRecords: maintenanceLogs.length,
      totalDowntimeHours: downtime,
    );
  }
}

// ============================================================
// استهلاك الوقود اليومي لكل مشروع
// ============================================================

/// استهلاك مشروع واحد في يوم واحد (نافذة «استهلاك الوقود»):
/// رقم المشروع + كمية استهلاكه في اليوم.
class ProjectDayFuel {
  const ProjectDayFuel({
    required this.projectId,
    required this.projectCode,
    required this.projectName,
    required this.dayKey,
    required this.liters,
    required this.cost,
    required this.records,
    required this.equipmentCount,
  });

  final String projectId;

  /// رقم المشروع (الكود).
  final String projectCode;

  final String projectName;

  /// اليوم بصيغة yyyy-MM-dd.
  final String dayKey;

  /// كمية الوقود المستهلكة في اليوم (لتر).
  final double liters;

  /// تكلفة وقود اليوم.
  final double cost;

  /// عدد سجلات الصرف في اليوم.
  final int records;

  /// عدد المعدات التي صُرف لها في اليوم.
  final int equipmentCount;
}

/// يجمّع سجلات صرف الديزل حسب (رقم المشروع + اليوم).
///
/// تعرضه نافذة «استهلاك الوقود» في إدارة الديزل من وثائق
/// `project_fuel_daily` المتراكمة، وهذه الدالة تعيد بناء
/// النتيجة نفسها من السجلات الخام (للتحقق والاختبار).
///
/// النتيجة مرتبة: الأحدث أولًا، ثم برقم المشروع.
List<ProjectDayFuel> dailyFuelTotals(List<Map<String, dynamic>> dieselLogs) {
  final Map<String, _DayFuelAccumulator> byKey =
      <String, _DayFuelAccumulator>{};

  for (final Map<String, dynamic> log in dieselLogs) {
    final String projectId = (log['projectId'] ?? '').toString().trim();
    final String day = (log['dayKey'] ?? '').toString().trim();
    if (projectId.isEmpty || day.isEmpty) continue;

    final String key = '${projectId}__$day';
    final _DayFuelAccumulator acc = byKey.putIfAbsent(
      key,
      () => _DayFuelAccumulator(
        projectId: projectId,
        projectCode: (log['projectCode'] ?? '').toString(),
        projectName: (log['projectName'] ?? '').toString(),
        dayKey: day,
      ),
    );

    final double logLiters = EquipmentCalc.numOf(log['liters']);
    acc.liters += logLiters;

    final double savedCost = EquipmentCalc.numOf(log['totalCost']);
    acc.cost += savedCost > 0
        ? savedCost
        : EquipmentCalc.dieselCost(
            liters: logLiters,
            pricePerLiter: EquipmentCalc.numOf(log['pricePerLiter']),
          );

    acc.records++;

    final String equipmentId = (log['equipmentId'] ?? '').toString().trim();
    if (equipmentId.isNotEmpty) acc.equipmentIds.add(equipmentId);
  }

  final List<ProjectDayFuel> result = byKey.values
      .map(
        (_DayFuelAccumulator acc) => ProjectDayFuel(
          projectId: acc.projectId,
          projectCode: acc.projectCode,
          projectName: acc.projectName,
          dayKey: acc.dayKey,
          liters: acc.liters,
          cost: acc.cost,
          records: acc.records,
          equipmentCount: acc.equipmentIds.length,
        ),
      )
      .toList();

  result.sort((ProjectDayFuel a, ProjectDayFuel b) {
    final int byDay = b.dayKey.compareTo(a.dayKey);
    if (byDay != 0) return byDay;
    return a.projectCode.compareTo(b.projectCode);
  });

  return result;
}

class _DayFuelAccumulator {
  _DayFuelAccumulator({
    required this.projectId,
    required this.projectCode,
    required this.projectName,
    required this.dayKey,
  });

  final String projectId;
  final String projectCode;
  final String projectName;
  final String dayKey;

  double liters = 0;
  double cost = 0;
  int records = 0;
  final Set<String> equipmentIds = <String>{};
}

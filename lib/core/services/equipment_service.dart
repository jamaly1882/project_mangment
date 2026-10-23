import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/equipment_calculations.dart';

// ============================================================
// خدمة المعدات — إدارة الحركة / الديزل / الورشة والصيانة
// ============================================================
//
// الفكرة: المعدة تُكتب مرة واحدة في مجموعة `equipment` على
// يد مدير إدارة الحركة، وبعدها تعمل عليها ثلاث إدارات دون
// إعادة إدخال بياناتها:
//
//   • إدارة الحركة: تضيف المعدة بكودها، وتربطها بالمشروع
//     الذي تعمل فيه (برقم المشروع) وتنقلها بين المشاريع.
//     الربط الحالي محفوظ في حقول وثيقة المعدة:
//       currentProjectId / currentProjectCode / currentProjectName
//     وسجل التنقلات الكامل في مجموعة `equipment_assignments`.
//
//   • إدارة الديزل: كل صرف يذهب إلى `diesel_consumption_logs`
//     وهو يحمل كود المعدة ورقم مشروعها الحالي تلقائيًا،
//     وفي العملية نفسها (WriteBatch واحدة):
//       - تُحدَّث مجاميع ملف المعدة في وثيقتها
//         (totalDieselLiters / totalFuelCost / totalWorkUnits…)
//       - يُحدَّث استهلاك المشروع اليومي في `project_fuel_daily`
//         (وثيقة لكل مشروع في اليوم: {projectId}__{yyyy-MM-dd})
//         وهو ما تعرضه نافذة «استهلاك الوقود».
//
//   • إدارة الورشة والصيانة: الأعطال وبدلات التواير وقطع
//     الغيار في `maintenance_logs`، وتُحدَّث معها مجاميع
//     الصيانة في وثيقة المعدة، والعطل المفتوح يجعل حالة
//     المعدة «معطلة» حتى يُغلق.
//
// التوافق مع الصفحات السابقة:
//   توجد صفحتان قديمتان لحصر المعدات بحقلين مختلفين للكود
//   والنوع (`code`/`name` في equipment_page.dart و
//   `equipmentCode`/`equipmentType` في
//   equipment_management_pages.dart). هذه الخدمة تكتب
//   الاسمين معًا (مرآة) وتقرأ أيًا منهما، حتى ترى الصفحات
//   كلها المعدة نفسها دون تكرار.
//
// الاستعلامات هنا أحادية الحقل (`where` واحد) والفرز يتم
// في العميل، فلا حاجة إلى فهارس مركبة في Firestore.
// ============================================================

/// أسماء مجموعات Firestore المستخدمة في منظومة المعدات.
class EquipmentCollections {
  EquipmentCollections._();

  /// حصر المعدات (وثيقة لكل معدة = ملف المعدة).
  static const String equipment = 'equipment';

  /// سجلات صرف الديزل (نافذة «استهلاك المعدات»).
  static const String dieselLogs = 'diesel_consumption_logs';

  /// سجلات الورشة: الأعطال والتواير والقطع والصيانة.
  static const String maintenanceLogs = 'maintenance_logs';

  /// سجل نقل المعدات بين المشاريع.
  static const String assignments = 'equipment_assignments';

  /// استهلاك الوقود اليومي لكل مشروع (نافذة «استهلاك الوقود»).
  static const String projectFuelDaily = 'project_fuel_daily';

  /// المشاريع.
  static const String projects = 'projects';
}

/// خطأ تشغيلي برسالة عربية جاهزة للعرض على المستخدم.
class EquipmentServiceException implements Exception {
  const EquipmentServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

// ============================================================
// قراءة وثيقة معدة (تقبل الحقول القديمة والجديدة)
// ============================================================

/// معدة مقروءة من `equipment` بحقول موحّدة.
class EquipmentDoc {
  const EquipmentDoc({required this.id, required this.data});

  /// معرف الوثيقة في Firestore.
  final String id;

  /// بيانات الوثيقة الخام.
  final Map<String, dynamic> data;

  factory EquipmentDoc.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return EquipmentDoc(id: doc.id, data: doc.data() ?? <String, dynamic>{});
  }

  String _text(List<String> keys) {
    for (final String key in keys) {
      final String value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  double _number(List<String> keys) {
    for (final String key in keys) {
      final double value = EquipmentCalc.numOf(data[key]);
      if (value != 0) return value;
    }
    return 0;
  }

  /// كود المعدة / الرقم الإداري.
  String get code {
    final String value = _text(const <String>['code', 'equipmentCode']);
    return value.isNotEmpty ? value : id;
  }

  /// نوع المعدة.
  String get type {
    final String value =
        _text(const <String>['name', 'type', 'equipmentType']);
    return value.isNotEmpty ? value : 'معدة بدون نوع';
  }

  /// الاسم المعروض: «النوع — الكود».
  String get displayName => '$type — $code';

  String get manufacturer =>
      _text(const <String>['manufacturer', 'manufacturerCountry']);

  String get workUnit => _text(const <String>['workUnit']);

  double get currentMeter => _number(const <String>['currentMeter']);

  /// حالة المعدة: جيدة / متوسطة / تحتاج صيانة / معطلة.
  String get condition {
    final String value =
        _text(const <String>['condition', 'currentCondition']);
    return value.isNotEmpty ? value : 'غير محددة';
  }

  bool get isBroken => condition == 'معطلة';

  bool get isActive =>
      (data['status'] ?? 'active').toString() != 'inactive';

  String get driverName => _text(const <String>['driverName']);
  String get driverPhone => _text(const <String>['driverPhone']);

  // ------- المشروع الحالي الذي تعمل فيه المعدة -------

  String get projectId => _text(const <String>['currentProjectId']);

  /// رقم المشروع الحالي (الكود).
  String get projectCode => _text(const <String>['currentProjectCode']);

  String get projectName => _text(const <String>['currentProjectName']);

  bool get hasProject => projectId.isNotEmpty;

  // ------- مدخلات الإهلاك -------

  /// القيمة الحالية للمعدة.
  double get currentValue =>
      _number(const <String>['currentValue', 'currentEquipmentValue']);

  /// القيمة التخريدية.
  double get salvageValue => _number(const <String>['salvageValue']);

  /// عدد وحدات العمل المتوقعة في عمرها.
  double get expectedWorkUnits =>
      _number(const <String>['expectedWorkUnits']);

  // ------- مجاميع الملف المتراكمة (تحدّثها الخدمة) -------

  double get totalDieselLiters =>
      _number(const <String>['totalDieselLiters']);
  double get totalFuelCost => _number(const <String>['totalFuelCost']);
  double get totalWorkUnits => _number(const <String>['totalWorkUnits']);
  double get totalMaintenanceCost =>
      _number(const <String>['totalMaintenanceCost']);
  double get breakdownCostTotal =>
      _number(const <String>['breakdownCostTotal']);
  double get tiresCostTotal => _number(const <String>['tiresCostTotal']);
  double get partsCostTotal => _number(const <String>['partsCostTotal']);
  int get breakdownCount => _number(const <String>['breakdownCount']).toInt();
  int get openBreakdownCount =>
      _number(const <String>['openBreakdownCount']).toInt();
  double get totalDowntimeHours =>
      _number(const <String>['totalDowntimeHours']);
}

/// مشروع للاختيار من القوائم: معرفه ورقمه واسمه.
class ProjectOption {
  const ProjectOption({
    required this.id,
    required this.code,
    required this.name,
  });

  final String id;

  /// رقم المشروع (حقل `code` في وثيقة المشروع).
  final String code;

  final String name;

  factory ProjectOption.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return ProjectOption(
      id: doc.id,
      code: (data['code'] ?? '').toString().trim(),
      name: (data['name'] ?? '').toString().trim(),
    );
  }

  /// التسمية المعروضة: «رقم المشروع — اسمه».
  String get label {
    if (code.isNotEmpty && name.isNotEmpty) return '$code — $name';
    if (name.isNotEmpty) return name;
    if (code.isNotEmpty) return code;
    return 'مشروع بدون اسم';
  }
}

/// بيانات المعدة المدخلة من نموذج إدارة الحركة.
class EquipmentInput {
  const EquipmentInput({
    required this.code,
    required this.type,
    this.manufacturer = '',
    this.year,
    this.workUnit = '',
    this.meter = 0,
    this.driverName = '',
    this.driverPhone = '',
    this.condition = 'جيدة',
    this.currentValue = 0,
    this.salvageValue = 0,
    this.expectedWorkUnits = 0,
    this.notes = '',
  });

  final String code;
  final String type;
  final String manufacturer;
  final int? year;
  final String workUnit;
  final double meter;
  final String driverName;
  final String driverPhone;
  final String condition;
  final double currentValue;
  final double salvageValue;
  final double expectedWorkUnits;
  final String notes;
}

// ============================================================
// الخدمة
// ============================================================

class EquipmentService {
  EquipmentService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _equipment =>
      _firestore.collection(EquipmentCollections.equipment);

  CollectionReference<Map<String, dynamic>> get _dieselLogs =>
      _firestore.collection(EquipmentCollections.dieselLogs);

  CollectionReference<Map<String, dynamic>> get _maintenanceLogs =>
      _firestore.collection(EquipmentCollections.maintenanceLogs);

  CollectionReference<Map<String, dynamic>> get _assignments =>
      _firestore.collection(EquipmentCollections.assignments);

  CollectionReference<Map<String, dynamic>> get _projectFuelDaily =>
      _firestore.collection(EquipmentCollections.projectFuelDaily);

  CollectionReference<Map<String, dynamic>> get _projects =>
      _firestore.collection(EquipmentCollections.projects);

  // ==========================================================
  // تدفقات القراءة
  // ==========================================================

  /// كل المعدات مرتبة بالكود.
  Stream<List<EquipmentDoc>> equipmentStream() {
    return _equipment.snapshots().map((snapshot) {
      final List<EquipmentDoc> list = snapshot.docs
          .map(EquipmentDoc.fromDoc)
          .toList()
        ..sort((a, b) => a.code.toLowerCase().compareTo(b.code.toLowerCase()));
      return list;
    });
  }

  /// وثيقة معدة واحدة (ملف المعدة).
  Stream<EquipmentDoc?> equipmentDocStream(String equipmentId) {
    return _equipment.doc(equipmentId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return EquipmentDoc.fromDoc(doc);
    });
  }

  /// كل المشاريع مرتبة برقم المشروع.
  Stream<List<ProjectOption>> projectsStream() {
    return _projects.snapshots().map((snapshot) {
      final List<ProjectOption> list = snapshot.docs
          .map(ProjectOption.fromDoc)
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
      return list;
    });
  }

  /// سجلات صرف الديزل (كلها، أو لمعدة واحدة) — الأحدث أولًا.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> dieselLogsStream({
    String? equipmentId,
  }) {
    Query<Map<String, dynamic>> query = _dieselLogs;
    if (equipmentId != null && equipmentId.isNotEmpty) {
      query = query.where('equipmentId', isEqualTo: equipmentId);
    }
    return query.snapshots().map((snapshot) {
      final docs = snapshot.docs.toList();
      sortMapsByDateDesc(docs, (doc) => doc.data());
      return docs;
    });
  }

  /// سجلات الورشة والصيانة (كلها، أو لمعدة واحدة) — الأحدث أولًا.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      maintenanceLogsStream({String? equipmentId}) {
    Query<Map<String, dynamic>> query = _maintenanceLogs;
    if (equipmentId != null && equipmentId.isNotEmpty) {
      query = query.where('equipmentId', isEqualTo: equipmentId);
    }
    return query.snapshots().map((snapshot) {
      final docs = snapshot.docs.toList();
      sortMapsByDateDesc(docs, (doc) => doc.data());
      return docs;
    });
  }

  /// تنقلات معدة بين المشاريع — الأحدث أولًا.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      assignmentsStream(String equipmentId) {
    return _assignments
        .where('equipmentId', isEqualTo: equipmentId)
        .snapshots()
        .map((snapshot) {
      final docs = snapshot.docs.toList();
      sortMapsByDateDesc(docs, (doc) => doc.data(), key: 'fromDate');
      return docs;
    });
  }

  /// استهلاك الوقود اليومي للمشاريع — أحدث يوم أولًا.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      projectFuelDailyStream() {
    return _projectFuelDaily.snapshots().map((snapshot) {
      final docs = snapshot.docs.toList()
        ..sort((a, b) {
          final String dayA = (a.data()['dayKey'] ?? '').toString();
          final String dayB = (b.data()['dayKey'] ?? '').toString();
          final int byDay = dayB.compareTo(dayA);
          if (byDay != 0) return byDay;
          return (a.data()['projectCode'] ?? '')
              .toString()
              .compareTo((b.data()['projectCode'] ?? '').toString());
        });
      return docs;
    });
  }

  // ==========================================================
  // إدارة الحركة: إضافة المعدة وتعديلها ونقلها
  // ==========================================================

  /// هل توجد معدة بهذا الكود؟ يعيد معرف وثيقتها إن وُجدت.
  ///
  /// يفحص الحقلين القديم والجديد (`code` و`equipmentCode`)
  /// ومعرف الوثيقة نفسه (صفحة الإكسل تحفظ المعدة بمعرف = الكود).
  Future<String?> findEquipmentIdByCode(
    String code, {
    String? excludeId,
  }) async {
    final String value = code.trim();
    if (value.isEmpty) return null;

    final DocumentSnapshot<Map<String, dynamic>> byId =
        await _equipment.doc(value).get();
    if (byId.exists && byId.id != excludeId) return byId.id;

    for (final String field in const <String>['code', 'equipmentCode']) {
      final QuerySnapshot<Map<String, dynamic>> result =
          await _equipment.where(field, isEqualTo: value).limit(2).get();
      for (final doc in result.docs) {
        if (doc.id != excludeId) return doc.id;
      }
    }
    return null;
  }

  /// حمولة وثيقة المعدة من نموذج الإدخال (بمرآة الحقول القديمة).
  Map<String, dynamic> _equipmentPayload(EquipmentInput input) {
    return <String, dynamic>{
      // الكود والنوع بالاسمين حتى تراهما الصفحات القديمة والجديدة.
      'code': input.code.trim(),
      'equipmentCode': input.code.trim(),
      'name': input.type.trim(),
      'type': input.type.trim(),
      'equipmentType': input.type.trim(),
      'manufacturer': input.manufacturer.trim(),
      'manufacturerCountry': input.manufacturer.trim(),
      'modelYear': input.year,
      'year': input.year,
      'manufactureYear': input.year,
      'workUnit': input.workUnit.trim(),
      'currentMeter': EquipmentCalc.nonNegative(input.meter),
      'driverName': input.driverName.trim(),
      'driverPhone': input.driverPhone.trim(),
      'condition': input.condition,
      'currentCondition': input.condition,
      // مدخلات الإهلاك (تُقرأ في ملف المعدة وصفحة الإكسل).
      'currentValue': EquipmentCalc.nonNegative(input.currentValue),
      'currentEquipmentValue':
          EquipmentCalc.nonNegative(input.currentValue),
      'salvageValue': EquipmentCalc.nonNegative(input.salvageValue),
      'expectedWorkUnits':
          EquipmentCalc.nonNegative(input.expectedWorkUnits),
      'notes': input.notes.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// يضيف مديرُ الحركة معدة جديدة، ويربطها بمشروع إن اختير.
  ///
  /// من لحظة الحفظ تظهر المعدة في إدارة الديزل (بكودها ورقم
  /// مشروعها) وفي إدارة الورشة والصيانة، لأن القوائم كلها
  /// تقرأ من مجموعة `equipment` نفسها.
  Future<void> addEquipment({
    required EquipmentInput input,
    ProjectOption? project,
    DateTime? assignedAt,
    String byUid = '',
    String byName = '',
  }) async {
    if (input.code.trim().isEmpty) {
      throw const EquipmentServiceException('كود المعدة مطلوب');
    }
    if (input.type.trim().isEmpty) {
      throw const EquipmentServiceException('نوع المعدة مطلوب');
    }

    final String? duplicate = await findEquipmentIdByCode(input.code);
    if (duplicate != null) {
      throw const EquipmentServiceException(
        'هذا الرقم الإداري موجود مسبقًا. ابحث عن المعدة وعدّل '
        'بياناتها أو انقلها إلى مشروع بدل إنشاء معدة مكررة.',
      );
    }

    final DocumentReference<Map<String, dynamic>> ref = _equipment.doc();
    final WriteBatch batch = _firestore.batch();

    final Map<String, dynamic> payload = _equipmentPayload(input)
      ..addAll(<String, dynamic>{
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': byUid,
        'createdByName': byName,
        'registeredBy': 'movement_dept',
        // مجاميع ملف المعدة تبدأ من الصفر.
        'totalDieselLiters': 0,
        'totalFuelCost': 0,
        'totalWorkUnits': 0,
        'dieselRecordsCount': 0,
        'totalMaintenanceCost': 0,
        'breakdownCostTotal': 0,
        'tiresCostTotal': 0,
        'partsCostTotal': 0,
        'serviceCostTotal': 0,
        'breakdownCount': 0,
        'openBreakdownCount': 0,
        'totalDowntimeHours': 0,
        // المشروع الحالي (يُعبَّأ إن اختاره مدير الحركة الآن).
        'currentProjectId': project?.id ?? '',
        'currentProjectCode': project?.code ?? '',
        'currentProjectName': project?.name ?? '',
      });

    batch.set(ref, payload);

    if (project != null) {
      batch.set(_assignments.doc(), <String, dynamic>{
        'equipmentId': ref.id,
        'equipmentCode': input.code.trim(),
        'equipmentType': input.type.trim(),
        'projectId': project.id,
        'projectCode': project.code,
        'projectName': project.name,
        'fromDate': Timestamp.fromDate(assignedAt ?? DateTime.now()),
        'toDate': null,
        'notes': 'ربط عند إضافة المعدة',
        'createdByUid': byUid,
        'createdByName': byName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  /// تعديل بيانات معدة موجودة (الكود ثابت لا يتغير لحماية
  /// روابط سجلات الديزل والصيانة المحفوظة به).
  Future<void> updateEquipment({
    required String equipmentId,
    required EquipmentInput input,
  }) async {
    await _equipment
        .doc(equipmentId)
        .set(_equipmentPayload(input), SetOptions(merge: true));
  }

  /// نقل معدة إلى مشروع: يُغلق ربطها السابق، ويُفتح ربط جديد،
  /// وتُحدَّث حقول المشروع الحالي في وثيقة المعدة — فتنعكس
  /// في إدارة الديزل والورشة فورًا.
  Future<void> assignToProject({
    required EquipmentDoc equipment,
    required ProjectOption project,
    required DateTime date,
    String notes = '',
    String byUid = '',
    String byName = '',
  }) async {
    final WriteBatch batch = _firestore.batch();

    // إغلاق الربط المفتوح السابق إن وُجد.
    final QuerySnapshot<Map<String, dynamic>> previous = await _assignments
        .where('equipmentId', isEqualTo: equipment.id)
        .get();
    for (final doc in previous.docs) {
      if (doc.data()['toDate'] == null) {
        batch.update(doc.reference, <String, dynamic>{
          'toDate': Timestamp.fromDate(date),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    batch.set(_assignments.doc(), <String, dynamic>{
      'equipmentId': equipment.id,
      'equipmentCode': equipment.code,
      'equipmentType': equipment.type,
      'projectId': project.id,
      'projectCode': project.code,
      'projectName': project.name,
      'fromDate': Timestamp.fromDate(date),
      'toDate': null,
      'notes': notes.trim(),
      'createdByUid': byUid,
      'createdByName': byName,
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.update(_equipment.doc(equipment.id), <String, dynamic>{
      'currentProjectId': project.id,
      'currentProjectCode': project.code,
      'currentProjectName': project.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// فك ربط معدة عن مشروعها (عودة إلى ساحة الحركة/الورشة).
  Future<void> unassign({
    required EquipmentDoc equipment,
    required DateTime date,
  }) async {
    final WriteBatch batch = _firestore.batch();

    final QuerySnapshot<Map<String, dynamic>> previous = await _assignments
        .where('equipmentId', isEqualTo: equipment.id)
        .get();
    for (final doc in previous.docs) {
      if (doc.data()['toDate'] == null) {
        batch.update(doc.reference, <String, dynamic>{
          'toDate': Timestamp.fromDate(date),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    batch.update(_equipment.doc(equipment.id), <String, dynamic>{
      'currentProjectId': '',
      'currentProjectCode': '',
      'currentProjectName': '',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// حذف وثيقة المعدة فقط. سجلات الديزل والصيانة تبقى كما هي
  /// (سجل تاريخي) لكنها لن تظهر في ملف معدة.
  Future<void> deleteEquipment(String equipmentId) {
    return _equipment.doc(equipmentId).delete();
  }

  // ==========================================================
  // إدارة الديزل: تسجيل الصرف وحذفه
  // ==========================================================

  /// تسجيل صرف ديزل لمعدة (نافذة «استهلاك المعدات»).
  ///
  /// يحمل السجل كود المعدة ورقم مشروعها الحالي تلقائيًا،
  /// وتُحدَّث في العملية نفسها مجاميع ملف المعدة واستهلاك
  /// المشروع في اليوم (نافذة «استهلاك الوقود»).
  Future<void> recordDiesel({
    required EquipmentDoc equipment,
    required DateTime date,
    required double liters,
    required double pricePerLiter,
    double workUnits = 0,
    double meterReading = 0,
    String notes = '',
    String byUid = '',
    String byName = '',
  }) async {
    if (!equipment.hasProject) {
      throw const EquipmentServiceException(
        'المعدة غير مرتبطة بأي مشروع حاليًا. يربطها مدير الحركة '
        'بمشروع أولًا، ثم يُسجَّل صرف الديزل لها.',
      );
    }
    if (liters <= 0) {
      throw const EquipmentServiceException('كمية الديزل باللتر مطلوبة');
    }
    if (pricePerLiter < 0) {
      throw const EquipmentServiceException('سعر اللتر غير صحيح');
    }

    final double cleanLiters = EquipmentCalc.nonNegative(liters);
    final double cleanPrice = EquipmentCalc.nonNegative(pricePerLiter);
    final double cleanWork = EquipmentCalc.nonNegative(workUnits);
    final double cleanMeter = EquipmentCalc.nonNegative(meterReading);
    final double totalCost = EquipmentCalc.dieselCost(
      liters: cleanLiters,
      pricePerLiter: cleanPrice,
    );
    final String day = EquipmentCalc.dayKey(date);

    final WriteBatch batch = _firestore.batch();

    // 1) سجل الصرف — بكود المعدة ورقم مشروعها.
    batch.set(_dieselLogs.doc(), <String, dynamic>{
      'equipmentId': equipment.id,
      'equipmentCode': equipment.code,
      'equipmentType': equipment.type,
      'workUnit': equipment.workUnit,
      'projectId': equipment.projectId,
      'projectCode': equipment.projectCode,
      'projectName': equipment.projectName,
      'date': Timestamp.fromDate(date),
      'dayKey': day,
      'liters': cleanLiters,
      'pricePerLiter': cleanPrice,
      'totalCost': totalCost,
      'workUnits': cleanWork,
      'meterReading': cleanMeter,
      'notes': notes.trim(),
      'source': 'diesel_dept',
      'recordedByUid': byUid,
      'recordedByName': byName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2) استهلاك الوقود اليومي للمشروع (رقم المشروع + كمية اليوم).
    batch.set(
      _projectFuelDaily.doc('${equipment.projectId}__$day'),
      <String, dynamic>{
        'projectId': equipment.projectId,
        'projectCode': equipment.projectCode,
        'projectName': equipment.projectName,
        'dayKey': day,
        'date': Timestamp.fromDate(date),
        'totalLiters': FieldValue.increment(cleanLiters),
        'totalCost': FieldValue.increment(totalCost),
        'totalWorkUnits': FieldValue.increment(cleanWork),
        'recordsCount': FieldValue.increment(1),
        'equipmentIds': FieldValue.arrayUnion(<String>[equipment.id]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // 3) مجاميع ملف المعدة + العداد.
    final Map<String, dynamic> equipmentUpdate = <String, dynamic>{
      'totalDieselLiters': FieldValue.increment(cleanLiters),
      'totalFuelCost': FieldValue.increment(totalCost),
      'totalWorkUnits': FieldValue.increment(cleanWork),
      'dieselRecordsCount': FieldValue.increment(1),
      'lastFuelDate': Timestamp.fromDate(date),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (cleanMeter > equipment.currentMeter) {
      equipmentUpdate['currentMeter'] = cleanMeter;
    }
    batch.update(_equipment.doc(equipment.id), equipmentUpdate);

    await batch.commit();
  }

  /// حذف سجل صرف ديزل مع عكس أثره في ملف المعدة وفي
  /// استهلاك المشروع اليومي.
  Future<void> deleteDieselLog({
    required String logId,
    required Map<String, dynamic> log,
  }) async {
    final String equipmentId = (log['equipmentId'] ?? '').toString();
    final String projectId = (log['projectId'] ?? '').toString();
    final String day = (log['dayKey'] ?? '').toString();
    final double liters = EquipmentCalc.numOf(log['liters']);
    final double cost = EquipmentCalc.numOf(log['totalCost']);
    final double work = EquipmentCalc.numOf(log['workUnits']);

    final WriteBatch batch = _firestore.batch();
    batch.delete(_dieselLogs.doc(logId));

    if (equipmentId.isNotEmpty) {
      final DocumentSnapshot<Map<String, dynamic>> equipment =
          await _equipment.doc(equipmentId).get();
      if (equipment.exists) {
        batch.update(_equipment.doc(equipmentId), <String, dynamic>{
          'totalDieselLiters': FieldValue.increment(-liters),
          'totalFuelCost': FieldValue.increment(-cost),
          'totalWorkUnits': FieldValue.increment(-work),
          'dieselRecordsCount': FieldValue.increment(-1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    if (projectId.isNotEmpty && day.isNotEmpty) {
      batch.set(
        _projectFuelDaily.doc('${projectId}__$day'),
        <String, dynamic>{
          'totalLiters': FieldValue.increment(-liters),
          'totalCost': FieldValue.increment(-cost),
          'totalWorkUnits': FieldValue.increment(-work),
          'recordsCount': FieldValue.increment(-1),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  // ==========================================================
  // إدارة الورشة والصيانة: الأعطال والتواير والقطع
  // ==========================================================

  /// تسجيل بند ورشة على معدة: عطل / بدل تواير / قطع غيار / صيانة.
  ///
  /// يُحفظ في `maintenance_logs` ويُضاف إلى ملف المعدة:
  /// ترتفع مجاميع الصيانة في وثيقة المعدة، والعطل الذي ما زال
  /// قيد الإصلاح يجعل حالتها «معطلة».
  Future<void> recordMaintenance({
    required EquipmentDoc equipment,
    required String type,
    required DateTime date,
    String description = '',
    String partName = '',
    double quantity = 1,
    double unitCost = 0,
    double downtimeHours = 0,
    bool done = true,
    String notes = '',
    String byUid = '',
    String byName = '',
  }) async {
    if (!MaintenanceTypes.all.contains(type)) {
      throw const EquipmentServiceException('نوع سجل الصيانة غير معروف');
    }

    final double cleanQuantity =
        quantity <= 0 ? 1 : EquipmentCalc.nonNegative(quantity);
    final double cleanUnitCost = EquipmentCalc.nonNegative(unitCost);
    final double totalCost = EquipmentCalc.maintenanceCost(
      quantity: cleanQuantity,
      unitCost: cleanUnitCost,
    );
    final double cleanDowntime = EquipmentCalc.nonNegative(downtimeHours);
    final bool isOpenBreakdown =
        type == MaintenanceTypes.breakdown && !done;

    final WriteBatch batch = _firestore.batch();

    batch.set(_maintenanceLogs.doc(), <String, dynamic>{
      'equipmentId': equipment.id,
      'equipmentCode': equipment.code,
      'equipmentType': equipment.type,
      // مشروع المعدة وقت التسجيل (قد يكون فارغًا إن كانت في الورشة).
      'projectId': equipment.projectId,
      'projectCode': equipment.projectCode,
      'projectName': equipment.projectName,
      'type': type,
      'status': done
          ? MaintenanceTypes.statusDone
          : MaintenanceTypes.statusOpen,
      'date': Timestamp.fromDate(date),
      'dayKey': EquipmentCalc.dayKey(date),
      'description': description.trim(),
      'partName': partName.trim(),
      'quantity': cleanQuantity,
      'unitCost': cleanUnitCost,
      'totalCost': totalCost,
      'downtimeHours': cleanDowntime,
      'notes': notes.trim(),
      'source': 'workshop',
      'recordedByUid': byUid,
      'recordedByName': byName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final Map<String, dynamic> equipmentUpdate = <String, dynamic>{
      'totalMaintenanceCost': FieldValue.increment(totalCost),
      'maintenanceRecordsCount': FieldValue.increment(1),
      'totalDowntimeHours': FieldValue.increment(cleanDowntime),
      'lastMaintenanceDate': Timestamp.fromDate(date),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    switch (type) {
      case MaintenanceTypes.breakdown:
        equipmentUpdate['breakdownCostTotal'] =
            FieldValue.increment(totalCost);
        equipmentUpdate['breakdownCount'] = FieldValue.increment(1);
        if (isOpenBreakdown) {
          equipmentUpdate['openBreakdownCount'] = FieldValue.increment(1);
          equipmentUpdate['condition'] = 'معطلة';
          equipmentUpdate['currentCondition'] = 'معطلة';
        }
        break;
      case MaintenanceTypes.tire:
        equipmentUpdate['tiresCostTotal'] = FieldValue.increment(totalCost);
        break;
      case MaintenanceTypes.part:
        equipmentUpdate['partsCostTotal'] = FieldValue.increment(totalCost);
        break;
      default:
        equipmentUpdate['serviceCostTotal'] =
            FieldValue.increment(totalCost);
    }

    batch.update(_equipment.doc(equipment.id), equipmentUpdate);

    await batch.commit();
  }

  /// إغلاق سجل صيانة (اكتمل الإصلاح).
  ///
  /// إذا لم يتبقَّ للمعدة عطل مفتوح آخر تعود حالتها إلى «جيدة».
  Future<void> closeMaintenance({
    required String logId,
    required Map<String, dynamic> log,
  }) async {
    final String equipmentId = (log['equipmentId'] ?? '').toString();
    final bool wasOpenBreakdown =
        (log['type'] ?? '').toString() == MaintenanceTypes.breakdown &&
            (log['status'] ?? '').toString() == MaintenanceTypes.statusOpen;

    final WriteBatch batch = _firestore.batch();
    batch.update(_maintenanceLogs.doc(logId), <String, dynamic>{
      'status': MaintenanceTypes.statusDone,
      'closedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (equipmentId.isNotEmpty && wasOpenBreakdown) {
      // هل تبقى عطل مفتوح آخر لهذه المعدة؟
      final QuerySnapshot<Map<String, dynamic>> others =
          await _maintenanceLogs
              .where('equipmentId', isEqualTo: equipmentId)
              .get();
      final bool stillOpen = others.docs.any((doc) {
        if (doc.id == logId) return false;
        final Map<String, dynamic> d = doc.data();
        return (d['type'] ?? '').toString() ==
                MaintenanceTypes.breakdown &&
            (d['status'] ?? '').toString() == MaintenanceTypes.statusOpen;
      });

      final Map<String, dynamic> equipmentUpdate = <String, dynamic>{
        'openBreakdownCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!stillOpen) {
        equipmentUpdate['condition'] = 'جيدة';
        equipmentUpdate['currentCondition'] = 'جيدة';
      }
      batch.update(_equipment.doc(equipmentId), equipmentUpdate);
    }

    await batch.commit();
  }

  /// حذف سجل ورشة مع عكس أثره في مجاميع ملف المعدة.
  Future<void> deleteMaintenanceLog({
    required String logId,
    required Map<String, dynamic> log,
  }) async {
    final String equipmentId = (log['equipmentId'] ?? '').toString();
    final String type = (log['type'] ?? '').toString();
    final double cost = EquipmentCalc.numOf(log['totalCost']);
    final double downtime = EquipmentCalc.numOf(log['downtimeHours']);
    final bool wasOpenBreakdown =
        type == MaintenanceTypes.breakdown &&
            (log['status'] ?? '').toString() == MaintenanceTypes.statusOpen;

    final WriteBatch batch = _firestore.batch();
    batch.delete(_maintenanceLogs.doc(logId));

    if (equipmentId.isNotEmpty) {
      final DocumentSnapshot<Map<String, dynamic>> equipment =
          await _equipment.doc(equipmentId).get();
      if (equipment.exists) {
        final Map<String, dynamic> update = <String, dynamic>{
          'totalMaintenanceCost': FieldValue.increment(-cost),
          'maintenanceRecordsCount': FieldValue.increment(-1),
          'totalDowntimeHours': FieldValue.increment(-downtime),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        switch (type) {
          case MaintenanceTypes.breakdown:
            update['breakdownCostTotal'] = FieldValue.increment(-cost);
            update['breakdownCount'] = FieldValue.increment(-1);
            if (wasOpenBreakdown) {
              update['openBreakdownCount'] = FieldValue.increment(-1);
              // إن كان هذا آخر عطل مفتوح تعود الحالة إلى «جيدة».
              final QuerySnapshot<Map<String, dynamic>> others =
                  await _maintenanceLogs
                      .where('equipmentId', isEqualTo: equipmentId)
                      .get();
              final bool stillOpen = others.docs.any((doc) {
                if (doc.id == logId) return false;
                final Map<String, dynamic> d = doc.data();
                return (d['type'] ?? '').toString() ==
                        MaintenanceTypes.breakdown &&
                    (d['status'] ?? '').toString() ==
                        MaintenanceTypes.statusOpen;
              });
              if (!stillOpen) {
                update['condition'] = 'جيدة';
                update['currentCondition'] = 'جيدة';
              }
            }
            break;
          case MaintenanceTypes.tire:
            update['tiresCostTotal'] = FieldValue.increment(-cost);
            break;
          case MaintenanceTypes.part:
            update['partsCostTotal'] = FieldValue.increment(-cost);
            break;
          default:
            update['serviceCostTotal'] = FieldValue.increment(-cost);
        }
        batch.update(_equipment.doc(equipmentId), update);
      }
    }

    await batch.commit();
  }

  // ==========================================================
  // أدوات التاريخ والفرز (مشتركة بين الشاشات)
  // ==========================================================

  /// قراءة تاريخ من قيمة Firestore (Timestamp أو DateTime أو نص).
  static DateTime? dateOf(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// فرز وثائق تنازليًا حسب حقل تاريخ (ثم `createdAt`).
  static void sortMapsByDateDesc<T>(
    List<T> items,
    Map<String, dynamic> Function(T item) dataOf, {
    String key = 'date',
  }) {
    DateTime valueOf(T item) {
      final Map<String, dynamic> data = dataOf(item);
      return dateOf(data[key]) ??
          dateOf(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }

    items.sort((a, b) => valueOf(b).compareTo(valueOf(a)));
  }
}

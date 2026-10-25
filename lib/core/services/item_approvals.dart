import 'package:cloud_firestore/cloud_firestore.dart';

// ============================================================
// طلبات الكميات الإضافية وتمديد وقت البند
// ============================================================
//
// القاعدة:
//   • الكمية القصوى المسموحة للمشرف = الكمية التعاقدية، إلا إذا وافق
//     مدير إدارة الجودة على كمية إضافية بحد أقصى 20% من التعاقدية.
//   • زمن البند = مدة العقد من أول يوم يسجّل فيه المشرف كمية منفذة،
//     إلا إذا وافق مدير الجودة على تمديد.
//
// كل طلب يُخزَّن في `item_approvals`، وتُنسخ الموافقة إلى وثيقة البند
// بحقول واضحة ليقرأها المشرف دون استعلام إضافي:
//   extraQuantityApproved / extraQuantityPercent
//   timeExtensionDays / timeExtensionUntil
//
// قاعدة مهمة في هذا الملف: **لا استعلام بأكثر من حقل واحد**.
//   جمع فلترين أو أكثر (itemId + kind + status) يحتاج فهرسًا مركّبًا
//   في Firestore، وكان غيابه يجعل الطلب يفشل بصمت فلا يصل إلى
//   مدير الجودة إطلاقًا. لذلك نستعلم بحقل واحد (itemId أو projectId)
//   ونُفلتر بقية الحقول في الذاكرة، فلا حاجة إلى أي فهرس.
// ============================================================

/// أنواع الطلبات.
class ApprovalKind {
  ApprovalKind._();

  /// كمية إضافية تتجاوز الكمية التعاقدية (بحد 20%).
  static const String extraQuantity = 'extra_quantity';

  /// تمديد زمن البند بعد انتهاء مدة العقد.
  static const String timeExtension = 'time_extension';

  static String label(String kind) {
    switch (kind) {
      case extraQuantity:
        return 'كمية إضافية';
      case timeExtension:
        return 'تمديد وقت';
      default:
        return 'طلب';
    }
  }
}

/// حالات الطلب.
class ApprovalStatus {
  ApprovalStatus._();

  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';

  static String label(String status) {
    switch (status) {
      case approved:
        return 'موافق عليه';
      case rejected:
        return 'مرفوض';
      default:
        return 'بانتظار الموافقة';
    }
  }
}

/// الحد الأقصى للكمية الإضافية (نسبة من الكمية التعاقدية).
const double maxExtraQuantityPercent = 20;

/// خطأ في إرسال طلب إلى مدير الجودة، برسالة عربية جاهزة للعرض.
class ItemApprovalException implements Exception {
  const ItemApprovalException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// حساب «الكمية الإضافية» قبل تسجيل كمية منفذة.
///
/// يفصل هذا الصنف كل الحساب في مكان واحد قابل للاختبار، فتستخدمه
/// صفحة المشرف في القرار: هل الإدخال داخل الحد المسموح؟ وهل يحتاج
/// طلب كمية إضافية من مدير الجودة؟ وكم النسبة المطلوبة؟
///
/// مثال: تعاقدية 700، منفذة 650، والمشرف أدخل 100:
///   الإجمالي 750  ← يتجاوز التعاقدية بـ 50
///   النسبة المطلوبة = 50 / 700 × 100 = 7.14%
///   بعد الموافقة يصبح الحد المسموح 750 ويُقبل الإدخال.
class ExtraQuantityPlan {
  const ExtraQuantityPlan({
    required this.contractQuantity,
    required this.executedQuantity,
    required this.enteredQuantity,
    required this.allowedQuantity,
    required this.excessQuantity,
    required this.requestedPercent,
    required this.maxAllowedQuantity,
  });

  /// الكمية التعاقدية للبند.
  final double contractQuantity;

  /// الكمية المنفذة المسجّلة قبل الإدخال الجديد.
  final double executedQuantity;

  /// الكمية التي يُدخلها المشرف الآن.
  final double enteredQuantity;

  /// أقصى كمية مسموحة حاليًا = التعاقدية + أي كمية إضافية معتمدة.
  final double allowedQuantity;

  /// ما يتجاوز الكمية التعاقدية (صفر إن لم يتجاوز).
  final double excessQuantity;

  /// النسبة المطلوبة من الكمية التعاقدية (مقيّدة بسقف 20%).
  final double requestedPercent;

  /// أقصى إجمالي ممكن بعد موافقة مدير الجودة بسقف 20%.
  final double maxAllowedQuantity;

  /// إجمالي الكمية المنفذة بعد الإدخال الجديد.
  double get totalAfter =>
      executedQuantity + enteredQuantity;

  /// هل يحتاج هذا الإدخال إلى طلب كمية إضافية؟
  bool get needsRequest =>
      contractQuantity > 0 && totalAfter > allowedQuantity;

  /// هل تتجاوز الحاجة سقف 20% من الكمية التعاقدية؟
  bool get exceedsCap =>
      contractQuantity > 0 && totalAfter > maxAllowedQuantity;

  /// أعلى كمية يمكن إدخالها الآن (بعد موافقة 20%).
  double get maxEnterableNow {
    final double value = maxAllowedQuantity - executedQuantity;
    return value < 0 ? 0 : value;
  }

  /// نسبة الموافقة الحالية (0 إن لم توجد).
  double get approvedPercent {
    if (contractQuantity <= 0 || !allowedQuantity.isFinite) return 0;
    return ((allowedQuantity - contractQuantity) / contractQuantity * 100)
        .clamp(0, maxExtraQuantityPercent)
        .toDouble();
  }

  /// الكمية الإضافية التي يجب طلبها (لا تتجاوز سقف 20%).
  double get requestedQuantity =>
      (contractQuantity * requestedPercent / 100);

  /// إجمالي الكمية المطلوب الوصول إليه بعد الموافقة.
  double get requestedTotal =>
      contractQuantity + requestedQuantity;

  factory ExtraQuantityPlan.of({
    required double contractQuantity,
    required double executedQuantity,
    required double enteredQuantity,
    double approvedPercent = 0,
    bool extraApproved = false,
  }) {
    final double contract =
        contractQuantity < 0 ? 0 : contractQuantity;
    final double executed =
        executedQuantity < 0 ? 0 : executedQuantity;
    final double entered =
        enteredQuantity < 0 ? 0 : enteredQuantity;

    final double approved = extraApproved
        ? approvedPercent.clamp(0, maxExtraQuantityPercent).toDouble()
        : 0;

    final double allowed = contract <= 0
        ? double.infinity
        : contract * (1 + approved / 100);

    final double total = executed + entered;

    final double excess = contract <= 0 || total <= contract
        ? 0
        : total - contract;

    final double percent = contract <= 0
        ? 0
        : (excess / contract * 100)
            .clamp(0, maxExtraQuantityPercent)
            .toDouble();

    final double maxAllowed = contract <= 0
        ? double.infinity
        : contract * (1 + maxExtraQuantityPercent / 100);

    return ExtraQuantityPlan(
      contractQuantity: contract,
      executedQuantity: executed,
      enteredQuantity: entered,
      allowedQuantity: allowed,
      excessQuantity: excess,
      requestedPercent: percent,
      maxAllowedQuantity: maxAllowed,
    );
  }
}

/// طلب واحد.
class ItemApproval {
  const ItemApproval({
    required this.id,
    required this.itemId,
    required this.projectId,
    required this.kind,
    required this.status,
    this.itemName = '',
    this.typeName = '',
    this.unit = '',
    this.contractQuantity = 0,
    this.executedQuantity = 0,
    this.requestedQuantity = 0,
    this.requestedTotal = 0,
    this.requestedPercent = 0,
    this.requestedDays = 0,
    this.approvedPercent = 0,
    this.approvedQuantity = 0,
    this.approvedDays = 0,
    this.note = '',
    this.createdAt,
  });

  final String id;
  final String itemId;
  final String projectId;
  final String kind;
  final String status;

  final String itemName;
  final String typeName;
  final String unit;

  final double contractQuantity;
  final double executedQuantity;

  /// الكمية الإضافية المطلوبة بالوحدات (ما يتجاوز الكمية التعاقدية).
  ///
  /// هي الرقم الذي يقرأه مدير الجودة ويوافق عليه؛ النسبة مشتقة منها.
  final double requestedQuantity;

  /// إجمالي الكمية المنفذة المطلوب الوصول إليه بعد الموافقة
  /// (= الكمية التعاقدية + [requestedQuantity]).
  final double requestedTotal;

  /// النسبة المطلوبة للكمية الإضافية (مشتقة من [requestedQuantity]).
  final double requestedPercent;

  /// عدد الأيام المطلوبة للتمديد.
  final double requestedDays;

  /// النسبة الموافق عليها (≤ 20).
  final double approvedPercent;

  /// الكمية الإضافية الموافق عليها بالوحدات.
  final double approvedQuantity;

  /// الأيام الموافق عليها.
  final double approvedDays;

  final String note;
  final DateTime? createdAt;

  bool get isPending => status == ApprovalStatus.pending;

  /// النسبة المعروضة: الموافق عليها إن وُجدت، وإلا المطلوبة.
  double get effectivePercent =>
      approvedPercent > 0 ? approvedPercent : requestedPercent;

  /// الكمية المعروضة: الموافق عليها إن وُجدت، وإلا المطلوبة.
  double get effectiveQuantity {
    if (approvedQuantity > 0) return approvedQuantity;
    if (requestedQuantity > 0) return requestedQuantity;
    if (contractQuantity > 0) {
      return contractQuantity * effectivePercent / 100;
    }
    return 0;
  }

  String get kindLabel => ApprovalKind.label(kind);

  String get statusLabel => ApprovalStatus.label(status);

  static ItemApproval fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final created = data['createdAt'];

    final double contract = _num(data['contractQuantity']);
    final double percent = _num(data['requestedPercent']);

    // طلبات قديمة سُجّلت بالنسبة فقط: نستخرج الكمية منها حتى تُعرض
    // بالوحدات كما تُعرض الطلبات الجديدة.
    double requestedQuantity = _num(data['requestedQuantity']);
    if (requestedQuantity <= 0 && contract > 0 && percent > 0) {
      requestedQuantity = contract * percent / 100;
    }

    double approvedQuantity = _num(data['approvedQuantity']);
    final double approvedPercent = _num(data['approvedPercent']);
    if (approvedQuantity <= 0 && contract > 0 && approvedPercent > 0) {
      approvedQuantity = contract * approvedPercent / 100;
    }

    return ItemApproval(
      id: doc.id,
      itemId: (data['itemId'] ?? '').toString(),
      projectId: (data['projectId'] ?? '').toString(),
      kind: (data['kind'] ?? '').toString(),
      status: (data['status'] ?? ApprovalStatus.pending).toString(),
      itemName: (data['itemName'] ?? '').toString(),
      typeName: (data['typeName'] ?? '').toString(),
      unit: (data['unit'] ?? '').toString(),
      contractQuantity: contract,
      executedQuantity: _num(data['executedQuantity']),
      requestedQuantity: requestedQuantity,
      requestedTotal: _num(data['requestedTotal']),
      requestedPercent: percent,
      requestedDays: _num(data['requestedDays']),
      approvedPercent: approvedPercent,
      approvedQuantity: approvedQuantity,
      approvedDays: _num(data['approvedDays']),
      note: (data['note'] ?? '').toString(),
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }

  static double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// حساب ما يُسمح به للبند الواحد.
class ItemAllowance {
  const ItemAllowance({
    required this.contractQuantity,
    required this.executedQuantity,
    required this.extraPercent,
    required this.extraApproved,
    required this.contractStart,
    required this.contractEnd,
    required this.extensionDays,
    required this.extensionUntil,
  });

  final double contractQuantity;
  final double executedQuantity;

  /// النسبة الموافق عليها من مدير الجودة (0 إن لم توجد).
  final double extraPercent;
  final bool extraApproved;

  /// أول يوم تنفيذ ومدة العقد.
  final DateTime? contractStart;
  final DateTime? contractEnd;

  /// تمديد موافق عليه.
  final double extensionDays;
  final DateTime? extensionUntil;

  /// آخر يوم مسموح بعد التمديد.
  DateTime? get effectiveEnd {
    if (extensionUntil != null) return extensionUntil;
    if (contractEnd == null || extensionDays <= 0) return contractEnd;
    return contractEnd!.add(Duration(days: extensionDays.round()));
  }

  /// أقصى كمية مسموحة.
  double get maxQuantity {
    if (contractQuantity <= 0) return double.infinity;
    if (!extraApproved || extraPercent <= 0) return contractQuantity;

    final safePercent = extraPercent.clamp(0, maxExtraQuantityPercent);
    return contractQuantity * (1 + safePercent / 100);
  }

  /// الكمية الإضافية المسموحة (بالوحدات).
  double get extraAllowance =>
      maxQuantity.isFinite ? (maxQuantity - contractQuantity) : 0;

  /// هل انتهى زمن البند؟
  bool get isTimeExpired {
    final end = effectiveEnd;
    if (end == null) return false;

    return DateTime.now().isAfter(
      DateTime(end.year, end.month, end.day, 23, 59, 59),
    );
  }

  /// هل تجاوز المنفذ الكمية التعاقدية؟
  bool get isOverContract =>
      contractQuantity > 0 && executedQuantity > contractQuantity;

  /// المتبقي حتى أقصى كمية مسموحة.
  double get remaining {
    if (!maxQuantity.isFinite) return double.infinity;
    final value = maxQuantity - executedQuantity;
    return value < 0 ? 0 : value;
  }

  static ItemAllowance fromData(Map<String, dynamic> data) {
    return ItemAllowance(
      contractQuantity: _num(data['contractQuantity']),
      executedQuantity: _num(data['executedQuantity']),
      extraPercent: _num(data['extraQuantityPercent']),
      extraApproved: data['extraQuantityApproved'] == true,
      contractStart: _date(data['executionStartDate'] ?? data['contractStartDate']),
      contractEnd: _date(data['contractEndDate']),
      extensionDays: _num(data['timeExtensionDays']),
      extensionUntil: _date(data['timeExtensionUntil']),
    );
  }

  static double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

/// خدمة الطلبات والموافقات.
class ItemApprovals {
  ItemApprovals._();

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('item_approvals');

  /// طلبات مشروع واحد بحالة معينة (بث مباشر).
  ///
  /// الاستعلام بحقل واحد فقط (`projectId`)، و`kind`/`status` يُفلتران
  /// في الذاكرة؛ لأن جمع الفلاتر يحتاج فهرسًا مركّبًا في Firestore
  /// وكان غيابه يعطّل عدّادات مدير الجودة.
  static Stream<List<ItemApproval>> stream({
    String? projectId,
    String? kind,
    String? status,
  }) {
    Query<Map<String, dynamic>> query = _collection;

    if (projectId != null && projectId.isNotEmpty) {
      query = query.where('projectId', isEqualTo: projectId);
    }

    return query.snapshots().map((snapshot) {
      final List<ItemApproval> approvals = <ItemApproval>[];

      for (final doc in snapshot.docs) {
        final ItemApproval approval = ItemApproval.fromDoc(doc);

        if (kind != null && kind.isNotEmpty && approval.kind != kind) {
          continue;
        }
        if (status != null &&
            status.isNotEmpty &&
            approval.status != status) {
          continue;
        }

        approvals.add(approval);
      }

      // المعلّق أولًا، ثم الأحدث.
      approvals.sort((a, b) {
        if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
        return (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000));
      });

      return approvals;
    });
  }

  /// أحدث طلب معلّق لهذا البند من النوع المحدد (أو null).
  ///
  /// استعلام بحقل واحد بلا فهرس، ويُستخدم لعرض «طلبك قيد المراجعة»
  /// في صفحة المشرف ومنع تكرار الطلب.
  static Future<ItemApproval?> pendingFor({
    required String itemId,
    String kind = ApprovalKind.extraQuantity,
  }) async {
    if (itemId.isEmpty) return null;

    try {
      final snapshot =
          await _collection.where('itemId', isEqualTo: itemId).get();

      ItemApproval? latest;

      for (final doc in snapshot.docs) {
        final ItemApproval approval = ItemApproval.fromDoc(doc);

        if (approval.kind != kind || !approval.isPending) continue;

        if (latest == null ||
            (approval.createdAt ?? DateTime(2000))
                .isAfter(latest.createdAt ?? DateTime(2000))) {
          latest = approval;
        }
      }

      return latest;
    } catch (_) {
      return null;
    }
  }

  /// ينشئ طلبًا إن لم يكن هناك طلب معلّق من النوع نفسه للبند.
  ///
  /// يعيد معرّف الطلب (القديم أو الجديد)، ويرمي
  /// [ItemApprovalException] برسالة عربية إن فشل الإرسال — بدل
  /// ابتلاع الخطأ كما كان سابقًا حين كانت الطلبات تفشل بلا أثر.
  static Future<String> request({
    required String itemId,
    required String projectId,
    required String kind,
    String itemName = '',
    String typeName = '',
    String unit = '',
    double contractQuantity = 0,
    double executedQuantity = 0,
    double requestedQuantity = 0,
    double requestedTotal = 0,
    double requestedPercent = 0,
    double requestedDays = 0,
    String note = '',
    String? requestedBy,
  }) async {
    if (itemId.isEmpty) {
      throw const ItemApprovalException('تعذر تحديد البند المطلوب.');
    }
    if (projectId.isEmpty) {
      throw const ItemApprovalException(
        'البند غير مرتبط بمشروع؛ راجع مدير المشروع.',
      );
    }

    try {
      // حقل واحد فقط: الفلاتر الثلاثة معًا تحتاج فهرسًا مركّبًا،
      // وغيابه كان يجعل الطلب يفشل بصمت فلا يصل إلى مدير الجودة.
      final existing =
          await _collection.where('itemId', isEqualTo: itemId).get();

      for (final doc in existing.docs) {
        final data = doc.data();
        final bool sameKind = (data['kind'] ?? '').toString() == kind;
        final bool sameStatus =
            (data['status'] ?? ApprovalStatus.pending).toString() ==
                ApprovalStatus.pending;
        final bool sameProject =
            (data['projectId'] ?? '').toString() == projectId;

        if (sameKind && sameStatus && sameProject) return doc.id;
      }

      final safePercent =
          requestedPercent.clamp(0, maxExtraQuantityPercent).toDouble();

      final double contract =
          contractQuantity < 0 ? 0 : contractQuantity;
      final double quantity = requestedQuantity < 0 || contract <= 0
          ? 0
          : requestedQuantity;
      final double total = requestedTotal > 0
          ? requestedTotal
          : contract + quantity;

      final doc = await _collection.add(<String, dynamic>{
        'itemId': itemId,
        'projectId': projectId,
        'kind': kind,
        'status': ApprovalStatus.pending,
        'itemName': itemName,
        'typeName': typeName,
        'unit': unit,
        'contractQuantity': contract,
        'executedQuantity': executedQuantity,
        'requestedQuantity': quantity,
        'requestedTotal': total,
        'requestedPercent': safePercent,
        'requestedDays': requestedDays,
        'approvedPercent': 0,
        'approvedQuantity': 0,
        'approvedDays': 0,
        'note': note,
        'requestedBy': requestedBy,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return doc.id;
    } on ItemApprovalException {
      rethrow;
    } on FirebaseException catch (e) {
      throw ItemApprovalException(
        'تعذر إرسال الطلب إلى مدير الجودة (${e.code}).',
      );
    } catch (e) {
      throw ItemApprovalException(
        'تعذر إرسال الطلب إلى مدير الجودة.\n$e',
      );
    }
  }

  /// موافقة مدير الجودة على كمية إضافية بنسبة لا تتجاوز 20%.
  ///
  /// تُحفظ النسبة والكمية معًا؛ النسبة هي التي يقرأها حساب المباحات
  /// ([ItemAllowance])، والكمية للعرض المفهوم بالوحدات.
  static Future<void> approveExtraQuantity({
    required ItemApproval approval,
    required double percent,
    required String decidedBy,
    String note = '',
  }) async {
    final double safePercent =
        percent.clamp(0, maxExtraQuantityPercent).toDouble();

    final double contract = approval.contractQuantity;
    final double quantity = contract > 0 ? contract * safePercent / 100 : 0;

    final batch = _firestore.batch();

    batch.set(
      _collection.doc(approval.id),
      <String, dynamic>{
        'status': ApprovalStatus.approved,
        'approvedPercent': safePercent,
        'approvedQuantity': quantity,
        'decidedBy': decidedBy,
        'decidedAt': FieldValue.serverTimestamp(),
        if (note.trim().isNotEmpty) 'decisionNote': note.trim(),
      },
      SetOptions(merge: true),
    );

    batch.set(
      _firestore.collection('items').doc(approval.itemId),
      <String, dynamic>{
        'extraQuantityApproved': true,
        'extraQuantityPercent': safePercent,
        'extraQuantityApprovedQuantity': quantity,
        'extraQuantityApprovedAt': FieldValue.serverTimestamp(),
        'extraQuantityApprovedBy': decidedBy,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  /// موافقة على تمديد الزمن بعدد أيام.
  static Future<void> approveTimeExtension({
    required ItemApproval approval,
    required double days,
    required String decidedBy,
    String note = '',
  }) async {
    final itemRef = _firestore.collection('items').doc(approval.itemId);
    final snapshot = await itemRef.get();
    final data = snapshot.data() ?? <String, dynamic>{};

    final allowance = ItemAllowance.fromData(data);
    final base = allowance.effectiveEnd ?? DateTime.now();
    final until = base.add(Duration(days: days.round()));

    final batch = _firestore.batch();

    batch.set(
      _collection.doc(approval.id),
      <String, dynamic>{
        'status': ApprovalStatus.approved,
        'approvedDays': days,
        'decidedBy': decidedBy,
        'decidedAt': FieldValue.serverTimestamp(),
        if (note.trim().isNotEmpty) 'decisionNote': note.trim(),
      },
      SetOptions(merge: true),
    );

    batch.set(
      itemRef,
      <String, dynamic>{
        'timeExtensionDays':
            ItemAllowance._num(data['timeExtensionDays']) + days,
        'timeExtensionUntil': Timestamp.fromDate(until),
        'timeExtensionApprovedAt': FieldValue.serverTimestamp(),
        'timeExtensionApprovedBy': decidedBy,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  /// رفض الطلب (يمكن للمشرف إعادة الطلب لاحقًا).
  static Future<void> reject({
    required ItemApproval approval,
    required String decidedBy,
    String note = '',
  }) async {
    await _collection.doc(approval.id).set(
      <String, dynamic>{
        'status': ApprovalStatus.rejected,
        'decidedBy': decidedBy,
        'decidedAt': FieldValue.serverTimestamp(),
        if (note.trim().isNotEmpty) 'decisionNote': note.trim(),
      },
      SetOptions(merge: true),
    );
  }
}

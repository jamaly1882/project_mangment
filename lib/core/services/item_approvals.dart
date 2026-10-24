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
    this.requestedPercent = 0,
    this.requestedDays = 0,
    this.approvedPercent = 0,
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

  /// النسبة المطلوبة للكمية الإضافية.
  final double requestedPercent;

  /// عدد الأيام المطلوبة للتمديد.
  final double requestedDays;

  /// النسبة الموافق عليها (≤ 20).
  final double approvedPercent;

  /// الأيام الموافق عليها.
  final double approvedDays;

  final String note;
  final DateTime? createdAt;

  bool get isPending => status == ApprovalStatus.pending;

  String get kindLabel => ApprovalKind.label(kind);

  String get statusLabel => ApprovalStatus.label(status);

  static ItemApproval fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final created = data['createdAt'];

    return ItemApproval(
      id: doc.id,
      itemId: (data['itemId'] ?? '').toString(),
      projectId: (data['projectId'] ?? '').toString(),
      kind: (data['kind'] ?? '').toString(),
      status: (data['status'] ?? ApprovalStatus.pending).toString(),
      itemName: (data['itemName'] ?? '').toString(),
      typeName: (data['typeName'] ?? '').toString(),
      unit: (data['unit'] ?? '').toString(),
      contractQuantity: _num(data['contractQuantity']),
      executedQuantity: _num(data['executedQuantity']),
      requestedPercent: _num(data['requestedPercent']),
      requestedDays: _num(data['requestedDays']),
      approvedPercent: _num(data['approvedPercent']),
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
  static Stream<QuerySnapshot<Map<String, dynamic>>> stream({
    String? projectId,
    String? kind,
    String? status,
  }) {
    Query<Map<String, dynamic>> query = _collection;

    if (projectId != null && projectId.isNotEmpty) {
      query = query.where('projectId', isEqualTo: projectId);
    }
    if (kind != null) {
      query = query.where('kind', isEqualTo: kind);
    }
    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }

    return query.snapshots();
  }

  /// ينشئ طلبًا إن لم يكن هناك طلب معلّق من النوع نفسه للبند.
  static Future<String?> request({
    required String itemId,
    required String projectId,
    required String kind,
    String itemName = '',
    String typeName = '',
    String unit = '',
    double contractQuantity = 0,
    double executedQuantity = 0,
    double requestedPercent = 0,
    double requestedDays = 0,
    String note = '',
    String? requestedBy,
  }) async {
    try {
      final existing = await _collection
          .where('itemId', isEqualTo: itemId)
          .where('kind', isEqualTo: kind)
          .where('status', isEqualTo: ApprovalStatus.pending)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) return existing.docs.first.id;

      final doc = await _collection.add(<String, dynamic>{
        'itemId': itemId,
        'projectId': projectId,
        'kind': kind,
        'status': ApprovalStatus.pending,
        'itemName': itemName,
        'typeName': typeName,
        'unit': unit,
        'contractQuantity': contractQuantity,
        'executedQuantity': executedQuantity,
        'requestedPercent': requestedPercent.clamp(0, maxExtraQuantityPercent),
        'requestedDays': requestedDays,
        'approvedPercent': 0,
        'approvedDays': 0,
        'note': note,
        'requestedBy': requestedBy,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return doc.id;
    } catch (e) {
      return null;
    }
  }

  /// موافقة مدير الجودة على كمية إضافية بنسبة لا تتجاوز 20%.
  static Future<void> approveExtraQuantity({
    required ItemApproval approval,
    required double percent,
    required String decidedBy,
    String note = '',
  }) async {
    final safePercent = percent.clamp(0, maxExtraQuantityPercent);

    final batch = _firestore.batch();

    batch.set(
      _collection.doc(approval.id),
      <String, dynamic>{
        'status': ApprovalStatus.approved,
        'approvedPercent': safePercent,
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

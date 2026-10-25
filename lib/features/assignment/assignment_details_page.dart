import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/roles.dart';
import '../../core/services/item_approvals.dart';
import '../../core/services/project_cost_sync.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/cost_lines.dart';
import '../../core/utils/costs.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/cost_lines_editor.dart';
import '../../core/widgets/cost_table_editor.dart';
import '../../core/widgets/cost_widgets.dart';

/// صفحة مشرف البند (وصفحة البند وتفاصيله).
///
/// المشرف يدخل هنا:
///   1) الكمية المنفذة التي أُنجزت فعلًا في البند،
///      فتُضاف إلى الكمية المنفذة السابقة داخل معاملة (Transaction)
///      ولا تتجاوز الكمية التعاقدية.
///   2) التكاليف الفعلية للبند بأقسامها الأربعة:
///      المواد، أجور العمالة، المعدات، المحروقات.
///
/// ساعات العمل والوقود والزيت تُسجَّل كأسطر داخل قسمي المعدات
/// والمحروقات، فلا تُكرَّر في حقول مستقلة (كانت سابقًا بطاقة
/// «الاستهلاك الفعلي»، وقد أُزيلت لأنها ازدواج مع أسطر التكلفة).
///
/// ما يدخله المشرف هو «فعلي»، أما ما يدخله مدير المشروع في صفحة
/// تفاصيل البند فهو «مخطط». وبعد الحفظ تُجمَّع تكاليف المشروع تلقائيًا
/// من بنوده (لا تُدخل تكاليف المشروع يدويًا أبدًا).
///
/// لا تعدّل هذه الصفحة قراءة عدّاد المعدة ولا بيانات التكليف
/// (المشرف والمعدة)؛ فهي من صلاحية مدير المشروع.
class AssignmentDetailsPage extends StatefulWidget {
  final String projectId;
  final String itemId;

  const AssignmentDetailsPage({
    super.key,
    required this.projectId,
    required this.itemId,
  });

  @override
  State<AssignmentDetailsPage> createState() =>
      _AssignmentDetailsPageState();
}

class _AssignmentDetailsPageState extends State<AssignmentDetailsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ============================================================
  // أسطر التكاليف الفعلية (نفس أقسام مدير المشروع الأربعة)
  // ============================================================

  final Map<CostLineKind, CostLinesEditorController> _costEditors =
      <CostLineKind, CostLinesEditorController>{
    for (final schema in CostLineSchema.ordered)
      schema.kind: CostLinesEditorController(schema),
  };

  // ============================================================
  // حقل الكمية المنفذة (يدخله مشرف البند)
  // ============================================================

  final TextEditingController _executedQuantityController =
      TextEditingController();
  bool _savingQuantity = false;

  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  Map<String, dynamic>? _itemData;
  Map<String, dynamic>? _detailsData;
  Map<String, dynamic>? _assignmentData;

  /// مباحات البند: الكمية الإضافية والزمن (من مدير الجودة).
  ItemAllowance? _allowance;

  /// طلب كمية إضافية قيد مراجعة مدير الجودة (إن وُجد).
  ItemApproval? _pendingExtra;

  double? _defaultWorkingHours;
  double? _defaultFuelQuantity;
  double? _defaultOilQuantity;

  /// مجاميع تكاليف المشروع (محسوبة من بنوده).
  ProjectCostTotals? _projectTotals;

  @override
  void initState() {
    super.initState();
    _loadExecutionData();
  }

  @override
  void dispose() {
    for (final editor in _costEditors.values) {
      editor.dispose();
    }

    _executedQuantityController.dispose();

    super.dispose();
  }

  // ============================================================
  // أدوات قراءة البيانات
  // ============================================================

  String _stringValue(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString().trim();
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return null;
    return double.tryParse(value.toString().trim().replaceAll(',', '.'));
  }

  String _formatNumber(dynamic value) {
    final number = _toDouble(value);
    if (number == null) return 'غير محدد';
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  /// الكمية التي تُحسب منها التكلفة الفعلية:
  /// المنفذة إن وُجدت، وإلا التعاقدية.
  double get _costQuantity {
    final item = _itemData ?? const <String, dynamic>{};

    final executed = ProjectCosts.nonNegative(item['executedQuantity']);
    if (executed > 0) return executed;

    return ProjectCosts.nonNegative(item['contractQuantity']);
  }

  /// التكلفة المخططة للبند (ما أدخله مدير المشروع).
  Map<String, dynamic> get _plannedSource {
    final item = _itemData ?? const <String, dynamic>{};
    final details = _detailsData ?? const <String, dynamic>{};

    // تفاصيل البند هي الأصل، ووثيقة البند نسخة محدّثة.
    return ProjectCosts.totalOf(details) > 0 ? details : item;
  }

  double get _plannedItemTotal =>
      ProjectCosts.totalOf(_plannedSource);

  /// الأسطر الفعلية كما هي في المحرّرات الآن.
  CostLines get _actualLines {
    return CostLines(<CostLineKind, List<Map<String, dynamic>>>{
      for (final schema in CostLineSchema.ordered)
        schema.kind: _costEditors[schema.kind]?.lines ??
            const <Map<String, dynamic>>[],
    });
  }

  /// أسطر المخطط كما حددها مدير المشروع (للمقارنة فقط هنا).
  CostLines get _plannedLines => CostLines.fromData(
        _plannedSource,
        contractQuantity: _costQuantity,
        unit: _stringValue(_plannedSource['unit']),
      );

  /// بطاقة مقارنة سطر بسطر بين المخطط وما يسجله المشرف الآن.
  Widget _buildComparisonCard() {
    final plannedLines = _plannedLines;
    final actualLines = _actualLines;

    if (plannedLines.isEmpty && actualLines.isEmpty) {
      return const SizedBox.shrink();
    }

    return CostLinesComparison(
      planned: plannedLines,
      actual: actualLines,
      title: 'مقارنة أسطر التكلفة',
      plannedLabel: 'المخطط',
      actualLabel: 'المسجَّل',
      accent: AppColors.supervisor,
    );
  }

  /// إجمالي التكاليف الفعلية المحفوظة سابقًا.
  double get _savedActualTotal =>
      ProjectCosts.actualTotalOf(_detailsData) > 0
          ? ProjectCosts.actualTotalOf(_detailsData)
          : ProjectCosts.actualTotalOf(_itemData);

  /// لون القسم المقابل.
  Color _accentFor(CostLineKind kind) {
    final key = _categoryKeyOf(kind);

    return ProjectCosts.categories
        .firstWhere(
          (category) => category.key == key,
          orElse: () => ProjectCosts.categories.first,
        )
        .color;
  }

  static String _categoryKeyOf(CostLineKind kind) {
    switch (kind) {
      case CostLineKind.material:
        return 'materials';
      case CostLineKind.labor:
        return 'labor';
      case CostLineKind.equipment:
        return 'equipment';
      case CostLineKind.fuel:
        return 'fuel';
    }
  }

  // ============================================================
  // التكليف: مشرف البند فقط
  // ============================================================

  /// يعيد تكليف المشرف الحالي؛ نتحقق من المستند القياسي أولًا،
  /// ثم ندعم بنودًا أُسندت قديمًا عبر سجلات السائق (لمستخدم حُوّل إلى مشرف).
  Future<Map<String, dynamic>?> _getCurrentAssignment(String uid) async {
    final supervisors = _firestore.collection('item_supervisors');

    final standardDoc = await supervisors.doc(widget.itemId).get();
    if (standardDoc.exists) {
      final data = standardDoc.data() ?? <String, dynamic>{};
      if (data['active'] != false &&
          _stringValue(data['supervisorId']) == uid &&
          _stringValue(data['itemId'], fallback: widget.itemId) ==
              widget.itemId &&
          _stringValue(data['projectId']) == widget.projectId) {
        return data;
      }
    }

    // سجلات سابقة قد تستخدم معرّف مستند مختلفًا.
    final oldAssignments = await supervisors
        .where('itemId', isEqualTo: widget.itemId)
        .get();
    for (final doc in oldAssignments.docs) {
      final data = doc.data();
      if (data['active'] != false &&
          _stringValue(data['supervisorId']) == uid &&
          _stringValue(data['projectId']) == widget.projectId) {
        return data;
      }
    }

    return null;
  }

  /// هل هذا البند مسند إلى حساب المشرف في سجلات السائق القديمة؟
  Future<bool> _hasLegacyAssignment(String uid) async {
    try {
      final legacy = await _firestore
          .collection('item_drivers')
          .where('itemId', isEqualTo: widget.itemId)
          .get();

      for (final doc in legacy.docs) {
        final data = doc.data();
        if (_stringValue(data['driverId']) == uid &&
            _stringValue(data['projectId']) == widget.projectId) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('تعذرت قراءة سجلات التكليف القديمة: $e');
    }

    return false;
  }

  Future<void> _loadExecutionData() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('يجب تسجيل الدخول بحساب مشرف البند أولًا.');
      }

      final userDoc =
          await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? <String, dynamic>{};

      final role = _stringValue(userData['role']).toLowerCase();

      // الحساب القديم `supervisor` والجديد `project_supervisor`
      // والدور القديم `driver` كلها أدوار مشرف ميداني بعد التطبيع؛
      // الاعتماد على المقارنة الحرفية كان يمنع مشرف المشروع الجديد
      // من فتح صفحة البند ويظهر له «هذا الحساب ليس مشرف بند فعلًا».
      if (!userDoc.exists || !AppRoles.isFieldSupervisor(role)) {
        throw Exception(
          'هذا الحساب ليس حساب مشرف مشروع '
          '(${AppRoles.label(role)}). اطلب من مدير إدارة المشاريع '
          'إنشاء حسابك بدور «مشرف المشروع» وربطه بالمشروع، '
          'ثم إسناد البنود إليك.',
        );
      }

      if (userData['active'] != true) {
        throw Exception(
          'حسابك موقوف أو غير مفعّل؛ راجع مسؤول النظام لتفعيل الحساب.',
        );
      }

      var assignment = await _getCurrentAssignment(user.uid);

      final legacyAssignment =
          assignment == null && await _hasLegacyAssignment(user.uid);

      if (assignment == null && !legacyAssignment) {
        throw Exception('هذا البند غير مسند إلى حسابك (أو تم إيقاف التكليف).');
      }

      final itemDoc = await _firestore
          .collection('items')
          .doc(widget.itemId)
          .get();
      if (!itemDoc.exists) {
        throw Exception('البند غير موجود.');
      }
      final item = itemDoc.data() ?? <String, dynamic>{};
      if (_stringValue(item['projectId']) != widget.projectId) {
        throw Exception('هذا البند لا يتبع المشروع المحدد.');
      }

      final detailsDoc = await _firestore
          .collection('item_details')
          .doc(widget.itemId)
          .get();

      final details = detailsDoc.data() ?? <String, dynamic>{};

      if (detailsDoc.exists) {
        if (_stringValue(details['projectId']) != widget.projectId) {
          throw Exception('تفاصيل البند لا تتبع المشروع المحدد.');
        }

        final detailsSupervisor = _stringValue(details['supervisorId']);
        final detailsDriver = _stringValue(details['driverId']);

        if (detailsSupervisor.isNotEmpty &&
            detailsSupervisor != user.uid &&
            detailsDriver != user.uid) {
          throw Exception(
            'مشرف البند المسجل في تفاصيل البند لا يطابق حسابك.',
          );
        }
      }

      _defaultWorkingHours = _toDouble(details['defaultWorkingHours']);
      _defaultFuelQuantity = _toDouble(
        details['defaultFuelQuantity'] ?? details['defaultDieselQuantity'],
      );
      _defaultOilQuantity = _toDouble(details['defaultOilQuantity']);

      // أسطر التكاليف الفعلية المحفوظة، مع ترحيل الرقم المفرد القديم
      // إلى سطر واحد قابل للتعديل.
      final costSource =
          ProjectCosts.actualTotalOf(details) > 0 ? details : item;

      final saved = CostLines.fromData(
        costSource,
        actual: true,
        contractQuantity: _quantityOf(costSource),
        unit: _stringValue(item['unit']),
      );

      for (final schema in CostLineSchema.ordered) {
        _costEditors[schema.kind]?.applyLines(saved[schema.kind]);
      }

      ProjectCostTotals? totals;
      try {
        totals = await ProjectCostSync.totalsFor(widget.projectId);
      } catch (e) {
        debugPrint('تعذر حساب تكاليف المشروع: $e');
      }

      // هل يوجد طلب كمية إضافية قيد المراجعة عند مدير الجودة؟
      ItemApproval? pendingExtra;
      try {
        pendingExtra = await ItemApprovals.pendingFor(
          itemId: widget.itemId,
        );
      } catch (e) {
        debugPrint('تعذر تحميل حالة طلب الكمية الإضافية: $e');
      }

      if (!mounted) return;
      setState(() {
        _itemData = item;
        _pendingExtra = pendingExtra;
        _detailsData = detailsDoc.exists
            ? details
            : null;
        _assignmentData = assignment;
        _projectTotals = totals;
        _allowance = ItemAllowance.fromData(item);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  static double _quantityOf(Map<String, dynamic> data) {
    final executed = ProjectCosts.nonNegative(data['executedQuantity']);
    if (executed > 0) return executed;
    return ProjectCosts.nonNegative(data['contractQuantity']);
  }

  // ============================================================
  // الحفظ: التكاليف الفعلية
  // ============================================================

  Future<void> _saveActualCosts() async {
    if (_saving) return;

    // التحقق من أسطر التكاليف الفعلية إن أدخل المشرف شيئًا منها.
    if (_actualLines.isNotEmpty) {
      final errors = _actualLines.validate();

      if (errors.isNotEmpty) {
        AppWidgets.showWarning(
          context,
          'راجع التكاليف الفعلية:\n' + errors.take(3).join('\n'),
        );
        return;
      }
    }

    final user = _auth.currentUser;
    if (user == null) {
      AppWidgets.showError(context, 'انتهت جلسة تسجيل الدخول؛ سجل الدخول مجددًا.');
      return;
    }

    setState(() => _saving = true);

    try {
      // إعادة فحص التكليف قبل الحفظ حتى لا يستمر المستخدم بعد تغيير الإسناد.
      final assignment = await _getCurrentAssignment(user.uid);
      if (assignment == null && !await _hasLegacyAssignment(user.uid)) {
        throw Exception(
          'لم يعد هذا البند مسندًا إلى حسابك. حدّث الصفحة أو راجع مدير المشروع.',
        );
      }

      final itemDoc = await _firestore
          .collection('items')
          .doc(widget.itemId)
          .get();
      if (!itemDoc.exists ||
          _stringValue(itemDoc.data()?['projectId']) != widget.projectId) {
        throw Exception('تعذر التحقق من البند أو المشروع.');
      }

      final detailsRef =
          _firestore.collection('item_details').doc(widget.itemId);
      final detailsDoc = await detailsRef.get();
      final currentDetails = detailsDoc.data() ?? <String, dynamic>{};

      if (detailsDoc.exists) {
        final assigned = _stringValue(currentDetails['supervisorId']);
        final legacyAssigned = _stringValue(currentDetails['driverId']);

        if (assigned.isNotEmpty &&
            assigned != user.uid &&
            legacyAssigned != user.uid) {
          throw Exception('تفاصيل البند لم تعد مسندة إلى حسابك.');
        }
      }

      // تحديث التكاليف فقط مع إبقاء بيانات الاستهلاك السابقة دون تغيير.
      final detailsUpdate = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final itemUpdate = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // التكاليف الفعلية للبند: أسطر مفصّلة + مجاميع الأقسام.
      Map<String, dynamic> actualData = const <String, dynamic>{};

      if (_actualLines.isNotEmpty) {
        actualData = _actualLines.toSaveData(
          actual: true,
          contractQuantity: _costQuantity,
        );

        detailsUpdate.addAll(actualData);
        itemUpdate.addAll(actualData);

        detailsUpdate[ProjectCosts.actualByField] = user.uid;
        detailsUpdate[ProjectCosts.actualAtField] =
            FieldValue.serverTimestamp();

        itemUpdate[ProjectCosts.actualByField] = user.uid;
        itemUpdate[ProjectCosts.actualAtField] =
            FieldValue.serverTimestamp();
      }

      final batch = _firestore.batch();

      batch.set(detailsRef, detailsUpdate, SetOptions(merge: true));

      batch.set(
        _firestore.collection('items').doc(widget.itemId),
        itemUpdate,
        SetOptions(merge: true),
      );

      await batch.commit();

      // تكاليف المشروع = مجموع بنوده.
      ProjectCostTotals? projectTotals;
      try {
        projectTotals =
            await ProjectCostSync.applyTotals(widget.projectId);

        if (mounted) {
          setState(() => _projectTotals = projectTotals);
        }
      } catch (e) {
        debugPrint('تعذرت مزامنة تكاليف المشروع: $e');
      }

      if (!mounted) return;

      setState(() {
        _detailsData = <String, dynamic>{
          ...currentDetails,
          ...detailsUpdate,
        };
      });

      final actualTotal =
          ProjectCosts.toDouble(actualData[ProjectCosts.actualTotalField]);

      final successMessage = <String>[
        'تم حفظ التكاليف الفعلية بنجاح.',
        if (actualTotal > 0)
          'تكلفة البند الفعلية: '
              '${ProjectCosts.formatMoney(actualTotal)}',
        if (projectTotals != null)
          'إجمالي تكلفة المشروع: '
              '${ProjectCosts.formatMoney(projectTotals.displayTotal)}',
      ].join('\n');

      AppWidgets.showSuccess(context, successMessage);
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showError(context, 'تعذر حفظ التكاليف الفعلية:\n$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ============================================================
  // تسجيل الكمية المنفذة
  // ============================================================

  // ============================================================
  // الكمية الإضافية: الطلب من مدير إدارة الجودة
  // ============================================================

  /// يرسل طلبًا إلى مدير إدارة الجودة ويعيد هل نجح الإرسال.
  ///
  /// كل الطلبات تمر من هنا؛ والفشل يُعرض برسالة عربية صريحة
  /// بدل أن يضيع الطلب بصمت.
  Future<bool> _sendApprovalRequest({
    required String kind,
    required double contractQuantity,
    required double executedQuantity,
    required double totalAfter,
    required double requestedQuantity,
    required double requestedPercent,
    String note = '',
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      if (mounted) {
        AppWidgets.showError(
          context,
          'انتهت جلسة تسجيل الدخول؛ سجل الدخول مجددًا.',
        );
      }
      return false;
    }

    final item = _itemData ?? const <String, dynamic>{};

    try {
      await ItemApprovals.request(
        itemId: widget.itemId,
        projectId: widget.projectId,
        kind: kind,
        itemName: _itemName(item),
        typeName: _stringValue(item['typeName']),
        unit: _stringValue(item['unit']),
        contractQuantity: contractQuantity,
        executedQuantity: executedQuantity,
        requestedQuantity: requestedQuantity,
        requestedTotal: totalAfter,
        requestedPercent: requestedPercent,
        note: note,
        requestedBy: user.uid,
      );
    } on ItemApprovalException catch (error) {
      if (mounted) AppWidgets.showError(context, error.message);
      return false;
    } catch (error) {
      if (mounted) {
        AppWidgets.showError(
          context,
          'تعذر إرسال الطلب إلى مدير الجودة:\n$error',
        );
      }
      return false;
    }

    // تحديث حالة «قيد المراجعة» في الصفحة فورًا.
    ItemApproval? pending;
    try {
      pending = await ItemApprovals.pendingFor(itemId: widget.itemId);
    } catch (_) {
      pending = null;
    }

    if (mounted) setState(() => _pendingExtra = pending);

    return true;
  }

  /// نافذة «كمية إضافية».
  ///
  /// تُفتح في حالتين:
  ///   1) تلقائيًا حين يتجاوز مجموع (المنفذة + المدخلة) الكمية التعاقدية.
  ///   2) من زر «طلب كمية إضافية» في بطاقة البند.
  ///
  /// الكمية المطلوبة تُدخل بالوحدات (لا بالنسبة) لأنها لغة الميدان،
  /// وتُحوَّل إلى نسبة بسقف 20% لحظة الإرسال.
  Future<void> _showExtraQuantityDialog({
    required double suggestedExtra,
    double enteredQuantity = 0,
  }) async {
    final item = _itemData ?? const <String, dynamic>{};
    final unit = _stringValue(item['unit']);
    final allowance =
        _allowance ?? ItemAllowance.fromData(item);
    final double contract = allowance.contractQuantity;
    final double executed = allowance.executedQuantity;

    if (contract <= 0) {
      AppWidgets.showWarning(
        context,
        'الكمية التعاقدية لهذا البند غير محددة، فلا يمكن طلب كمية '
        'إضافية. راجع مدير المشروع لتحديد الكمية التعاقدية أولًا.',
      );
      return;
    }

    // سقف الكمية الإضافية = 20% من الكمية التعاقدية.
    final double maxExtra =
        contract * maxExtraQuantityPercent / 100;

    final double initialExtra =
        suggestedExtra.clamp(0, maxExtra).toDouble();

    final controller = TextEditingController(
      text: initialExtra > 0
          ? ProjectCosts.toEditText(initialExtra)
          : '',
    );
    final noteController = TextEditingController();

    double extra = initialExtra;
    String? errorText;

    final input = await showDialog<_ExtraRequestInput>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final double total = contract + extra;
            final double percent =
                contract > 0 ? extra / contract * 100 : 0;

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.add_chart, color: AppColors.warning),
                  SizedBox(width: 10),
                  Expanded(child: Text('كمية إضافية')),
                ],
              ),
              content: SizedBox(
                width: 430,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'مجموع الكمية المنفذة يتجاوز الكمية التعاقدية '
                        'لهذا البند. أدخل الكمية الإضافية التي تحتاجها '
                        'ويُرسل الطلب إلى مدير إدارة الجودة للموافقة.',
                        style: AppTextStyles.bodySecondary,
                      ),
                      AppSpacing.verticalMd,
                      AppInfoRow(
                        label: 'الكمية التعاقدية',
                        value: '${_formatNumber(contract)} $unit',
                        icon: Icons.assignment_outlined,
                      ),
                      AppSpacing.verticalXs,
                      AppInfoRow(
                        label: 'الكمية المنفذة',
                        value: '${_formatNumber(executed)} $unit',
                        icon: Icons.done_all,
                      ),
                      if (enteredQuantity > 0) ...[
                        AppSpacing.verticalXs,
                        AppInfoRow(
                          label: 'الكمية المدخلة الآن',
                          value:
                              '${_formatNumber(enteredQuantity)} $unit',
                          icon: Icons.add,
                        ),
                      ],
                      AppSpacing.verticalXs,
                      AppInfoRow(
                        label: 'أقصى كمية إضافية مسموحة',
                        value: '${_formatNumber(maxExtra)} $unit '
                            '(${_formatNumber(maxExtraQuantityPercent)}%)',
                        icon: Icons.speed_outlined,
                      ),
                      AppSpacing.verticalMd,
                      TextField(
                        controller: controller,
                        keyboardType:
                            const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'الكمية الإضافية المطلوبة',
                          hintText: 'مثال: 50',
                          suffixText: unit.isEmpty ? null : unit,
                          prefixIcon: const Icon(Icons.add_chart),
                          errorText: errorText,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          final double? parsed = _toDouble(value.trim());

                          setDialogState(() {
                            extra = parsed ?? 0;
                            if (parsed == null || parsed <= 0) {
                              errorText =
                                  'أدخل كمية إضافية أكبر من صفر';
                            } else if (parsed > maxExtra) {
                              errorText =
                                  'الحد الأقصى ${_formatNumber(maxExtra)} '
                                  '$unit';
                            } else {
                              errorText = null;
                            }
                          });
                        },
                      ),
                      AppSpacing.verticalSm,
                      AppInfoRow(
                        label: 'النسبة من الكمية التعاقدية',
                        value: '${_formatNumber(percent)}%',
                        icon: Icons.percent,
                      ),
                      AppSpacing.verticalXs,
                      AppInfoRow(
                        label: 'إجمالي المنفذ بعد الموافقة',
                        value: '${_formatNumber(total)} $unit',
                        icon: Icons.stacked_line_chart,
                      ),
                      AppSpacing.verticalSm,
                      Text(
                        'لا تُحفظ أي كمية الآن؛ بعد موافقة مدير الجودة '
                        'يُضاف إلى الحد المسموح للبند وتستطيع تسجيل '
                        'الكمية من جديد.',
                        style: AppTextStyles.small,
                      ),
                      AppSpacing.verticalMd,
                      TextField(
                        controller: noteController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'سبب الطلب (اختياري)',
                          hintText: 'مثال: زيادة في أطوال الطريق',
                          prefixIcon: Icon(Icons.notes_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final double? parsed =
                        _toDouble(controller.text.trim());

                    if (parsed == null || parsed <= 0) {
                      setDialogState(() {
                        errorText = 'أدخل كمية إضافية أكبر من صفر';
                      });
                      return;
                    }

                    if (parsed > maxExtra) {
                      setDialogState(() {
                        errorText = 'الحد الأقصى '
                            '${_formatNumber(maxExtra)} $unit';
                      });
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      _ExtraRequestInput(
                        extra: parsed,
                        note: noteController.text.trim(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.send),
                  label: const Text('إرسال إلى مدير الجودة'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    noteController.dispose();

    if (!mounted || input == null) return;

    final double percent =
        (input.extra / contract * 100)
            .clamp(0, maxExtraQuantityPercent)
            .toDouble();

    final bool sent = await _sendApprovalRequest(
      kind: ApprovalKind.extraQuantity,
      contractQuantity: contract,
      executedQuantity: executed,
      totalAfter: contract + input.extra,
      requestedQuantity: input.extra,
      requestedPercent: percent,
      note: input.note.isEmpty
          ? 'تجاوزت الكمية المنفذة الكمية التعاقدية'
          : input.note,
    );

    if (!mounted || !sent) return;

    AppWidgets.showSuccess(
      context,
      'تم إرسال طلب كمية إضافية ${_formatNumber(input.extra)} $unit '
      'إلى مدير إدارة الجودة. '
      'لن تُحفظ الكمية حتى تتم الموافقة.',
    );
  }

  /// يضيف الكمية التي يدخلها المشرف إلى `executedQuantity`
  /// في معاملة واحدة، فلا تضيع أي إضافة عند تعدد الأجهزة،
  /// ولا تتجاوز الكمية التعاقدية.
  Future<void> _saveExecutedQuantity() async {
    if (_savingQuantity) return;

    final entered = _toDouble(_executedQuantityController.text);

    if (entered == null || entered <= 0) {
      AppWidgets.showWarning(
        context,
        'أدخل كمية منفذة صحيحة أكبر من صفر.',
      );
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      AppWidgets.showError(
        context,
        'انتهت جلسة تسجيل الدخول؛ سجل الدخول مجددًا.',
      );
      return;
    }

    // ==========================================================
    // قراءة أحدث بيانات البند قبل القرار
    // ==========================================================
    // مدير الجودة قد يكون وافق للتو على كمية إضافية أو رفض الطلب،
    // فالقرار لا يُبنى على بيانات قديمة (كان الطلب يظهر مرتين).
    try {
      final fresh =
          await _firestore.collection('items').doc(widget.itemId).get();
      final data = fresh.data();

      if (fresh.exists && data != null) {
        final freshAllowance = ItemAllowance.fromData(data);

        ItemApproval? pending;
        try {
          pending = await ItemApprovals.pendingFor(itemId: widget.itemId);
        } catch (_) {
          pending = _pendingExtra;
        }

        if (mounted) {
          setState(() {
            _itemData = <String, dynamic>{...?_itemData, ...data};
            _allowance = freshAllowance;
            _pendingExtra = pending;
          });
        }
      }
    } catch (e) {
      debugPrint('تعذر تحديث بيانات البند قبل الحفظ: $e');
    }

    // ==========================================================
    // قبل الكتابة: هل يتجاوز الإدخال الحد المسموح؟
    // ==========================================================
    // إن تجاوز، تُفتح واجهة «كمية إضافية» ويُرسل الطلب إلى مدير
    // الجودة، ولا تُحفظ الكمية حتى يوافق (كما هو مطلوب).
    final allowance =
        _allowance ?? ItemAllowance.fromData(_itemData ?? const {});
    final enteredDouble = entered;

    if (!allowance.isTimeExpired) {
      final plan = ExtraQuantityPlan.of(
        contractQuantity: allowance.contractQuantity,
        executedQuantity: allowance.executedQuantity,
        enteredQuantity: enteredDouble,
        approvedPercent: allowance.extraPercent,
        extraApproved: allowance.extraApproved,
      );

      if (plan.needsRequest) {
        await _showExtraQuantityDialog(
          suggestedExtra: plan.excessQuantity,
          enteredQuantity: enteredDouble,
        );
        return;
      }
    }

    setState(() => _savingQuantity = true);

    // تُعلن قبل try لتكون مرئية داخل catch عند رفع الطلب لمدير الجودة.
    double previousExecuted = 0;
    double newExecuted = 0;
    double contractQuantity = 0;
    bool requestedExtra = false;
    bool requestedTime = false;

    try {
      // إعادة التحقق من التكليف قبل الكتابة.
      final assignment = await _getCurrentAssignment(user.uid);
      if (assignment == null && !await _hasLegacyAssignment(user.uid)) {
        throw Exception(
          'لم يعد هذا البند مسندًا إلى حسابك. راجع مدير المشروع.',
        );
      }

      final itemRef =
          _firestore.collection('items').doc(widget.itemId);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(itemRef);

        if (!snapshot.exists) {
          throw Exception('البند غير موجود.');
        }

        final data = snapshot.data() ?? <String, dynamic>{};

        if (_stringValue(data['projectId']) != widget.projectId) {
          throw Exception('هذا البند لا يتبع المشروع المحدد.');
        }

        contractQuantity =
            ProjectCosts.nonNegative(data['contractQuantity']);
        previousExecuted =
            ProjectCosts.nonNegative(data['executedQuantity']);
        newExecuted = previousExecuted + entered;

        final allowance = ItemAllowance.fromData(data);

        // 1) زمن البند: مدة العقد من أول يوم تنفيذ + أي تمديد معتمد.
        if (allowance.isTimeExpired) {
          requestedTime = true;

          final end = allowance.effectiveEnd;

          throw Exception(
            'انتهى زمن هذا البند'
            '${end == null ? '' : ' في ${_formatDateValue(end)}'}'
            '. رُفع طلب تمديد إلى مدير إدارة الجودة، '
            'ولا يمكن تسجيل كميات حتى تتم الموافقة.',
          );
        }

        // 2) الكمية: التعاقدية، وأي كمية إضافية لن تتجاوز 20% بموافقة
        //    مدير إدارة الجودة.
        if (contractQuantity > 0 && newExecuted > allowance.maxQuantity) {
          final remaining = allowance.remaining;

          if (!allowance.extraApproved) {
            requestedExtra = true;

            throw Exception(
              'الكمية المضافة تتجاوز الكمية التعاقدية. '
              'المتبقي: ${_formatNumber(remaining)} '
              '${_stringValue(data['unit'])}. '
              'رُفع طلب كمية إضافية إلى مدير إدارة الجودة '
              '(الحد الأقصى 20% من الكمية التعاقدية).',
            );
          }

          throw Exception(
            'الكمية المضافة تتجاوز الحد المسموح بعد الكمية الإضافية '
            '(${_formatNumber(allowance.extraPercent)}% من التعاقدية). '
            'المتبقي المسموح: ${_formatNumber(remaining)} '
            '${_stringValue(data['unit'])}',
          );
        }

        final updates = <String, dynamic>{
          'executedQuantity': newExecuted,
          'updatedAt': FieldValue.serverTimestamp(),
          'executionUpdatedBy': user.uid,
          'executionUpdatedAt': FieldValue.serverTimestamp(),
        };

        // أول يوم تنفيذ: يُسجَّل تلقائيًا من أول إدخال للمشرف،
        // ومنه يُحسب تاريخ انتهاء البند = البداية + مدة العقد.
        if (data['executionStartDate'] == null) {
          final start = DateTime.now();

          updates['executionStartDate'] = Timestamp.fromDate(start);
          updates['contractStartDate'] = Timestamp.fromDate(start);

          final days = ProjectCosts.nonNegative(data['durationDays']).round();
          if (days > 0) {
            updates['contractEndDate'] = Timestamp.fromDate(
              start.add(Duration(days: days)),
            );
          }
        }

        // تكلفة التنفيذ = تكلفة الوحدة × الكمية المنفذة الجديدة.
        final unitCost = ProjectCosts.totalUnitCost(data);
        if (unitCost > 0) {
          updates[ProjectCosts.executedCostField] = unitCost * newExecuted;
        }

        transaction.update(itemRef, updates);
      });

      // سجل التنفيذ: يظهر في صفحة المهندس وتقارير التنفيذ.
      final itemData = _itemData ?? const <String, dynamic>{};
      try {
        await _firestore.collection('item_executions').add(
          <String, dynamic>{
            'itemId': widget.itemId,
            'projectId': widget.projectId,
            'projectName': itemData['projectName'],
            'itemName': _itemName(itemData),
            'typeName': itemData['typeName'],
            'executedQuantity': entered,
            'executedQuantityBefore': previousExecuted,
            'executedQuantityAfter': newExecuted,
            'contractQuantity': contractQuantity,
            'unit': _stringValue(itemData['unit']),
            'source': 'supervisor',
            'createdBy': user.uid,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      } catch (e) {
        debugPrint('تعذر تسجيل حركة التنفيذ: $e');
      }

      // مزامنة الكمية المنفذة إلى تفاصيل البند.
      try {
        await _firestore.collection('item_details').doc(widget.itemId).set(
          <String, dynamic>{
            'executedQuantity': newExecuted,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (e) {
        debugPrint('تعذر مزامنة الكمية في تفاصيل البند: $e');
      }

      // تحديث الحالة المحلية فورًا.
      if (mounted) {
        setState(() {
          _itemData = <String, dynamic>{
            ...(_itemData ?? const <String, dynamic>{}),
            'executedQuantity': newExecuted,
          };
          _detailsData = <String, dynamic>{
            ...(_detailsData ?? const <String, dynamic>{}),
            'executedQuantity': newExecuted,
          };
        });
      }

      ProjectCostTotals? projectTotals;
      try {
        projectTotals = await ProjectCostSync.applyTotals(widget.projectId);
      } catch (e) {
        debugPrint('تعذرت مزامنة تكاليف المشروع: $e');
      }

      _executedQuantityController.clear();

      if (!mounted) return;

      if (projectTotals != null) {
        setState(() => _projectTotals = projectTotals);
      }

      AppWidgets.showSuccess(
        context,
        'تم تسجيل الكمية المنفذة: ${_formatNumber(entered)} '
        '${_stringValue(_itemData?['unit'])}.\n'
        'إجمالي المنفذ بعد الإضافة: '
        '${_formatNumber(newExecuted)} '
        '${_stringValue(_itemData?['unit'])}',
      );
    } catch (e) {
      // رفع الطلب إلى مدير إدارة الجودة إن كان السبب كمية أو زمنًا.
      if (requestedExtra || requestedTime) {
        final double excess = requestedExtra
            ? (newExecuted - contractQuantity)
                .clamp(0, double.infinity)
                .toDouble()
            : 0;
        final double percent = requestedExtra && contractQuantity > 0
            ? (excess / contractQuantity * 100)
                .clamp(0, maxExtraQuantityPercent)
                .toDouble()
            : 0;

        await _sendApprovalRequest(
          kind: requestedExtra
              ? ApprovalKind.extraQuantity
              : ApprovalKind.timeExtension,
          contractQuantity: contractQuantity,
          executedQuantity: previousExecuted,
          totalAfter: newExecuted,
          requestedQuantity: excess,
          requestedPercent: percent,
          note: requestedExtra
              ? 'تجاوزت الكمية المنفذة الكمية التعاقدية'
              : 'انتهى زمن البند',
        );
      }

      if (!mounted) return;
      AppWidgets.showError(
        context,
        'تعذر تسجيل الكمية المنفذة:\n'
        '${e.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      if (mounted) setState(() => _savingQuantity = false);
    }
  }

  /// تنسيق تاريخ للعرض داخل الرسائل.
  String _formatDateValue(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  // ============================================================
  // العرض
  // ============================================================

  String _itemName(Map<String, dynamic> item) {
    final name = _stringValue(item['name']);
    if (name.isNotEmpty) return name;
    final definition = _stringValue(item['itemDefinitionName']);
    if (definition.isNotEmpty) return definition;
    return _stringValue(item['typeName'], fallback: 'بدون اسم');
  }

  String _assigneeName(Map<String, dynamic> details) {
    final name = _stringValue(details['supervisorName']);
    if (name.isNotEmpty) return name;
    return _stringValue(details['driverName'], fallback: 'غير محدد');
  }

  // ============================================================
  // بطاقة تسجيل الكمية المنفذة
  // ============================================================

  Widget _buildExecutionCard() {
    final item = _itemData ?? const <String, dynamic>{};
    final unit = _stringValue(item['unit']);
    final allowance =
        _allowance ?? ItemAllowance.fromData(item);
    final contract = allowance.contractQuantity;
    final executed = allowance.executedQuantity;
    final maxQuantity = allowance.maxQuantity;

    final remaining = maxQuantity.isFinite
        ? (maxQuantity - executed).clamp(0.0, double.infinity).toDouble()
        : null;

    final progress = contract <= 0
        ? 0.0
        : (executed / contract).clamp(0.0, 1.0).toDouble();

    // «اكتملت» تعني استهلاك كل المسموح بعد الكمية الإضافية المعتمدة.
    final completed = maxQuantity.isFinite && executed >= maxQuantity;
    final timeExpired = allowance.isTimeExpired;
    final start = allowance.contractStart;
    final end = allowance.effectiveEnd;

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if ((_allowance?.extraApproved ?? false) ||
              (_allowance?.extensionDays ?? 0) > 0) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.verified_outlined,
                    color: AppColors.success,
                    size: 20,
                  ),
                  AppSpacing.horizontalSm,
                  Expanded(
                    child: Text(
                      [
                        if (_allowance?.extraApproved ?? false)
                          'سمح لك مدير الجودة بإدخال كمية إضافية حتى '
                              '${_formatNumber(_allowance!.extraPercent)}% '
                              'من الكمية التعاقدية.',
                        if ((_allowance?.extensionDays ?? 0) > 0)
                          'تم تمديد زمن البند '
                              '${_formatNumber(_allowance!.extensionDays)} يومًا.',
                      ].join(' '),
                      style: AppTextStyles.small.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const AppSectionTitle(
            title: 'تسجيل الكمية المنفذة',
            subtitle:
                'أدخل الكمية التي نفذتها في هذا البند؛ تُضاف إلى الكمية '
                'المنفذة السابقة ولا تتجاوز الكمية التعاقدية (إلا بكمية '
                'إضافية معتمدة من مدير الجودة بحد 20%)، وتُحدَّث معها '
                'تكلفة التنفيذ وتكاليف المشروع تلقائيًا. '
                'أول إدخال يسجّل تاريخ بداية البند ويُحسب منه تاريخ الانتهاء.',
            icon: Icons.playlist_add_check,
          ),
          AppInfoRow(
            label: 'الكمية التعاقدية',
            value: contract <= 0
                ? 'غير محددة'
                : '${_formatNumber(contract)} $unit',
            icon: Icons.assignment_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'الكمية المنفذة',
            value: '${_formatNumber(executed)} $unit',
            icon: Icons.done_all,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'المتبقي',
            value: remaining == null
                ? 'غير محدد'
                : '${_formatNumber(remaining)} $unit',
            icon: Icons.pending_actions_outlined,
          ),
          if (start != null) ...[
            AppSpacing.verticalSm,
            AppInfoRow(
              label: 'أول يوم تنفيذ (بداية البند)',
              value: _formatDateValue(start),
              icon: Icons.event_available_outlined,
            ),
          ],
          if (end != null) ...[
            AppSpacing.verticalSm,
            AppInfoRow(
              label: 'تاريخ انتهاء البند',
              value: _formatDateValue(end) +
                  (allowance.extensionDays > 0 ? ' (بعد تمديد)' : ''),
              icon: Icons.event_busy_outlined,
            ),
          ],
          if (allowance.extraApproved) ...[
            AppSpacing.verticalSm,
            AppInfoRow(
              label: 'كمية إضافية معتمدة من مدير الجودة',
              value: '+${_formatNumber(allowance.extraAllowance)} $unit '
                  '(${_formatNumber(allowance.extraPercent)}%)',
              icon: Icons.verified_outlined,
            ),
          ],
          if (_pendingExtra != null) ...[
            AppSpacing.verticalSm,
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.hourglass_top,
                    color: AppColors.warning,
                    size: 20,
                  ),
                  AppSpacing.horizontalSm,
                  Expanded(
                    child: Text(
                      'طلب كمية إضافية قيد مراجعة مدير إدارة الجودة: '
                      '+${_formatNumber(_pendingExtra!.effectiveQuantity)} '
                      '$unit '
                      '(${_formatNumber(_pendingExtra!.effectivePercent)}%). '
                      'لا يمكن تجاوز الكمية التعاقدية حتى تتم الموافقة.',
                      style: AppTextStyles.small.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!allowance.extraApproved && allowance.isOverContract) ...[
            AppSpacing.verticalSm,
            Text(
              'الكمية المنفذة تجاوزت الكمية التعاقدية دون موافقة. '
              'راجع مدير إدارة الجودة.',
              style: AppTextStyles.small.copyWith(color: AppColors.danger),
            ),
          ],
          if (timeExpired) ...[
            AppSpacing.verticalSm,
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'انتهى زمن هذا البند. رُفع طلب تمديد إلى مدير إدارة '
                'الجودة، ولا يمكن تسجيل كميات حتى تتم الموافقة.',
                style: AppTextStyles.small,
              ),
            ),
          ],
          AppSpacing.verticalMd,
          AppProgress(
            value: progress,
            label: 'نسبة التنفيذ',
            progressColor: AppColors.supervisor,
          ),
          AppSpacing.verticalMd,
          AppNumberField(
            controller: _executedQuantityController,
            label: 'الكمية المنفذة المضافة',
            hint: 'أدخل الكمية التي أنجزتها الآن',
            suffixText: unit.isEmpty ? null : unit,
            prefixIcon: Icons.add_chart,
            enabled: !completed && !timeExpired,
          ),
          if (completed) ...[
            AppSpacing.verticalSm,
            Text(
              'اكتملت الكمية التعاقدية لهذا البند.',
              style: AppTextStyles.small.copyWith(color: AppColors.success),
              textAlign: TextAlign.center,
            ),
          ],
          AppSpacing.verticalMd,
          AppButton(
            label: 'إضافة الكمية المنفذة',
            icon: Icons.add_task,
            expanded: true,
            loading: _savingQuantity,
            onPressed: completed || timeExpired || _savingQuantity
                ? null
                : _saveExecutedQuantity,
          ),
          if (completed && _pendingExtra == null) ...[
            AppSpacing.verticalSm,
            Text(
              'استُهلكت الكمية المسموحة لهذا البند. إن كانت لديك كمية '
              'أخرى فاطلب كمية إضافية من مدير الجودة.',
              style: AppTextStyles.small,
              textAlign: TextAlign.center,
            ),
          ],
          if (contract > 0 && !timeExpired) ...[
            AppSpacing.verticalSm,
            AppOutlinedButton(
              label: _pendingExtra == null
                  ? 'طلب كمية إضافية'
                  : 'طلب كمية إضافية (قيد المراجعة)',
              icon: Icons.add_chart_outlined,
              expanded: true,
              onPressed: _savingQuantity || _pendingExtra != null
                  ? null
                  : () => _showExtraQuantityDialog(
                        suggestedExtra: 0,
                      ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemCard() {
    final item = _itemData ?? <String, dynamic>{};
    final details = _detailsData ?? <String, dynamic>{};
    final unit = _stringValue(item['unit'], fallback: '');
    final quantity = _toDouble(item['contractQuantity']);
    final executed = _toDouble(item['executedQuantity']);
    final remaining = quantity == null || executed == null
        ? null
        : (quantity - executed).clamp(0, double.infinity).toDouble();
    // قد يعمل على البند أكثر من معدة.
    final equipmentNames = <String>[];
    final rawEquipmentNames = details['equipmentNames'];
    if (rawEquipmentNames is Iterable) {
      for (final value in rawEquipmentNames) {
        final name = (value ?? '').toString().trim();
        if (name.isNotEmpty) equipmentNames.add(name);
      }
    }
    if (equipmentNames.isEmpty) {
      final single = _stringValue(details['equipmentName']);
      if (single.isNotEmpty) equipmentNames.add(single);
    }

    final equipmentName = equipmentNames.isEmpty
        ? 'غير محددة'
        : equipmentNames.join(' + ');
    final equipmentCode = _stringValue(details['equipmentCode'], fallback: '—');
    final equipmentWorkUnit =
        _stringValue(details['equipmentWorkUnit'], fallback: 'غير محددة');
    final meter =
        _toDouble(details['equipmentCurrentMeterAtAssignment']);

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(
            title: _itemName(item),
            subtitle: 'بيانات البند والتكاليف الفعلية',
            icon: Icons.supervisor_account_outlined,
          ),
          AppSpacing.verticalMd,
          AppInfoRow(
            label: 'مشرف البند',
            value: _assigneeName(details),
            icon: Icons.person_outline,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'حالة التكليف',
            value: _assignmentData?['active'] == true
                ? 'نشط'
                : 'نشط من سجل قديم',
            icon: Icons.person_outline,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'نوع البند',
            value: _stringValue(item['typeName'], fallback: 'غير محدد'),
            icon: Icons.category_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'المشروع',
            value: _stringValue(
              item['projectName'],
              fallback: widget.projectId,
            ),
            icon: Icons.business_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'الكمية التعاقدية',
            value: quantity == null
                ? 'غير محددة'
                : '${_formatNumber(quantity)} $unit',
            icon: Icons.assignment_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'الكمية المنفذة المسجلة',
            value: executed == null
                ? 'لم يسجل بعد'
                : '${_formatNumber(executed)} $unit',
            icon: Icons.engineering_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'المتبقي من الكمية التعاقدية',
            value: remaining == null
                ? 'غير محدد'
                : '${_formatNumber(remaining)} $unit',
            icon: Icons.pending_actions_outlined,
          ),
          const Divider(height: 28),
          const AppSectionTitle(
            title: 'المعدة المسندة',
            icon: Icons.precision_manufacturing_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: equipmentNames.length > 1
                ? 'المعدات (${equipmentNames.length})'
                : 'اسم المعدة',
            value: equipmentName,
            icon: Icons.construction_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'كود المعدة',
            value: equipmentCode,
            icon: Icons.tag_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'وحدة عمل المعدة',
            value: equipmentWorkUnit,
            icon: Icons.speed_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'قراءة العداد وقت الإسناد',
            value: meter == null ? 'غير مسجلة' : _formatNumber(meter),
            icon: Icons.speed_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildLimitsCard() {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'الكميات المخططة للتكليف',
            icon: Icons.rule_outlined,
          ),
          AppSpacing.verticalMd,
          AppInfoRow(
            label: 'الوقود المخطط',
            value: _defaultFuelQuantity == null
                ? 'غير محدد'
                : '${_formatNumber(_defaultFuelQuantity)} لتر',
            icon: Icons.local_gas_station_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'الزيت المخطط',
            value: _defaultOilQuantity == null
                ? 'غير محدد'
                : '${_formatNumber(_defaultOilQuantity)} لتر',
            icon: Icons.oil_barrel_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'ساعات العمل المخططة',
            value: _defaultWorkingHours == null
                ? 'غير محددة'
                : '${_formatNumber(_defaultWorkingHours)} ساعة',
            icon: Icons.schedule_outlined,
          ),
          AppSpacing.verticalMd,
          const Text(
            'هذه الكميات المخططة من مدير المشروع للمقارنة فقط. '
            'الفعلي تسجّله في بطاقة «الكمية المنفذة» وأسطر التكاليف '
            'أدناه (ساعات العمل والوقود والزيت سطرًا سطرًا)، وقراءة '
            'عدّاد المعدة تبقى بيد إدارة الحركة.',
            style: AppTextStyles.bodySecondary,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // التكاليف الفعلية للبند + تكاليف المشروع
  // ============================================================

  Widget _buildCostsCard() {
    final lines = _actualLines;
    final planned = ProjectCosts.breakdownOf(_plannedSource);
    final plannedTotal = _plannedItemTotal;
    final actualTotal = lines.grandTotal;
    final savedActual = _savedActualTotal;
    final unit = _stringValue(_itemData?['unit']);
    final quantity = _costQuantity;
    final difference = actualTotal - plannedTotal;

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'التكاليف الفعلية للبند',
            subtitle:
                'أنت تسجّل المستهلك فعليًا: سطر لكل مادة أو مهنة أو معدة '
                'أو نوع وقود. أرقام مدير المشروع تبقى كما هي للمقارنة.',
            icon: Icons.account_balance_wallet_outlined,
          ),
          AppSpacing.verticalSm,
          Text(
            'الكمية المحسوب عليها الإجمالي: '
            '${_formatNumber(quantity)} $unit\n'
            'المخطط لهذا البند (إدخال مدير المشروع): '
            '${ProjectCosts.formatMoney(plannedTotal)}',
            style: AppTextStyles.bodySecondary,
          ),
          AppSpacing.verticalSm,
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.price_change_outlined,
                  color: AppColors.info,
                ),
                AppSpacing.horizontalSm,
                Expanded(
                  child: Text(
                    'الأسعار منقولة من مدير إدارة الجودة وتظهر لك '
                    'للقراءة فقط — أدخل الكميات.',
                    style: AppTextStyles.bodySecondary,
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.verticalMd,

          // جداول الاختيار: علّم ✓ على السطر ثم أدخل الكمية/العدد والمدة،
          // فتظهر التكلفة. الأسعار منقولة من إدارة الجودة (مقفلة).
          for (final schema in CostLineSchema.ordered) ...[
            CostTableEditor(
              schema: schema,
              controller: _costEditors[schema.kind]!,
              priceEditable: false,
              // نفس تجربة مدير الجودة: القسم يبدأ فارغًا والبحث يكشف الأسطر.
              searchFirst: true,
              quantitySelection: false,
              // الإضافة من البحث تبدأ بكمية ١ فتظهر التكلفة فورًا.
              autoQuantityOnAdd: true,
              trailingNote: 'ابحث بالاسم ثم اضغط ＋ لإضافة السطر، '
                  'وأدخل الكميات؛ السعر من إدارة الجودة — للقراءة فقط.',
              accent: _accentFor(schema.kind),
              onChanged: () {
                if (mounted) setState(() {});
              },
            ),
            AppSpacing.verticalMd,
          ],

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.supervisor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppInfoRow(
                  label: 'إجمالي تكلفتك الفعلية لهذا البند',
                  value: ProjectCosts.formatMoney(actualTotal),
                  icon: Icons.payments_outlined,
                ),
                if (savedActual > 0 &&
                    (savedActual - actualTotal).abs() >= 0.01) ...[
                  AppSpacing.verticalXs,
                  AppInfoRow(
                    label: 'آخر إجماليات محفوظة',
                    value: ProjectCosts.formatMoney(savedActual),
                    icon: Icons.history,
                  ),
                ],
                if (actualTotal > 0 && plannedTotal > 0) ...[
                  AppSpacing.verticalXs,
                  AppInfoRow(
                    label: difference >= 0
                        ? 'زيادة عن المخطط'
                        : 'أقل من المخطط',
                    value: ProjectCosts.formatMoney(difference.abs()),
                    icon: difference > 0
                        ? Icons.trending_up_outlined
                        : Icons.trending_down_outlined,
                  ),
                  AppSpacing.verticalXs,
                  AppProgress(
                    value: (actualTotal / plannedTotal)
                        .clamp(0.0, 1.0)
                        .toDouble(),
                    label: 'الفعلي مقابل المخطط',
                    height: 8,
                  ),
                ],
              ],
            ),
          ),
          AppSpacing.verticalMd,
          CostSummaryCard(
            title: 'أقسام التكلفة: الفعلي مقابل المخطط',
            breakdown: lines.categoryTotals(),
            reference: planned,
            referenceLabel: 'المخطط',
            total: actualTotal,
            icon: Icons.swap_horiz,
          ),
          AppSpacing.verticalMd,
          _buildProjectCostsCard(),
        ],
      ),
    );
  }

  Widget _buildProjectCostsCard() {
    final totals = _projectTotals;

    if (totals == null) {
      return const AppLoading(message: 'جاري حساب تكاليف المشروع...');
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'تكاليف المشروع بعد حفظك',
            subtitle:
                'مجموع تكاليف كل بنود المشروع، تُحسب تلقائيًا.',
            icon: Icons.business_outlined,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'المخطط للمشروع',
            value: ProjectCosts.formatMoney(totals.total),
            icon: Icons.timeline_outlined,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'الفعلي المسجل في البنود',
            value: ProjectCosts.formatMoney(totals.actualTotal),
            icon: Icons.check_circle_outline,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'إجمالي تكلفة المشروع المعتمد',
            value: ProjectCosts.formatMoney(totals.displayTotal),
            icon: Icons.payments_outlined,
          ),
          AppSpacing.verticalSm,
          Text(
            'عدد بنود المشروع: ${totals.itemCount}، '
            'ولـ ${totals.costedItemCount} بند تكلفة مخططة، '
            'ولـ ${totals.actualItemCount} بند تكلفة فعلية. '
            'تُجمَّع هذه الأرقام تلقائيًا من البنود ولا تُدخل يدويًا.',
            style: AppTextStyles.small,
          ),
        ],
      ),
    );
  }

  Widget _buildSaveCard() {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            label: _saving
                ? 'جارٍ الحفظ...'
                : 'حفظ التكاليف الفعلية',
            icon: Icons.save_outlined,
            loading: _saving,
            expanded: true,
            onPressed: _saving ? null : _saveActualCosts,
          ),
          AppSpacing.verticalSm,
          const Text(
            'بعد الحفظ تُحدَّث تكاليف المشروع تلقائيًا من بنوده.',
            style: AppTextStyles.small,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'صفحة البند: الكميات المنفذة والتكاليف',
      showBackButton: true,
      child: _loading
          ? const AppLoading(
              message: 'جارٍ التحقق من التكليف وتحميل التفاصيل...',
            )
          : _errorMessage != null
              ? AppPage(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            size: 56,
                            color: AppColors.warning,
                          ),
                          AppSpacing.verticalMd,
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.body,
                          ),
                          AppSpacing.verticalLg,
                          AppButton(
                            label: 'إعادة المحاولة',
                            icon: Icons.refresh,
                            expanded: true,
                            onPressed: _loadExecutionData,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : AppPage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildItemCard(),
                      AppSpacing.verticalMd,
                      _buildExecutionCard(),
                      AppSpacing.verticalMd,
                      _buildCostsCard(),
                      AppSpacing.verticalMd,
                      _buildComparisonCard(),
                      AppSpacing.verticalMd,
                      _buildLimitsCard(),
                      AppSpacing.verticalMd,
                      _buildSaveCard(),
                      AppSpacing.verticalXl,
                    ],
                  ),
                ),
    );
  }
}

/// نتيجة نافذة «كمية إضافية»: الكمية المطلوبة بالوحدات وسبب الطلب.
class _ExtraRequestInput {
  const _ExtraRequestInput({
    required this.extra,
    required this.note,
  });

  final double extra;
  final String note;
}

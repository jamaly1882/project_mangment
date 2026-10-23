import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/roles.dart';
import '../../core/services/project_cost_sync.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/cost_lines.dart';
import '../../core/utils/costs.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/cost_lines_editor.dart';
import '../../core/widgets/cost_widgets.dart';

/// صفحة مشرف البند (وصفحة البند وتفاصيله).
///
/// المشرف يدخل هنا:
///   1) الكمية المنفذة التي أُنجزت فعلًا في البند،
///      فتُضاف إلى الكمية المنفذة السابقة داخل معاملة (Transaction)
///      ولا تتجاوز الكمية التعاقدية.
///   2) الاستهلاك الفعلي: ساعات التنفيذ والوقود والزيت المستهلك.
///   3) التكاليف الفعلية للبند بأقسامها الأربعة:
///      المواد، أجور العمالة، المعدات، المحروقات.
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

  /// خيارات الاختيار من بيانات النظام (المواد وحصر المعدات).
  List<CostPickerOption> _materialOptions = const <CostPickerOption>[];
  List<CostPickerOption> _equipmentOptions = const <CostPickerOption>[];

  // ============================================================
  // حقول التنفيذ والاستهلاك الفعلي (يدخلها مشرف البند)
  // ============================================================

  final TextEditingController _executedQuantityController =
      TextEditingController();
  final TextEditingController _workingHoursController = TextEditingController();
  final TextEditingController _fuelConsumedController = TextEditingController();
  final TextEditingController _oilConsumedController = TextEditingController();

  bool _savingQuantity = false;
  bool _savingConsumption = false;

  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  Map<String, dynamic>? _itemData;
  Map<String, dynamic>? _detailsData;
  Map<String, dynamic>? _assignmentData;

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
    _workingHoursController.dispose();
    _fuelConsumedController.dispose();
    _oilConsumedController.dispose();

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

  /// يضع قيمة رقمية محفوظة في حقل نصي دون كتابة «null».
  void _setControllerValue(TextEditingController controller, dynamic value) {
    final number = _toDouble(value);
    if (number == null || number <= 0) {
      controller.text = '';
      return;
    }

    controller.text = number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toString();
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

      // الاستهلاك الفعلي المحفوظ سابقًا (ساعات / وقود / زيت).
      _setControllerValue(
        _workingHoursController,
        details['executedWorkingHours'],
      );
      _setControllerValue(
        _fuelConsumedController,
        details['consumedFuelQuantity'],
      );
      _setControllerValue(
        _oilConsumedController,
        details['consumedOilQuantity'],
      );

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

      // خيارات الأسطر: المواد وحصر المعدات.
      try {
        final materialsSnapshot =
            await _firestore.collection('materials').get();

        final options = <CostPickerOption>[
          for (final doc in materialsSnapshot.docs)
            CostPickerOption(
              id: doc.id,
              label: _stringValue(
                doc.data()['name'],
                fallback: 'مادة بدون اسم',
              ),
            ),
        ]..sort((a, b) => a.label.compareTo(b.label));

        _materialOptions = options;
      } catch (e) {
        debugPrint('تعذر تحميل المواد لأسطر التكلفة: $e');
      }

      try {
        final equipmentSnapshot = await _firestore
            .collection('equipment')
            .where('status', isEqualTo: 'active')
            .get();

        _equipmentOptions = <CostPickerOption>[
          for (final doc in equipmentSnapshot.docs)
            CostPickerOption(
              id: doc.id,
              label: '${_stringValue(doc.data()['code'], fallback: '—')} — '
                  '${_stringValue(doc.data()['name'], fallback: _stringValue(doc.data()['type'], fallback: 'معدة'))}',
            ),
        ]..sort((a, b) => a.label.compareTo(b.label));
      } catch (e) {
        debugPrint('تعذر تحميل المعدات لأسطر التكلفة: $e');
      }

      ProjectCostTotals? totals;
      try {
        totals = await ProjectCostSync.totalsFor(widget.projectId);
      } catch (e) {
        debugPrint('تعذر حساب تكاليف المشروع: $e');
      }

      if (!mounted) return;
      setState(() {
        _itemData = item;
        _detailsData = detailsDoc.exists
            ? details
            : null;
        _assignmentData = assignment;
        _projectTotals = totals;
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

    setState(() => _savingQuantity = true);

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

      double previousExecuted = 0;
      double newExecuted = 0;
      double contractQuantity = 0;

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

        if (contractQuantity > 0 && newExecuted > contractQuantity) {
          final remaining = (contractQuantity - previousExecuted)
              .clamp(0.0, double.infinity)
              .toDouble();

          throw Exception(
            'الكمية المضافة تتجاوز الكمية التعاقدية. '
            'المتبقي: ${_formatNumber(remaining)} '
            '${_stringValue(data['unit'])}',
          );
        }

        final updates = <String, dynamic>{
          'executedQuantity': newExecuted,
          'updatedAt': FieldValue.serverTimestamp(),
          'executionUpdatedBy': user.uid,
          'executionUpdatedAt': FieldValue.serverTimestamp(),
        };

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

  // ============================================================
  // حفظ الاستهلاك الفعلي (ساعات / وقود / زيت)
  // ============================================================

  Future<void> _saveConsumption() async {
    if (_savingConsumption) return;

    final rawValues = <String, String>{
      'executedWorkingHours': _workingHoursController.text.trim(),
      'consumedFuelQuantity': _fuelConsumedController.text.trim(),
      'consumedOilQuantity': _oilConsumedController.text.trim(),
    };

    final values = <String, double>{};

    for (final entry in rawValues.entries) {
      if (entry.value.isEmpty) continue;

      final parsed = _toDouble(entry.value);
      if (parsed == null || parsed < 0) {
        AppWidgets.showWarning(
          context,
          'أدخل أرقامًا صحيحة غير سالبة في حقول الاستهلاك.',
        );
        return;
      }

      values[entry.key] = parsed;
    }

    if (values.isEmpty) {
      AppWidgets.showWarning(
        context,
        'أدخل ساعات التنفيذ أو الوقود أو الزيت المستهلك أولًا.',
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

    setState(() => _savingConsumption = true);

    try {
      final assignment = await _getCurrentAssignment(user.uid);
      if (assignment == null && !await _hasLegacyAssignment(user.uid)) {
        throw Exception(
          'لم يعد هذا البند مسندًا إلى حسابك. راجع مدير المشروع.',
        );
      }

      final update = <String, dynamic>{
        ...values,
        'consumptionUpdatedBy': user.uid,
        'consumptionUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('item_details').doc(widget.itemId).set(
            update,
            SetOptions(merge: true),
          );

      if (!mounted) return;

      setState(() {
        _detailsData = <String, dynamic>{
          ...(_detailsData ?? const <String, dynamic>{}),
          ...values,
        };
      });

      AppWidgets.showSuccess(
        context,
        'تم حفظ الاستهلاك الفعلي للبند.',
      );
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showError(
        context,
        'تعذر حفظ الاستهلاك الفعلي:\n'
        '${e.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      if (mounted) setState(() => _savingConsumption = false);
    }
  }

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
    final item = _itemData ?? <String, dynamic>{};
    final unit = _stringValue(item['unit']);
    final contract = ProjectCosts.nonNegative(item['contractQuantity']);
    final executed = ProjectCosts.nonNegative(item['executedQuantity']);
    final remaining = contract > 0
        ? (contract - executed).clamp(0.0, double.infinity).toDouble()
        : null;
    final progress = contract <= 0
        ? 0.0
        : (executed / contract).clamp(0.0, 1.0).toDouble();
    final completed = contract > 0 && executed >= contract;

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'تسجيل الكمية المنفذة',
            subtitle:
                'أدخل الكمية التي نفذتها في هذا البند؛ تُضاف إلى الكمية '
                'المنفذة السابقة ولا تتجاوز الكمية التعاقدية، وتُحدَّث '
                'معها تكلفة التنفيذ وتكاليف المشروع تلقائيًا.',
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
            label: 'الكمية المنفذة المسجلة',
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
            enabled: !completed,
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
            onPressed: completed || _savingQuantity
                ? null
                : _saveExecutedQuantity,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // بطاقة الاستهلاك الفعلي
  // ============================================================

  Widget _buildConsumptionCard() {
    final details = _detailsData ?? <String, dynamic>{};

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'الاستهلاك الفعلي للبند',
            subtitle:
                'سجّل ساعات التنفيذ والوقود والزيت المستهلك فعلًا؛ '
                'تظهر هذه القيم في بطاقة البند لدى لوحة المشرف.',
            icon: Icons.local_gas_station_outlined,
          ),
          AppNumberField(
            controller: _workingHoursController,
            label: 'ساعات التنفيذ الفعلية',
            suffixText: 'ساعة',
            prefixIcon: Icons.schedule_outlined,
          ),
          AppSpacing.verticalSm,
          AppNumberField(
            controller: _fuelConsumedController,
            label: 'الوقود المستهلك',
            suffixText: 'لتر',
            prefixIcon: Icons.local_gas_station_outlined,
          ),
          AppSpacing.verticalSm,
          AppNumberField(
            controller: _oilConsumedController,
            label: 'الزيت المستهلك',
            suffixText: 'لتر',
            prefixIcon: Icons.oil_barrel_outlined,
          ),
          AppSpacing.verticalSm,
          if (_defaultWorkingHours != null ||
              _defaultFuelQuantity != null ||
              _defaultOilQuantity != null)
            Text(
              'المخطط من مدير المشروع: '
              '${_defaultWorkingHours == null ? '—' : _formatNumber(_defaultWorkingHours)} ساعة، '
              '${_defaultFuelQuantity == null ? '—' : _formatNumber(_defaultFuelQuantity)} لتر وقود، '
              '${_defaultOilQuantity == null ? '—' : _formatNumber(_defaultOilQuantity)} لتر زيت.',
              style: AppTextStyles.small,
            ),
          if (_stringValue(details['consumptionUpdatedBy']).isNotEmpty) ...[
            AppSpacing.verticalXs,
            Text(
              'آخر حفظ للاستهلاك: تم من حسابك.',
              style: AppTextStyles.small,
            ),
          ],
          AppSpacing.verticalMd,
          AppButton(
            label: 'حفظ الاستهلاك الفعلي',
            icon: Icons.save_outlined,
            expanded: true,
            loading: _savingConsumption,
            onPressed:
                _savingConsumption ? null : _saveConsumption,
          ),
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
    final equipmentName =
        _stringValue(details['equipmentName'], fallback: 'غير محددة');
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
            label: 'اسم المعدة',
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
            'هذه الكميات المخططة من مدير المشروع للمقارنة. '
            'ما تسجله أنت في بطاقتي «الكمية المنفذة» و«الاستهلاك '
            'الفعلي» هو الفعلي، وقراءة عدّاد المعدة تبقى بيد '
            'إدارة الحركة.',
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
          AppSpacing.verticalMd,

          for (final schema in CostLineSchema.ordered) ...[
            CostLinesEditor(
              schema: schema,
              controller: _costEditors[schema.kind]!,
              options: schema.kind == CostLineKind.material
                  ? _materialOptions
                  : (schema.kind == CostLineKind.equipment
                      ? _equipmentOptions
                      : const <CostPickerOption>[]),
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
                      _buildConsumptionCard(),
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

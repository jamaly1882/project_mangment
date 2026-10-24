import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/project_cost_sync.dart';
import '../../core/services/item_approvals.dart';
import '../../core/services/project_team.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/cost_lines.dart';
import '../../core/utils/costs.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/constants/previous_prices.dart';
import '../../core/constants/roles.dart';
import '../../core/widgets/cost_lines_editor.dart';

/// تفاصيل بند المشروع: اختيار المعدة ومشرف البند وتحديد الاستهلاك المخطط
/// وتكاليف البند (المواد، أجور العمالة، المعدات، المحروقات).
///
/// ملاحظة: تم استبدال «السائق» بـ «مشرف البند» في إسناد البنود،
/// وتُقرأ بيانات السائق القديمة تلقائيًا لعرضها كمشرف للبند.
/// قراءة العداد وكمية تنفيذ البند تبقيان مستقلتين عن هذه الصفحة.
class ItemDetailsPage extends StatefulWidget {
  final String projectId;
  final String itemId;

  const ItemDetailsPage({
    super.key,
    required this.projectId,
    required this.itemId,
  });

  @override
  State<ItemDetailsPage> createState() => _ItemDetailsPageState();
}

class _ItemDetailsPageState extends State<ItemDetailsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  /// كمية العقد — يمكن تعديلها من نفس الصفحة.
  final TextEditingController _contractQuantityController =
      TextEditingController();

  String? _selectedUnit;

  /// سعر سابق (1447هـ) لهذا النوع — مرجع من خلاصة الأسعار.
  double? _previousPrice;
  String _previousPriceYear = previousPricesYear;
  String? _previousPriceCode;

  /// قائمة الوحدات المعروضة (تشمل أي وحدة قديمة محفوظة في البند).
  List<String> _knownUnits = <String>[];

  List<String> get _unitOptions =>
      _knownUnits.isEmpty ? _units : _knownUnits;

  static const List<String> _units = [
    'م3',
    'م2',
    'م',
    'م.ط',
    'طن',
    'كجم',
    'قطعة',
    'عدد',
    'كم',
    'م3*كم',
    'طن*كم',
    'ساعة',
    'لتر',
    'يوم',
    'أخرى',
  ];

  /// محرّرات أسطر التكلفة الأربعة: إدخال مدير المشروع هو «المخطط»،
  /// وما يسجله مشرف البند في صفحته هو «الفعلي».
  final Map<CostLineKind, CostLinesEditorController> _costEditors =
      <CostLineKind, CostLinesEditorController>{
    for (final schema in CostLineSchema.ordered)
      schema.kind: CostLinesEditorController(schema),
  };

  /// خيارات الاختيار من بيانات النظام لأسطر المواد والمعدات.
  List<CostPickerOption> _materialOptions = const <CostPickerOption>[];
  List<CostPickerOption> _equipmentOptions = const <CostPickerOption>[];

  Map<String, dynamic>? _itemData;
  String? _projectName;
  bool _loadingItem = true;
  bool _savingAll = false;

  String? _selectedSupervisorId;
  String? _selectedSupervisorName;

  /// هل مشرف البند مُسند تلقائيًا من ربط المشروع (لا اختيار يدوي)؟
  bool _supervisorFromProject = false;

  /// هل طلب المستخدم تغيير المشرف المقترح يدويًا؟
  bool _showSupervisorPicker = false;

  /// يمكن أن يعمل على البند أكثر من معدة. القائمة هي المصدر الوحيد؛
  /// أول معدة فيها تُحفظ أيضًا في الحقول المفردة للتوافق مع بقية الصفحات.
  List<String> _selectedEquipmentIds = <String>[];
  /// مجموع تكاليف بقية بنود المشروع،
  /// لأن تكلفة المشروع تُحسب تلقائيًا من بنوده.
  Map<String, double> _otherItemsCosts = <String, double>{};
  int _otherItemsCount = 0;

  /// التكاليف الفعلية لبقية بنود المشروع (ما يسجله مشرفو البنود).
  Map<String, double> _otherItemsEffective = <String, double>{};

  CollectionReference<Map<String, dynamic>> get _equipmentCollection =>
      _firestore.collection('equipment');

  @override
  void initState() {
    super.initState();
    _loadItem();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _notesController.dispose();
    _contractQuantityController.dispose();

    for (final editor in _costEditors.values) {
      editor.dispose();
    }

    super.dispose();
  }

  /// الكمية التعاقدية: القيمة المدخلة حاليًا أو المحفوظة.
  double get _contractQuantity {
    final entered =
        ProjectCosts.parseOptional(_contractQuantityController.text);

    if (entered != null && entered > 0) return entered;

    return ProjectCosts.toDouble(_itemData?['contractQuantity']);
  }

  /// تنسيق تاريخ قادم من Firestore.
  String _formatDate(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    }

    if (value is DateTime) {
      return '${value.day.toString().padLeft(2, '0')}/'
          '${value.month.toString().padLeft(2, '0')}/'
          '${value.year}';
    }

    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'لم يُحدد بعد' : text;
  }

  /// الأسطر الحالية لكل الأقسام كما تظهر في المحرّرات.
  CostLines get _plannedLines {
    return CostLines(<CostLineKind, List<Map<String, dynamic>>>{
      for (final schema in CostLineSchema.ordered)
        schema.kind: _costEditors[schema.kind]?.lines ??
            const <Map<String, dynamic>>[],
    });
  }

  /// إجمالي قسم بمفتاحه (materials / labor / equipment / fuel).
  double _plannedTotalOf(String categoryKey) {
    return _plannedLines.totalOf(_kindOf(categoryKey));
  }

  static CostLineKind _kindOf(String categoryKey) {
    switch (categoryKey) {
      case 'materials':
        return CostLineKind.material;
      case 'labor':
        return CostLineKind.labor;
      case 'equipment':
        return CostLineKind.equipment;
      default:
        return CostLineKind.fuel;
    }
  }

  double get _itemActualTotal =>
      ProjectCosts.actualTotalOf(_itemData);

  /// الأسطر الفعلية التي سجلها مشرف البند (للعرض والمقارنة هنا).
  CostLines get _actualLines => CostLines.fromData(
        _itemData,
        actual: true,
        contractQuantity: _contractQuantity,
        unit: _stringValue(_itemData?['unit']),
      );

  String _stringValue(dynamic value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    return value.toString().trim();
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return null;
    return double.tryParse(value.toString().trim().replaceAll(',', '.'));
  }

  Future<void> _loadItem() async {
    if (mounted && !_loadingItem) {
      setState(() => _loadingItem = true);
    }
    try {
      final itemDoc = await _firestore.collection('items').doc(widget.itemId).get();
      if (!itemDoc.exists) {
        if (!mounted) return;
        setState(() {
          _loadingItem = false;
          _itemData = null;
        });
        AppWidgets.showError(context, 'لم يتم العثور على البند');
        return;
      }

      final itemData = itemDoc.data() ?? <String, dynamic>{};
      if (_stringValue(itemData['projectId']) != widget.projectId) {
        if (!mounted) return;
        setState(() {
          _loadingItem = false;
          _itemData = null;
        });
        AppWidgets.showError(context, 'هذا البند لا يتبع للمشروع المحدد');
        return;
      }

      final detailsDoc = await _firestore.collection('item_details').doc(widget.itemId).get();
      final details = detailsDoc.data() ?? <String, dynamic>{};

      _descriptionController.text = _stringValue(details['description']);
      _notesController.text = _stringValue(details['notes']);

      // مشرف البند (مع دعم السجل القديم للسائق).
      final supervisorId = _stringValue(
        details['supervisorId'] ?? details['driverId'],
      );
      final supervisorName = _stringValue(
        details['supervisorName'] ?? details['driverName'],
      );

      _selectedSupervisorId =
          supervisorId.isEmpty ? null : supervisorId;
      _selectedSupervisorName =
          supervisorName.isEmpty ? null : supervisorName;

      // إن لم يُحدد مشرف بعد: يُؤخذ المشرف المرتبط بالمشروع تلقائيًا،
      // فلا يُطلب اختياره من جديد.
      if (_selectedSupervisorId == null) {
        final member = await ProjectTeam.supervisorForItem(
          projectId: widget.projectId,
          itemSupervisorId: _stringValue(itemData['supervisorId']),
          itemSupervisorName: _stringValue(itemData['supervisorName']),
        );

        if (member != null) {
          _selectedSupervisorId = member.id;
          _selectedSupervisorName = member.displayName;
          _supervisorFromProject = true;
        }
      }

      _contractQuantityController.text = ProjectCosts.toEditText(
        ProjectCosts.toDouble(itemData['contractQuantity']),
      );

      final loadedUnit = _stringValue(itemData['unit']);

      if (loadedUnit.isEmpty) {
        _selectedUnit = null;
      } else if (_units.contains(loadedUnit)) {
        _selectedUnit = loadedUnit;
      } else {
        // وحدة قديمة غير موجودة في القائمة: نضيفها مؤقتًا.
        _selectedUnit = loadedUnit;
        if (!_units.contains(loadedUnit)) {
          _knownUnits = <String>[..._units, loadedUnit];
        }
      }

      // سعر سابق (1447هـ): من البند نفسه، وإلا من نوع البند المرتبط به.
      await _loadPreviousPrice(itemData);

      // تكاليف البند: نقرأ من التفاصيل أولًا ثم من بيانات البند.
      final costSource = <String, dynamic>{
        ...itemData,
        ...details,
      };

      final loadedQuantity =
          ProjectCosts.toDouble(itemData['contractQuantity']);

      // أسطر التكلفة: تُقرأ من التفاصيل أولًا، ومعها ترحيل الإدخال القديم
      // (رقم واحد لكل قسم) إلى سطر واحد قابل للتعديل.
      final saved = CostLines.fromData(
        costSource,
        contractQuantity: loadedQuantity,
        unit: loadedUnit,
      );

      for (final schema in CostLineSchema.ordered) {
        _costEditors[schema.kind]?.applyLines(saved[schema.kind]);
      }

      final savedEquipmentIds = <String>[];

      final rawEquipmentIds = details['equipmentIds'];
      if (rawEquipmentIds is Iterable) {
        for (final value in rawEquipmentIds) {
          final id = (value ?? '').toString().trim();
          if (id.isNotEmpty) savedEquipmentIds.add(id);
        }
      }

      final singleEquipmentId = _stringValue(details['equipmentId']);
      if (singleEquipmentId.isNotEmpty && !savedEquipmentIds.contains(singleEquipmentId)) {
        savedEquipmentIds.insert(0, singleEquipmentId);
      }

      _selectedEquipmentIds = savedEquipmentIds;

      String? projectName;

      final projectDoc = await _firestore.collection('projects').doc(widget.projectId).get();
      if (projectDoc.exists) {
        final project = projectDoc.data() ?? <String, dynamic>{};
        projectName = _stringValue(
          project['name'] ?? project['projectName'] ?? project['title'],
        );
        if (projectName.isEmpty) projectName = null;

      }

      // مجموع تكاليف بقية بنود المشروع لنفس أقسام التكلفة.
      var otherCosts = <String, double>{
        for (final category in ProjectCosts.categories) category.key: 0.0,
      };
      var otherCount = 0;

      final otherEffectiveSums = <String, double>{
        for (final category in ProjectCosts.categories) category.key: 0.0,
      };

      try {
        final itemsSnapshot = await _firestore
            .collection('items')
            .where('projectId', isEqualTo: widget.projectId)
            .get();

        for (final doc in itemsSnapshot.docs) {
          if (doc.id == widget.itemId) continue;

          otherCount++;

          final other = ProjectCosts.breakdownOf(doc.data());

          for (final entry in other.entries) {
            otherCosts[entry.key] =
                (otherCosts[entry.key] ?? 0) + entry.value;
          }

          final otherEffective =
              ProjectCosts.effectiveBreakdownOf(doc.data());

          for (final entry in otherEffective.entries) {
            otherEffectiveSums[entry.key] =
                (otherEffectiveSums[entry.key] ?? 0) + entry.value;
          }
        }
      } catch (e) {
        debugPrint('تعذر حساب تكاليف بقية البنود: $e');
      }

      // خيارات أسطر التكلفة: المواد وحصر المعدات.
      var materialOptions = const <CostPickerOption>[];
      var equipmentOptions = const <CostPickerOption>[];

      try {
        final materialsSnapshot =
            await _firestore.collection('materials').get();

        materialOptions = <CostPickerOption>[
          for (final doc in materialsSnapshot.docs)
            CostPickerOption(
              id: doc.id,
              label: _stringValue(
                doc.data()['name'],
                defaultValue: 'مادة بدون اسم',
              ),
            ),
        ]..sort((a, b) => a.label.compareTo(b.label));
      } catch (e) {
        debugPrint('تعذر تحميل المواد لأسطر التكلفة: $e');
      }

      try {
        final equipmentSnapshot = await _equipmentCollection.get();

        equipmentOptions = <CostPickerOption>[
          for (final doc in equipmentSnapshot.docs)
            CostPickerOption(
              id: doc.id,
              label: '${_stringValue(doc.data()['code'], defaultValue: '—')} — '
                  '${_stringValue(doc.data()['name'], defaultValue: _stringValue(doc.data()['type'], defaultValue: 'معدة'))}',
            ),
        ]..sort((a, b) => a.label.compareTo(b.label));
      } catch (e) {
        debugPrint('تعذر تحميل المعدات لأسطر التكلفة: $e');
      }

      if (!mounted) return;
      setState(() {
        _itemData = itemData;
        _projectName = projectName;
        _otherItemsCosts = otherCosts;
        _otherItemsEffective = otherEffectiveSums;
        _otherItemsCount = otherCount;
        _materialOptions = materialOptions;
        _equipmentOptions = equipmentOptions;
        _loadingItem = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingItem = false);
      AppWidgets.showError(context, 'حدث خطأ أثناء تحميل بيانات البند:\n$e');
    }
  }

  /// حسابات مشرفي البنود في النظام؛ يُفلترون على المشروع داخل
  /// الواجهة حتى يُقبل الربط عبر `projectIds` أو `projectId` المفرد.
  /// (الاستعلام الثلاثي السابق كان يُسقط المشرفين المرتبطين بحقل
  /// مفرد أو بحسابات قديمة بلا حقل `active`.)
  Stream<QuerySnapshot<Map<String, dynamic>>> _supervisorsStream() {
    return _firestore
        .collection('users')
        .where(
          'role',
          whereIn: <String>[
            AppRoles.supervisor,
            AppRoles.projectSupervisor,
            AppRoles.driver,
          ],
        )
        .snapshots();
  }

  /// هل مشرف البند [data] مرتبط بالمشروع الحالي؟
  bool _supervisorBelongsToProject(Map<String, dynamic> data) {
    if (data['active'] == false) return false;

    final Set<String> ids = <String>{};

    final dynamic rawList = data['projectIds'];
    if (rawList is Iterable) {
      for (final value in rawList) {
        final id = (value ?? '').toString().trim();
        if (id.isNotEmpty) ids.add(id);
      }
    } else if (rawList != null) {
      final id = rawList.toString().trim();
      if (id.isNotEmpty) ids.add(id);
    }

    final single = (data['projectId'] ?? '').toString().trim();
    if (single.isNotEmpty) ids.add(single);

    return ids.contains(widget.projectId);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _equipmentStream() {
    return _equipmentCollection.snapshots();
  }

  String _equipmentDisplayName(Map<String, dynamic> data) {
    final name = _stringValue(data['name'] ?? data['type'], defaultValue: 'معدة بدون اسم');
    final code = _stringValue(data['code']);
    return code.isEmpty ? name : '$name — $code';
  }

  Future<void> _saveAll() async {
    if (_savingAll || _itemData == null) return;

    if (_selectedEquipmentIds.isEmpty) {
      AppWidgets.showWarning(context, 'يرجى اختيار معدة واحدة على الأقل من حصر المعدات');
      return;
    }
    if (_selectedSupervisorId == null || _selectedSupervisorId!.isEmpty) {
      // محاولة أخيرة: المشرف المرتبط بالمشروع.
      final member = await ProjectTeam.supervisorForItem(
        projectId: widget.projectId,
        itemSupervisorId: _stringValue(_itemData?['supervisorId']),
        itemSupervisorName: _stringValue(_itemData?['supervisorName']),
      );

      if (member == null) {
        AppWidgets.showWarning(
          context,
          'لا يوجد مشرف مرتبط بهذا المشروع. '
          'اربط مشرف المشروع من إدارة المستخدمين أولًا.',
        );
        return;
      }

      if (!mounted) return;

      setState(() {
        _selectedSupervisorId = member.id;
        _selectedSupervisorName = member.displayName;
        _supervisorFromProject = true;
      });
    }

    // التحقق من أسطر التكلفة المدخلة.
    if (_plannedLines.isNotEmpty) {
      final errors = _plannedLines.validate();

      if (errors.isNotEmpty) {
        AppWidgets.showWarning(
          context,
          'راجع تكاليف البند:\n' + errors.take(3).join('\n'),
        );
        return;
      }
    }

    // بيانات البند: الكمية التعاقدية والوحدة.
    final quantityValue =
        ProjectCosts.parseOptional(_contractQuantityController.text);

    if (quantityValue == null || quantityValue <= 0) {
      AppWidgets.showWarning(context, 'أدخل كمية تعاقدية صحيحة');
      return;
    }

    if (_selectedUnit == null || _selectedUnit!.trim().isEmpty) {
      AppWidgets.showWarning(context, 'اختر وحدة البند');
      return;
    }

    final executedSoFar = ProjectCosts.nonNegative(
      _itemData?['executedQuantity'],
    );

    if (quantityValue < executedSoFar) {
      AppWidgets.showWarning(
        context,
        'لا يمكن أن تكون الكمية التعاقدية أقل من الكمية المنفذة '
        '(${ProjectCosts.formatNumber(executedSoFar)})',
      );
      return;
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      AppWidgets.showError(context, 'المستخدم غير مسجل الدخول');
      return;
    }

    setState(() => _savingAll = true);
    try {
      // إعادة قراءة المعدات ومشرف البند قبل الحفظ للتأكد من صحة سجلاتها.
      // يمكن أن يعمل على البند أكثر من معدة.
      final equipmentNamesList = <String>[];
      final equipmentCodesList = <String>[];
      final equipmentIdsList = <String>[];
      final equipmentWorkUnitsList = <String>[];
      final equipmentMetersList = <double?>[];

      for (final id in _selectedEquipmentIds) {
        final equipmentDoc = await _equipmentCollection.doc(id).get();
        if (!equipmentDoc.exists) {
          throw Exception('إحدى المعدات المحددة لم تعد موجودة في حصر المعدات');
        }

        final data = equipmentDoc.data() ?? <String, dynamic>{};
        if (_stringValue(data['status'], defaultValue: 'active') == 'inactive') {
          throw Exception('إحدى المعدات المحددة غير نشطة؛ اختر معدة نشطة أخرى');
        }

        equipmentIdsList.add(id);
        equipmentNamesList.add(
          _stringValue(
            data['name'] ?? data['type'],
            defaultValue: 'معدة بدون اسم',
          ),
        );
        equipmentCodesList.add(_stringValue(data['code']));
        equipmentWorkUnitsList.add(_stringValue(data['workUnit']));
        equipmentMetersList.add(_toDouble(data['currentMeter']));
      }

      if (equipmentIdsList.isEmpty) {
        throw Exception('اختر معدة واحدة على الأقل');
      }

      final supervisorDoc =
          await _firestore.collection('users').doc(_selectedSupervisorId).get();

      if (!supervisorDoc.exists) throw Exception('حساب المشرف غير موجود');

      final supervisorData = supervisorDoc.data() ?? <String, dynamic>{};

      final supervisorRole = _stringValue(supervisorData['role']);

      // دور السائق هو الدور القديم الذي استُبدل بمشرف البند.
      // كل أدوار المشرف الميداني (الجديدة والقديمة) تُقبل بعد التطبيع.
      final bool isSupervisorAccount =
          supervisorData['active'] == true &&
              AppRoles.isFieldSupervisor(supervisorRole);

      if (!isSupervisorAccount) {
        throw Exception('حساب المشرف غير نشط أو ليس حساب مشرف بند');
      }

      if (!_supervisorBelongsToProject(supervisorData)) {
        throw Exception(
          'المشرف غير مرتبط بهذا المشروع. اربطه بالمشروع من إدارة المستخدمين أولاً.',
        );
      }

      // الحقول المفردة = أول معدة (توافق مع بقية الصفحات والتقارير)،
      // والقوائم تحمل كل المعدات.
      final equipmentId = equipmentIdsList.first;
      final equipmentName = equipmentNamesList.first;
      final equipmentCode = equipmentCodesList.first;
      final equipmentWorkUnit = equipmentWorkUnitsList.first;
      final equipmentCurrentMeter = equipmentMetersList.first;

      // مزامنة الاسم من حساب المشرف لتجنب حفظ اسم قديم.
      final supervisorName = _stringValue(
        supervisorData['name'],
        defaultValue: _stringValue(
          supervisorData['username'],
          defaultValue: _selectedSupervisorName ?? 'مشرف',
        ),
      );
      final supervisorJobNumber = _stringValue(supervisorData['jobNumber']);
      final supervisorDisplayName = supervisorJobNumber.isEmpty
          ? supervisorName
          : '$supervisorName - $supervisorJobNumber';

      final detailsRef = _firestore.collection('item_details').doc(widget.itemId);
      final assignmentCollection = _firestore.collection('item_supervisors');
      final assignmentRef = assignmentCollection.doc(widget.itemId);
      final existingAssignment = await assignmentRef.get();
      final existingAssignments = await assignmentCollection
          .where('itemId', isEqualTo: widget.itemId)
          .get();

      // تكاليف البند: أسطر مفصّلة + مجاميع الأقسام،
      // وتُحفظ في التفاصيل وفي وثيقة البند.
      final costData = _plannedLines.toSaveData(
        contractQuantity: _contractQuantity,
      );

      final itemTotalCost =
          ProjectCosts.toDouble(costData[ProjectCosts.totalField]);

      final detailsData = <String, dynamic>{
        'projectId': widget.projectId,
        'itemId': widget.itemId,
        'itemDefinitionId': _itemData!['itemDefinitionId'],
        'itemDefinitionName': _itemData!['itemDefinitionName'],
        'itemTypeId': _itemData!['typeId'],
        'itemTypeName': _itemData!['typeName'],
        'contractQuantity': quantityValue,
        'unit': _selectedUnit,
        'code': _itemData!['code'],
        'description': _descriptionController.text.trim(),
        'notes': _notesController.text.trim(),
        'supervisorId': _selectedSupervisorId,
        'supervisorName': supervisorDisplayName,
        'assignedToType': 'supervisor',
        // أول معدة (توافق) + كل المعدات المرتبطة بالبند.
        'equipmentId': equipmentId,
        'equipmentName': equipmentName,
        'equipmentCode': equipmentCode,
        'equipmentWorkUnit': equipmentWorkUnit,
        'equipmentCurrentMeterAtAssignment': equipmentCurrentMeter,
        'equipmentIds': equipmentIdsList,
        'equipmentNames': equipmentNamesList,
        'equipmentCodes': equipmentCodesList,
        'equipmentWorkUnits': equipmentWorkUnitsList,
        'equipmentMetersAtAssignment': equipmentMetersList,
        'equipmentCount': equipmentIdsList.length,
        // صفحة المدير لم تعد تدخل نوع الوقود والكميات المخططة: تُسجَّل
        // أسطرًا في قسم «تكلفة استهلاك المحروقات» أعلاه. نتوقف عن الكتابة
        // فقط، فلا تُمسح القيم القديمة المحفوظة في البنود الحالية.
        ...costData,
        'detailsAdded': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUser.uid,
      };

      final assignmentData = <String, dynamic>{
        'itemId': widget.itemId,
        'projectId': widget.projectId,
        'supervisorId': _selectedSupervisorId,
        'supervisorName': supervisorDisplayName,
        'equipmentId': equipmentId,
        'equipmentName': equipmentName,
        'equipmentCode': equipmentCode,
        'equipmentIds': equipmentIdsList,
        'equipmentNames': equipmentNamesList,
        'active': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUser.uid,
      };
      if (!existingAssignment.exists) {
        assignmentData['createdAt'] = FieldValue.serverTimestamp();
        assignmentData['createdBy'] = currentUser.uid;
      }

      final batch = _firestore.batch();
      batch.set(detailsRef, detailsData, SetOptions(merge: true));

      // نسخ التكاليف والإسناد إلى وثيقة البند لتظهر في قائمة البنود والتقارير.
      batch.set(
        _firestore.collection('items').doc(widget.itemId),
        <String, dynamic>{
          ...costData,
          'contractQuantity': quantityValue,
          'unit': _selectedUnit,
          'supervisorId': _selectedSupervisorId,
          'supervisorName': supervisorDisplayName,
          'equipmentId': equipmentId,
          'equipmentName': equipmentName,
          'equipmentIds': equipmentIdsList,
          'equipmentNames': equipmentNamesList,
          'equipmentCount': equipmentIdsList.length,

          // إعادة حساب تكلفة المنفذ من تكلفة الوحدة الجديدة.
          ProjectCosts.executedCostField:
              ProjectCosts.totalUnitCost(costData) *
                  ProjectCosts.nonNegative(
                _itemData?['executedQuantity'],
              ),
          'detailsAdded': true,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': currentUser.uid,
        },
        SetOptions(merge: true),
      );

      // تعطيل أي سجلات تكليف قديمة لهذا البند قبل إنشاء التكليف الحالي.
      // نتجنب تحديث المستند نفسه الذي سنكتب فيه التكليف الجديد.
      for (final oldDoc in existingAssignments.docs) {
        if (oldDoc.id != assignmentRef.id && oldDoc.data()['active'] == true) {
          batch.update(oldDoc.reference, {
            'active': false,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': currentUser.uid,
          });
        }
      }
      // إيقاف سجلات إسناد السائق القديمة حتى لا يظهر البند في لوحة السائق.
      try {
        final legacyDrivers = await _firestore
            .collection('item_drivers')
            .where('itemId', isEqualTo: widget.itemId)
            .get();

        for (final oldDoc in legacyDrivers.docs) {
          if (oldDoc.data()['active'] == true) {
            batch.update(oldDoc.reference, {
              'active': false,
              'updatedAt': FieldValue.serverTimestamp(),
              'updatedBy': currentUser.uid,
            });
          }
        }
      } catch (e) {
        debugPrint('تعذر تحديث سجلات السائق القديمة: $e');
      }

      batch.set(assignmentRef, assignmentData, SetOptions(merge: true));
      await batch.commit();

      if (!mounted) return;
      setState(() {
        _selectedSupervisorName = supervisorDisplayName;
      });
      // تكاليف المشروع = مجموع تكاليف بنوده.
      ProjectCostTotals? projectTotals;

      try {
        projectTotals =
            await ProjectCostSync.applyTotals(widget.projectId);
      } catch (e) {
        debugPrint('تعذرت مزامنة تكاليف المشروع: $e');
      }

      if (!mounted) return;

      AppWidgets.showSuccess(
        context,
        'تم حفظ تفاصيل البند وتكاليفه'
        '${itemTotalCost > 0 ? ' — ${ProjectCosts.formatMoney(itemTotalCost)}' : ''}'
        '${projectTotals != null ? '\nإجمالي تكلفة المشروع: ${ProjectCosts.formatMoney(projectTotals.total)}' : ''}',
      );

      await _loadItem();
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showError(context, 'تعذر حفظ تفاصيل البند:\n$e');
    } finally {
      if (mounted) setState(() => _savingAll = false);
    }
  }

  // ============================================================
  // بيانات البند (بيانات العقد + تفاصيله)
  // ============================================================

  Widget _buildItemDataSection() {
    final data = _itemData!;

    final definitionName = _stringValue(
      data['itemDefinitionName'],
      defaultValue: _stringValue(data['name'], defaultValue: 'بدون اسم'),
    );

    final typeName =
        _stringValue(data['typeName'], defaultValue: 'بدون نوع');
    final code = _stringValue(data['code'], defaultValue: '—');
    final projectName = _projectName ?? widget.projectId;

    final unitOptions = <String>{
      ..._unitOptions,
      if (_selectedUnit != null && _selectedUnit!.isNotEmpty) _selectedUnit!,
    }.toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'بيانات البند',
            subtitle:
                'البند والنوع والكمية التعاقدية والوحدة وتفاصيل البند',
            icon: Icons.assignment_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'المشروع',
            value: projectName,
            icon: Icons.business_outlined,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'البند',
            value: definitionName,
            icon: Icons.category_outlined,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'النوع',
            value: typeName,
            icon: Icons.list_alt_outlined,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'كود البند',
            value: code,
            icon: Icons.qr_code_2_outlined,
          ),
          AppSpacing.verticalMd,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: AppNumberField(
                  controller: _contractQuantityController,
                  label: 'الكمية التعاقدية *',
                  hint: 'أدخل الكمية التعاقدية',
                  prefixIcon: Icons.numbers_outlined,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              AppSpacing.horizontalMd,
              Expanded(
                child: AppDropdown<String>(
                  label: 'الوحدة *',
                  hint: 'اختر الوحدة',
                  value: _selectedUnit,
                  prefixIcon: Icons.straighten_outlined,
                  items: unitOptions
                      .map(
                        (unit) => DropdownMenuItem<String>(
                          value: unit,
                          child: Text(unit),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _selectedUnit = value;
                  }),
                ),
              ),
            ],
          ),
          AppSpacing.verticalSm,
          _buildContractDatesCard(),
          AppSpacing.verticalMd,
          AppTextField(
            controller: _descriptionController,
            label: 'تفاصيل البند',
            hint: 'أدخل وصف البند',
            prefixIcon: Icons.description_outlined,
            maxLines: 3,
          ),
          AppSpacing.verticalMd,
          AppTextField(
            controller: _notesController,
            label: 'ملاحظات',
            hint: 'أدخل الملاحظات',
            prefixIcon: Icons.notes_outlined,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ملخص التنفيذ
  // ============================================================

  Widget _buildExecutionSummaryCard() {
    final data = _itemData!;

    final contract = _contractQuantity;
    final executed = ProjectCosts.nonNegative(data['executedQuantity']);
    final remaining =
        (contract - executed) < 0 ? 0.0 : (contract - executed);
    final progress = contract <= 0
        ? 0.0
        : (executed / contract).clamp(0.0, 1.0).toDouble();
    final unit = _stringValue(data['unit']);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'التنفيذ',
            subtitle: 'الكميات المنفذة والمتبقية وتواريخ التنفيذ',
            icon: Icons.timeline_outlined,
          ),
          AppSpacing.verticalSm,
          AppProgress(
            value: progress,
            label: 'نسبة التنفيذ',
            height: 8,
          ),
          AppSpacing.verticalMd,
          AppInfoRow(
            label: 'الكمية المنفذة',
            value:
                '${ProjectCosts.formatNumber(executed)} $unit'.trim(),
            icon: Icons.done_all,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'الكمية المتبقية',
            value:
                '${ProjectCosts.formatNumber(remaining)} $unit'.trim(),
            icon: Icons.pending_actions_outlined,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'تاريخ بداية التنفيذ',
            value: _formatDate(data['executionStartDate']),
            icon: Icons.calendar_month_outlined,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'تاريخ نهاية التنفيذ',
            value: _formatDate(data['executionEndDate']),
            icon: Icons.event_outlined,
          ),
          AppSpacing.verticalSm,
          const Text(
            'تواريخ التنفيذ يسجّلها المهندس، والكميات المنفذة يتابعها '
            'مدير المشروع من صفحة البنود، والاستهلاك يسجّله مشرف البند.',
            style: AppTextStyles.bodySecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildEquipmentDropdown() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _equipmentStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppError(message: 'تعذر تحميل حصر المعدات:\n${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading(message: 'جاري تحميل المعدات...');
        }

        final allDocs = snapshot.data?.docs ?? [];
        final options = allDocs.where((doc) {
          final status = _stringValue(doc.data()['status'], defaultValue: 'active');
          return status != 'inactive' ||
              _selectedEquipmentIds.contains(doc.id);
        }).toList()
          ..sort(
            (a, b) => _stringValue(a.data()['code'])
                .compareTo(_stringValue(b.data()['code'])),
          );

        if (options.isEmpty) {
          return const AppEmpty(
            message:
                'لا توجد معدات مسجلة. أضف المعدات أولًا من صفحة «حصر المعدات» لدى مسؤول النظام.',
            icon: Icons.precision_manufacturing_outlined,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'المعدات العاملة على البند — يمكن اختيار أكثر من معدة.',
              style: AppTextStyles.bodySecondary,
            ),
            AppSpacing.verticalSm,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final doc in options)
                  _buildEquipmentChip(doc),
              ],
            ),
            if (_selectedEquipmentIds.isEmpty) ...[
              AppSpacing.verticalXs,
              Text(
                'اختر معدة واحدة على الأقل.',
                style: AppTextStyles.small.copyWith(color: AppColors.danger),
              ),
            ],
            if (_selectedEquipmentIds.isNotEmpty) ...[
              AppSpacing.verticalSm,
              AppCard(
                color: AppColors.background,
                child: Column(
                  children: [
                    AppInfoRow(
                      label: 'عدد المعدات',
                      value: '${_selectedEquipmentIds.length}',
                      icon: Icons.precision_manufacturing_outlined,
                    ),
                    for (var i = 0; i < _selectedEquipmentIds.length; i++) ...[
                      AppSpacing.verticalXs,
                      AppInfoRow(
                        label: i == 0 ? 'المعدة الرئيسية' : 'معدة إضافية ${i + 1}',
                        value: _equipmentLabelById(options, _selectedEquipmentIds[i]),
                        icon: Icons.construction_outlined,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _equipmentLabelById(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> options,
    String id,
  ) {
    for (final doc in options) {
      if (doc.id == id) return _equipmentDisplayName(doc.data());
    }
    return 'معدة محذوفة';
  }

  Widget _buildEquipmentChip(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final selected = _selectedEquipmentIds.contains(doc.id);
    final inactive =
        _stringValue(data['status'], defaultValue: 'active') == 'inactive';

    return FilterChip(
      selected: selected,
      onSelected: inactive && !selected
          ? null
          : (_) {
              setState(() {
                if (selected) {
                  _selectedEquipmentIds =
                      _selectedEquipmentIds.where((id) => id != doc.id).toList();
                } else {
                  _selectedEquipmentIds = <String>[
                    ..._selectedEquipmentIds,
                    doc.id,
                  ];
                }
              });
            },
      avatar: Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 18,
      ),
      label: Text(
        '${_equipmentDisplayName(data)}${inactive ? ' (غير نشطة)' : ''}',
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// قسم مشرف البند: يُعرض المشرف المرتبط بالمشروع جاهزًا،
  /// ولا يُفتح الاختيار اليدوي إلا إذا طلب المستخدم تغييره أو تعدد
  /// المشرفون المرتبطون بالمشروع.
  Widget _buildSupervisorSection() {
    if (_supervisorFromProject &&
        !_showSupervisorPicker &&
        _selectedSupervisorId != null) {
      return AppCard(
        color: AppColors.info.withValues(alpha: 0.07),
        child: Row(
          children: [
            const Icon(
              Icons.supervisor_account_outlined,
              color: AppColors.info,
            ),
            AppSpacing.horizontalSm,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مشرف البند: ${_selectedSupervisorName ?? 'مشرف المشروع'}',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'مرتبط بالمشروع مسبقًا — لا حاجة لاختياره.',
                    style: AppTextStyles.small,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() => _showSupervisorPicker = true);
              },
              child: const Text('تغيير'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSupervisorDropdown(),
        if (_showSupervisorPicker) ...[
          AppSpacing.verticalXs,
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () {
                setState(() => _showSupervisorPicker = false);
              },
              icon: const Icon(Icons.undo_outlined),
              label: const Text('رجوع إلى مشرف المشروع'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSupervisorDropdown() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _supervisorsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppError(message: 'تعذر تحميل مشرفي البنود:\n${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading(message: 'جاري تحميل المشرفين...');
        }
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
            (snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .where((doc) => _supervisorBelongsToProject(doc.data()))
                .toList();
        if (docs.isEmpty) {
          return const AppEmpty(
            message:
                'لا يوجد مشرفو بنود مرتبطون بهذا المشروع. '
                'أضف المشرف من «المستخدمون ← المشرفون» لدى مسؤول النظام واربطه بالمشروع أولًا.',
            icon: Icons.supervisor_account_outlined,
          );
        }

        final selectedExists = docs.any((doc) => doc.id == _selectedSupervisorId);
        return AppDropdown<String>(
          label: 'مشرف البند *',
          hint: 'اختر مشرف البند',
          value: selectedExists ? _selectedSupervisorId : null,
          prefixIcon: Icons.supervisor_account_outlined,
          items: docs.map((doc) {
            final data = doc.data();
            final name = _stringValue(
              data['name'],
              defaultValue: _stringValue(data['username'], defaultValue: 'مشرف'),
            );
            final jobNumber = _stringValue(data['jobNumber']);
            return DropdownMenuItem<String>(
              value: doc.id,
              child: Text(
                jobNumber.isEmpty ? name : '$name - $jobNumber',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (id) {
            if (id == null) return;
            final data = docs.firstWhere((doc) => doc.id == id).data();
            final name = _stringValue(
              data['name'],
              defaultValue: _stringValue(data['username'], defaultValue: 'مشرف'),
            );
            final jobNumber = _stringValue(data['jobNumber']);
            setState(() {
              _selectedSupervisorId = id;
              _selectedSupervisorName =
                  jobNumber.isEmpty ? name : '$name - $jobNumber';
              _supervisorFromProject = false;
            });
          },
        );
      },
    );
  }

  // ============================================================
  // سعر سابق (1447هـ)
  // ============================================================

  /// يقرأ السعر السابق من البند، وإن لم يكن محفوظًا يقرأه من نوع البند
  /// في مجموعة item_definitions (الأنواع التي أنشأها استيراد 1447هـ).
  Future<void> _loadPreviousPrice(Map<String, dynamic> itemData) async {
    double? price = _toDouble(itemData['previousPrice']);
    String year = _stringValue(itemData['previousPriceYear']);
    String? code = _stringValue(itemData['previousPriceCode']);

    if (price == null || price <= 0) {
      final definitionId = _stringValue(itemData['itemDefinitionId']);
      final typeId = _stringValue(itemData['typeId']);

      if (definitionId.isNotEmpty && typeId.isNotEmpty) {
        try {
          final typeDoc = await _firestore
              .collection('item_definitions')
              .doc(definitionId)
              .collection('types')
              .doc(typeId)
              .get();

          final data = typeDoc.data();

          if (data != null) {
            price = _toDouble(data['previousPrice']);
            year = _stringValue(data['previousPriceYear']);
            code = _stringValue(data['code'] ?? data['previousPriceCode']);
          }
        } catch (e) {
          debugPrint('تعذر قراءة سعر 1447هـ لنوع البند: $e');
        }
      }
    }

    if (price != null && price <= 0) price = null;

    // آخر محاولة: كود البند نفسه في خلاصة الأسعار.
    if (price == null) {
      final itemCode = int.tryParse(_stringValue(itemData['code']));
      final fromList = itemCode == null
          ? null
          : PreviousPrices.findByCode(itemCode);
      if (fromList != null && fromList.hasPrice) {
        price = fromList.price;
        code ??= PreviousPrices.bandOfCode(fromList.code) != null
            ? PreviousPrices.bandOfCode(fromList.code)!.typeCodeOf(fromList)
            : fromList.code.toString();
      }
    }

    _previousPrice = price;
    _previousPriceYear = year.trim().isEmpty ? previousPricesYear : year;
    _previousPriceCode = (code == null || code.trim().isEmpty) ? null : code.trim();
  }

  /// عدد الأسطر التي لا تحتوي سعر وحدة بعد.
  int get _linesMissingUnitPrice {
    var count = 0;

    for (final kind in const <CostLineKind>[
      CostLineKind.material,
      CostLineKind.equipment,
      CostLineKind.labor,
    ]) {
      final lines = _costEditors[kind]?.lines ?? const <Map<String, dynamic>>[];
      for (final line in lines) {
        if (kind == CostLineKind.labor) {
          final basis = (line['wageBasis'] ?? '').toString().trim();
          if (basis != 'للوحدة') continue;

          final wage = _toDouble(line['wage']) ?? 0;
          if (wage <= 0) count++;
          continue;
        }

        final value = _toDouble(line['unitPrice']) ?? 0;
        if (value <= 0) count++;
      }
    }

    return count;
  }

  /// يضع السعر السابق في خانة سعر الوحدة للأسطر التي لم تُسعَّر بعد.
  ///
  /// لا يستبدل أي سعر أدخله المستخدم، ويُبقي التكلفة قابلة للتعديل.
  void _applyPreviousPriceToLines() {
    final price = _previousPrice;
    if (price == null || price <= 0) return;

    final text = ProjectCosts.toEditText(price);
    var applied = 0;

    for (final kind in const <CostLineKind>[
      CostLineKind.material,
      CostLineKind.equipment,
      CostLineKind.labor,
    ]) {
      final editor = _costEditors[kind];
      if (editor == null) continue;

      final lines = editor.lines;

      for (var index = 0; index < lines.length; index++) {
        if (kind == CostLineKind.labor) {
          // الأجرة ليست سعر وحدة إلا عندما يكون أساس الأجرة «للوحدة».
          final basis = (lines[index]['wageBasis'] ?? '').toString().trim();
          if (basis != 'للوحدة') continue;

          final current = _toDouble(lines[index]['wage']) ?? 0;
          if (current > 0) continue;

          editor.setText(index, 'wage', text);
          applied++;
          continue;
        }

        final current = _toDouble(lines[index]['unitPrice']) ?? 0;
        if (current > 0) continue;

        editor.setText(index, 'unitPrice', text);
        applied++;
      }
    }

    if (!mounted) return;

    setState(() {});

    if (applied == 0) {
      AppWidgets.showWarning(
        context,
        'كل الأسطر مسعّرة بالفعل. عدّل السعر يدويًا من السطر نفسه.',
      );
      return;
    }

    AppWidgets.showSuccess(
      context,
      'تم تطبيق السعر السابق على $applied سطرًا.',
    );
  }

  /// بطاقة السعر السابق (1447هـ) مع زر التطبيق على الأسطر.
  Widget _buildPreviousPriceCard() {
    final price = _previousPrice;

    if (price == null || price <= 0) {
      return const SizedBox.shrink();
    }

    final missing = _linesMissingUnitPrice;

    return AppCard(
      color: AppColors.info.withValues(alpha: 0.07),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppInfoRow(
            label: 'سعر سابق ($_previousPriceYear)',
            value: ProjectCosts.formatMoney(price),
            icon: Icons.price_change_outlined,
          ),
          if (_previousPriceCode != null) ...[
            AppSpacing.verticalXs,
            AppInfoRow(
              label: 'كود البند في قائمة الأسعار',
              value: '$_previousPriceCode',
              icon: Icons.tag_outlined,
            ),
          ],
          AppSpacing.verticalXs,
          Text(
            'سعر مرجعي للوحدة من خلاصة أسعار 1447هـ، '
            'لا يُحتسب في التكلفة حتى يُطبَّق على أسطر التكلفة.',
            style: AppTextStyles.small,
          ),
          AppSpacing.verticalSm,
          Row(
            children: [
              Expanded(
                child: Text(
                  missing > 0
                      ? '$missing سطرًا بلا سعر وحدة'
                      : 'كل الأسطر مسعّرة',
                  style: AppTextStyles.bodySecondary,
                ),
              ),
              AppOutlinedButton(
                text: 'تطبيق السعر',
                icon: Icons.playlist_add_check_outlined,
                onPressed: _applyPreviousPriceToLines,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// تاريخ بداية البند وانتهائه:
  /// البداية = أول يوم يسجّل فيه المشرف كمية منفذة،
  /// والانتهاء = البداية + مدة العقد (+ أي تمديد معتمد).
  Widget _buildContractDatesCard() {
    final item = _itemData ?? const <String, dynamic>{};

    final DateTime? start = _toDate(
      item['executionStartDate'] ?? item['contractStartDate'],
    );
    final durationDays = _toDouble(item['durationDays']) ?? 0;

    DateTime? end = _toDate(item['contractEndDate']);
    if (end == null && start != null && durationDays > 0) {
      end = start.add(Duration(days: durationDays.round()));
    }

    final extensionUntil = _toDate(item['timeExtensionUntil']);
    final extensionDays = _toDouble(item['timeExtensionDays']) ?? 0;

    final effectiveEnd = extensionUntil ?? end;

    final allowance = ItemAllowance.fromData(item);

    return AppCard(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'زمن البند',
            subtitle:
                'البداية تُسجَّل تلقائيًا من أول إدخال للمشرف للكمية '
                'المنفذة، والانتهاء = البداية + مدة العقد.',
            icon: Icons.event_note_outlined,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'أول يوم تنفيذ (بداية البند)',
            value: start == null ? 'لم يبدأ التنفيذ بعد' : _formatDate(start),
            icon: Icons.play_circle_outline,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'مدة العقد',
            value: durationDays <= 0
                ? 'غير محددة'
                : '${ProjectCosts.formatNumber(durationDays)} يومًا',
            icon: Icons.timelapse_outlined,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'تاريخ انتهاء البند',
            value: effectiveEnd == null ? 'غير محدد' : _formatDate(effectiveEnd),
            icon: Icons.event_busy_outlined,
          ),
          if (extensionDays > 0) ...[
            AppSpacing.verticalXs,
            AppInfoRow(
              label: 'تمديد معتمد من مدير الجودة',
              value: '${ProjectCosts.formatNumber(extensionDays)} يومًا',
              icon: Icons.more_time_outlined,
            ),
          ],
          if (allowance.extraApproved) ...[
            AppSpacing.verticalXs,
            AppInfoRow(
              label: 'كمية إضافية معتمدة',
              value:
                  '${ProjectCosts.formatNumber(allowance.extraPercent)}% '
                  '(${ProjectCosts.formatNumber(allowance.extraAllowance)} '
                  '${_stringValue(item['unit'])})',
              icon: Icons.verified_outlined,
            ),
          ],
        ],
      ),
    );
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  // ============================================================
  // تكاليف البند
  // ============================================================

  /// قسم تكاليف البند: جدول أسطر لكل قسم من الأقسام الأربعة.
  Widget _buildCostsSection() {
    final lines = _plannedLines;
    final plannedTotal = lines.grandTotal;
    final actualTotal = _itemActualTotal;
    final contract = _contractQuantity;
    final unit =
        (_selectedUnit ?? _stringValue(_itemData?['unit'])).trim();

    final quantityNote = contract > 0
        ? 'مرايا تكلفة الوحدة تُحسب على الكمية التعاقدية '
            '(${ProjectCosts.formatNumber(contract)} $unit)'
        : 'أدخل الكمية التعاقدية ليُحسب نصيب الوحدة';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionTitle(
          title: 'تكاليف البند (المخطط)',
          subtitle:
              'سطر لكل مادة أو مهنة أو معدة أو نوع وقود. '
              'التكلفة تُحسب من المعادلة ويمكن تثبيتها يدويًا، '
              'ومجاميع الأقسام تنتقل تلقائيًا إلى تكلفة المشروع.',
          icon: Icons.payments_outlined,
        ),
        AppSpacing.verticalSm,
        AppCard(
          color: AppColors.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppInfoRow(
                label: 'بنود التكلفة المدخلة',
                value: lines.summaryLabel(),
                icon: Icons.list_alt,
              ),
              AppSpacing.verticalXs,
              AppInfoRow(
                label: 'إجمالي تكلفة البند المخططة',
                value: ProjectCosts.formatMoney(plannedTotal),
                icon: Icons.account_balance_wallet_outlined,
              ),
              if (actualTotal > 0) ...[
                AppSpacing.verticalXs,
                AppInfoRow(
                  label: 'التكلفة الفعلية المسجلة بواسطة المشرف',
                  value: ProjectCosts.formatMoney(actualTotal),
                  icon: Icons.check_circle_outline,
                ),
                AppSpacing.verticalXs,
                AppInfoRow(
                  label: actualTotal >= plannedTotal
                      ? 'زيادة الفعلية عن المخطط'
                      : 'الفعلية أقل من المخطط',
                  value: ProjectCosts.formatMoney(
                    (actualTotal - plannedTotal).abs(),
                  ),
                  icon: Icons.swap_horiz,
                ),
              ],
              AppSpacing.verticalXs,
              Text(
                quantityNote,
                style: AppTextStyles.small,
              ),
            ],
          ),
        ),
        if (_previousPrice != null && _previousPrice! > 0) ...[
          _buildPreviousPriceCard(),
          AppSpacing.verticalMd,
        ],
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
        if (_actualLines.isNotEmpty) ...[
          CostLinesComparison(
            planned: lines,
            actual: _actualLines,
            title: 'ما سجله مشرف البند مقابل المخطط',
            plannedLabel: 'مخطط',
            actualLabel: 'فعلي',
            accent: AppColors.supervisor,
          ),
          AppSpacing.verticalMd,
        ],
        _buildProjectCostsCard(),
      ],
    );
  }

  /// لون القسم المقابل في الواجهة.
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

  /// ملخص تكلفة المشروع بعد حفظ هذا البند.
  /// تكلفة المشروع ليست إدخالًا يدويًا، بل مجموع تكاليف بنوده.
  Widget _buildProjectCostsCard() {
    final current = <String, double>{
      for (final category in ProjectCosts.categories)
        category.key: _plannedTotalOf(category.key),
    };

    final projected = <String, double>{
      for (final category in ProjectCosts.categories)
        category.key:
            (current[category.key] ?? 0) +
                (_otherItemsCosts[category.key] ?? 0),
    };

    double sumOf(Map<String, double> map) =>
        map.values.fold<double>(0, (sum, value) => sum + value);

    final projectedTotal = sumOf(projected);
    final itemTotal = sumOf(current);

    // التكاليف الفعلية التي سجلها مشرف هذا البند.
    final actual = ProjectCosts.actualBreakdownOf(_itemData);
    final actualTotal = sumOf(actual);

    // الإجمالي المعتمد للمشروع: الفعلي لقسم البند إن وُجد وإلا المخطط.
    final projectedEffective = <String, double>{
      for (final category in ProjectCosts.categories)
        category.key:
            (actual[category.key] ?? 0) > 0
                ? (actual[category.key] ?? 0)
                : (current[category.key] ?? 0) +
                    (_otherItemsEffective[category.key] ?? 0),
    };

    final effectiveTotal = sumOf(projectedEffective);
    final share = projectedTotal <= 0
        ? 0.0
        : (itemTotal / projectedTotal).clamp(0.0, 1.0).toDouble();

    return AppCard(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'تكلفة المشروع',
            subtitle: 'محسوبة تلقائيًا من مجموع تكاليف البنود',
            icon: Icons.account_balance_wallet_outlined,
          ),
          AppSpacing.verticalSm,
          for (final category in ProjectCosts.categories)
            AppInfoRow(
              label: category.label,
              value: '${ProjectCosts.formatMoney(current[category.key] ?? 0)}'
                  ' / ${ProjectCosts.formatMoney(projected[category.key] ?? 0)}',
              icon: category.icon,
            ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'تكلفة هذا البند',
            value: ProjectCosts.formatMoney(itemTotal),
            icon: Icons.receipt_long_outlined,
          ),
          AppInfoRow(
            label: 'إجمالي تكلفة المشروع المخطط بعد الحفظ',
            value: ProjectCosts.formatMoney(projectedTotal),
            icon: Icons.payments_outlined,
          ),
          if (effectiveTotal > 0 && effectiveTotal != projectedTotal) ...[
            AppSpacing.verticalXs,
            AppInfoRow(
              label: 'الإجمالي المعتمد (الفعلي عند توفره)',
              value: ProjectCosts.formatMoney(effectiveTotal),
              icon: Icons.swap_horiz,
            ),
          ],
          if (actualTotal > 0) ...[
            AppSpacing.verticalXs,
            AppInfoRow(
              label: 'التكلفة الفعلية التي سجلها مشرف البند',
              value: ProjectCosts.formatMoney(actualTotal),
              icon: Icons.check_circle_outline,
            ),
            AppSpacing.verticalXs,
            Text(
              actualTotal > itemTotal
                  ? 'أعلى من مخططك بفارق '
                      '${ProjectCosts.formatMoney(actualTotal - itemTotal)}'
                  : 'أقل من مخططك بفارق '
                      '${ProjectCosts.formatMoney(itemTotal - actualTotal)}',
              style: AppTextStyles.small,
            ),
          ] else ...[
            AppSpacing.verticalXs,
            const Text(
              'لم يسجل مشرف هذا البند تكاليف فعلية بعد؛ '
              'يدخلها من صفحته (المواد والعمالة والمعدات والمحروقات).',
              style: AppTextStyles.small,
            ),
          ],
          if (projectedTotal > 0) ...[
            AppSpacing.verticalSm,
            AppProgress(
              value: share,
              label: 'حصة هذا البند من تكلفة المشروع',
              height: 6,
            ),
          ],
          AppSpacing.verticalSm,
          Text(
            _otherItemsCount == 0
                ? 'لا توجد بنود أخرى في هذا المشروع بعد.'
                : 'مجموع تكاليف $_otherItemsCount بند آخر: '
                    '${ProjectCosts.formatMoney(sumOf(_otherItemsCosts))}',
            style: AppTextStyles.small,
          ),
        ],
      ),
    );
  }

  Widget _buildExecutionSection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'المسؤول عن البند: مشرف البند والمعدة',
            icon: Icons.settings_outlined,
          ),
          AppSpacing.verticalSm,
          const Text(
            'اختر المعدة من حصر المعدات؛ ومشرف البند مرتبط بالمشروع '
            'مسبقًا فيُسند إليه البند تلقائيًا ما لم تُغيّره. الاستهلاك المخطط '
            '(الوقود والزيت وساعات العمل) لم يعد يُدخل هنا: يُسجَّل أسطرًا في '
            'قسم «تكلفة استهلاك المحروقات» ضمن تكاليف البند، ويسجّل مشرف '
            'البند المستهلك الفعلي من صفحته، ويسجّل المهندس كمية البند '
            'المنفذة بشكل مستقل.',
            style: AppTextStyles.bodySecondary,
          ),
          AppSpacing.verticalMd,
          _buildEquipmentDropdown(),
          AppSpacing.verticalMd,
          _buildSupervisorSection(),
          AppSpacing.verticalMd,
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 20, color: AppColors.primary),
                AppSpacing.horizontalSm,
                Expanded(
                  child: Text(
                    'اختيار المعدة لا يحسب كمية البند ولا يغيّر قراءة العداد. قراءة العداد منفصلة، وكمية التنفيذ يسجلها المهندس، والاستهلاك الفعلي يسجله مشرف البند.',
                    style: AppTextStyles.bodySecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'تفاصيل البند والتكاليف',
      showBackButton: true,
      child: _loadingItem
          ? const AppLoading(message: 'جاري تحميل بيانات البند...')
          : _itemData == null
              ? const AppEmpty(message: 'لا توجد بيانات للبند', icon: Icons.assignment_outlined)
              : AppPage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppPageHeader(
                        title: 'تفاصيل البند والتكاليف',
                        subtitle:
                            'بيانات البند، تكاليفه، تنفيذه، والمسؤول عنه (مشرف البند)',
                        icon: Icons.settings_outlined,
                      ),
                      AppSpacing.verticalLg,
                      _buildItemDataSection(),
                      AppSpacing.verticalMd,
                      _buildCostsSection(),
                      AppSpacing.verticalMd,
                      _buildExecutionSummaryCard(),
                      AppSpacing.verticalMd,
                      _buildExecutionSection(),
                      AppSpacing.verticalLg,
                      AppButton(
                        label: _savingAll
                            ? 'جارٍ حفظ التفاصيل...'
                            : 'حفظ تفاصيل البند وتكاليفه',
                        icon: Icons.save_outlined,
                        loading: _savingAll,
                        expanded: true,
                        onPressed: _savingAll ? null : _saveAll,
                      ),
                      AppSpacing.verticalLg,
                    ],
                  ),
                ),
    );
  }
}

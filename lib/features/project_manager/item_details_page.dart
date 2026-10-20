import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/costs.dart';
import '../../core/widgets/app_widgets.dart';

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
  final TextEditingController _defaultFuelQuantityController = TextEditingController();
  final TextEditingController _defaultOilQuantityController = TextEditingController();
  final TextEditingController _defaultWorkingHoursController = TextEditingController();

  /// تكلفة الوحدة لكل قسم تكلفة (مواد / أجور / معدات / محروقات).
  final Map<String, TextEditingController> _unitCostControllers = {
    for (final category in ProjectCosts.categories)
      category.key: TextEditingController(),
  };

  /// الإجمالي المتوقع لكل قسم، ويمكن تعديله يدويًا.
  final Map<String, TextEditingController> _totalCostControllers = {
    for (final category in ProjectCosts.categories)
      category.key: TextEditingController(),
  };

  /// الأقسام التي أدخل فيها المدير إجماليًا يدويًا
  /// فلا تُعاد حوسبته من تكلفة الوحدة.
  final Set<String> _manualTotalCategories = <String>{};

  Map<String, dynamic>? _itemData;
  String? _projectName;
  bool _loadingItem = true;
  bool _savingAll = false;

  String? _selectedSupervisorId;
  String? _selectedSupervisorName;
  String? _selectedEquipmentId;
  String? _selectedEquipmentName;
  String? _selectedEquipmentCode;
  String? _selectedEquipmentWorkUnit;
  double? _equipmentMeterAtAssignment;
  String? _selectedFuelType;

  /// التكاليف المخططة للمشروع (للمقارنة عند حفظ تكاليف البند).
  Map<String, double> _projectPlannedCosts = <String, double>{};
  double _projectPlannedTotal = 0;

  /// مجموع تكاليف بقية بنود المشروع لنفس الأقسام.
  Map<String, double> _otherItemsCosts = <String, double>{};

  static const List<String> _fuelTypes = ['ديزل', 'بترول'];

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
    _defaultFuelQuantityController.dispose();
    _defaultOilQuantityController.dispose();
    _defaultWorkingHoursController.dispose();

    for (final controller in _unitCostControllers.values) {
      controller.dispose();
    }

    for (final controller in _totalCostControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  /// الكمية التعاقدية للبند كما هي محفوظة.
  double get _contractQuantity =>
      _toDouble(_itemData?['contractQuantity']) ?? 0;

  /// قيمة تكلفة الوحدة المدخلة حاليًا.
  double _unitCostValue(String key) =>
      ProjectCosts.parseOptional(_unitCostControllers[key]?.text ?? '') ?? 0;

  /// الإجمالي المتوقع المحسوب أو المدخل يدويًا.
  double _totalCostValue(String key) =>
      ProjectCosts.parseOptional(_totalCostControllers[key]?.text ?? '') ?? 0;

  double get _itemTotalCost {
    double total = 0;

    for (final category in ProjectCosts.categories) {
      total += _totalCostValue(category.key);
    }

    return total;
  }

  /// عند تغيير تكلفة الوحدة نُحدّث الإجمالي تلقائيًا ما لم يُدخل يدويًا.
  void _onUnitCostChanged(String key) {
    if (_manualTotalCategories.contains(key)) return;

    final total = _unitCostValue(key) * _contractQuantity;

    _totalCostControllers[key]?.text =
        ProjectCosts.toEditText(total);

    if (mounted) setState(() {});
  }

  void _onTotalCostChanged(String key) {
    if (_totalCostControllers[key]?.text.trim().isNotEmpty ?? false) {
      _manualTotalCategories.add(key);
    } else {
      _manualTotalCategories.remove(key);
      _onUnitCostChanged(key);
      return;
    }

    if (mounted) setState(() {});
  }

  String _stringValue(dynamic value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    return value.toString().trim();
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return null;
    return double.tryParse(value.toString().trim().replaceAll(',', '.'));
  }

  double? _parsePositiveDouble(String value) {
    final result = _toDouble(value);
    if (result == null || result <= 0) return null;
    return result;
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
      _defaultFuelQuantityController.text =
          _stringValue(details['defaultFuelQuantity'] ?? details['defaultDieselQuantity']);
      _defaultOilQuantityController.text = _stringValue(details['defaultOilQuantity']);
      _defaultWorkingHoursController.text = _stringValue(details['defaultWorkingHours']);

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

      // تكاليف البند: نقرأ من التفاصيل أولًا ثم من بيانات البند.
      final costSource = <String, dynamic>{
        ...itemData,
        ...details,
      };

      final loadedQuantity =
          ProjectCosts.toDouble(itemData['contractQuantity']);

      for (final category in ProjectCosts.categories) {
        final unitValue =
            ProjectCosts.toDouble(costSource[category.unitField]);
        final totalValue =
            ProjectCosts.toDouble(costSource[category.totalField]);

        _unitCostControllers[category.key]?.text =
            ProjectCosts.toEditText(unitValue);

        _totalCostControllers[category.key]?.text =
            ProjectCosts.toEditText(totalValue);

        // الإجمالي المكتوب يدويًا لا يُعاد حسابه من تكلفة الوحدة.
        final autoTotal = unitValue * loadedQuantity;

        if (totalValue > 0 &&
            unitValue > 0 &&
            loadedQuantity > 0 &&
            (totalValue - autoTotal).abs() > 0.01) {
          _manualTotalCategories.add(category.key);
        } else {
          _manualTotalCategories.remove(category.key);
        }
      }

      _selectedEquipmentId = _stringValue(details['equipmentId']).isEmpty
          ? null
          : _stringValue(details['equipmentId']);
      _selectedEquipmentName = _stringValue(details['equipmentName']).isEmpty
          ? null
          : _stringValue(details['equipmentName']);
      _selectedEquipmentCode = _stringValue(details['equipmentCode']).isEmpty
          ? null
          : _stringValue(details['equipmentCode']);
      _selectedEquipmentWorkUnit = _stringValue(details['equipmentWorkUnit']).isEmpty
          ? null
          : _stringValue(details['equipmentWorkUnit']);
      _equipmentMeterAtAssignment = _toDouble(details['equipmentCurrentMeterAtAssignment']);

      final fuelType = _stringValue(details['fuelType']);
      _selectedFuelType = _fuelTypes.contains(fuelType) ? fuelType : null;

      String? projectName;

      var plannedCosts = <String, double>{};
      var plannedTotal = 0.0;

      final projectDoc = await _firestore.collection('projects').doc(widget.projectId).get();
      if (projectDoc.exists) {
        final project = projectDoc.data() ?? <String, dynamic>{};
        projectName = _stringValue(
          project['name'] ?? project['projectName'] ?? project['title'],
        );
        if (projectName.isEmpty) projectName = null;

        plannedCosts = ProjectCosts.breakdownOf(project);
        plannedTotal = ProjectCosts.totalOf(project);
      }

      // مجموع تكاليف بقية بنود المشروع لنفس أقسام التكلفة.
      var otherCosts = <String, double>{
        for (final category in ProjectCosts.categories) category.key: 0.0,
      };

      try {
        final itemsSnapshot = await _firestore
            .collection('items')
            .where('projectId', isEqualTo: widget.projectId)
            .get();

        for (final doc in itemsSnapshot.docs) {
          if (doc.id == widget.itemId) continue;

          final other = ProjectCosts.breakdownOf(doc.data());

          for (final entry in other.entries) {
            otherCosts[entry.key] =
                (otherCosts[entry.key] ?? 0) + entry.value;
          }
        }
      } catch (e) {
        debugPrint('تعذر حساب تكاليف بقية البنود: $e');
      }

      if (!mounted) return;
      setState(() {
        _itemData = itemData;
        _projectName = projectName;
        _projectPlannedCosts = plannedCosts;
        _projectPlannedTotal = plannedTotal;
        _otherItemsCosts = otherCosts;
        _loadingItem = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingItem = false);
      AppWidgets.showError(context, 'حدث خطأ أثناء تحميل بيانات البند:\n$e');
    }
  }

  /// حسابات مشرفي البنود المرتبطين بهذا المشروع.
  Stream<QuerySnapshot<Map<String, dynamic>>> _supervisorsStream() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'supervisor')
        .where('active', isEqualTo: true)
        .where('projectIds', arrayContains: widget.projectId)
        .snapshots();
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

    if (_selectedEquipmentId == null || _selectedEquipmentId!.isEmpty) {
      AppWidgets.showWarning(context, 'يرجى اختيار المعدة من حصر المعدات');
      return;
    }
    if (_selectedSupervisorId == null || _selectedSupervisorId!.isEmpty) {
      AppWidgets.showWarning(context, 'يرجى تحديد مشرف البند');
      return;
    }

    // التحقق من تكاليف البند المدخلة (اختيارية لكن يجب أن تكون صحيحة).
    for (final category in ProjectCosts.categories) {
      final unitText =
          _unitCostControllers[category.key]?.text.trim() ?? '';
      final totalText =
          _totalCostControllers[category.key]?.text.trim() ?? '';

      if (unitText.isNotEmpty &&
          ProjectCosts.parseOptional(unitText) == null) {
        AppWidgets.showWarning(
          context,
          'أدخل ${category.label} للوحدة بشكل صحيح',
        );
        return;
      }

      if (totalText.isNotEmpty &&
          ProjectCosts.parseOptional(totalText) == null) {
        AppWidgets.showWarning(
          context,
          'أدخل ${category.label} بشكل صحيح',
        );
        return;
      }
    }
    if (_selectedFuelType == null || _selectedFuelType!.isEmpty) {
      AppWidgets.showWarning(context, 'يرجى اختيار نوع الوقود');
      return;
    }

    final fuelQuantity = _parsePositiveDouble(_defaultFuelQuantityController.text);
    final oilQuantity = _parsePositiveDouble(_defaultOilQuantityController.text);
    final workingHours = _parsePositiveDouble(_defaultWorkingHoursController.text);

    if (fuelQuantity == null) {
      AppWidgets.showWarning(context, 'أدخل كمية الوقود المخططة بشكل صحيح');
      return;
    }
    if (oilQuantity == null) {
      AppWidgets.showWarning(context, 'أدخل كمية الزيت المخططة بشكل صحيح');
      return;
    }
    if (workingHours == null) {
      AppWidgets.showWarning(context, 'أدخل ساعات العمل المخططة بشكل صحيح');
      return;
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      AppWidgets.showError(context, 'المستخدم غير مسجل الدخول');
      return;
    }

    setState(() => _savingAll = true);
    try {
      // إعادة قراءة المعدة ومشرف البند قبل الحفظ للتأكد من صحة سجلاتهما.
      final equipmentDoc = await _equipmentCollection.doc(_selectedEquipmentId).get();
      if (!equipmentDoc.exists) {
        throw Exception('المعدة المحددة لم تعد موجودة في حصر المعدات');
      }
      final equipment = equipmentDoc.data() ?? <String, dynamic>{};
      if (_stringValue(equipment['status'], defaultValue: 'active') == 'inactive') {
        throw Exception('المعدة المحددة غير نشطة؛ اختر معدة نشطة أخرى');
      }

      final supervisorDoc =
          await _firestore.collection('users').doc(_selectedSupervisorId).get();

      if (!supervisorDoc.exists) throw Exception('حساب المشرف غير موجود');

      final supervisorData = supervisorDoc.data() ?? <String, dynamic>{};

      final supervisorRole = _stringValue(supervisorData['role']);

      // دور السائق هو الدور القديم الذي استُبدل بمشرف البند.
      final bool isSupervisorAccount =
          supervisorData['active'] == true &&
              (supervisorRole == 'supervisor' || supervisorRole == 'driver');

      if (!isSupervisorAccount) {
        throw Exception('حساب المشرف غير نشط أو ليس حساب مشرف بند');
      }

      final supervisorProjects = (supervisorData['projectIds'] as List?)
              ?.map((value) => value.toString())
              .toSet() ??
          <String>{};

      if (!supervisorProjects.contains(widget.projectId)) {
        throw Exception(
          'المشرف غير مرتبط بهذا المشروع. اربطه بالمشروع من إدارة المستخدمين أولاً.',
        );
      }

      final equipmentName = _stringValue(
        equipment['name'] ?? equipment['type'],
        defaultValue: 'معدة بدون اسم',
      );
      final equipmentCode = _stringValue(equipment['code']);
      final equipmentWorkUnit = _stringValue(equipment['workUnit']);
      final equipmentCurrentMeter = _toDouble(equipment['currentMeter']);

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

      // تكاليف البند: تُحفظ في التفاصيل وفي وثيقة البند.
      final costData = ProjectCosts.buildSaveData(
        totalTexts: {
          for (final entry in _totalCostControllers.entries)
            entry.key: entry.value.text,
        },
        unitTexts: {
          for (final entry in _unitCostControllers.entries)
            entry.key: entry.value.text,
        },
        contractQuantity: _contractQuantity,
        includeZeros: true,
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
        'contractQuantity': _itemData!['contractQuantity'],
        'unit': _itemData!['unit'],
        'code': _itemData!['code'],
        'description': _descriptionController.text.trim(),
        'notes': _notesController.text.trim(),
        'supervisorId': _selectedSupervisorId,
        'supervisorName': supervisorDisplayName,
        'assignedToType': 'supervisor',
        'equipmentId': _selectedEquipmentId,
        'equipmentName': equipmentName,
        'equipmentCode': equipmentCode,
        'equipmentWorkUnit': equipmentWorkUnit,
        'equipmentCurrentMeterAtAssignment': equipmentCurrentMeter,
        'fuelType': _selectedFuelType,
        // defaultFuelQuantity هو الاسم الأساسي، ونحفظ الاسم القديم للتوافق مع النسخة الحالية.
        'defaultFuelQuantity': fuelQuantity,
        'defaultDieselQuantity': fuelQuantity,
        'defaultOilQuantity': oilQuantity,
        'defaultWorkingHours': workingHours,
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
        'equipmentId': _selectedEquipmentId,
        'equipmentName': equipmentName,
        'equipmentCode': equipmentCode,
        'active': true,
        'fuelType': _selectedFuelType,
        'defaultFuelQuantity': fuelQuantity,
        'defaultOilQuantity': oilQuantity,
        'defaultWorkingHours': workingHours,
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
          'supervisorId': _selectedSupervisorId,
          'supervisorName': supervisorDisplayName,

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
        _selectedEquipmentName = equipmentName;
        _selectedEquipmentCode = equipmentCode;
        _selectedEquipmentWorkUnit = equipmentWorkUnit;
        _equipmentMeterAtAssignment = equipmentCurrentMeter;
      });
      AppWidgets.showSuccess(
        context,
        'تم حفظ تفاصيل البند وربط المعدة ومشرف البند بنجاح',
      );

      // تنبيه غير معطّل عند تجاوز المخطط العام للمشروع.
      if (_projectPlannedTotal > 0) {
        final remaining = _projectPlannedTotal - itemTotalCost;

        if (remaining < 0 && mounted) {
          AppWidgets.showWarning(
            context,
            'إجمالي تكلفة البند تجاوز المخطط العام للمشروع بمبلغ '
            '${ProjectCosts.formatMoney(remaining.abs())}',
          );
        }
      }

      await _loadItem();
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showError(context, 'تعذر حفظ تفاصيل البند:\n$e');
    } finally {
      if (mounted) setState(() => _savingAll = false);
    }
  }

  Widget _buildItemInfo() {
    final data = _itemData!;
    final itemName = _stringValue(
      data['name'],
      defaultValue: _stringValue(data['itemDefinitionName'], defaultValue: 'بدون اسم'),
    );
    final typeName = _stringValue(data['typeName'], defaultValue: 'بدون نوع');
    final quantity = _stringValue(data['contractQuantity'], defaultValue: '0');
    final unit = _stringValue(data['unit'], defaultValue: '');
    final code = _stringValue(data['code'], defaultValue: '—');

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.assignment_outlined, size: 38, color: AppColors.primary),
          AppSpacing.verticalSm,
          Text(itemName, textAlign: TextAlign.center, style: AppTextStyles.pageTitle),
          AppSpacing.verticalXs,
          Text('النوع: $typeName', textAlign: TextAlign.center, style: AppTextStyles.bodySecondary),
          AppSpacing.verticalMd,
          AppInfoRow(label: 'المشروع', value: _projectName ?? widget.projectId, icon: Icons.business_outlined),
          AppSpacing.verticalSm,
          AppInfoRow(label: 'كود البند', value: code, icon: Icons.qr_code_2_outlined),
          AppSpacing.verticalSm,
          AppInfoRow(label: 'كمية العقد', value: '$quantity $unit', icon: Icons.numbers_outlined),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'مشرف البند',
            value: _selectedSupervisorName ?? 'لم يُحدد بعد',
            icon: Icons.supervisor_account_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'إجمالي تكلفة البند',
            value: ProjectCosts.formatMoney(ProjectCosts.totalOf(data)),
            icon: Icons.payments_outlined,
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
          return status != 'inactive' || doc.id == _selectedEquipmentId;
        }).toList()
          ..sort((a, b) => _stringValue(a.data()['code']).compareTo(_stringValue(b.data()['code'])));

        if (options.isEmpty) {
          return const AppEmpty(
            message: 'لا توجد معدات مسجلة. أضف المعدات أولًا من صفحة «حصر المعدات» لدى مسؤول النظام.',
            icon: Icons.precision_manufacturing_outlined,
          );
        }

        final valueExists = options.any((doc) => doc.id == _selectedEquipmentId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDropdown<String>(
              label: 'المعدة *',
              hint: 'اختر المعدة من حصر المعدات',
              value: valueExists ? _selectedEquipmentId : null,
              prefixIcon: Icons.precision_manufacturing_outlined,
              items: options.map((doc) {
                final data = doc.data();
                final inactive = _stringValue(data['status'], defaultValue: 'active') == 'inactive';
                return DropdownMenuItem<String>(
                  value: doc.id,
                  enabled: !inactive,
                  child: Text(
                    '${_equipmentDisplayName(data)}${inactive ? ' (غير نشطة)' : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (id) {
                if (id == null) return;
                final selectedDoc = options.firstWhere((doc) => doc.id == id);
                final data = selectedDoc.data();
                setState(() {
                  _selectedEquipmentId = id;
                  _selectedEquipmentName = _stringValue(data['name'] ?? data['type'], defaultValue: 'معدة بدون اسم');
                  _selectedEquipmentCode = _stringValue(data['code']);
                  _selectedEquipmentWorkUnit = _stringValue(data['workUnit']);
                  _equipmentMeterAtAssignment = _toDouble(data['currentMeter']);
                });
              },
            ),
            if (_selectedEquipmentId != null) ...[
              AppSpacing.verticalSm,
              AppCard(
                color: AppColors.background,
                child: Column(
                  children: [
                    AppInfoRow(label: 'كود المعدة', value: _selectedEquipmentCode?.isNotEmpty == true ? _selectedEquipmentCode! : '—', icon: Icons.tag),
                    AppSpacing.verticalXs,
                    AppInfoRow(label: 'وحدة عمل المعدة', value: _selectedEquipmentWorkUnit?.isNotEmpty == true ? _selectedEquipmentWorkUnit! : 'غير محددة', icon: Icons.speed),
                    AppSpacing.verticalXs,
                    AppInfoRow(label: 'قراءة العداد عند الإسناد', value: _equipmentMeterAtAssignment == null ? 'غير مسجلة' : _equipmentMeterAtAssignment!.toString(), icon: Icons.speed_outlined),
                  ],
                ),
              ),
            ],
          ],
        );
      },
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
        final docs = snapshot.data?.docs ?? [];
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
            });
          },
        );
      },
    );
  }

  // ============================================================
  // تكاليف البند
  // ============================================================

  Widget _buildCostsSection() {
    final rows = <Widget>[];

    for (int i = 0; i < ProjectCosts.categories.length; i++) {
      final category = ProjectCosts.categories[i];

      if (i != 0) rows.add(AppSpacing.verticalMd);

      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppNumberField(
                controller: _unitCostControllers[category.key],
                label: 'تكلفة وحدة: ${category.shortLabel}',
                hint: 'للوحدة الواحدة',
                suffixText: ProjectCosts.currency,
                prefixIcon: category.icon,
                onChanged: (_) => _onUnitCostChanged(category.key),
              ),
            ),
            AppSpacing.horizontalMd,
            Expanded(
              child: AppNumberField(
                controller: _totalCostControllers[category.key],
                label: 'إجمالي ${category.shortLabel}',
                hint: 'محسوب تلقائيًا',
                suffixText: ProjectCosts.currency,
                prefixIcon: Icons.calculate_outlined,
                onChanged: (_) => _onTotalCostChanged(category.key),
              ),
            ),
          ],
        ),
      );
    }

    final totalUnitCost = ProjectCosts.categories
        .map((category) => _unitCostValue(category.key))
        .fold<double>(0, (sum, value) => sum + value);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'تكاليف البند',
            subtitle:
                'المواد وأجور العمالة والمعدات والمحروقات. '
                'أدخل تكلفة الوحدة ليُحسب الإجمالي تلقائيًا، '
                'أو أدخل الإجمالي مباشرة.',
            icon: Icons.payments_outlined,
          ),
          AppSpacing.verticalMd,
          ...rows,
          AppSpacing.verticalMd,
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppInfoRow(
                  label: 'كمية العقد',
                  value: '${ProjectCosts.formatNumber(_contractQuantity)} '
                      '${_stringValue(_itemData?['unit'])}'.trim(),
                  icon: Icons.numbers_outlined,
                ),
                AppSpacing.verticalXs,
                AppInfoRow(
                  label: 'إجمالي تكلفة الوحدة',
                  value: ProjectCosts.formatMoney(totalUnitCost),
                  icon: Icons.trending_up_outlined,
                ),
                AppSpacing.verticalXs,
                AppInfoRow(
                  label: 'إجمالي تكلفة البند المتوقع',
                  value: ProjectCosts.formatMoney(_itemTotalCost),
                  icon: Icons.payments_outlined,
                ),
              ],
            ),
          ),
          AppSpacing.verticalMd,
          _buildCostComparison(),
        ],
      ),
    );
  }

  /// مقارنة تكلفة البند بالتكلفة المخططة للمشروع.
  Widget _buildCostComparison() {
    if (_projectPlannedTotal <= 0) {
      return const AppCard(
        color: AppColors.background,
        child: Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.textSecondary, size: 20),
            AppSpacing.horizontalSm,
            Expanded(
              child: Text(
                'لم يحدد مسؤول النظام تكاليف المشروع بعد، '
                'لذلك لا توجد مقارنة مع المخطط العام للمشروع.',
                style: AppTextStyles.bodySecondary,
              ),
            ),
          ],
        ),
      );
    }

    final othersTotal = _otherItemsCosts.values
        .fold<double>(0, (sum, value) => sum + value);

    final total = _itemTotalCost;
    final remaining = _projectPlannedTotal - othersTotal;
    final exceeded = total > remaining + 0.01;

    return AppCard(
      color: exceeded
          ? AppColors.danger.withValues(alpha: 0.06)
          : AppColors.success.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                exceeded
                    ? Icons.warning_amber_rounded
                    : Icons.verified_outlined,
                size: 20,
                color: exceeded ? AppColors.danger : AppColors.success,
              ),
              AppSpacing.horizontalSm,
              Expanded(
                child: Text(
                  exceeded
                      ? 'تكلفة هذا البند تتجاوز المتبقي من مخطط المشروع'
                      : 'تكلفة هذا البند ضمن المخطط العام للمشروع',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.bold,
                    color: exceeded ? AppColors.danger : AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.verticalSm,
          for (final category in ProjectCosts.categories)
            AppInfoRow(
              label: 'متبقي ${category.shortLabel}',
              value: ProjectCosts.formatMoney(
                (() {
                  final left = (_projectPlannedCosts[category.key] ?? 0) -
                      (_otherItemsCosts[category.key] ?? 0);
                  return left < 0 ? 0.0 : left;
                })(),
              ),
              icon: category.icon,
            ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'إجمالي مخطط المشروع',
            value: ProjectCosts.formatMoney(_projectPlannedTotal),
            icon: Icons.business_outlined,
          ),
          AppInfoRow(
            label: 'مخصص لبقية البنود',
            value: ProjectCosts.formatMoney(othersTotal),
            icon: Icons.playlist_add_check_outlined,
          ),
          AppInfoRow(
            label: 'المتبقي لهذا البند',
            value: ProjectCosts.formatMoney(remaining < 0 ? 0 : remaining),
            icon: Icons.savings_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(title: 'تفاصيل البند', icon: Icons.description_outlined),
          AppSpacing.verticalMd,
          AppTextField(
            controller: _descriptionController,
            label: 'وصف البند',
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

  Widget _buildExecutionSection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(title: 'المعدة ومشرف البند والاستهلاك المخطط', icon: Icons.settings_outlined),
          AppSpacing.verticalSm,
          const Text(
            'اختر المعدة من حصر المعدات، ثم مشرف البند. هذه الكميات مخططة للتكليف؛ مشرف البند يسجل الاستهلاك الفعلي لاحقًا، والمهندس يسجل كمية البند المنفذة بشكل مستقل.',
            style: AppTextStyles.bodySecondary,
          ),
          AppSpacing.verticalMd,
          _buildEquipmentDropdown(),
          AppSpacing.verticalMd,
          _buildSupervisorDropdown(),
          AppSpacing.verticalMd,
          AppDropdown<String>(
            label: 'نوع الوقود *',
            hint: 'اختر نوع الوقود',
            value: _selectedFuelType,
            prefixIcon: Icons.local_gas_station_outlined,
            items: _fuelTypes.map((fuel) => DropdownMenuItem<String>(value: fuel, child: Text(fuel))).toList(),
            onChanged: (value) => setState(() => _selectedFuelType = value),
          ),
          AppSpacing.verticalMd,
          AppNumberField(
            controller: _defaultFuelQuantityController,
            label: 'كمية الوقود المخططة *',
            hint: 'أدخل الكمية المخططة',
            suffixText: 'لتر',
            prefixIcon: Icons.local_gas_station_outlined,
          ),
          AppSpacing.verticalMd,
          AppNumberField(
            controller: _defaultOilQuantityController,
            label: 'كمية الزيت المخططة *',
            hint: 'أدخل كمية الزيت المخططة',
            suffixText: 'لتر',
            prefixIcon: Icons.oil_barrel_outlined,
          ),
          AppSpacing.verticalMd,
          AppNumberField(
            controller: _defaultWorkingHoursController,
            label: 'ساعات العمل المخططة *',
            hint: 'أدخل ساعات العمل المخططة',
            suffixText: 'ساعة',
            prefixIcon: Icons.schedule_outlined,
          ),
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
      title: 'تفاصيل البند',
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
                        title: 'تفاصيل البند',
                        subtitle:
                            'ربط البند بالمعدة ومشرف البند، وتحديد التكاليف والاستهلاك المخطط',
                        icon: Icons.settings_outlined,
                      ),
                      AppSpacing.verticalLg,
                      _buildItemInfo(),
                      AppSpacing.verticalMd,
                      _buildDetailsSection(),
                      AppSpacing.verticalMd,
                      _buildCostsSection(),
                      AppSpacing.verticalMd,
                      _buildExecutionSection(),
                      AppSpacing.verticalLg,
                      AppButton(
                        label: _savingAll ? 'جارٍ حفظ التفاصيل...' : 'حفظ التفاصيل وتكليف المشرف',
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

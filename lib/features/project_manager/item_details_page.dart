import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

/// تفاصيل بند المشروع: اختيار المعدة والسائق وتحديد الاستهلاك المخطط.
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

  Map<String, dynamic>? _itemData;
  String? _projectName;
  bool _loadingItem = true;
  bool _savingAll = false;

  String? _selectedDriverId;
  String? _selectedDriverName;
  String? _selectedEquipmentId;
  String? _selectedEquipmentName;
  String? _selectedEquipmentCode;
  String? _selectedEquipmentWorkUnit;
  double? _equipmentMeterAtAssignment;
  String? _selectedFuelType;

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
    super.dispose();
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

      _selectedDriverId = _stringValue(details['driverId']).isEmpty
          ? null
          : _stringValue(details['driverId']);
      _selectedDriverName = _stringValue(details['driverName']).isEmpty
          ? null
          : _stringValue(details['driverName']);

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
      final projectDoc = await _firestore.collection('projects').doc(widget.projectId).get();
      if (projectDoc.exists) {
        final project = projectDoc.data() ?? <String, dynamic>{};
        projectName = _stringValue(
          project['name'] ?? project['projectName'] ?? project['title'],
        );
        if (projectName.isEmpty) projectName = null;
      }

      if (!mounted) return;
      setState(() {
        _itemData = itemData;
        _projectName = projectName;
        _loadingItem = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingItem = false);
      AppWidgets.showError(context, 'حدث خطأ أثناء تحميل بيانات البند:\n$e');
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _driversStream() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'driver')
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
    if (_selectedDriverId == null || _selectedDriverId!.isEmpty) {
      AppWidgets.showWarning(context, 'يرجى تحديد السائق المسؤول عن البند');
      return;
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
      // إعادة قراءة المعدة والسائق قبل الحفظ للتأكد من أن سجلاتهما ما زالت صالحة.
      final equipmentDoc = await _equipmentCollection.doc(_selectedEquipmentId).get();
      if (!equipmentDoc.exists) {
        throw Exception('المعدة المحددة لم تعد موجودة في حصر المعدات');
      }
      final equipment = equipmentDoc.data() ?? <String, dynamic>{};
      if (_stringValue(equipment['status'], defaultValue: 'active') == 'inactive') {
        throw Exception('المعدة المحددة غير نشطة؛ اختر معدة نشطة أخرى');
      }

      final driverDoc = await _firestore.collection('users').doc(_selectedDriverId).get();
      if (!driverDoc.exists) throw Exception('حساب السائق غير موجود');
      final driverData = driverDoc.data() ?? <String, dynamic>{};
      if (driverData['active'] != true || _stringValue(driverData['role']) != 'driver') {
        throw Exception('حساب السائق غير نشط أو ليس حساب سائق');
      }
      final driverProjects = (driverData['projectIds'] as List?)
              ?.map((value) => value.toString())
              .toSet() ??
          <String>{};
      if (!driverProjects.contains(widget.projectId)) {
        throw Exception('السائق غير مرتبط بهذا المشروع. اربطه بالمشروع من إدارة المستخدمين أولاً.');
      }

      final equipmentName = _stringValue(
        equipment['name'] ?? equipment['type'],
        defaultValue: 'معدة بدون اسم',
      );
      final equipmentCode = _stringValue(equipment['code']);
      final equipmentWorkUnit = _stringValue(equipment['workUnit']);
      final equipmentCurrentMeter = _toDouble(equipment['currentMeter']);

      // مزامنة الاسم من حساب السائق لتجنب حفظ اسم قديم.
      final driverName = _stringValue(
        driverData['name'],
        defaultValue: _stringValue(driverData['username'], defaultValue: _selectedDriverName ?? 'سائق'),
      );
      final driverJobNumber = _stringValue(driverData['jobNumber']);
      final driverDisplayName = driverJobNumber.isEmpty
          ? driverName
          : '$driverName - $driverJobNumber';

      final detailsRef = _firestore.collection('item_details').doc(widget.itemId);
      final assignmentCollection = _firestore.collection('item_drivers');
      final assignmentRef = assignmentCollection.doc(widget.itemId);
      final existingAssignment = await assignmentRef.get();
      final existingAssignments = await assignmentCollection
          .where('itemId', isEqualTo: widget.itemId)
          .get();

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
        'driverId': _selectedDriverId,
        'driverName': driverDisplayName,
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
        'detailsAdded': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUser.uid,
      };

      final assignmentData = <String, dynamic>{
        'itemId': widget.itemId,
        'projectId': widget.projectId,
        'driverId': _selectedDriverId,
        'driverName': driverDisplayName,
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
      batch.set(assignmentRef, assignmentData, SetOptions(merge: true));
      await batch.commit();

      if (!mounted) return;
      setState(() {
        _selectedDriverName = driverDisplayName;
        _selectedEquipmentName = equipmentName;
        _selectedEquipmentCode = equipmentCode;
        _selectedEquipmentWorkUnit = equipmentWorkUnit;
        _equipmentMeterAtAssignment = equipmentCurrentMeter;
      });
      AppWidgets.showSuccess(context, 'تم حفظ تفاصيل البند وربط المعدة والسائق بنجاح');
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

  Widget _buildDriverDropdown() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _driversStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return AppError(message: 'تعذر تحميل السائقين:\n${snapshot.error}');
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading(message: 'جاري تحميل السائقين...');
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const AppEmpty(
            message: 'لا يوجد سائقون فعالون مرتبطون بهذا المشروع. اربط السائق بالمشروع من إدارة المستخدمين أولًا.',
            icon: Icons.person_outline,
          );
        }

        final selectedExists = docs.any((doc) => doc.id == _selectedDriverId);
        return AppDropdown<String>(
          label: 'السائق المسؤول *',
          hint: 'اختر السائق',
          value: selectedExists ? _selectedDriverId : null,
          prefixIcon: Icons.local_shipping_outlined,
          items: docs.map((doc) {
            final data = doc.data();
            final name = _stringValue(data['name'], defaultValue: _stringValue(data['username'], defaultValue: 'سائق'));
            final jobNumber = _stringValue(data['jobNumber']);
            return DropdownMenuItem<String>(
              value: doc.id,
              child: Text(jobNumber.isEmpty ? name : '$name - $jobNumber', overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (id) {
            if (id == null) return;
            final data = docs.firstWhere((doc) => doc.id == id).data();
            final name = _stringValue(data['name'], defaultValue: _stringValue(data['username'], defaultValue: 'سائق'));
            final jobNumber = _stringValue(data['jobNumber']);
            setState(() {
              _selectedDriverId = id;
              _selectedDriverName = jobNumber.isEmpty ? name : '$name - $jobNumber';
            });
          },
        );
      },
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
          const AppSectionTitle(title: 'المعدة والسائق والاستهلاك المخطط', icon: Icons.settings_outlined),
          AppSpacing.verticalSm,
          const Text(
            'اختر المعدة من حصر المعدات، ثم السائق. هذه الكميات مخططة للتكليف؛ السائق يسجل الاستهلاك الفعلي لاحقًا، والمهندس يسجل كمية البند المنفذة بشكل مستقل.',
            style: AppTextStyles.bodySecondary,
          ),
          AppSpacing.verticalMd,
          _buildEquipmentDropdown(),
          AppSpacing.verticalMd,
          _buildDriverDropdown(),
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
                    'اختيار المعدة لا يحسب كمية البند ولا يغيّر قراءة العداد. قراءة العداد منفصلة، وكمية التنفيذ يسجلها المهندس، والاستهلاك الفعلي يسجله السائق.',
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
                        subtitle: 'ربط البند بالمعدة والسائق وتحديد الاستهلاك المخطط',
                        icon: Icons.settings_outlined,
                      ),
                      AppSpacing.verticalLg,
                      _buildItemInfo(),
                      AppSpacing.verticalMd,
                      _buildDetailsSection(),
                      AppSpacing.verticalMd,
                      _buildExecutionSection(),
                      AppSpacing.verticalLg,
                      AppButton(
                        label: _savingAll ? 'جارٍ حفظ التفاصيل...' : 'حفظ التفاصيل وتكليف السائق',
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

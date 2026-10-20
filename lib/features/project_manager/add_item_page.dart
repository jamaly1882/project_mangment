import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';
import 'item_details_page.dart';

class AddItemPage extends StatefulWidget {
  final String projectId;

  const AddItemPage({
    super.key,
    required this.projectId,
  });

  @override
  State<AddItemPage> createState() => _AddItemPageState();
}

class _AddItemPageState extends State<AddItemPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();

  String? _projectName;

  String? _selectedItemDefinitionId;
  String? _selectedItemDefinitionName;

  String? _selectedTypeId;
  String? _selectedTypeName;

  String? _selectedEngineerId;
  String? _selectedEngineerName;

  String? _selectedEquipmentId;
  String? _selectedEquipmentCode;
  String? _selectedEquipmentName;
  String? _selectedEquipmentWorkUnit;
  double? _selectedEquipmentMeter;

  String? _selectedUnit;

  bool _saving = false;

  static const List<String> _units = [
    'م3',
    'م2',
    'م',
    'طن',
    'كجم',
    'قطعة',
    'ساعة',
    'لتر',
    'يوم',
    'أخرى',
  ];

  @override
  void initState() {
    super.initState();
    _loadProjectName();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _quantityController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  double? _parseNumber(String value) {
    final normalized = value
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
        .replaceAll(',', '.')
        .trim();

    return double.tryParse(normalized);
  }

  String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Future<void> _loadProjectName() async {
    try {
      final doc = await _firestore
          .collection('projects')
          .doc(widget.projectId)
          .get();

      if (!doc.exists) return;

      final data = doc.data();
      if (data == null) return;

      final name = _text(
        data['name'],
        fallback: _text(
          data['projectName'],
          fallback: _text(data['title']),
        ),
      );

      if (!mounted) return;

      setState(() {
        _projectName = name.isEmpty ? null : name;
      });
    } catch (e) {
      debugPrint('خطأ في جلب اسم المشروع: $e');
    }
  }

  bool get _canSelectType =>
      _selectedItemDefinitionId != null &&
      _selectedItemDefinitionName != null &&
      _selectedItemDefinitionName!.trim().isNotEmpty;

  bool get _canSelectEngineer =>
      _canSelectType &&
      _selectedTypeId != null &&
      _selectedTypeName != null &&
      _selectedTypeName!.trim().isNotEmpty &&
      _codeController.text.trim().isNotEmpty &&
      (_parseNumber(_quantityController.text) ?? 0) > 0 &&
      _selectedUnit != null &&
      _selectedUnit!.trim().isNotEmpty;

  bool get _canSelectEquipment =>
      _canSelectEngineer &&
      _selectedEngineerId != null &&
      _selectedEngineerId!.trim().isNotEmpty;

  bool get _canSave =>
      _canSelectEquipment &&
      _selectedEquipmentId != null &&
      _durationController.text.trim().isNotEmpty &&
      (int.tryParse(_durationController.text.trim()) ?? 0) > 0;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _typedDocs(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
  ) {
    return List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
      snapshot?.docs ??
          <QueryDocumentSnapshot<Map<String, dynamic>>>[],
    );
  }

  List<Map<String, dynamic>> _currentTypes(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> definitionDocs,
  ) {
    final selected = definitionDocs.where(
      (doc) => doc.id == _selectedItemDefinitionId,
    );

    if (selected.isEmpty) return const [];

    final data = selected.first.data();
    final rawTypes = data['types'];

    if (rawTypes is List) {
      return rawTypes
          .whereType<Map>()
          .map(
            (type) => Map<String, dynamic>.from(type),
          )
          .where(
            (type) => type['active'] != false,
          )
          .toList();
    }

    return const [];
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadTypesFromSubcollection() async {
    final id = _selectedItemDefinitionId;
    if (id == null) {
      return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }

    try {
      final snapshot = await _firestore
          .collection('item_definitions')
          .doc(id)
          .collection('types')
          .where('active', isEqualTo: true)
          .get();

      return List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
        snapshot.docs,
      );
    } catch (e) {
      debugPrint('تعذر تحميل أنواع البند: $e');
      return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }
  }

  Widget _buildDefinitionDropdown() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('item_definitions')
          .where('active', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppError(
            message: 'حدث خطأ في تحميل البنود:\n${snapshot.error}',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading(message: 'جاري تحميل البنود...');
        }

        final List<QueryDocumentSnapshot<Map<String, dynamic>>> definitionDocs =
            _typedDocs(snapshot.data);

        if (definitionDocs.isEmpty) {
          return const AppEmpty(
            icon: Icons.category_outlined,
            title: 'لا توجد بنود متاحة',
            message: 'أضف تعريفات البنود أولاً من إدارة البنود.',
          );
        }

        final items = definitionDocs.map((doc) {
          final data = doc.data();
          return DropdownMenuItem<String>(
            value: doc.id,
            child: Text(
              _text(data['name'], fallback: 'بدون اسم'),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList();

        final selectedExists = definitionDocs.any(
          (doc) => doc.id == _selectedItemDefinitionId,
        );

        return AppDropdown<String>(
          label: 'البند *',
          hint: 'اختر البند',
          value: selectedExists ? _selectedItemDefinitionId : null,
          items: items,
          prefixIcon: Icons.category_outlined,
          onChanged: (value) {
            if (value == null) return;

            final doc = definitionDocs.firstWhere(
              (element) => element.id == value,
            );
            final data = doc.data();

            setState(() {
              _selectedItemDefinitionId = doc.id;
              _selectedItemDefinitionName =
                  _text(data['name'], fallback: 'بدون اسم');
              _selectedTypeId = null;
              _selectedTypeName = null;
              _selectedEngineerId = null;
              _selectedEngineerName = null;
              _selectedEquipmentId = null;
              _selectedEquipmentCode = null;
              _selectedEquipmentName = null;
              _selectedEquipmentWorkUnit = null;
              _selectedEquipmentMeter = null;
            });
          },
        );
      },
    );
  }

  Widget _buildTypeDropdown() {
    if (!_canSelectType) {
      return const AppCard(
        color: AppColors.background,
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: AppColors.textSecondary),
            AppSpacing.horizontalSm,
            Expanded(
              child: Text(
                'اختر البند أولاً لعرض الأنواع.',
                style: AppTextStyles.bodySecondary,
              ),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('item_definitions')
          .doc(_selectedItemDefinitionId)
          .collection('types')
          .where('active', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppError(
            message: 'حدث خطأ في تحميل الأنواع:\n${snapshot.error}',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading(message: 'جاري تحميل الأنواع...');
        }

        final subcollectionDocs = _typedDocs(snapshot.data);
        final items = <DropdownMenuItem<String>>[];

        if (subcollectionDocs.isNotEmpty) {
          for (final doc in subcollectionDocs) {
            final data = doc.data();
            items.add(
              DropdownMenuItem<String>(
                value: doc.id,
                child: Text(
                  _text(data['name'], fallback: 'بدون اسم'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }
        } else {
          return AppCard(
            color: AppColors.warning.withValues(alpha: 0.08),
            child: const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.warning,
                ),
                AppSpacing.horizontalSm,
                Expanded(
                  child: Text(
                    'لا توجد أنواع فعالة لهذا البند في مجموعة الأنواع.',
                    style: AppTextStyles.bodySecondary,
                  ),
                ),
              ],
            ),
          );
        }

        if (items.isEmpty) {
          return const AppCard(
            color: AppColors.warning,
            child: Text('لا توجد أنواع فعالة لهذا البند.'),
          );
        }

        final selectedExists = items.any(
          (item) => item.value == _selectedTypeId,
        );

        return AppDropdown<String>(
          label: 'نوع البند *',
          hint: 'اختر نوع البند',
          value: selectedExists ? _selectedTypeId : null,
          items: items,
          prefixIcon: Icons.list_alt_outlined,
          onChanged: (value) async {
            if (value == null) return;

            String typeName = '';

            if (subcollectionDocs.isNotEmpty) {
              final doc = subcollectionDocs.firstWhere(
                (element) => element.id == value,
              );
              typeName = _text(doc.data()['name']);
            } else {
              return;
            }

            if (!mounted) return;

            setState(() {
              _selectedTypeId = value;
              _selectedTypeName = typeName;
              _selectedEngineerId = null;
              _selectedEngineerName = null;
              _selectedEquipmentId = null;
              _selectedEquipmentCode = null;
              _selectedEquipmentName = null;
              _selectedEquipmentWorkUnit = null;
              _selectedEquipmentMeter = null;
            });
          },
        );
      },
    );
  }

  Widget _buildEngineerDropdown() {
    if (!_canSelectEngineer) {
      return AppCard(
        color: AppColors.background,
        child: Row(
          children: [
            const Icon(Icons.lock_outline, color: AppColors.textSecondary),
            AppSpacing.horizontalSm,
            const Expanded(
              child: Text(
                'أكمل البند والنوع والكود والكمية والوحدة أولاً لتحديد المهندس.',
                style: AppTextStyles.bodySecondary,
              ),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('users')
          .where('role', isEqualTo: 'engineer')
          .where('active', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppError(
            message: 'تعذر تحميل المهندسين:\n${snapshot.error}',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading(message: 'جاري تحميل المهندسين...');
        }

        final docs = _typedDocs(snapshot.data);

        if (docs.isEmpty) {
          return const AppCard(
            color: AppColors.warning,
            child: Text('لا يوجد مهندسون فعالون. أضف المهندس من إدارة المستخدمين أولاً.'),
          );
        }

        final sorted = [...docs]
          ..sort(
            (a, b) => _text(
              a.data()['name'],
              fallback: _text(a.data()['username']),
            ).compareTo(
              _text(
                b.data()['name'],
                fallback: _text(b.data()['username']),
              ),
            ),
          );

        final items = sorted.map((doc) {
          final data = doc.data();
          final name = _text(
            data['name'],
            fallback: _text(data['username'], fallback: doc.id),
          );

          return DropdownMenuItem<String>(
            value: doc.id,
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList();

        final selectedExists = sorted.any(
          (doc) => doc.id == _selectedEngineerId,
        );

        return AppDropdown<String>(
          label: 'المهندس *',
          hint: 'اختر المهندس',
          value: selectedExists ? _selectedEngineerId : null,
          items: items,
          prefixIcon: Icons.engineering_outlined,
          onChanged: (value) {
            if (value == null) return;

            final doc = sorted.firstWhere(
              (element) => element.id == value,
            );
            final data = doc.data();

            setState(() {
              _selectedEngineerId = doc.id;
              _selectedEngineerName = _text(
                data['name'],
                fallback: _text(data['username'], fallback: doc.id),
              );
              _selectedEquipmentId = null;
              _selectedEquipmentCode = null;
              _selectedEquipmentName = null;
              _selectedEquipmentWorkUnit = null;
              _selectedEquipmentMeter = null;
            });
          },
        );
      },
    );
  }

  Widget _buildEquipmentDropdown() {
    if (!_canSelectEquipment) {
      return AppCard(
        color: AppColors.background,
        child: Row(
          children: [
            const Icon(Icons.lock_outline, color: AppColors.textSecondary),
            AppSpacing.horizontalSm,
            const Expanded(
              child: Text(
                'اختر المهندس أولاً لتحديد المعدة.',
                style: AppTextStyles.bodySecondary,
              ),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('equipment')
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppError(
            message: 'تعذر تحميل المعدات:\n${snapshot.error}',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading(message: 'جاري تحميل المعدات...');
        }

        final docs = _typedDocs(snapshot.data);

        if (docs.isEmpty) {
          return const AppCard(
            color: AppColors.warning,
            child: Text(
              'لا توجد معدات نشطة. أضف المعدات من صفحة حصر المعدات أولاً.',
            ),
          );
        }

        final sorted = [...docs]
          ..sort(
            (a, b) => _text(a.data()['code']).compareTo(
              _text(b.data()['code']),
            ),
          );

        final items = sorted.map((doc) {
          final data = doc.data();
          final code = _text(data['code']);
          final name = _text(
            data['name'],
            fallback: _text(data['type'], fallback: 'معدة'),
          );

          final title = code.isEmpty ? name : '$name — $code';

          return DropdownMenuItem<String>(
            value: doc.id,
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList();

        final selectedExists = sorted.any(
          (doc) => doc.id == _selectedEquipmentId,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDropdown<String>(
              label: 'المعدة *',
              hint: 'اختر المعدة',
              value: selectedExists ? _selectedEquipmentId : null,
              items: items,
              prefixIcon: Icons.precision_manufacturing_outlined,
              onChanged: (value) {
                if (value == null) return;

                final doc = sorted.firstWhere(
                  (element) => element.id == value,
                );
                final data = doc.data();

                final rawMeter = data['currentMeter'];
                double? meter;

                if (rawMeter is num) {
                  meter = rawMeter.toDouble();
                } else if (rawMeter != null) {
                  meter = _parseNumber(rawMeter.toString());
                }

                setState(() {
                  _selectedEquipmentId = doc.id;
                  _selectedEquipmentCode = _text(data['code']);
                  _selectedEquipmentName = _text(
                    data['name'],
                    fallback: _text(data['type'], fallback: 'معدة'),
                  );
                  _selectedEquipmentWorkUnit = _text(data['workUnit']);
                  _selectedEquipmentMeter = meter;
                });
              },
            ),
            if (selectedExists) ...[
              AppSpacing.verticalSm,
              AppCard(
                color: AppColors.success.withValues(alpha: 0.08),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: AppColors.success,
                        ),
                        AppSpacing.horizontalSm,
                        Expanded(
                          child: Text(
                            'تم اختيار المعدة',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                    AppSpacing.verticalSm,
                    AppInfoRow(
                      label: 'المعدة',
                      value: _selectedEquipmentName ?? '—',
                      icon: Icons.precision_manufacturing_outlined,
                    ),
                    AppSpacing.verticalSm,
                    AppInfoRow(
                      label: 'الكود',
                      value: _selectedEquipmentCode?.isEmpty == false
                          ? _selectedEquipmentCode!
                          : '—',
                      icon: Icons.tag_outlined,
                    ),
                    AppSpacing.verticalSm,
                    AppInfoRow(
                      label: 'وحدة العمل',
                      value: _selectedEquipmentWorkUnit?.isEmpty == false
                          ? _selectedEquipmentWorkUnit!
                          : 'غير محددة',
                      icon: Icons.speed_outlined,
                    ),
                    if (_selectedEquipmentMeter != null) ...[
                      AppSpacing.verticalSm,
                      AppInfoRow(
                        label: 'قراءة العداد الحالية',
                        value: _selectedEquipmentMeter!.toString(),
                        icon: Icons.speed_outlined,
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

  Widget _buildUnitDropdown() {
    return AppDropdown<String>(
      label: 'الوحدة *',
      hint: 'اختر الوحدة',
      value: _selectedUnit,
      items: _units
          .map(
            (unit) => DropdownMenuItem<String>(
              value: unit,
              child: Text(unit),
            ),
          )
          .toList(),
      prefixIcon: Icons.straighten_outlined,
      onChanged: (value) {
        setState(() {
          _selectedUnit = value;
          if (value == null) {
            _selectedEngineerId = null;
            _selectedEngineerName = null;
            _selectedEquipmentId = null;
          }
        });
      },
    );
  }

  Future<void> _saveItem() async {
    if (_saving) return;

    if (!_canSave) {
      AppWidgets.showWarning(
        context,
        'أكمل جميع البيانات المطلوبة قبل الحفظ.',
      );
      return;
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      AppWidgets.showError(context, 'المستخدم غير مسجل الدخول.');
      return;
    }

    final quantity = _parseNumber(_quantityController.text);
    final durationDays = int.tryParse(_durationController.text.trim());

    if (quantity == null || quantity <= 0) {
      AppWidgets.showWarning(context, 'كمية العقد غير صحيحة.');
      return;
    }

    if (durationDays == null || durationDays <= 0) {
      AppWidgets.showWarning(context, 'مدة العقد غير صحيحة.');
      return;
    }

    if (_projectName == null || _projectName!.trim().isEmpty) {
      await _loadProjectName();
    }

    if (!mounted) return;

    setState(() {
      _saving = true;
    });

    try {
      final itemRef = _firestore.collection('items').doc();

      final itemData = <String, dynamic>{
        'projectId': widget.projectId,
        'projectName': _projectName,

        'name': _selectedTypeName,
        'itemDefinitionId': _selectedItemDefinitionId,
        'itemDefinitionName': _selectedItemDefinitionName,
        'typeId': _selectedTypeId,
        'typeName': _selectedTypeName,

        'code': _codeController.text.trim(),
        'contractQuantity': quantity,
        'unit': _selectedUnit,

        'engineerId': _selectedEngineerId,
        'engineerName': _selectedEngineerName,

        'equipmentId': _selectedEquipmentId,
        'equipmentCode': _selectedEquipmentCode,
        'equipmentName': _selectedEquipmentName,
        'equipmentWorkUnit': _selectedEquipmentWorkUnit,
        'equipmentCurrentMeter': _selectedEquipmentMeter,

        'durationDays': durationDays,

        // تاريخ العقد غير محدد هنا.
        // تاريخ بداية ونهاية التنفيذ يحددهما المهندس من صفحة التفاصيل.
        'contractStartDate': null,
        'contractEndDate': null,
        'executionStartDate': null,
        'executionEndDate': null,

        // يبدأ التنفيذ من صفر.
        'executedQuantity': 0.0,

        'detailsAdded': false,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': currentUser.uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUser.uid,
      };

      await itemRef.set(itemData);

      if (!mounted) return;

      AppWidgets.showSuccess(
        context,
        'تم إنشاء البند بنجاح.',
      );

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ItemDetailsPage(
            projectId: widget.projectId,
            itemId: itemRef.id,
          ),
        ),
      );
    } catch (e) {
      debugPrint('خطأ في حفظ البند: $e');

      if (!mounted) return;

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء حفظ البند:\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Widget _buildLockedInfo(String message) {
    return AppCard(
      color: AppColors.background,
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline,
            color: AppColors.textSecondary,
          ),
          AppSpacing.horizontalSm,
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySecondary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إضافة بند',
      showBackButton: true,
      child: AppPage(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppPageHeader(
                title: 'إضافة بند جديد',
                subtitle:
                    'إضافة بند تعاقدي وربطه بالمشروع والمهندس والمعدة',
                icon: Icons.add_business_outlined,
              ),

              AppSpacing.verticalLg,

              const AppSectionTitle(
                title: 'بيانات المشروع',
                icon: Icons.business_outlined,
              ),
              AppSpacing.verticalSm,

              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppInfoRow(
                      label: 'المشروع',
                      value: _projectName ?? 'جاري تحميل اسم المشروع...',
                      icon: Icons.business_outlined,
                    ),
                    const Divider(height: 24),
                    AppInfoRow(
                      label: 'رقم المشروع',
                      value: widget.projectId,
                      icon: Icons.tag_outlined,
                    ),
                  ],
                ),
              ),

              AppSpacing.verticalLg,

              const AppSectionTitle(
                title: 'البند',
                icon: Icons.category_outlined,
              ),
              AppSpacing.verticalSm,
              _buildDefinitionDropdown(),

              AppSpacing.verticalMd,
              const AppSectionTitle(
                title: 'نوع البند',
                icon: Icons.list_alt_outlined,
              ),
              AppSpacing.verticalSm,
              _buildTypeDropdown(),

              if (_selectedTypeName != null &&
                  _selectedTypeName!.trim().isNotEmpty) ...[
                AppSpacing.verticalSm,
                AppCard(
                  color: AppColors.success.withValues(alpha: 0.08),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: AppColors.success,
                      ),
                      AppSpacing.horizontalSm,
                      Expanded(
                        child: Text(
                          'اسم البند: $_selectedTypeName',
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              AppSpacing.verticalLg,

              const AppSectionTitle(
                title: 'بيانات العقد',
                icon: Icons.description_outlined,
              ),
              AppSpacing.verticalSm,

              AppTextField(
                controller: _codeController,
                label: 'كود البند *',
                hint: 'أدخل كود البند',
                prefixIcon: Icons.qr_code_2_outlined,
                onChanged: (_) => setState(() {}),
              ),

              AppSpacing.verticalMd,

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: AppNumberField(
                      controller: _quantityController,
                      label: 'الكمية التعاقدية *',
                      hint: 'أدخل الكمية',
                      prefixIcon: Icons.numbers_outlined,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  AppSpacing.horizontalMd,
                  Expanded(
                    flex: 1,
                    child: _buildUnitDropdown(),
                  ),
                ],
              ),

              AppSpacing.verticalLg,

              const AppSectionTitle(
                title: 'المهندس',
                icon: Icons.engineering_outlined,
              ),
              AppSpacing.verticalSm,
              _canSelectEngineer
                  ? _buildEngineerDropdown()
                  : _buildLockedInfo(
                      'أكمل بيانات البند والكمية والوحدة أولاً.',
                    ),

              AppSpacing.verticalLg,

              const AppSectionTitle(
                title: 'المعدة',
                icon: Icons.precision_manufacturing_outlined,
              ),
              AppSpacing.verticalSm,
              _canSelectEquipment
                  ? _buildEquipmentDropdown()
                  : _buildLockedInfo(
                      'اختر المهندس أولاً لتتمكن من اختيار المعدة.',
                    ),

              AppSpacing.verticalLg,

              const AppSectionTitle(
                title: 'مدة العقد',
                icon: Icons.timelapse_outlined,
              ),
              AppSpacing.verticalSm,

              AppNumberField(
                controller: _durationController,
                label: 'مدة العقد بالأيام *',
                hint: 'مثال: 30',
                suffixText: 'يوم',
                prefixIcon: Icons.timelapse_outlined,
                onChanged: (_) => setState(() {}),
              ),

              AppSpacing.verticalLg,

              const AppSectionTitle(
                title: 'تواريخ التنفيذ',
                icon: Icons.event_note_outlined,
              ),
              AppSpacing.verticalSm,

              AppCard(
                color: AppColors.background,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.engineering_outlined,
                          color: AppColors.info,
                        ),
                        AppSpacing.horizontalSm,
                        Expanded(
                          child: Text(
                            'المهندس هو المسؤول عن تحديد تواريخ التنفيذ.',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.info,
                            ),
                          ),
                        ),
                      ],
                    ),
                    AppSpacing.verticalMd,
                    const AppInfoRow(
                      label: 'تاريخ بداية التنفيذ',
                      value: 'لم يحدد بعد',
                      icon: Icons.calendar_month_outlined,
                    ),
                    AppSpacing.verticalSm,
                    const AppInfoRow(
                      label: 'تاريخ نهاية التنفيذ',
                      value: 'لم يحدد بعد',
                      icon: Icons.event_outlined,
                    ),
                    AppSpacing.verticalMd,
                    const Text(
                      'بعد إنشاء البند يستطيع المهندس تحديد تاريخ بداية التنفيذ ونهاية التنفيذ من صفحة تفاصيل البند.',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ],
                ),
              ),

              AppSpacing.verticalLg,

              const AppSectionTitle(
                title: 'كمية التنفيذ',
                icon: Icons.construction_outlined,
              ),
              AppSpacing.verticalSm,

              const AppCard(
                color: AppColors.background,
                child: Text(
                  'تبدأ كمية التنفيذ من 0. ويقوم مدير المشروع بإضافة الكميات المنفذة من صفحة البنود، بينما تبقى تواريخ التنفيذ تحت مسؤولية المهندس.',
                  style: AppTextStyles.bodySecondary,
                ),
              ),

              AppSpacing.verticalXl,

              AppButton(
                label: 'حفظ البند والمتابعة للتفاصيل',
                icon: Icons.arrow_forward_outlined,
                loading: _saving,
                expanded: true,
                onPressed: _canSave && !_saving ? _saveItem : null,
              ),

              AppSpacing.verticalLg,
            ],
          ),
        ),
      ),
    );
  }
}

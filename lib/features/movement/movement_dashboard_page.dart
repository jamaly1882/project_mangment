import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/equipment_service.dart';
import 'equipment_file_page.dart';
import 'movement_widgets.dart';

// ============================================================
// لوحة إدارة الحركة — مدير إدارة الحركة
// ============================================================
//
// مدير الحركة هو من يضيف المعدة إلى الحصر بكودها، ويربطها
// بالمشروع الذي تعمل فيه (برقم المشروع) وينقلها بين المشاريع.
// بمجرد حفظ المعدة تظهر بياناتها في إدارة الديزل (استهلاك
// المعدات والوقود) وفي إدارة الورشة والصيانة، لأن الإدارات
// الثلاث تقرأ من مجموعة `equipment` نفسها، وكل ما يُسجَّل
// عليها يتجمع في «ملف المعدة».
// ============================================================

class MovementDashboardPage extends StatefulWidget {
  const MovementDashboardPage({super.key});

  @override
  State<MovementDashboardPage> createState() =>
      _MovementDashboardPageState();
}

class _MovementDashboardPageState extends State<MovementDashboardPage> {
  final EquipmentService _service = EquipmentService();
  final TextEditingController _searchController = TextEditingController();

  String _search = '';
  String _filter = 'all'; // all | withProject | withoutProject | broken

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _userName =>
      FirebaseAuth.instance.currentUser?.displayName ?? '';

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  void _openFile(EquipmentDoc equipment) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => EquipmentFilePage(equipmentId: equipment.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة الحركة — المعدات'),
          centerTitle: true,
          actions: <Widget>[
            IconButton(
              tooltip: 'تسجيل الخروج',
              icon: const Icon(Icons.logout),
              onPressed: _logout,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openEquipmentForm(),
          icon: const Icon(Icons.add),
          label: const Text('إضافة معدة'),
        ),
        body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'بحث بكود المعدة أو نوعها أو رقم المشروع...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) =>
                    setState(() => _search = value.trim().toLowerCase()),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: <Widget>[
                  _filterChip('all', 'الكل'),
                  _filterChip('withProject', 'تعمل في مشروع'),
                  _filterChip('withoutProject', 'بدون مشروع'),
                  _filterChip('broken', 'معطلة'),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<EquipmentDoc>>(
                stream: _service.equipmentStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'تعذر تحميل حصر المعدات.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final List<EquipmentDoc> all =
                      snapshot.data ?? <EquipmentDoc>[];

                  final List<EquipmentDoc> docs = all.where((e) {
                    switch (_filter) {
                      case 'withProject':
                        if (!e.hasProject) return false;
                        break;
                      case 'withoutProject':
                        if (e.hasProject) return false;
                        break;
                      case 'broken':
                        if (!e.isBroken) return false;
                        break;
                    }
                    if (_search.isEmpty) return true;
                    final String text =
                        '${e.code} ${e.type} ${e.projectCode} ${e.projectName} '
                                '${e.driverName} ${e.manufacturer}'
                            .toLowerCase();
                    return text.contains(_search);
                  }).toList();

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
                    children: <Widget>[
                      MovementStatGrid(
                        stats: <MovementStat>[
                          MovementStat(
                            label: 'كل المعدات',
                            value: '${all.length}',
                            icon: Icons.precision_manufacturing_outlined,
                          ),
                          MovementStat(
                            label: 'تعمل في مشروع',
                            value:
                                '${all.where((e) => e.hasProject).length}',
                            icon: Icons.apartment_outlined,
                            color: Colors.green,
                          ),
                          MovementStat(
                            label: 'بدون مشروع',
                            value:
                                '${all.where((e) => !e.hasProject).length}',
                            icon: Icons.warehouse_outlined,
                            color: Colors.orange,
                          ),
                          MovementStat(
                            label: 'معطلة',
                            value: '${all.where((e) => e.isBroken).length}',
                            icon: Icons.build_circle_outlined,
                            color: Colors.red,
                          ),
                        ],
                      ),
                      const MovementSectionTitle(
                        title: 'حصر المعدات',
                        icon: Icons.list_alt_outlined,
                      ),
                      if (docs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 32),
                          child: MovementEmpty(
                            icon: Icons.precision_manufacturing_outlined,
                            message: 'لا توجد معدات مطابقة',
                            hint: 'اضغط «إضافة معدة» لإدخال معدة جديدة '
                                'بكودها وربطها بالمشروع الذي ستعمل فيه، '
                                'وستظهر فورًا في الديزل والورشة.',
                          ),
                        )
                      else
                        ...docs.map(_equipmentCard),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _equipmentCard(EquipmentDoc e) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (e.isBroken ? Colors.red : Colors.blue)
              .withValues(alpha: 0.10),
          child: Icon(
            Icons.precision_manufacturing_outlined,
            color: e.isBroken ? Colors.red : Colors.blue,
          ),
        ),
        title: Text(
          e.displayName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                e.hasProject
                    ? 'المشروع: ${e.projectCode}'
                        '${e.projectName.isEmpty ? '' : ' — ${e.projectName}'}'
                    : 'المشروع: بدون مشروع حاليًا (ساحة الحركة)',
              ),
              Text(
                'العداد: ${fmtNum(e.currentMeter)}'
                '${e.workUnit.isEmpty ? '' : ' ${e.workUnit}'}'
                '${e.driverName.isEmpty ? '' : '  |  السائق: ${e.driverName}'}',
              ),
              Text(
                'ديزل: ${fmtNum(e.totalDieselLiters)} لتر  |  '
                'عمل: ${fmtNum(e.totalWorkUnits)}  |  '
                'صيانة: ${fmtMoney(e.totalMaintenanceCost)}',
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: <Widget>[
                  ConditionChip(condition: e.condition),
                  if (e.openBreakdownCount > 0)
                    Chip(
                      label: Text(
                        'أعطال مفتوحة: ${e.openBreakdownCount}',
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                      backgroundColor: Colors.red.withValues(alpha: 0.08),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'file':
                _openFile(e);
                break;
              case 'assign':
                _openAssign(e);
                break;
              case 'edit':
                _openEquipmentForm(existing: e);
                break;
              case 'delete':
                _delete(e);
                break;
            }
          },
          itemBuilder: (_) => const <PopupMenuEntry<String>>[
            PopupMenuItem(value: 'file', child: Text('ملف المعدة')),
            PopupMenuItem(value: 'assign', child: Text('نقل إلى مشروع')),
            PopupMenuItem(value: 'edit', child: Text('تعديل البيانات')),
            PopupMenuItem(value: 'delete', child: Text('حذف')),
          ],
        ),
        onTap: () => _openFile(e),
      ),
    );
  }

  // ==========================================================
  // إضافة / تعديل معدة
  // ==========================================================

  Future<void> _openEquipmentForm({EquipmentDoc? existing}) async {
    final bool isEdit = existing != null;
    final Map<String, dynamic> data =
        existing?.data ?? <String, dynamic>{};
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    String initialOf(List<String> keys) {
      for (final String key in keys) {
        final String value = (data[key] ?? '').toString().trim();
        if (value.isNotEmpty && value != '0' && value != '0.0') return value;
      }
      return '';
    }

    final TextEditingController codeController = TextEditingController(
      text: existing?.code ?? '',
    );
    final TextEditingController typeController = TextEditingController(
      text: existing?.type ?? '',
    );
    final TextEditingController manufacturerController =
        TextEditingController(
      text: initialOf(const <String>['manufacturer', 'manufacturerCountry']),
    );
    final TextEditingController yearController = TextEditingController(
      text: initialOf(
          const <String>['modelYear', 'year', 'manufactureYear']),
    );
    final TextEditingController workUnitController =
        TextEditingController(text: initialOf(const <String>['workUnit']));
    final TextEditingController meterController = TextEditingController(
      text: initialOf(const <String>['currentMeter']),
    );
    final TextEditingController driverNameController =
        TextEditingController(text: initialOf(const <String>['driverName']));
    final TextEditingController driverPhoneController =
        TextEditingController(text: initialOf(const <String>['driverPhone']));
    final TextEditingController currentValueController =
        TextEditingController(
      text: initialOf(
          const <String>['currentValue', 'currentEquipmentValue']),
    );
    final TextEditingController salvageController = TextEditingController(
      text: initialOf(const <String>['salvageValue']),
    );
    final TextEditingController expectedUnitsController =
        TextEditingController(
      text: initialOf(const <String>['expectedWorkUnits']),
    );
    final TextEditingController notesController =
        TextEditingController(text: initialOf(const <String>['notes']));

    String condition = existing?.condition ?? 'جيدة';
    if (!const <String>['جيدة', 'متوسطة', 'تحتاج صيانة', 'معطلة']
        .contains(condition)) {
      condition = 'جيدة';
    }

    ProjectOption? selectedProject;
    bool saving = false;

    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text(
                  isEdit ? 'تعديل بيانات المعدة' : 'إضافة معدة إلى الحصر',
                ),
                content: SizedBox(
                  width: 580,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          movementTextField(
                            controller: codeController,
                            label: 'كود المعدة / الرقم الإداري',
                            required: true,
                            enabled: !isEdit,
                            hint: isEdit
                                ? 'الكود ثابت لحماية سجلات الديزل والصيانة'
                                : 'مثال: EQ-101',
                          ),
                          movementTextField(
                            controller: typeController,
                            label: 'نوع المعدة',
                            required: true,
                            hint: 'مثال: حفار، شيول، قلاب...',
                          ),
                          movementTextField(
                            controller: manufacturerController,
                            label: 'الشركة المصنعة / الدولة',
                          ),
                          movementTextField(
                            controller: yearController,
                            label: 'سنة الصنع',
                            number: true,
                          ),
                          movementTextField(
                            controller: workUnitController,
                            label: 'وحدة عمل المعدة',
                            required: true,
                            hint: 'ساعة / كم / يوم / مشوار',
                          ),
                          movementTextField(
                            controller: meterController,
                            label: 'قراءة العداد الحالية',
                            number: true,
                          ),
                          movementTextField(
                            controller: driverNameController,
                            label: 'اسم السائق / المشغّل',
                          ),
                          movementTextField(
                            controller: driverPhoneController,
                            label: 'تلفون السائق',
                          ),
                          if (!isEdit) ...<Widget>[
                            ProjectDropdown(
                              service: _service,
                              label: 'المشروع الذي ستعمل فيه',
                              isRequired: false,
                              allowNoneLabel: 'بدون مشروع حاليًا (ساحة الحركة)',
                              selectedId: selectedProject?.id,
                              onChanged: (ProjectOption? value) =>
                                  setDialogState(
                                      () => selectedProject = value),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Text(
                                'عند اختيار المشروع تنتقل بيانات المعدة '
                                'إلى إدارة الديزل برقم هذا المشروع، '
                                'وتظهر في الورشة والصيانة مباشرة.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                            ),
                          ],
                          const MovementSectionTitle(
                            title: 'بيانات الإهلاك',
                            icon: Icons.calculate_outlined,
                          ),
                          movementTextField(
                            controller: currentValueController,
                            label: 'القيمة الحالية للمعدة',
                            number: true,
                          ),
                          movementTextField(
                            controller: salvageController,
                            label: 'القيمة التخريدية',
                            number: true,
                          ),
                          movementTextField(
                            controller: expectedUnitsController,
                            label: 'عدد وحدات العمل المتوقعة في عمرها',
                            number: true,
                            hint: 'يُحتسب منه الإهلاك لكل وحدة عمل',
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: DropdownButtonFormField<String>(
                              key: ValueKey<String>('condition-$condition'),
                              initialValue: condition,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'حالة المعدة',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const <DropdownMenuItem<String>>[
                                DropdownMenuItem(
                                    value: 'جيدة', child: Text('جيدة')),
                                DropdownMenuItem(
                                    value: 'متوسطة', child: Text('متوسطة')),
                                DropdownMenuItem(
                                  value: 'تحتاج صيانة',
                                  child: Text('تحتاج صيانة'),
                                ),
                                DropdownMenuItem(
                                    value: 'معطلة', child: Text('معطلة')),
                              ],
                              onChanged: saving
                                  ? null
                                  : (String? value) {
                                      if (value != null) {
                                        setDialogState(
                                            () => condition = value);
                                      }
                                    },
                            ),
                          ),
                          movementTextField(
                            controller: notesController,
                            label: 'ملاحظات',
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.pop(dialogContext, false),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;

                            final double? yearValue =
                                parseMovementNumber(yearController.text);
                            final EquipmentInput input = EquipmentInput(
                              code: codeController.text.trim(),
                              type: typeController.text.trim(),
                              manufacturer:
                                  manufacturerController.text.trim(),
                              year: yearValue?.toInt(),
                              workUnit: workUnitController.text.trim(),
                              meter: parseMovementNumber(
                                      meterController.text) ??
                                  0,
                              driverName: driverNameController.text.trim(),
                              driverPhone:
                                  driverPhoneController.text.trim(),
                              condition: condition,
                              currentValue: parseMovementNumber(
                                      currentValueController.text) ??
                                  0,
                              salvageValue: parseMovementNumber(
                                      salvageController.text) ??
                                  0,
                              expectedWorkUnits: parseMovementNumber(
                                      expectedUnitsController.text) ??
                                  0,
                              notes: notesController.text.trim(),
                            );

                            setDialogState(() => saving = true);
                            try {
                              if (isEdit) {
                                await _service.updateEquipment(
                                  equipmentId: existing!.id,
                                  input: input,
                                );
                              } else {
                                await _service.addEquipment(
                                  input: input,
                                  project: selectedProject,
                                  byUid: _uid,
                                  byName: _userName,
                                );
                              }
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext, true);
                              }
                            } catch (error) {
                              setDialogState(() => saving = false);
                              if (mounted) {
                                showMovementMessage(
                                  context,
                                  error is EquipmentServiceException
                                      ? error.message
                                      : 'تعذر حفظ المعدة: $error',
                                  error: true,
                                );
                              }
                            }
                          },
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(saving ? 'جارٍ الحفظ...' : 'حفظ'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    for (final TextEditingController c in <TextEditingController>[
      codeController,
      typeController,
      manufacturerController,
      yearController,
      workUnitController,
      meterController,
      driverNameController,
      driverPhoneController,
      currentValueController,
      salvageController,
      expectedUnitsController,
      notesController,
    ]) {
      c.dispose();
    }

    if (saved == true && mounted) {
      showMovementMessage(
        context,
        isEdit
            ? 'تم تحديث بيانات المعدة'
            : 'تمت إضافة المعدة — بياناتها متاحة الآن في الديزل والورشة',
      );
    }
  }

  // ==========================================================
  // نقل معدة إلى مشروع / فك ارتباطها
  // ==========================================================

  Future<void> _openAssign(EquipmentDoc equipment) async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController notesController = TextEditingController();
    ProjectOption? selectedProject;
    DateTime date = DateTime.now();
    bool saving = false;

    final bool? done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text('نقل «${equipment.displayName}» إلى مشروع'),
                content: SizedBox(
                  width: 520,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              equipment.hasProject
                                  ? 'تعمل الآن في: ${equipment.projectCode}'
                                      ' ${equipment.projectName}'
                                  : 'غير مرتبطة بأي مشروع حاليًا.',
                            ),
                          ),
                          ProjectDropdown(
                            service: _service,
                            label: 'المشروع الجديد (برقمه)',
                            selectedId: selectedProject?.id,
                            onChanged: (ProjectOption? value) =>
                                setDialogState(
                                    () => selectedProject = value),
                          ),
                          MovementDateField(
                            label: 'تاريخ النقل',
                            value: date,
                            onChanged: (DateTime value) =>
                                setDialogState(() => date = value),
                          ),
                          movementTextField(
                            controller: notesController,
                            label: 'ملاحظات النقل',
                            maxLines: 2,
                          ),
                          const Text(
                            'سيُغلق ربطها بالمشروع السابق في هذا التاريخ، '
                            'ومن الآن يُسجَّل ديزلها وصيانتها على المشروع '
                            'الجديد، ويبقى تاريخ تنقلاتها في ملفها.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: <Widget>[
                  if (equipment.hasProject)
                    TextButton(
                      onPressed: saving
                          ? null
                          : () async {
                              setDialogState(() => saving = true);
                              try {
                                await _service.unassign(
                                  equipment: equipment,
                                  date: date,
                                );
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext, true);
                                }
                              } catch (error) {
                                setDialogState(() => saving = false);
                                if (mounted) {
                                  showMovementMessage(
                                    context,
                                    'تعذر فك الارتباط: $error',
                                    error: true,
                                  );
                                }
                              }
                            },
                      child: const Text('فك الارتباط (بدون مشروع)'),
                    ),
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.pop(dialogContext, false),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            if (selectedProject == null) {
                              showMovementMessage(
                                context,
                                'اختر المشروع الجديد برقمه',
                                error: true,
                              );
                              return;
                            }
                            setDialogState(() => saving = true);
                            try {
                              await _service.assignToProject(
                                equipment: equipment,
                                project: selectedProject!,
                                date: date,
                                notes: notesController.text.trim(),
                                byUid: _uid,
                                byName: _userName,
                              );
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext, true);
                              }
                            } catch (error) {
                              setDialogState(() => saving = false);
                              if (mounted) {
                                showMovementMessage(
                                  context,
                                  'تعذر نقل المعدة: $error',
                                  error: true,
                                );
                              }
                            }
                          },
                    child: Text(saving ? 'جارٍ النقل...' : 'نقل المعدة'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    notesController.dispose();
    if (done == true && mounted) {
      showMovementMessage(context, 'تم تحديث مشروع المعدة');
    }
  }

  Future<void> _delete(EquipmentDoc equipment) async {
    final bool confirmed = await confirmMovementAction(
      context,
      title: 'حذف المعدة من الحصر',
      message: 'هل تريد حذف «${equipment.displayName}»؟\n\n'
          'ستبقى سجلات ديزلها وصيانتها محفوظة كسجل تاريخي، '
          'لكنها لن تظهر في حصر المعدات ولا في ملف معدة.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!confirmed) return;
    try {
      await _service.deleteEquipment(equipment.id);
      if (mounted) showMovementMessage(context, 'تم حذف المعدة');
    } catch (error) {
      if (mounted) {
        showMovementMessage(context, 'تعذر حذف المعدة: $error', error: true);
      }
    }
  }
}

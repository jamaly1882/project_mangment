import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/equipment_service.dart';
import '../../core/utils/equipment_calculations.dart';
import 'equipment_file_page.dart';
import 'movement_widgets.dart';

// ============================================================
// إدارة الورشة والصيانة — مدير الورشة والصيانة
// ============================================================
//
// تكتب الورشة على كل معدة (تختارها بكودها من حصر إدارة
// الحركة):
//   • الأعطال — والعطل المفتوح يجعل المعدة «معطلة» حتى يُغلق.
//   • بدلات التواير — عدد التواير وسعر التاير.
//   • قطع الغيار — اسم القطعة وعددها وسعرها.
//   • الصيانة الدورية الأخرى.
//
// كل سجل يُحفظ في `maintenance_logs` ويُضاف إلى «ملف المعدة»
// ومجاميع صيانتها، ويدخل في حساب إهلاكها وبدل أعطالها.
// ============================================================

class WorkshopDashboardPage extends StatefulWidget {
  const WorkshopDashboardPage({super.key});

  @override
  State<WorkshopDashboardPage> createState() =>
      _WorkshopDashboardPageState();
}

class _WorkshopDashboardPageState extends State<WorkshopDashboardPage> {
  final EquipmentService _service = EquipmentService();

  String _filter = 'all'; // all | open | نوع من MaintenanceTypes

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _userName =>
      FirebaseAuth.instance.currentUser?.displayName ?? '';

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  void _openFile(String equipmentId) {
    if (equipmentId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => EquipmentFilePage(equipmentId: equipmentId),
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case MaintenanceTypes.breakdown:
        return Icons.report_problem_outlined;
      case MaintenanceTypes.tire:
        return Icons.tire_repair;
      case MaintenanceTypes.part:
        return Icons.settings_outlined;
      default:
        return Icons.handyman_outlined;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case MaintenanceTypes.breakdown:
        return Colors.red;
      case MaintenanceTypes.tire:
        return Colors.blueGrey;
      case MaintenanceTypes.part:
        return Colors.indigo;
      default:
        return Colors.teal;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة الورشة والصيانة'),
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
          onPressed: _openRecordForm,
          icon: const Icon(Icons.add),
          label: const Text('تسجيل عطل / صيانة'),
        ),
        body: Column(
          children: <Widget>[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: <Widget>[
                  _chip('all', 'الكل'),
                  _chip('open', 'أعطال مفتوحة'),
                  _chip(MaintenanceTypes.breakdown, 'الأعطال'),
                  _chip(MaintenanceTypes.tire, 'بدلات التواير'),
                  _chip(MaintenanceTypes.part, 'قطع الغيار'),
                  _chip(MaintenanceTypes.service, 'صيانة دورية'),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                stream: _service.maintenanceLogsStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'تعذر تحميل سجلات الورشة.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                      all = snapshot.data ??
                          <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                  int openCount = 0;
                  double breakdownCost = 0;
                  double totalCost = 0;
                  for (final doc in all) {
                    final Map<String, dynamic> d = doc.data();
                    final double cost = EquipmentCalc.numOf(d['totalCost']);
                    totalCost += cost;
                    if ((d['type'] ?? '').toString() ==
                        MaintenanceTypes.breakdown) {
                      breakdownCost += cost;
                      if ((d['status'] ?? '').toString() ==
                          MaintenanceTypes.statusOpen) {
                        openCount++;
                      }
                    }
                  }

                  final docs = all.where((doc) {
                    final Map<String, dynamic> d = doc.data();
                    if (_filter == 'all') return true;
                    if (_filter == 'open') {
                      return (d['type'] ?? '').toString() ==
                              MaintenanceTypes.breakdown &&
                          (d['status'] ?? '').toString() ==
                              MaintenanceTypes.statusOpen;
                    }
                    return (d['type'] ?? '').toString() == _filter;
                  }).toList();

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
                    children: <Widget>[
                      MovementStatGrid(
                        stats: <MovementStat>[
                          MovementStat(
                            label: 'سجلات الورشة',
                            value: '${all.length}',
                            icon: Icons.handyman_outlined,
                          ),
                          MovementStat(
                            label: 'أعطال قيد الإصلاح',
                            value: '$openCount',
                            icon: Icons.report_problem_outlined,
                            color: Colors.red,
                          ),
                          MovementStat(
                            label: 'تكلفة الأعطال',
                            value: fmtMoney(breakdownCost),
                            icon: Icons.build_circle_outlined,
                            color: Colors.deepOrange,
                          ),
                          MovementStat(
                            label: 'إجمالي الصيانة',
                            value: fmtMoney(totalCost),
                            icon: Icons.payments_outlined,
                            color: Colors.green,
                          ),
                        ],
                      ),
                      const MovementSectionTitle(
                        title: 'الأعطال والتواير والقطع والصيانة',
                        icon: Icons.list_alt_outlined,
                      ),
                      if (docs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: MovementEmpty(
                            icon: Icons.handyman_outlined,
                            message: 'لا توجد سجلات ورشة مطابقة',
                            hint: 'اضغط «تسجيل عطل / صيانة» واختر المعدة '
                                'بكودها — وسيُضاف العطل أو التاير أو '
                                'القطعة إلى ملفها مباشرة.',
                          ),
                        )
                      else
                        ...docs.map(_maintenanceCard),
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

  Widget _chip(String value, String label) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _maintenanceCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> d = doc.data();
    final String type = (d['type'] ?? '').toString();
    final String status = (d['status'] ?? '').toString();
    final bool isOpen = type == MaintenanceTypes.breakdown &&
        status == MaintenanceTypes.statusOpen;

    final String code = (d['equipmentCode'] ?? '').toString();
    final String equipmentType = (d['equipmentType'] ?? '').toString();
    final String equipmentId = (d['equipmentId'] ?? '').toString();
    final String projectCode = (d['projectCode'] ?? '').toString();
    final String partName = (d['partName'] ?? '').toString();
    final String description = (d['description'] ?? '').toString();
    final double quantity = EquipmentCalc.numOf(d['quantity']);
    final double unitCost = EquipmentCalc.numOf(d['unitCost']);
    final double cost = EquipmentCalc.numOf(d['totalCost']);
    final double downtime = EquipmentCalc.numOf(d['downtimeHours']);
    final DateTime? date = EquipmentService.dateOf(d['date']);

    final String headline = partName.isNotEmpty
        ? partName
        : (description.isNotEmpty
            ? description
            : MaintenanceTypes.label(type));

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _typeColor(type).withValues(alpha: 0.10),
          child: Icon(_typeIcon(type), color: _typeColor(type)),
        ),
        title: Text(
          '${MaintenanceTypes.label(type)}: $headline',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'المعدة: $equipmentType${code.isEmpty ? '' : ' — كود $code'}'
                '${projectCode.isEmpty ? '' : '  |  مشروع $projectCode'}'
                '\nالتاريخ: ${fmtDate(date)}  |  '
                '${fmtNum(quantity)} × ${fmtNum(unitCost)} = ${fmtMoney(cost)}'
                '${downtime > 0 ? '  |  التوقف: ${fmtNum(downtime)} ساعة' : ''}'
                '${description.isEmpty || headline == description ? '' : '\n$description'}',
              ),
              const SizedBox(height: 6),
              Chip(
                label: Text(
                  type == MaintenanceTypes.breakdown
                      ? MaintenanceTypes.statusLabel(status)
                      : 'منجز',
                  style: TextStyle(
                    fontSize: 12,
                    color: isOpen ? Colors.red : Colors.green,
                  ),
                ),
                backgroundColor: (isOpen ? Colors.red : Colors.green)
                    .withValues(alpha: 0.08),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'file':
                _openFile(equipmentId);
                break;
              case 'close':
                _closeLog(doc.id, d);
                break;
              case 'delete':
                _deleteLog(doc.id, d);
                break;
            }
          },
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            const PopupMenuItem(value: 'file', child: Text('ملف المعدة')),
            if (isOpen)
              const PopupMenuItem(
                value: 'close',
                child: Text('إنهاء الإصلاح'),
              ),
            const PopupMenuItem(value: 'delete', child: Text('حذف')),
          ],
        ),
        onTap: () => _openFile(equipmentId),
      ),
    );
  }

  // ==========================================================
  // تسجيل عطل / بدل تواير / قطع غيار / صيانة
  // ==========================================================

  Future<void> _openRecordForm() async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController partController = TextEditingController();
    final TextEditingController descriptionController =
        TextEditingController();
    final TextEditingController quantityController =
        TextEditingController(text: '1');
    final TextEditingController unitCostController = TextEditingController();
    final TextEditingController downtimeController = TextEditingController();
    final TextEditingController notesController = TextEditingController();

    EquipmentDoc? selected;
    String type = MaintenanceTypes.breakdown;
    bool done = true;
    DateTime date = DateTime.now();
    bool saving = false;

    String partLabel() {
      switch (type) {
        case MaintenanceTypes.tire:
          return 'مقاس / نوع التاير';
        case MaintenanceTypes.part:
          return 'اسم قطعة الغيار';
        case MaintenanceTypes.service:
          return 'بيان الصيانة';
        default:
          return 'العطل / القطعة المتعطلة';
      }
    }

    String quantityLabel() {
      switch (type) {
        case MaintenanceTypes.tire:
          return 'عدد التواير';
        case MaintenanceTypes.part:
          return 'عدد القطع';
        default:
          return 'الكمية';
      }
    }

    String unitLabel() {
      switch (type) {
        case MaintenanceTypes.tire:
          return 'سعر التاير الواحد';
        case MaintenanceTypes.part:
          return 'سعر القطعة الواحدة';
        default:
          return 'تكلفة الوحدة / العمل';
      }
    }

    double liveTotal() {
      final double q = parseMovementNumber(quantityController.text) ?? 0;
      final double u = parseMovementNumber(unitCostController.text) ?? 0;
      return EquipmentCalc.maintenanceCost(quantity: q, unitCost: u);
    }

    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('تسجيل في الورشة على معدة'),
                content: SizedBox(
                  width: 540,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          EquipmentDropdown(
                            service: _service,
                            selectedId: selected?.id,
                            onChanged: (EquipmentDoc? value) =>
                                setDialogState(() => selected = value),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: DropdownButtonFormField<String>(
                              key: ValueKey<String>('maint-type-$type'),
                              initialValue: type,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'نوع التسجيل *',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: MaintenanceTypes.all
                                  .map(
                                    (String t) =>
                                        DropdownMenuItem<String>(
                                      value: t,
                                      child: Text(MaintenanceTypes.label(t)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: saving
                                  ? null
                                  : (String? value) {
                                      if (value != null) {
                                        setDialogState(() => type = value);
                                      }
                                    },
                            ),
                          ),
                          MovementDateField(
                            label: 'تاريخ التسجيل',
                            value: date,
                            onChanged: (DateTime value) =>
                                setDialogState(() => date = value),
                          ),
                          movementTextField(
                            controller: partController,
                            label: partLabel(),
                            required: true,
                          ),
                          movementTextField(
                            controller: descriptionController,
                            label: 'شرح العمل / ملاحظات الفني',
                            maxLines: 2,
                          ),
                          movementTextField(
                            controller: quantityController,
                            label: quantityLabel(),
                            required: true,
                            number: true,
                            onChanged: (_) => setDialogState(() {}),
                          ),
                          movementTextField(
                            controller: unitCostController,
                            label: unitLabel(),
                            required: true,
                            number: true,
                            onChanged: (_) => setDialogState(() {}),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'الإجمالي: ${fmtMoney(liveTotal())} — '
                              'سيُضاف إلى ملف المعدة',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          movementTextField(
                            controller: downtimeController,
                            label: 'ساعات توقف المعدة',
                            number: true,
                          ),
                          if (type == MaintenanceTypes.breakdown)
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('تم إصلاح العطل'),
                              subtitle: Text(
                                done
                                    ? 'المعدة عادت للعمل'
                                    : 'ما زال قيد الإصلاح — ستظهر المعدة '
                                        '«معطلة» حتى إنهاء الإصلاح',
                              ),
                              value: done,
                              onChanged: saving
                                  ? null
                                  : (bool value) =>
                                      setDialogState(() => done = value),
                            ),
                          movementTextField(
                            controller: notesController,
                            label: 'ملاحظات إضافية',
                            maxLines: 2,
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
                            if (selected == null) {
                              showMovementMessage(
                                context,
                                'اختر المعدة بكودها أولًا',
                                error: true,
                              );
                              return;
                            }

                            setDialogState(() => saving = true);
                            try {
                              await _service.recordMaintenance(
                                equipment: selected!,
                                type: type,
                                date: date,
                                partName: partController.text.trim(),
                                description:
                                    descriptionController.text.trim(),
                                quantity: parseMovementNumber(
                                        quantityController.text) ??
                                    1,
                                unitCost: parseMovementNumber(
                                        unitCostController.text) ??
                                    0,
                                downtimeHours: parseMovementNumber(
                                        downtimeController.text) ??
                                    0,
                                done: type == MaintenanceTypes.breakdown
                                    ? done
                                    : true,
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
                                  error is EquipmentServiceException
                                      ? error.message
                                      : 'تعذر التسجيل: $error',
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
                    label: Text(saving ? 'جارٍ الحفظ...' : 'حفظ في ملف المعدة'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    partController.dispose();
    descriptionController.dispose();
    quantityController.dispose();
    unitCostController.dispose();
    downtimeController.dispose();
    notesController.dispose();

    if (saved == true && mounted) {
      showMovementMessage(
        context,
        'تم التسجيل — أُضيف إلى ملف المعدة ومجاميع صيانتها',
      );
    }
  }

  Future<void> _closeLog(String logId, Map<String, dynamic> log) async {
    final bool confirmed = await confirmMovementAction(
      context,
      title: 'إنهاء الإصلاح',
      message: 'سيُغلق عطل المعدة «${log['equipmentCode'] ?? ''}»، '
          'وستعود حالتها إلى «جيدة» إن لم يكن لها عطل مفتوح آخر.',
      confirmLabel: 'إنهاء الإصلاح',
    );
    if (!confirmed) return;
    try {
      await _service.closeMaintenance(logId: logId, log: log);
      if (mounted) showMovementMessage(context, 'تم إنهاء الإصلاح');
    } catch (error) {
      if (mounted) {
        showMovementMessage(
            context, 'تعذر إنهاء الإصلاح: $error', error: true);
      }
    }
  }

  Future<void> _deleteLog(String logId, Map<String, dynamic> log) async {
    final bool confirmed = await confirmMovementAction(
      context,
      title: 'حذف سجل ورشة',
      message: 'سيُحذف «${MaintenanceTypes.label((log['type'] ?? '').toString())}» '
          'عن المعدة «${log['equipmentCode'] ?? ''}» بتكلفة '
          '${fmtMoney(EquipmentCalc.numOf(log['totalCost']))}، '
          'وسيُخصم أثره من ملف المعدة.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!confirmed) return;
    try {
      await _service.deleteMaintenanceLog(logId: logId, log: log);
      if (mounted) showMovementMessage(context, 'تم حذف السجل');
    } catch (error) {
      if (mounted) {
        showMovementMessage(
            context, 'تعذر حذف السجل: $error', error: true);
      }
    }
  }
}

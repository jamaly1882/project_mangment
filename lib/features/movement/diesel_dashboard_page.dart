import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/equipment_service.dart';
import '../../core/utils/equipment_calculations.dart';
import 'equipment_file_page.dart';
import 'movement_widgets.dart';

// ============================================================
// إدارة الديزل — مدير المحروقات ومراقب الحركة
// ============================================================
//
// نافذتان:
//
//  1) «استهلاك المعدات»: كل سجل صرف فيه المعدة بكودها ورقم
//     المشروع الذي تعمل فيه (يأتيان تلقائيًا من ربط مدير
//     الحركة)، مع اللترات وسعر اللتر والكمية التي اشتغلتها
//     المعدة. تسجيل الصرف من زر «تسجيل صرف ديزل».
//
//  2) «استهلاك الوقود»: استهلاك كل مشروع برقمه وكمية
//     استهلاكه في اليوم (لتر/يوم) وتكلفته — يُجمَّع تلقائيًا
//     من سجلات النافذة الأولى في `project_fuel_daily`.
//
// كل صرف يُضاف أيضًا إلى «ملف المعدة» ومجاميعها.
// ============================================================

class DieselDashboardPage extends StatefulWidget {
  const DieselDashboardPage({super.key});

  @override
  State<DieselDashboardPage> createState() => _DieselDashboardPageState();
}

class _DieselDashboardPageState extends State<DieselDashboardPage> {
  final EquipmentService _service = EquipmentService();

  /// آخر سعر لتر استُخدم — يُقترح في التسجيل التالي.
  static double _lastPricePerLiter = 0;

  String _filter = 'all'; // all | today
  String? _selectedProjectId;

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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('إدارة الديزل'),
            centerTitle: true,
            actions: <Widget>[
              IconButton(
                tooltip: 'تسجيل الخروج',
                icon: const Icon(Icons.logout),
                onPressed: _logout,
              ),
            ],
            bottom: const TabBar(
              tabs: <Tab>[
                Tab(
                  icon: Icon(Icons.precision_manufacturing_outlined),
                  text: 'استهلاك المعدات',
                ),
                Tab(
                  icon: Icon(Icons.local_gas_station_outlined),
                  text: 'استهلاك الوقود',
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openRecordForm,
            icon: const Icon(Icons.add),
            label: const Text('تسجيل صرف ديزل'),
          ),
          body: TabBarView(
            children: <Widget>[
              _equipmentConsumptionTab(),
              _fuelConsumptionTab(),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // النافذة الأولى: استهلاك المعدات
  // (كل معدة بكودها ورقم مشروعها)
  // ==========================================================

  Widget _equipmentConsumptionTab() {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _service.dieselLogsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'تعذر تحميل سجلات الديزل.\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final List<QueryDocumentSnapshot<Map<String, dynamic>>> all =
            snapshot.data ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final String today = EquipmentCalc.dayKey(DateTime.now());

        double todayLiters = 0;
        double todayCost = 0;
        for (final doc in all) {
          if ((doc.data()['dayKey'] ?? '').toString() == today) {
            todayLiters += EquipmentCalc.numOf(doc.data()['liters']);
            todayCost += EquipmentCalc.numOf(doc.data()['totalCost']);
          }
        }

        final docs = _filter == 'today'
            ? all
                .where(
                    (d) => (d.data()['dayKey'] ?? '').toString() == today)
                .toList()
            : all;

        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: <Widget>[
            MovementStatGrid(
              stats: <MovementStat>[
                MovementStat(
                  label: 'سجلات الصرف',
                  value: '${all.length}',
                  icon: Icons.receipt_long_outlined,
                ),
                MovementStat(
                  label: 'ديزل اليوم (لتر)',
                  value: fmtNum(todayLiters),
                  icon: Icons.local_gas_station_outlined,
                  color: Colors.deepOrange,
                ),
                MovementStat(
                  label: 'تكلفة اليوم',
                  value: fmtMoney(todayCost),
                  icon: Icons.payments_outlined,
                  color: Colors.green,
                ),
                MovementStat(
                  label: 'آخر سعر لتر',
                  value: _lastPricePerLiter > 0
                      ? fmtMoney(_lastPricePerLiter)
                      : '—',
                  icon: Icons.sell_outlined,
                  color: Colors.blueGrey,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                ChoiceChip(
                  label: const Text('كل السجلات'),
                  selected: _filter == 'all',
                  onSelected: (_) => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('اليوم فقط'),
                  selected: _filter == 'today',
                  onSelected: (_) => setState(() => _filter = 'today'),
                ),
              ],
            ),
            const MovementSectionTitle(
              title: 'صرف الديزل للمعدات',
              icon: Icons.list_alt_outlined,
            ),
            if (docs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: MovementEmpty(
                  icon: Icons.local_gas_station_outlined,
                  message: 'لا توجد سجلات صرف ديزل بعد',
                  hint: 'اضغط «تسجيل صرف ديزل» واختر المعدة بكودها — '
                      'سيظهر رقم مشروعها تلقائيًا، وسيُضاف الصرف '
                      'إلى ملفها وإلى استهلاك مشروعها اليومي.',
                ),
              )
            else
              ...docs.map(_dieselLogCard),
          ],
        );
      },
    );
  }

  Widget _dieselLogCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> d = doc.data();
    final String code = (d['equipmentCode'] ?? '').toString();
    final String type = (d['equipmentType'] ?? '').toString();
    final String projectCode = (d['projectCode'] ?? '').toString();
    final String projectName = (d['projectName'] ?? '').toString();
    final String equipmentId = (d['equipmentId'] ?? '').toString();
    final double liters = EquipmentCalc.numOf(d['liters']);
    final double price = EquipmentCalc.numOf(d['pricePerLiter']);
    final double cost = EquipmentCalc.numOf(d['totalCost']);
    final double work = EquipmentCalc.numOf(d['workUnits']);
    final String workUnit = (d['workUnit'] ?? '').toString();
    final DateTime? date = EquipmentService.dateOf(d['date']);
    final String notes = (d['notes'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.local_gas_station)),
        title: Text(
          code.isEmpty ? type : '$type — كود $code',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            'رقم المشروع: ${projectCode.isEmpty ? '—' : projectCode}'
            '${projectName.isEmpty ? '' : ' — $projectName'}\n'
            'التاريخ: ${fmtDate(date)}  |  '
            '${fmtNum(liters)} لتر × ${fmtNum(price)} = ${fmtMoney(cost)}'
            '${work > 0 ? '\nاشتغلت: ${fmtNum(work)} $workUnit' : ''}'
            '${notes.isEmpty ? '' : '\n$notes'}',
          ),
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'حذف السجل',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteLog(doc.id, d),
        ),
        onTap: () => _openFile(equipmentId),
      ),
    );
  }

  // ==========================================================
  // النافذة الثانية: استهلاك الوقود
  // (رقم المشروع وكمية استهلاكه في اليوم)
  // ==========================================================

  Widget _fuelConsumptionTab() {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: ProjectDropdown(
            service: _service,
            label: 'تصفية برقم المشروع',
            isRequired: false,
            allowNoneLabel: 'كل المشاريع',
            selectedId: _selectedProjectId,
            onChanged: (ProjectOption? value) =>
                setState(() => _selectedProjectId = value?.id),
          ),
        ),
        Expanded(
          child: StreamBuilder<
              List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            stream: _service.projectFuelDailyStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'تعذر تحميل استهلاك الوقود.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final List<QueryDocumentSnapshot<Map<String, dynamic>>> all =
                  snapshot.data ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[];

              final docs = (_selectedProjectId == null ||
                      _selectedProjectId!.isEmpty)
                  ? all
                  : all
                      .where((d) =>
                          (d.data()['projectId'] ?? '').toString() ==
                          _selectedProjectId)
                      .toList();

              double totalLiters = 0;
              double totalCost = 0;
              for (final doc in docs) {
                totalLiters += EquipmentCalc.numOf(doc.data()['totalLiters']);
                totalCost += EquipmentCalc.numOf(doc.data()['totalCost']);
              }
              final double dailyAverage =
                  docs.isEmpty ? 0 : totalLiters / docs.length;

              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                children: <Widget>[
                  MovementStatGrid(
                    stats: <MovementStat>[
                      MovementStat(
                        label: 'أيام الاستهلاك',
                        value: '${docs.length}',
                        icon: Icons.calendar_month_outlined,
                      ),
                      MovementStat(
                        label: 'إجمالي اللترات',
                        value: fmtNum(totalLiters),
                        icon: Icons.local_gas_station_outlined,
                        color: Colors.deepOrange,
                      ),
                      MovementStat(
                        label: 'متوسط اليوم (لتر)',
                        value: fmtNum(dailyAverage),
                        icon: Icons.show_chart,
                        color: Colors.blue,
                      ),
                      MovementStat(
                        label: 'إجمالي التكلفة',
                        value: fmtMoney(totalCost),
                        icon: Icons.payments_outlined,
                        color: Colors.green,
                      ),
                    ],
                  ),
                  const MovementSectionTitle(
                    title: 'استهلاك كل مشروع في اليوم',
                    icon: Icons.table_rows_outlined,
                  ),
                  if (docs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: MovementEmpty(
                        icon: Icons.local_gas_station_outlined,
                        message: 'لا يوجد استهلاك وقود مسجل بعد',
                        hint: 'يظهر هنا تلقائيًا استهلاك كل مشروع برقمه '
                            'وكميته في اليوم بمجرد تسجيل صرف الديزل '
                            'لأي معدة تعمل فيه.',
                      ),
                    )
                  else
                    ...docs.map(_fuelDayCard),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _fuelDayCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> d = doc.data();
    final String projectCode = (d['projectCode'] ?? '').toString();
    final String projectName = (d['projectName'] ?? '').toString();
    final String day = (d['dayKey'] ?? '').toString();
    final double liters = EquipmentCalc.numOf(d['totalLiters']);
    final double cost = EquipmentCalc.numOf(d['totalCost']);
    final int records = EquipmentCalc.numOf(d['recordsCount']).toInt();
    final int equipmentCount = (d['equipmentIds'] as List?)?.length ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.apartment_outlined)),
        title: Text(
          'مشروع ${projectCode.isEmpty ? '—' : projectCode}'
          '${projectName.isEmpty ? '' : ' — $projectName'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            'اليوم: $day\n'
            'استهلاك اليوم: ${fmtNum(liters)} لتر  |  '
            'التكلفة: ${fmtMoney(cost)}\n'
            'سجلات الصرف: $records  |  المعدات: $equipmentCount',
          ),
        ),
        isThreeLine: true,
      ),
    );
  }

  // ==========================================================
  // تسجيل صرف ديزل
  // ==========================================================

  Future<void> _openRecordForm() async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController litersController = TextEditingController();
    final TextEditingController priceController = TextEditingController(
      text: _lastPricePerLiter > 0 ? fmtNum(_lastPricePerLiter) : '',
    );
    final TextEditingController workController = TextEditingController();
    final TextEditingController meterController = TextEditingController();
    final TextEditingController notesController = TextEditingController();

    EquipmentDoc? selected;
    DateTime date = DateTime.now();
    bool saving = false;

    double liveTotal() {
      final double liters = parseMovementNumber(litersController.text) ?? 0;
      final double price = parseMovementNumber(priceController.text) ?? 0;
      return EquipmentCalc.dieselCost(liters: liters, pricePerLiter: price);
    }

    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final bool noProject = selected != null && !selected!.hasProject;
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('تسجيل صرف ديزل لمعدة'),
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
                            onChanged: (EquipmentDoc? value) {
                              setDialogState(() {
                                selected = value;
                                if (value != null &&
                                    value.currentMeter > 0 &&
                                    meterController.text.isEmpty) {
                                  meterController.text =
                                      fmtNum(value.currentMeter);
                                }
                              });
                            },
                          ),
                          if (selected != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: noProject
                                    ? Colors.red.withValues(alpha: 0.06)
                                    : Colors.green.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: (noProject
                                          ? Colors.red
                                          : Colors.green)
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                noProject
                                    ? 'تنبيه: المعدة «${selected!.code}» غير '
                                        'مرتبطة بأي مشروع حاليًا. يربطها مدير '
                                        'الحركة بمشروع أولًا، ثم يُسجَّل '
                                        'صرف الديزل لها.'
                                    : 'سيُسجَّل الصرف على: رقم المشروع '
                                        '${selected!.projectCode}'
                                        '${selected!.projectName.isEmpty ? '' : ' — ${selected!.projectName}'}'
                                        '\nوستُضاف الكمية إلى ملف المعدة وإلى '
                                        'استهلاك المشروع في اليوم.',
                              ),
                            ),
                          MovementDateField(
                            label: 'تاريخ الصرف',
                            value: date,
                            onChanged: (DateTime value) =>
                                setDialogState(() => date = value),
                          ),
                          movementTextField(
                            controller: litersController,
                            label: 'كمية الديزل (لتر)',
                            required: true,
                            number: true,
                            onChanged: (_) => setDialogState(() {}),
                          ),
                          movementTextField(
                            controller: priceController,
                            label: 'سعر اللتر',
                            required: true,
                            number: true,
                            onChanged: (_) => setDialogState(() {}),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'إجمالي تكلفة الصرف: ${fmtMoney(liveTotal())}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          movementTextField(
                            controller: workController,
                            label: selected == null ||
                                    selected!.workUnit.isEmpty
                                ? 'الكمية التي اشتغلتها المعدة (وحدة عمل)'
                                : 'الكمية التي اشتغلتها المعدة '
                                    '(${selected!.workUnit})',
                            number: true,
                          ),
                          movementTextField(
                            controller: meterController,
                            label: 'قراءة العداد عند الصرف',
                            number: true,
                          ),
                          movementTextField(
                            controller: notesController,
                            label: 'ملاحظات',
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

                            final double liters =
                                parseMovementNumber(litersController.text) ??
                                    0;
                            final double price =
                                parseMovementNumber(priceController.text) ??
                                    0;

                            setDialogState(() => saving = true);
                            try {
                              await _service.recordDiesel(
                                equipment: selected!,
                                date: date,
                                liters: liters,
                                pricePerLiter: price,
                                workUnits:
                                    parseMovementNumber(workController.text) ??
                                        0,
                                meterReading:
                                    parseMovementNumber(meterController.text) ??
                                        0,
                                notes: notesController.text.trim(),
                                byUid: _uid,
                                byName: _userName,
                              );
                              _lastPricePerLiter = price;
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
                                      : 'تعذر تسجيل الصرف: $error',
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
                    label: Text(saving ? 'جارٍ الحفظ...' : 'حفظ الصرف'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    litersController.dispose();
    priceController.dispose();
    workController.dispose();
    meterController.dispose();
    notesController.dispose();

    if (saved == true && mounted) {
      setState(() {});
      showMovementMessage(
        context,
        'تم تسجيل الصرف — أُضيف إلى ملف المعدة واستهلاك مشروعها اليومي',
      );
    }
  }

  Future<void> _deleteLog(
    String logId,
    Map<String, dynamic> log,
  ) async {
    final bool confirmed = await confirmMovementAction(
      context,
      title: 'حذف سجل صرف',
      message: 'سيُحذف سجل صرف ${fmtNum(EquipmentCalc.numOf(log['liters']))} '
          'لتر للمعدة «${log['equipmentCode'] ?? ''}»، وسيُخصم أثره من '
          'ملف المعدة ومن استهلاك مشروعها في ذلك اليوم.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!confirmed) return;
    try {
      await _service.deleteDieselLog(logId: logId, log: log);
      if (mounted) showMovementMessage(context, 'تم حذف سجل الصرف');
    } catch (error) {
      if (mounted) {
        showMovementMessage(
            context, 'تعذر حذف السجل: $error', error: true);
      }
    }
  }
}

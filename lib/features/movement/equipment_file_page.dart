import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/services/equipment_service.dart';
import '../../core/utils/equipment_calculations.dart';
import 'movement_widgets.dart';

// ============================================================
// ملف المعدة
// ============================================================
//
// صفحة واحدة تجمع عمر المعدة كله:
//   • بياناتها الأساسية ومشروعها الحالي (من إدارة الحركة).
//   • كل صرف ديزل سجلته إدارة الديزل (مع رقم المشروع).
//   • كل ما كتبته الورشة: الأعطال وبدلات التواير وقطع الغيار.
//   • سجل تنقلاتها بين المشاريع.
//   • الإهلاك المحتسب بطريقتين: بقيمة المعدة ووحدات عملها،
//     ومن تكلفة ديزلها (نسبة الإكسل 50%) ومعه بدل الأعطال (5%).
//
// المجاميع هنا تُحسب من السجلات نفسها (EquipmentFileTotals)
// فهي مرجع التحقق، وتطابق المجاميع المتراكمة في وثيقة المعدة.
// ============================================================

class EquipmentFilePage extends StatefulWidget {
  const EquipmentFilePage({super.key, required this.equipmentId});

  final String equipmentId;

  @override
  State<EquipmentFilePage> createState() => _EquipmentFilePageState();
}

class _EquipmentFilePageState extends State<EquipmentFilePage> {
  final EquipmentService _service = EquipmentService();

  /// أحدث سجلات تُعرض في كل قسم من الملف.
  static const int _maxShown = 50;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('ملف المعدة'), centerTitle: true),
        body: StreamBuilder<EquipmentDoc?>(
          stream: _service.equipmentDocStream(widget.equipmentId),
          builder: (context, equipmentSnapshot) {
            if (equipmentSnapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'تعذر تحميل ملف المعدة.\n${equipmentSnapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (equipmentSnapshot.connectionState ==
                    ConnectionState.waiting &&
                !equipmentSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final EquipmentDoc? equipment = equipmentSnapshot.data;
            if (equipment == null) {
              return const MovementEmpty(
                icon: Icons.search_off_outlined,
                message: 'المعدة غير موجودة',
                hint: 'ربما حُذفت من حصر المعدات. سجلات ديزلها '
                    'وصيانتها السابقة محفوظة كسجل تاريخي.',
              );
            }

            return StreamBuilder<
                List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              stream: _service.dieselLogsStream(
                equipmentId: widget.equipmentId,
              ),
              builder: (context, dieselSnapshot) {
                return StreamBuilder<
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                  stream: _service.maintenanceLogsStream(
                    equipmentId: widget.equipmentId,
                  ),
                  builder: (context, maintenanceSnapshot) {
                    return StreamBuilder<
                        List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                      stream: _service.assignmentsStream(widget.equipmentId),
                      builder: (context, assignmentsSnapshot) {
                        final bool loading =
                            (dieselSnapshot.connectionState ==
                                        ConnectionState.waiting &&
                                    !dieselSnapshot.hasData) ||
                                (maintenanceSnapshot.connectionState ==
                                        ConnectionState.waiting &&
                                    !maintenanceSnapshot.hasData);
                        if (loading) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final List<
                                QueryDocumentSnapshot<Map<String, dynamic>>>
                            dieselDocs = dieselSnapshot.data ??
                                <QueryDocumentSnapshot<
                                    Map<String, dynamic>>>[];
                        final List<
                                QueryDocumentSnapshot<Map<String, dynamic>>>
                            maintenanceDocs = maintenanceSnapshot.data ??
                                <QueryDocumentSnapshot<
                                    Map<String, dynamic>>>[];
                        final List<
                                QueryDocumentSnapshot<Map<String, dynamic>>>
                            assignmentDocs = assignmentsSnapshot.data ??
                                <QueryDocumentSnapshot<
                                    Map<String, dynamic>>>[];

                        final EquipmentFileTotals totals =
                            EquipmentFileTotals.fromLogs(
                          dieselLogs:
                              dieselDocs.map((d) => d.data()).toList(),
                          maintenanceLogs:
                              maintenanceDocs.map((d) => d.data()).toList(),
                        );

                        return ListView(
                          padding:
                              const EdgeInsets.fromLTRB(12, 12, 12, 32),
                          children: <Widget>[
                            _header(equipment),
                            const MovementSectionTitle(
                              title: 'الديزل والعمل (إدارة الديزل)',
                              icon: Icons.local_gas_station_outlined,
                            ),
                            MovementStatGrid(
                              stats: <MovementStat>[
                                MovementStat(
                                  label: 'إجمالي الديزل (لتر)',
                                  value: fmtNum(totals.totalLiters),
                                  icon: Icons.local_gas_station_outlined,
                                  color: Colors.deepOrange,
                                ),
                                MovementStat(
                                  label: 'تكلفة الديزل',
                                  value: fmtMoney(totals.totalFuelCost),
                                  icon: Icons.payments_outlined,
                                  color: Colors.green,
                                ),
                                MovementStat(
                                  label: 'وحدات العمل المنفذة'
                                      '${equipment.workUnit.isEmpty ? '' : ' (${equipment.workUnit})'}',
                                  value: fmtNum(totals.totalWorkUnits),
                                  icon: Icons.speed_outlined,
                                  color: Colors.blue,
                                ),
                                MovementStat(
                                  label: 'تكلفة الديزل / وحدة عمل',
                                  value:
                                      fmtMoney(totals.dieselCostPerWorkUnit),
                                  icon: Icons.functions_outlined,
                                  color: Colors.blueGrey,
                                ),
                              ],
                            ),
                            const MovementSectionTitle(
                              title: 'الورشة والصيانة (الأعطال والتواير والقطع)',
                              icon: Icons.handyman_outlined,
                            ),
                            MovementStatGrid(
                              stats: <MovementStat>[
                                MovementStat(
                                  label: 'إجمالي الصيانة',
                                  value:
                                      fmtMoney(totals.totalMaintenanceCost),
                                  icon: Icons.handyman_outlined,
                                  color: Colors.indigo,
                                ),
                                MovementStat(
                                  label: 'الأعطال: ${totals.breakdownCount} '
                                      '(مفتوحة ${totals.openBreakdownCount})',
                                  value: fmtMoney(totals.breakdownCost),
                                  icon: Icons.report_problem_outlined,
                                  color: Colors.red,
                                ),
                                MovementStat(
                                  label: 'بدلات التواير',
                                  value: fmtMoney(totals.tiresCost),
                                  icon: Icons.tire_repair,
                                  color: Colors.blueGrey,
                                ),
                                MovementStat(
                                  label: 'قطع الغيار',
                                  value: fmtMoney(totals.partsCost),
                                  icon: Icons.settings_outlined,
                                  color: Colors.deepPurple,
                                ),
                                MovementStat(
                                  label: 'صيانة أخرى',
                                  value: fmtMoney(totals.serviceCost),
                                  icon: Icons.build_outlined,
                                  color: Colors.teal,
                                ),
                                MovementStat(
                                  label: 'ساعات التوقف',
                                  value: fmtNum(totals.totalDowntimeHours),
                                  icon: Icons.timer_off_outlined,
                                  color: Colors.brown,
                                ),
                                MovementStat(
                                  label: 'إجمالي التشغيل (ديزل + صيانة)',
                                  value: fmtMoney(totals.totalOperatingCost),
                                  icon: Icons.account_balance_wallet_outlined,
                                  color: Colors.green.shade800,
                                ),
                              ],
                            ),
                            const MovementSectionTitle(
                              title: 'الإهلاك وبدل الأعطال المحتسب',
                              icon: Icons.calculate_outlined,
                            ),
                            _depreciationCard(equipment, totals),
                            const MovementSectionTitle(
                              title: 'سجل صرف الديزل',
                              icon: Icons.receipt_long_outlined,
                            ),
                            if (dieselDocs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  'لا يوجد صرف ديزل مسجل لهذه المعدة بعد. '
                                  'يُسجَّل من إدارة الديزل — نافذة '
                                  '«استهلاك المعدات».',
                                ),
                              )
                            else ...<Widget>[
                              ...dieselDocs
                                  .take(_maxShown)
                                  .map(_dieselRow),
                              if (dieselDocs.length > _maxShown)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Text(
                                    'يُعرض أحدث $_maxShown سجلًا من أصل '
                                    '${dieselDocs.length}.',
                                    style: const TextStyle(
                                        color: Colors.black54),
                                  ),
                                ),
                            ],
                            const MovementSectionTitle(
                              title: 'سجل الورشة: الأعطال والتواير والقطع',
                              icon: Icons.handyman_outlined,
                            ),
                            if (maintenanceDocs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  'لا توجد أعطال أو صيانة مسجلة لهذه '
                                  'المعدة بعد. تُسجَّل من إدارة الورشة '
                                  'والصيانة.',
                                ),
                              )
                            else ...<Widget>[
                              ...maintenanceDocs
                                  .take(_maxShown)
                                  .map(_maintenanceRow),
                              if (maintenanceDocs.length > _maxShown)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Text(
                                    'يُعرض أحدث $_maxShown سجلًا من أصل '
                                    '${maintenanceDocs.length}.',
                                    style: const TextStyle(
                                        color: Colors.black54),
                                  ),
                                ),
                            ],
                            const MovementSectionTitle(
                              title: 'سجل التنقلات بين المشاريع',
                              icon: Icons.swap_horiz_outlined,
                            ),
                            if (assignmentDocs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  'لا توجد تنقلات مسجلة. ينقلها مدير '
                                  'الحركة من لوحة إدارة الحركة.',
                                ),
                              )
                            else
                              ...assignmentDocs.map(_assignmentRow),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ==========================================================
  // رأس الملف
  // ==========================================================

  Widget _header(EquipmentDoc e) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const CircleAvatar(
                  radius: 26,
                  child: Icon(
                    Icons.precision_manufacturing_outlined,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        e.type,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text('الكود / الرقم الإداري: ${e.code}'),
                    ],
                  ),
                ),
                ConditionChip(condition: e.condition),
              ],
            ),
            const Divider(height: 24),
            MovementInfoRow(
              label: 'المشروع الحالي',
              value: e.hasProject
                  ? 'رقم ${e.projectCode}'
                      '${e.projectName.isEmpty ? '' : ' — ${e.projectName}'}'
                  : 'بدون مشروع حاليًا (ساحة الحركة)',
            ),
            MovementInfoRow(label: 'الشركة المصنعة', value: e.manufacturer),
            MovementInfoRow(label: 'وحدة العمل', value: e.workUnit),
            MovementInfoRow(
              label: 'العداد الحالي',
              value:
                  '${fmtNum(e.currentMeter)}${e.workUnit.isEmpty ? '' : ' ${e.workUnit}'}',
            ),
            MovementInfoRow(
              label: 'السائق / المشغّل',
              value: e.driverName.isEmpty
                  ? ''
                  : '${e.driverName}'
                      '${e.driverPhone.isEmpty ? '' : ' — ${e.driverPhone}'}',
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // الإهلاك وبدل الأعطال
  // ==========================================================

  Widget _depreciationCard(EquipmentDoc e, EquipmentFileTotals totals) {
    final double perUnit = EquipmentCalc.depreciationPerWorkUnit(
      currentValue: e.currentValue,
      salvageValue: e.salvageValue,
      expectedWorkUnits: e.expectedWorkUnits,
    );
    final double accumulated = EquipmentCalc.accumulatedDepreciation(
      perWorkUnit: perUnit,
      workedUnits: totals.totalWorkUnits,
      currentValue: e.currentValue,
      salvageValue: e.salvageValue,
    );
    final double book = EquipmentCalc.bookValue(
      currentValue: e.currentValue,
      accumulated: accumulated,
    );
    final double lifeRatio = EquipmentCalc.consumedLifeRatio(
      workedUnits: totals.totalWorkUnits,
      expectedWorkUnits: e.expectedWorkUnits,
    );

    // طريقة الإكسل: الإهلاك 50% من تكلفة الديزل/وحدة،
    // وبدل الأعطال 5% منه.
    final double depFromDiesel = EquipmentCalc.depreciationFromDieselCost(
      dieselCostPerWorkUnit: totals.dieselCostPerWorkUnit,
    );
    final double allowancePerUnit =
        EquipmentCalc.breakdownAllowancePerWorkUnit(
      depreciationPerWorkUnit: depFromDiesel,
    );
    final double allowanceTotal = allowancePerUnit * totals.totalWorkUnits;

    final bool hasInputs = e.currentValue > 0 && e.expectedWorkUnits > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'أولًا: الإهلاك بقيمة المعدة ووحدات عملها',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (!hasInputs)
              const Text(
                'لا تُحتسب هذه الطريقة بعد: يلزم إدخال «القيمة الحالية '
                'للمعدة» و«عدد وحدات العمل المتوقعة» من تعديل بيانات '
                'المعدة في إدارة الحركة (قسم بيانات الإهلاك).',
              )
            else ...<Widget>[
              MovementInfoRow(
                label: 'القيمة الحالية للمعدة',
                value: fmtMoney(e.currentValue),
              ),
              MovementInfoRow(
                label: 'القيمة التخريدية',
                value: fmtMoney(e.salvageValue),
              ),
              MovementInfoRow(
                label: 'وحدات العمل المتوقعة',
                value:
                    '${fmtNum(e.expectedWorkUnits)}${e.workUnit.isEmpty ? '' : ' ${e.workUnit}'}',
              ),
              MovementInfoRow(
                label: 'إهلاك وحدة العمل',
                value: '${fmtMoney(perUnit)} / ${e.workUnit.isEmpty ? 'وحدة' : e.workUnit}',
              ),
              MovementInfoRow(
                label: 'وحدات العمل المنفذة',
                value: fmtNum(totals.totalWorkUnits),
              ),
              MovementInfoRow(
                label: 'الإهلاك المتراكم حتى الآن',
                value: fmtMoney(accumulated),
              ),
              MovementInfoRow(
                label: 'القيمة الدفترية الحالية',
                value: fmtMoney(book),
              ),
              const SizedBox(height: 8),
              Text(
                'نسبة استهلاك عمر المعدة: '
                '${fmtNum(lifeRatio * 100)}%',
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: lifeRatio),
            ],
            const Divider(height: 28),
            const Text(
              'ثانيًا: الإهلاك وبدل الأعطال من تكلفة الديزل (طريقة الإكسل)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            MovementInfoRow(
              label: 'تكلفة الديزل / وحدة عمل',
              value: fmtMoney(totals.dieselCostPerWorkUnit),
            ),
            MovementInfoRow(
              label: 'إهلاك الوحدة (50% من تكلفة الديزل)',
              value: fmtMoney(depFromDiesel),
            ),
            MovementInfoRow(
              label: 'بدل الأعطال / وحدة عمل (5%)',
              value: fmtMoney(allowancePerUnit),
            ),
            MovementInfoRow(
              label: 'بدل الأعطال المحتسب عن العمل المنفذ',
              value: fmtMoney(allowanceTotal),
            ),
            MovementInfoRow(
              label: 'تكلفة صيانتها الفعلية (للورشة)',
              value: fmtMoney(totals.totalMaintenanceCost),
            ),
            const SizedBox(height: 6),
            const Text(
              'قارن بدل الأعطال المحتسب بتكلفة الصيانة الفعلية: '
              'الفعلية الأعلى باستمرار تعني أن المعدة تكلّف أكثر '
              'مما خُصص لمواجهة أعطالها.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // صفوف السجلات
  // ==========================================================

  Widget _dieselRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data();
    final double liters = EquipmentCalc.numOf(d['liters']);
    final double price = EquipmentCalc.numOf(d['pricePerLiter']);
    final double cost = EquipmentCalc.numOf(d['totalCost']);
    final double work = EquipmentCalc.numOf(d['workUnits']);
    final String workUnit = (d['workUnit'] ?? '').toString();
    final String projectCode = (d['projectCode'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.local_gas_station_outlined),
        title: Text(
          '${fmtNum(liters)} لتر × ${fmtNum(price)} = ${fmtMoney(cost)}',
        ),
        subtitle: Text(
          '${fmtDate(EquipmentService.dateOf(d['date']))}'
          '${projectCode.isEmpty ? '' : '  |  مشروع $projectCode'}'
          '${work > 0 ? '  |  اشتغلت ${fmtNum(work)} $workUnit' : ''}',
        ),
      ),
    );
  }

  Widget _maintenanceRow(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> d = doc.data();
    final String type = (d['type'] ?? '').toString();
    final String status = (d['status'] ?? '').toString();
    final bool isOpen = type == MaintenanceTypes.breakdown &&
        status == MaintenanceTypes.statusOpen;
    final String partName = (d['partName'] ?? '').toString();
    final String description = (d['description'] ?? '').toString();
    final double quantity = EquipmentCalc.numOf(d['quantity']);
    final double cost = EquipmentCalc.numOf(d['totalCost']);
    final double downtime = EquipmentCalc.numOf(d['downtimeHours']);
    final String projectCode = (d['projectCode'] ?? '').toString();

    final IconData icon;
    switch (type) {
      case MaintenanceTypes.breakdown:
        icon = Icons.report_problem_outlined;
        break;
      case MaintenanceTypes.tire:
        icon = Icons.tire_repair;
        break;
      case MaintenanceTypes.part:
        icon = Icons.settings_outlined;
        break;
      default:
        icon = Icons.handyman_outlined;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: isOpen ? Colors.red : null),
        title: Text(
          '${MaintenanceTypes.label(type)}'
          '${partName.isEmpty ? '' : ': $partName'}'
          '${quantity > 1 ? ' × ${fmtNum(quantity)}' : ''}'
          ' — ${fmtMoney(cost)}',
        ),
        subtitle: Text(
          '${fmtDate(EquipmentService.dateOf(d['date']))}'
          '${projectCode.isEmpty ? '' : '  |  مشروع $projectCode'}'
          '${downtime > 0 ? '  |  توقف ${fmtNum(downtime)} س' : ''}'
          '${type == MaintenanceTypes.breakdown ? '  |  ${MaintenanceTypes.statusLabel(status)}' : ''}'
          '${description.isEmpty ? '' : '\n$description'}',
        ),
      ),
    );
  }

  Widget _assignmentRow(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> d = doc.data();
    final String projectCode = (d['projectCode'] ?? '').toString();
    final String projectName = (d['projectName'] ?? '').toString();
    final DateTime? from = EquipmentService.dateOf(d['fromDate']);
    final DateTime? to = EquipmentService.dateOf(d['toDate']);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.apartment_outlined),
        title: Text(
          'مشروع ${projectCode.isEmpty ? '—' : projectCode}'
          '${projectName.isEmpty ? '' : ' — $projectName'}',
        ),
        subtitle: Text(
          'من ${fmtDate(from)}'
          '${to == null ? ' حتى الآن (تعمل فيه)' : ' إلى ${fmtDate(to)}'}',
        ),
        trailing: to == null
            ? const Chip(
                label: Text('الحالي', style: TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
              )
            : null,
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'assignment_details_page.dart';

/// صفحة العمل المشتركة لمشرفي البنود (ولوحة السائق القديمة).
///
/// عند [supervisorMode] = true تُقرأ الإسنادات من
/// item_supervisors/supervisorId،
/// وعند false تُقرأ من السجل القديم item_drivers/driverId.
class AssignmentWorkspacePage extends StatelessWidget {
  // =========================================================
  // المشاريع المرتبط بها المستخدم
  // =========================================================

  final List<String> projectIds;

  final bool supervisorMode;

  const AssignmentWorkspacePage({
    super.key,
    required this.projectIds,
    this.supervisorMode = true,
  });

  // =========================================================
  // نصوص وأسماء الحقول حسب الوضع
  // =========================================================

  String get _assigneeLabel => supervisorMode ? 'المشرف' : 'السائق';

  String get _collectionName =>
      supervisorMode ? 'item_supervisors' : 'item_drivers';

  String get _idField => supervisorMode ? 'supervisorId' : 'driverId';

  IconData get _roleIcon => supervisorMode
      ? Icons.supervisor_account_outlined
      : Icons.local_shipping_outlined;

  // =========================================================
  // Firestore
  // =========================================================

  FirebaseFirestore get firestore => FirebaseFirestore.instance;

  // =========================================================
  // جلب البنود المسندة للمستخدم الحالي
  // =========================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> assignmentsStream() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Stream.empty();
    }

    // نفلتر على المعرّف فقط، ثم نستبعد غير النشط داخل الواجهة.
    // السبب: شرط `active` مع معرّف المشرف يحتاج فهرسًا مركّبًا في
    // Firestore، وإذا لم يكن موجودًا يفشل تحميل اللوحة بالكامل،
    // كما أن بعض السجلات القديمة لا تحتوي الحقل أصلًا.
    return firestore
        .collection(_collectionName)
        .where(
          _idField,
          isEqualTo: user.uid,
        )
        .snapshots();
  }

  // =========================================================
  // تحويل الرقم
  // =========================================================

  double toDouble(dynamic value) {
    if (value == null) {
      return 0;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }

  // =========================================================
  // تنسيق الرقم
  // =========================================================

  String formatNumber(dynamic value) {
    if (value == null) {
      return '0';
    }

    final number = toDouble(value);

    if (number == number.roundToDouble()) {
      return number.toInt().toString();
    }

    return number.toString();
  }

  // =========================================================
  // Build
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            supervisorMode
                ? 'لوحة مشرف البند'
                : 'لوحة السائق',
          ),
          centerTitle: true,
        ),
        body: user == null
            ? const Center(
                child: Text(
                  'يجب تسجيل الدخول أولاً',
                  textDirection: TextDirection.rtl,
                ),
              )
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: assignmentsStream(),
                builder: (
                  context,
                  snapshot,
                ) {
                  // =================================================
                  // تحميل
                  // =================================================

                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  // =================================================
                  // خطأ
                  // =================================================

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'حدث خطأ أثناء تحميل البنود:\n'
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    );
                  }

                  // السجل نشط ما لم يكن `active` صريحًا بـ false،
                  // حتى لا تختفي التكليفات القديمة التي لا تحمل الحقل.
                  final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                      assignments = (snapshot.data?.docs ??
                              <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                          .where(
                            (doc) => doc.data()['active'] != false,
                          )
                          .toList();

                  // =================================================
                  // لا توجد بنود
                  // =================================================

                  if (assignments.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _roleIcon,
                            size: 75,
                          ),
                          const SizedBox(height: 15),
                          const Text(
                            'لا توجد بنود مسندة إليك',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                            textDirection: TextDirection.rtl,
                          ),
                          const SizedBox(height: 8),
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 30,
                            ),
                            child: Text(
                              'ستظهر هنا البنود التي يسندها لك مدير المشروع '
                              'بعد اختيار مشرف البند في صفحة تفاصيل البند. '
                              'وبعد إسناد أي بند اضغطه هنا لإدخال تكاليفه '
                              'الفعلية واستهلاك محروقاته — وستصل محروقاته '
                              'تلقائيًا إلى مدير المحروقات.',
                              textAlign: TextAlign.center,
                              textDirection: TextDirection.rtl,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // =================================================
                  // البنود المسندة
                  // =================================================

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: assignments.length,
                    itemBuilder: (
                      context,
                      index,
                    ) {
                      final assignment = assignments[index].data();

                      // =================================================
                      // رقم البند
                      // =================================================

                      final itemId = assignment['itemId']?.toString();

                      if (itemId == null || itemId.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      // =================================================
                      // جلب بيانات البند
                      // =================================================

                      // StreamBuilder بدل FutureBuilder حتى تتحدث
                      // الكميات فور تسجيل المشرف لها في صفحة البند.
                      return StreamBuilder<
                          DocumentSnapshot<Map<String, dynamic>>>(
                        stream: firestore
                            .collection('items')
                            .doc(itemId)
                            .snapshots(),
                        builder: (
                          context,
                          itemSnapshot,
                        ) {
                          // =================================================
                          // تحميل
                          // =================================================

                          if (itemSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Card(
                              margin: EdgeInsets.only(
                                bottom: 15,
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(25),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            );
                          }

                          // =================================================
                          // خطأ
                          // =================================================

                          if (itemSnapshot.hasError) {
                            return Card(
                              margin: const EdgeInsets.only(
                                bottom: 15,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'حدث خطأ أثناء تحميل البند:\n'
                                  '${itemSnapshot.error}',
                                  textAlign: TextAlign.center,
                                  textDirection: TextDirection.rtl,
                                ),
                              ),
                            );
                          }

                          // =================================================
                          // البند غير موجود
                          // =================================================

                          final itemDocument = itemSnapshot.data;

                          if (itemDocument == null ||
                              !itemDocument.exists) {
                            return const SizedBox.shrink();
                          }

                          final itemData = itemDocument.data() ?? {};

                          // =================================================
                          // التأكد من المشروع
                          // =================================================

                          final itemProjectId =
                              itemData['projectId']?.toString();

                          if (itemProjectId == null ||
                              itemProjectId.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          if (projectIds.isNotEmpty &&
                              !projectIds.contains(itemProjectId)) {
                            return const SizedBox.shrink();
                          }

                          // =================================================
                          // جلب تفاصيل البند
                          //
                          // item_details/{itemId}
                          // =================================================

                          return StreamBuilder<
                              DocumentSnapshot<Map<String, dynamic>>>(
                            stream: firestore
                                .collection('item_details')
                                .doc(itemId)
                                .snapshots(),
                            builder: (
                              context,
                              detailsSnapshot,
                            ) {
                              // =================================================
                              // تحميل التفاصيل
                              // =================================================

                              if (detailsSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Card(
                                  margin: EdgeInsets.only(
                                    bottom: 15,
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(25),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                );
                              }

                              // =================================================
                              // خطأ في التفاصيل
                              // =================================================

                              if (detailsSnapshot.hasError) {
                                return Card(
                                  margin: const EdgeInsets.only(
                                    bottom: 15,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      'حدث خطأ أثناء تحميل تفاصيل البند:\n'
                                      '${detailsSnapshot.error}',
                                      textAlign: TextAlign.center,
                                      textDirection: TextDirection.rtl,
                                    ),
                                  ),
                                );
                              }

                              // =================================================
                              // بيانات التفاصيل
                              // =================================================

                              final detailsData =
                                  detailsSnapshot.data?.data() ?? {};

                              // =================================================
                              // بطاقة البند
                              // =================================================

                              return _AssignmentItemCard(
                                data: itemData,
                                detailsData: detailsData,
                                formatNumber: formatNumber,
                                toDouble: toDouble,
                                supervisorMode: supervisorMode,
                                assigneeLabel: _assigneeLabel,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AssignmentDetailsPage(
                                        projectId: itemProjectId,
                                        itemId: itemId,
                                      ),
                                    ),
                                  );
                                },
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
}

// =============================================================
// بطاقة البند المسند
// =============================================================

class _AssignmentItemCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final Map<String, dynamic> detailsData;
  final String Function(dynamic) formatNumber;
  final double Function(dynamic) toDouble;
  final bool supervisorMode;
  final String assigneeLabel;
  final VoidCallback onTap;

  const _AssignmentItemCard({
    required this.data,
    required this.detailsData,
    required this.formatNumber,
    required this.toDouble,
    required this.supervisorMode,
    required this.assigneeLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // =========================================================
    // اسم البند
    // =========================================================

    final itemName =
        data['itemDefinitionName']?.toString() ??
        data['name']?.toString() ??
        'بدون اسم';

    // =========================================================
    // نوع البند
    // =========================================================

    final typeName = data['typeName']?.toString() ?? '';

    // =========================================================
    // الكود
    // =========================================================

    final code = data['code']?.toString() ?? '-';

    // =========================================================
    // الوحدة
    // =========================================================

    final unit = data['unit']?.toString() ?? '';

    // =========================================================
    // الكمية التعاقدية
    // =========================================================

    final contractQuantity = formatNumber(
      data['contractQuantity'],
    );

    // =========================================================
    // متابعة التنفيذ
    // =========================================================

    final contractValue = toDouble(data['contractQuantity']);
    final executedValue = toDouble(data['executedQuantity']);

    final remainingValue = (contractValue - executedValue) < 0
        ? 0.0
        : (contractValue - executedValue);

    final progressValue = contractValue <= 0
        ? 0.0
        : (executedValue / contractValue).clamp(0.0, 1.0).toDouble();

    // =========================================================
    // القيم الافتراضية
    // =========================================================

    final defaultWorkingHours =
        detailsData['defaultWorkingHours'];

    final defaultDiesel =
        detailsData['defaultDieselQuantity'];

    final defaultOil =
        detailsData['defaultOilQuantity'];

    // =========================================================
    // القيم الفعلية التي يسجلها المشرف
    // =========================================================

    final consumedFuelQuantity =
        detailsData['consumedFuelQuantity'];

    final executedWorkingHours =
        detailsData['executedWorkingHours'];

    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // =================================================
              // اسم البند
              // =================================================

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                    ),
                    child: Icon(
                      supervisorMode
                          ? Icons.supervisor_account_outlined
                          : Icons.local_shipping,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemName,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        if (typeName.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'النوع: $typeName',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                            ),
                            textDirection: TextDirection.rtl,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          'الكود: $code',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const Divider(height: 25),

              // =================================================
              // الكمية التعاقدية
              // =================================================

              _Info(
                title: 'الكمية التعاقدية',
                value: '$contractQuantity $unit',
                icon: Icons.assignment,
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: _Info(
                      title: 'الكمية المنفذة',
                      value:
                          '${formatNumber(executedValue)} $unit',
                      icon: Icons.done_all,
                    ),
                  ),
                  Expanded(
                    child: _Info(
                      title: 'المتبقي',
                      value:
                          '${formatNumber(remainingValue)} $unit',
                      icon: Icons.pending_actions,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 8,
                  backgroundColor:
                      Colors.blueGrey.shade100,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                'نسبة التنفيذ: '
                '${(progressValue * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
                textDirection: TextDirection.rtl,
              ),

              if ('${detailsData['supervisorName'] ?? detailsData['driverName'] ?? ''}'
                      .isNotEmpty) ...[
                const SizedBox(height: 8),
                _Info(
                  title: assigneeLabel,
                  value:
                      '${detailsData['supervisorName'] ?? detailsData['driverName']}',
                  icon: Icons.person_outline,
                ),
              ],

              const SizedBox(height: 15),

              // =================================================
              // القيم الافتراضية
              // =================================================

              const Text(
                'القيم الافتراضية',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textDirection: TextDirection.rtl,
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _Info(
                      title: 'ساعات العمل',
                      value: defaultWorkingHours == null
                          ? 'غير محدد'
                          : '${formatNumber(defaultWorkingHours)} ساعة',
                      icon: Icons.access_time,
                    ),
                  ),
                  Expanded(
                    child: _Info(
                      title: 'الديزل',
                      value: defaultDiesel == null
                          ? 'غير محدد'
                          : '${formatNumber(defaultDiesel)} لتر',
                      icon: Icons.local_gas_station,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 15),

              _Info(
                title: 'الزيت',
                value: defaultOil == null
                    ? 'غير محدد'
                    : '${formatNumber(defaultOil)} لتر',
                icon: Icons.oil_barrel,
              ),

              const SizedBox(height: 20),

              // =================================================
              // بيانات التنفيذ الفعلية
              // =================================================

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.grey.shade300,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'بيانات التنفيذ الفعلية',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 12),
                    _Info(
                      title: 'ساعات التنفيذ',
                      value: executedWorkingHours == null
                          ? 'لم تدخل بعد'
                          : '${formatNumber(executedWorkingHours)} ساعة',
                      icon: Icons.access_time,
                    ),
                    const SizedBox(height: 12),
                    _Info(
                      title: 'الوقود المستهلك',
                      value: consumedFuelQuantity == null
                          ? 'لم يدخل بعد'
                          : '${formatNumber(consumedFuelQuantity)} لتر',
                      icon: Icons.local_gas_station,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // =================================================
              // زر التفاصيل
              // =================================================

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.visibility),
                  label: Text(
                    supervisorMode
                        ? 'عرض البند وتسجيل الكميات'
                        : 'عرض البند والتفاصيل',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// معلومات
// =============================================================

class _Info extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _Info({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
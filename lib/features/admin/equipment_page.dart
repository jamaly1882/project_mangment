import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// صفحة حصر المعدات لمسؤول النظام.
///
/// ملاحظات:
/// - مشرف البند (أو السائق قديمًا) يتم تهيئته مسبقًا من صفحة المستخدمين.
/// - هذه الصفحة تقوم فقط بربط المعدة بمشرف موجود.
/// - يتم حفظ driverId/driverName مع بيانات المشرف الحالية للعرض السريع.
///
/// Firestore:
/// collection: equipment
/// collection: users
class EquipmentPage extends StatefulWidget {
  const EquipmentPage({super.key});

  @override
  State<EquipmentPage> createState() => _EquipmentPageState();
}

class _EquipmentPageState extends State<EquipmentPage> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final TextEditingController _searchController =
      TextEditingController();

  String _search = '';

  // =========================================================
  // Collections
  // =========================================================

  CollectionReference<Map<String, dynamic>>
      get _equipment =>
          _firestore.collection('equipment');

  CollectionReference<Map<String, dynamic>>
      get _users =>
          _firestore.collection('users');

  // =========================================================
  // Dispose
  // =========================================================

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // =========================================================
  // رسالة
  // =========================================================

  void _showMessage(
    String message, {
    bool error = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            error ? Colors.red : Colors.green,
      ),
    );
  }

  // =========================================================
  // جلب مشرفي البنود (مع حسابات السائقين القديمة)
  // =========================================================

  Stream<QuerySnapshot<Map<String, dynamic>>>
      _driversStream() {
    return _users
        .where(
          'role',
          whereIn: [
            'supervisor',
            'driver',
          ],
        )
        .where(
          'active',
          isEqualTo: true,
        )
        .snapshots();
  }

  // =========================================================
  // صفحة اختيار مشرف المعدة
  // =========================================================

  String _driverDisplayName(
    Map<String, dynamic> data,
  ) {
    final name =
        data['name']?.toString().trim() ?? '';

    final username =
        data['username']?.toString().trim() ?? '';

    final phone =
        data['phone']?.toString().trim() ?? '';

    if (name.isNotEmpty) {
      if (phone.isNotEmpty) {
        return '$name - $phone';
      }

      return name;
    }

    if (username.isNotEmpty) {
      if (phone.isNotEmpty) {
        return '$username - $phone';
      }

      return username;
    }

    if (phone.isNotEmpty) {
      return phone;
    }

    return 'مشرف بدون اسم';
  }

  String _driverName(
    Map<String, dynamic> data,
  ) {
    final name =
        data['name']?.toString().trim() ?? '';

    if (name.isNotEmpty) {
      return name;
    }

    final username =
        data['username']?.toString().trim() ?? '';

    if (username.isNotEmpty) {
      return username;
    }

    return 'مشرف بدون اسم';
  }

  String _driverPhone(
    Map<String, dynamic> data,
  ) {
    return data['phone']?.toString().trim() ?? '';
  }

  // =========================================================
  // فتح محرر المعدة
  // =========================================================

  Future<void> _openEditor({
    DocumentSnapshot<Map<String, dynamic>>?
        document,
  }) async {
    final data =
        document?.data() ?? <String, dynamic>{};

    final formKey =
        GlobalKey<FormState>();

    // =======================================================
    // Controllers
    // =======================================================

    final codeController =
        TextEditingController(
      text: '${data['code'] ?? ''}',
    );

    final nameController =
        TextEditingController(
      text:
          '${data['name'] ?? data['type'] ?? ''}',
    );

    final manufacturerController =
        TextEditingController(
      text: '${data['manufacturer'] ?? ''}',
    );

    final yearController =
        TextEditingController(
      text:
          '${data['modelYear'] ?? data['year'] ?? ''}',
    );

    final workUnitController =
        TextEditingController(
      text: '${data['workUnit'] ?? ''}',
    );

    final meterController =
        TextEditingController(
      text: '${data['currentMeter'] ?? ''}',
    );

    final notesController =
        TextEditingController(
      text: '${data['notes'] ?? ''}',
    );

    // =======================================================
    // القيم
    // =======================================================

    String condition =
        '${data['condition'] ?? 'جيدة'}';

    String status =
        '${data['status'] ?? 'active'}';

    String? selectedDriverId =
        data['driverId']?.toString();

    String? selectedDriverName =
        data['driverName']?.toString();

    String? selectedDriverPhone =
        data['driverPhone']?.toString();

    bool saving = false;

    // =======================================================
    // Dialog
    // =======================================================

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: Text(
                document == null
                    ? 'إضافة معدة إلى الحصر'
                    : 'تعديل بيانات المعدة',
              ),

              content: SizedBox(
                width: 620,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        // =====================================
                        // كود المعدة
                        // =====================================

                        _field(
                          codeController,
                          'كود / الرقم الإداري للمعدة *',
                          required: true,
                        ),

                        // =====================================
                        // نوع المعدة
                        // =====================================

                        _field(
                          nameController,
                          'نوع المعدة *',
                          required: true,
                        ),

                        // =====================================
                        // الشركة المصنعة
                        // =====================================

                        _field(
                          manufacturerController,
                          'الشركة المصنعة',
                        ),

                        // =====================================
                        // سنة الصنع
                        // =====================================

                        _field(
                          yearController,
                          'سنة الصنع',
                          numeric: true,
                        ),

                        // =====================================
                        // وحدة العمل
                        // =====================================

                        _field(
                          workUnitController,
                          'وحدة العمل (ساعة، كم، يوم...) *',
                          required: true,
                        ),

                        // =====================================
                        // قراءة العداد
                        // =====================================

                        _field(
                          meterController,
                          'قراءة العداد الحالية',
                          numeric: true,
                        ),

                        const SizedBox(
                          height: 4,
                        ),

                        // =====================================
                        // مشرف المعدة
                        // =====================================

                        Align(
                          alignment:
                              Alignment.centerRight,
                          child: Text(
                            'مشرف المعدة',
                            style: Theme.of(
                              context,
                            )
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                          ),
                        ),

                        const SizedBox(
                          height: 8,
                        ),

                        StreamBuilder<
                            QuerySnapshot<
                                Map<String,
                                    dynamic>>>(
                          stream:
                              _driversStream(),
                          builder: (
                            context,
                            snapshot,
                          ) {
                            if (snapshot
                                    .connectionState ==
                                ConnectionState
                                    .waiting) {
                              return const InputDecorator(
                                decoration:
                                    InputDecoration(
                                  labelText:
                                      'مشرف المعدة',
                                  border:
                                      OutlineInputBorder(),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth:
                                            2,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 10,
                                    ),
                                    Text(
                                      'جاري تحميل المشرفين...',
                                    ),
                                  ],
                                ),
                              );
                            }

                            if (snapshot.hasError) {
                              return InputDecorator(
                                decoration:
                                    const InputDecoration(
                                  labelText:
                                      'مشرف المعدة',
                                  border:
                                      OutlineInputBorder(),
                                ),
                                child: Text(
                                  'تعذر تحميل المشرفين',
                                  style:
                                      TextStyle(
                                    color:
                                        Colors.red,
                                  ),
                                ),
                              );
                            }

                            final driverDocs =
                                snapshot.data?.docs ??
                                    [];

                            // ---------------------------------
                            // إذا كان المشرف السابق غير نشط
                            // ---------------------------------

                            final hasSelectedDriver =
                                selectedDriverId !=
                                        null &&
                                    driverDocs.any(
                                      (doc) =>
                                          doc.id ==
                                          selectedDriverId,
                                    );

                            if (!hasSelectedDriver &&
                                selectedDriverId !=
                                    null) {
                              return Column(
                                children: [
                                  InputDecorator(
                                    decoration:
                                        const InputDecoration(
                                      labelText:
                                          'المشرف الحالي',
                                      border:
                                          OutlineInputBorder(),
                                    ),
                                    child:
                                        Row(
                                      children: [
                                        const Icon(
                                          Icons
                                              .person_off_outlined,
                                          color:
                                              Colors.orange,
                                        ),
                                        const SizedBox(
                                          width: 8,
                                        ),
                                        Expanded(
                                          child:
                                              Text(
                                            selectedDriverName ??
                                                'مشرف غير متاح حاليًا',
                                          ),
                                        ),
                                        IconButton(
                                          tooltip:
                                              'إزالة المشرف',
                                          onPressed:
                                              saving
                                                  ? null
                                                  : () {
                                                      setDialogState(
                                                        () {
                                                          selectedDriverId =
                                                              null;
                                                          selectedDriverName =
                                                              null;
                                                          selectedDriverPhone =
                                                              null;
                                                        },
                                                      );
                                                    },
                                          icon:
                                              const Icon(
                                            Icons
                                                .clear,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 8,
                                  ),
                                ],
                              );
                            }

                            // ---------------------------------
                            // Dropdown
                            // ---------------------------------

                            return DropdownButtonFormField<
                                String>(
                              // القيمة هنا تُصفَّر برمجيًا بزرّ المسح ✕، فلا
                              // تكفي initialValue وحدها: المفتاح يتغيّر مع
                              // الاختيار فيُعاد تهيئة الحقل، ويختفي اسم
                              // المشرف المحذوف من العرض بدل أن يبقى ظاهرًا.
                              key: ValueKey<String?>(
                                'equipment-driver-$selectedDriverId',
                              ),
                              initialValue: hasSelectedDriver
                                  ? selectedDriverId
                                  : null,
                              isExpanded:
                                  true,
                              decoration:
                                  const InputDecoration(
                                labelText:
                                    'اختر مشرف المعدة',
                                border:
                                    OutlineInputBorder(),
                                prefixIcon:
                                    Icon(
                                  Icons
                                      .person_outline,
                                ),
                              ),
                              hint:
                                  const Text(
                                'اختر مشرفًا مهيأ مسبقًا',
                              ),
                              items:
                                  driverDocs
                                      .map(
                                (
                                  driverDoc,
                                ) {
                                  final driverData =
                                      driverDoc
                                          .data();

                                  return DropdownMenuItem<
                                      String>(
                                    value:
                                        driverDoc
                                            .id,
                                    child:
                                        Text(
                                      _driverDisplayName(
                                        driverData,
                                      ),
                                      overflow:
                                          TextOverflow
                                              .ellipsis,
                                    ),
                                  );
                                },
                              ).toList(),
                              onChanged:
                                  saving
                                      ? null
                                      : (
                                          value,
                                        ) {
                                          if (value ==
                                              null) {
                                            return;
                                          }

                                          final driverDoc =
                                              driverDocs
                                                  .firstWhere(
                                            (
                                              doc,
                                            ) =>
                                                doc.id ==
                                                value,
                                          );

                                          final driverData =
                                              driverDoc
                                                  .data();

                                          setDialogState(
                                            () {
                                              selectedDriverId =
                                                  driverDoc
                                                      .id;

                                              selectedDriverName =
                                                  _driverName(
                                                driverData,
                                              );

                                              selectedDriverPhone =
                                                  _driverPhone(
                                                driverData,
                                              );
                                            },
                                          );
                                        },
                              validator: (
                                value,
                              ) {
                                if (value ==
                                    null ||
                                    value
                                        .trim()
                                        .isEmpty) {
                                  return 'يجب اختيار مشرف المعدة';
                                }

                                return null;
                              },
                            );
                          },
                        ),

                        const SizedBox(
                          height: 12,
                        ),

                        // =====================================
                        // حالة المعدة
                        // =====================================

                        DropdownButtonFormField<
                            String>(
                          initialValue: const [
                            'جيدة',
                            'متوسطة',
                            'تحتاج صيانة',
                            'معطلة',
                          ].contains(
                            condition,
                          )
                              ? condition
                              : 'جيدة',
                          decoration:
                              const InputDecoration(
                            labelText:
                                'حالة المعدة',
                            border:
                                OutlineInputBorder(),
                            prefixIcon:
                                Icon(
                              Icons
                                  .build_circle_outlined,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'جيدة',
                              child:
                                  Text('جيدة'),
                            ),
                            DropdownMenuItem(
                              value: 'متوسطة',
                              child:
                                  Text('متوسطة'),
                            ),
                            DropdownMenuItem(
                              value:
                                  'تحتاج صيانة',
                              child: Text(
                                'تحتاج صيانة',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'معطلة',
                              child:
                                  Text('معطلة'),
                            ),
                          ],
                          onChanged:
                              saving
                                  ? null
                                  : (
                                      value,
                                    ) {
                                      if (value !=
                                          null) {
                                        setDialogState(
                                          () {
                                            condition =
                                                value;
                                          },
                                        );
                                      }
                                    },
                        ),

                        const SizedBox(
                          height: 12,
                        ),

                        // =====================================
                        // حالة التسجيل
                        // =====================================

                        DropdownButtonFormField<
                            String>(
                          initialValue:
                              status ==
                                      'inactive'
                                  ? 'inactive'
                                  : 'active',
                          decoration:
                              const InputDecoration(
                            labelText:
                                'حالة التسجيل',
                            border:
                                OutlineInputBorder(),
                            prefixIcon:
                                Icon(
                              Icons
                                  .toggle_on_outlined,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'active',
                              child:
                                  Text('نشطة'),
                            ),
                            DropdownMenuItem(
                              value:
                                  'inactive',
                              child: Text(
                                'غير نشطة',
                              ),
                            ),
                          ],
                          onChanged:
                              saving
                                  ? null
                                  : (
                                      value,
                                    ) {
                                      if (value !=
                                          null) {
                                        setDialogState(
                                          () {
                                            status =
                                                value;
                                          },
                                        );
                                      }
                                    },
                        ),

                        const SizedBox(
                          height: 12,
                        ),

                        // =====================================
                        // ملاحظات
                        // =====================================

                        _field(
                          notesController,
                          'ملاحظات',
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // =================================================
              // الأزرار
              // =================================================

              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.pop(
                            dialogContext,
                            false,
                          );
                        },
                  child:
                      const Text('إلغاء'),
                ),

                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          // ===================================
                          // التحقق من الحقول
                          // ===================================

                          if (!formKey
                              .currentState!
                              .validate()) {
                            return;
                          }

                          // ===================================
                          // السنة
                          // ===================================

                          final parsedYear =
                              yearController.text
                                      .trim()
                                      .isEmpty
                                  ? null
                                  : int.tryParse(
                                      yearController
                                          .text
                                          .trim(),
                                    );

                          if (yearController
                                  .text
                                  .trim()
                                  .isNotEmpty &&
                              parsedYear ==
                                  null) {
                            _showMessage(
                              'سنة الصنع غير صحيحة',
                              error: true,
                            );

                            return;
                          }

                          // ===================================
                          // العداد
                          // ===================================

                          final meterText =
                              meterController
                                  .text
                                  .trim();

                          final parsedMeter =
                              meterText.isEmpty
                                  ? 0.0
                                  : double.tryParse(
                                      meterText
                                          .replaceAll(
                                        ',',
                                        '.',
                                      ),
                                    );

                          if (parsedMeter ==
                                  null ||
                              parsedMeter < 0) {
                            _showMessage(
                              'قراءة العداد يجب أن تكون رقمًا غير سالب',
                              error: true,
                            );

                            return;
                          }

                          // ===================================
                          // مشرف المعدة
                          // ===================================

                          if (selectedDriverId ==
                                  null ||
                              selectedDriverId!
                                  .trim()
                                  .isEmpty) {
                            _showMessage(
                              'يجب اختيار مشرف للمعدة',
                              error: true,
                            );

                            return;
                          }

                          // ===================================
                          // منع الضغط المتكرر
                          // ===================================

                          setDialogState(
                            () {
                              saving = true;
                            },
                          );

                          try {
                            // =================================
                            // بيانات المعدة
                            // =================================

                            final payload =
                                <String, dynamic>{
                              'code':
                                  codeController
                                      .text
                                      .trim(),

                              'name':
                                  nameController
                                      .text
                                      .trim(),

                              // الاحتفاظ بـ type
                              // للتوافق مع البيانات القديمة
                              'type':
                                  nameController
                                      .text
                                      .trim(),

                              'manufacturer':
                                  manufacturerController
                                      .text
                                      .trim(),

                              'modelYear':
                                  parsedYear,

                              'year':
                                  parsedYear,

                              'workUnit':
                                  workUnitController
                                      .text
                                      .trim(),

                              'currentMeter':
                                  parsedMeter,

                              // =================================
                              // مشرف المعدة
                              // =================================

                              'driverId':
                                  selectedDriverId,

                              'driverName':
                                  selectedDriverName,

                              'driverPhone':
                                  selectedDriverPhone,

                              // =================================
                              // الحالة
                              // =================================

                              'condition':
                                  condition,

                              'status':
                                  status,

                              'notes':
                                  notesController
                                      .text
                                      .trim(),

                              'updatedAt':
                                  FieldValue
                                      .serverTimestamp(),
                            };

                            // ===================================
                            // إضافة
                            // ===================================

                            if (document ==
                                null) {
                              payload[
                                      'createdAt'] =
                                  FieldValue
                                      .serverTimestamp();

                              await _equipment
                                  .add(
                                payload,
                              );
                            }

                            // ===================================
                            // تعديل
                            // ===================================

                            else {
                              await _equipment
                                  .doc(
                                document.id,
                              )
                                  .update(
                                payload,
                              );
                            }

                            // ===================================
                            // إغلاق الحوار
                            // ===================================

                            if (dialogContext
                                .mounted) {
                              Navigator.pop(
                                dialogContext,
                                true,
                              );
                            }
                          } catch (e) {
                            if (!context
                                .mounted) {
                              return;
                            }

                            setDialogState(
                              () {
                                saving =
                                    false;
                              },
                            );

                            _showMessage(
                              'تعذر حفظ المعدة: $e',
                              error: true,
                            );
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons
                              .save_outlined,
                        ),
                  label: Text(
                    saving
                        ? 'جارٍ الحفظ...'
                        : 'حفظ',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    // =========================================================
    // Dispose controllers
    // =========================================================

    codeController.dispose();
    nameController.dispose();
    manufacturerController.dispose();
    yearController.dispose();
    workUnitController.dispose();
    meterController.dispose();
    notesController.dispose();

    // =========================================================
    // رسالة النجاح
    // =========================================================

    if (result == true) {
      _showMessage(
        document == null
            ? 'تمت إضافة المعدة وربطها بالمشرف'
            : 'تم تحديث بيانات المعدة',
      );
    }
  }

  // =========================================================
  // Text Field
  // =========================================================

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool numeric = false,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType ??
            (numeric
                ? const TextInputType
                    .numberWithOptions(
                    decimal: true,
                  )
                : TextInputType.text),
        maxLines: maxLines,
        decoration:
            InputDecoration(
          labelText: label,
          border:
              const OutlineInputBorder(),
        ),
        validator: required
            ? (value) {
                if (value == null ||
                    value
                        .trim()
                        .isEmpty) {
                  return 'هذا الحقل مطلوب';
                }

                return null;
              }
            : null,
      ),
    );
  }

  // =========================================================
  // حذف المعدة
  // =========================================================

  Future<void> _deleteEquipment(
    DocumentSnapshot<Map<String, dynamic>>
        doc,
  ) async {
    final data =
        doc.data() ?? {};

    final name =
        '${data['name'] ?? data['type'] ?? data['code'] ?? 'المعدة'}';

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
              const Text('تأكيد الحذف'),
          content: Text(
            'هل تريد حذف "$name" من حصر المعدات؟',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child:
                  const Text('إلغاء'),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(
                backgroundColor:
                    Colors.red,
              ),
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child:
                  const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _equipment
          .doc(doc.id)
          .delete();

      _showMessage(
        'تم حذف المعدة',
      );
    } catch (e) {
      _showMessage(
        'تعذر حذف المعدة: $e',
        error: true,
      );
    }
  }

  // =========================================================
  // Build
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection:
          TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title:
              const Text('حصر المعدات'),
          centerTitle: true,
        ),

        // =====================================================
        // إضافة معدة
        // =====================================================

        floatingActionButton:
            FloatingActionButton.extended(
          onPressed: () =>
              _openEditor(),
          icon:
              const Icon(Icons.add),
          label:
              const Text('إضافة معدة'),
        ),

        // =====================================================
        // Body
        // =====================================================

        body: Column(
          children: [
            // ===================================================
            // البحث
            // ===================================================

            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                16,
                16,
                16,
                8,
              ),
              child: TextField(
                controller:
                    _searchController,
                decoration:
                    InputDecoration(
                  hintText:
                      'بحث بالكود أو نوع المعدة أو المشرف',
                  prefixIcon:
                      const Icon(
                    Icons.search,
                  ),
                  suffixIcon:
                      _search.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController
                                    .clear();

                                setState(() {
                                  _search =
                                      '';
                                });
                              },
                              icon:
                                  const Icon(
                                Icons.clear,
                              ),
                            ),
                  border:
                      const OutlineInputBorder(),
                ),
                onChanged:
                    (value) {
                  setState(() {
                    _search =
                        value
                            .trim()
                            .toLowerCase();
                  });
                },
              ),
            ),

            // ===================================================
            // القائمة
            // ===================================================

            Expanded(
              child:
                  StreamBuilder<
                      QuerySnapshot<
                          Map<String,
                              dynamic>>>(
                stream:
                    _equipment
                        .snapshots(),
                builder: (
                  context,
                  snapshot,
                ) {
                  // =============================================
                  // Error
                  // =============================================

                  if (snapshot.hasError) {
                    return Center(
                      child:
                          Padding(
                        padding:
                            const EdgeInsets.all(
                          24,
                        ),
                        child:
                            Text(
                          'تعذر تحميل حصر المعدات.\n'
                          'تحقق من الاتصال والصلاحيات.\n\n'
                          '${snapshot.error}',
                          textAlign:
                              TextAlign.center,
                        ),
                      ),
                    );
                  }

                  // =============================================
                  // Loading
                  // =============================================

                  if (snapshot
                          .connectionState ==
                      ConnectionState
                          .waiting) {
                    return const Center(
                      child:
                          CircularProgressIndicator(),
                    );
                  }

                  // =============================================
                  // Documents
                  // =============================================

                  final allDocs =
                      snapshot.data
                              ?.docs ??
                          [];

                  // =============================================
                  // ترتيب محليًا بالكود
                  // =============================================

                  allDocs.sort(
                    (
                      a,
                      b,
                    ) {
                      final aCode =
                          '${a.data()['code'] ?? ''}'
                              .toLowerCase();

                      final bCode =
                          '${b.data()['code'] ?? ''}'
                              .toLowerCase();

                      return aCode.compareTo(
                        bCode,
                      );
                    },
                  );

                  // =============================================
                  // البحث
                  // =============================================

                  final docs =
                      allDocs.where(
                    (
                      doc,
                    ) {
                      final d =
                          doc.data();

                      final text =
                          '${d['code'] ?? ''} '
                          '${d['name'] ?? d['type'] ?? ''} '
                          '${d['driverName'] ?? ''} '
                          '${d['driverPhone'] ?? ''} '
                          '${d['manufacturer'] ?? ''}'
                              .toLowerCase();

                      return text.contains(
                        _search,
                      );
                    },
                  ).toList();

                  // =============================================
                  // لا توجد معدات
                  // =============================================

                  if (docs.isEmpty) {
                    return const Center(
                      child:
                          Padding(
                        padding:
                            EdgeInsets.all(
                          32,
                        ),
                        child:
                            Column(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Icon(
                              Icons
                                  .precision_manufacturing_outlined,
                              size: 56,
                              color:
                                  Colors.grey,
                            ),
                            SizedBox(
                              height: 12,
                            ),
                            Text(
                              'لا توجد معدات في الحصر بعد',
                              style:
                                  TextStyle(
                                fontSize:
                                    18,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                            SizedBox(
                              height: 6,
                            ),
                            Text(
                              'اضغط «إضافة معدة» لإدخال بيانات المعدات الموجودة.',
                              textAlign:
                                  TextAlign
                                      .center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // =============================================
                  // List
                  // =============================================

                  return ListView
                      .builder(
                    padding:
                        const EdgeInsets
                            .fromLTRB(
                      12,
                      4,
                      12,
                      88,
                    ),
                    itemCount:
                        docs.length,
                    itemBuilder:
                        (
                      context,
                      index,
                    ) {
                      final doc =
                          docs[index];

                      final d =
                          doc.data();

                      final code =
                          '${d['code'] ?? 'بدون كود'}';

                      final name =
                          '${d['name'] ?? d['type'] ?? 'معدة بدون اسم'}';

                      final meter =
                          d['currentMeter'];

                      final condition =
                          '${d['condition'] ?? 'غير محددة'}';

                      final driverName =
                          '${d['driverName'] ?? 'غير محدد'}';

                      final driverPhone =
                          '${d['driverPhone'] ?? ''}';

                      final active =
                          d['status'] !=
                              'inactive';

                      // =========================================
                      // بطاقة المعدة
                      // =========================================

                      return Card(
                        margin:
                            const EdgeInsets
                                .symmetric(
                          vertical: 6,
                        ),
                        child:
                            ListTile(
                          leading:
                              CircleAvatar(
                            backgroundColor:
                                active
                                    ? Colors
                                        .blue
                                        .withValues(
                                        alpha:
                                            0.1,
                                      )
                                    : Colors
                                        .grey
                                        .withValues(
                                        alpha:
                                            0.15,
                                      ),
                            child:
                                Icon(
                              Icons
                                  .precision_manufacturing_outlined,
                              color:
                                  active
                                      ? Colors
                                          .blue
                                      : Colors
                                          .grey,
                            ),
                          ),

                          title:
                              Text(
                            '$name — $code',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),

                          subtitle:
                              Padding(
                            padding:
                                const EdgeInsets
                                    .only(
                              top: 6,
                            ),
                            child:
                                Text(
                              'الشركة: ${d['manufacturer'] ?? '—'}\n'
                              'وحدة العمل: ${d['workUnit'] ?? '—'}  |  '
                              'العداد: ${meter ?? '—'}\n'
                              'المشرف: $driverName'
                              '${driverPhone.isEmpty ? '' : ' - $driverPhone'}\n'
                              'الحالة: $condition'
                              '${active ? '' : ' (غير نشطة)'}',
                            ),
                          ),

                          isThreeLine:
                              true,

                          trailing:
                              PopupMenuButton<
                                  String>(
                            onSelected:
                                (
                              value,
                            ) {
                              if (value ==
                                  'edit') {
                                _openEditor(
                                  document:
                                      doc,
                                );
                              }

                              if (value ==
                                  'delete') {
                                _deleteEquipment(
                                  doc,
                                );
                              }
                            },
                            itemBuilder:
                                (_) =>
                                    const [
                              PopupMenuItem(
                                value:
                                    'edit',
                                child:
                                    Text(
                                  'تعديل',
                                ),
                              ),
                              PopupMenuItem(
                                value:
                                    'delete',
                                child:
                                    Text(
                                  'حذف',
                                ),
                              ),
                            ],
                          ),

                          onTap: () =>
                              _openEditor(
                            document:
                                doc,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
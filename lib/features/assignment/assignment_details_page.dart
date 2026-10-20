import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/project_cost_sync.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/costs.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/cost_widgets.dart';

/// صفحة مشرف البند.
///
/// يسجّل المشرف هنا:
/// 1) الاستهلاك الفعلي (وقود/زيت/ساعات عمل).
/// 2) التكاليف الفعلية للبند بأقسامها الأربعة:
///    المواد، أجور العمالة، المعدات، المحروقات.
///
/// ما يدخله المشرف هو «فعلي»، أما ما يدخله مدير المشروع في صفحة
/// تفاصيل البند فهو «مخطط». وبعد الحفظ تُجمَّع تكاليف المشروع تلقائيًا
/// من بنوده (لا تُدخل تكاليف المشروع يدويًا أبدًا).
///
/// لا تعدّل هذه الصفحة كمية تنفيذ البند ولا قراءة العداد.
class AssignmentDetailsPage extends StatefulWidget {
  final String projectId;
  final String itemId;

  const AssignmentDetailsPage({
    super.key,
    required this.projectId,
    required this.itemId,
  });

  @override
  State<AssignmentDetailsPage> createState() =>
      _AssignmentDetailsPageState();
}

class _AssignmentDetailsPageState extends State<AssignmentDetailsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ============================================================
  // حقول الاستهلاك الفعلي
  // ============================================================

  final TextEditingController _fuelController = TextEditingController();
  final TextEditingController _oilController = TextEditingController();
  final TextEditingController _workingHoursController = TextEditingController();

  // ============================================================
  // حقول التكاليف الفعلية (مواد / عمالة / معدات / محروقات)
  // ============================================================

  final Map<String, TextEditingController> _actualUnitControllers =
      <String, TextEditingController>{};

  final Map<String, TextEditingController> _actualTotalControllers =
      <String, TextEditingController>{};

  /// الأقسام التي أدخل المشرف إجماليها يدويًا فلا تُحسب من تكلفة الوحدة.
  final Set<String> _manualActualTotals = <String>{};

  _AssignmentDetailsPageState() {
    for (final category in ProjectCosts.categories) {
      _actualUnitControllers[category.key] = TextEditingController();
      _actualTotalControllers[category.key] = TextEditingController();
    }
  }

  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  Map<String, dynamic>? _itemData;
  Map<String, dynamic>? _detailsData;
  Map<String, dynamic>? _assignmentData;

  double? _defaultWorkingHours;
  double? _defaultFuelQuantity;
  double? _defaultOilQuantity;

  /// مجاميع تكاليف المشروع (محسوبة من بنوده).
  ProjectCostTotals? _projectTotals;

  @override
  void initState() {
    super.initState();
    _loadExecutionData();
  }

  @override
  void dispose() {
    _fuelController.dispose();
    _oilController.dispose();
    _workingHoursController.dispose();

    for (final controller in _actualUnitControllers.values) {
      controller.dispose();
    }

    for (final controller in _actualTotalControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  // ============================================================
  // أدوات قراءة البيانات
  // ============================================================

  String _stringValue(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString().trim();
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return null;
    return double.tryParse(value.toString().trim().replaceAll(',', '.'));
  }

  double? _parseNonNegative(String value) {
    final parsed = _toDouble(value);
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  String _formatNumber(dynamic value) {
    final number = _toDouble(value);
    if (number == null) return 'غير محدد';
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  /// الكمية التي تُحسب منها التكلفة الفعلية:
  /// المنفذة إن وُجدت، وإلا التعاقدية.
  double get _costQuantity {
    final item = _itemData ?? const <String, dynamic>{};

    final executed = ProjectCosts.nonNegative(item['executedQuantity']);
    if (executed > 0) return executed;

    return ProjectCosts.nonNegative(item['contractQuantity']);
  }

  /// التكلفة المخططة للبند (ما أدخله مدير المشروع).
  Map<String, dynamic> get _plannedSource {
    final item = _itemData ?? const <String, dynamic>{};
    final details = _detailsData ?? const <String, dynamic>{};

    // تفاصيل البند هي الأصل، ووثيقة البند نسخة محدّثة.
    return ProjectCosts.totalOf(details) > 0 ? details : item;
  }

  double get _plannedItemTotal =>
      ProjectCosts.totalOf(_plannedSource);

  double get _actualItemTotal =>
      ProjectCosts.actualTotalOf(_detailsData) > 0
          ? ProjectCosts.actualTotalOf(_detailsData)
          : ProjectCosts.actualTotalOf(_itemData);

  bool get _hasActualCostInput {
    for (final category in ProjectCosts.categories) {
      final unit =
          _actualUnitControllers[category.key]?.text.trim() ?? '';
      final total =
          _actualTotalControllers[category.key]?.text.trim() ?? '';

      if (unit.isNotEmpty || total.isNotEmpty) return true;
    }

    return false;
  }

  // ============================================================
  // حساب التكاليف الفعلية أثناء الكتابة
  // ============================================================

  void _onActualUnitChanged(String key) {
    if (_manualActualTotals.contains(key)) return;

    final category = ProjectCosts.categoryByKey(key);
    if (category == null) return;

    final unit = ProjectCosts.parseOptional(
      _actualUnitControllers[key]?.text ?? '',
    );

    if (unit == null) {
      _actualTotalControllers[key]?.clear();
      return;
    }

    final total = _costQuantity > 0
        ? ProjectCosts.nonNegative(unit) * _costQuantity
        : ProjectCosts.nonNegative(unit);

    _actualTotalControllers[key]?.text =
        ProjectCosts.toEditText(total);
  }

  void _onActualTotalChanged(String key) {
    final text =
        _actualTotalControllers[key]?.text.trim() ?? '';

    final unitText =
        _actualUnitControllers[key]?.text.trim() ?? '';

    if (text.isEmpty) {
      _manualActualTotals.remove(key);
      return;
    }

    // إذا طابق الإجمالي المحسوب تلقائيًا نُبقي الحساب التلقائي فعّالًا.
    if (unitText.isNotEmpty) {
      final unit = ProjectCosts.parseOptional(unitText);
      final total = ProjectCosts.parseOptional(text);

      if (unit != null && total != null) {
        final expected = _costQuantity > 0
            ? unit * _costQuantity
            : unit;

        if ((expected - total).abs() < 0.01) {
          _manualActualTotals.remove(key);
          return;
        }
      }
    }

    _manualActualTotals.add(key);
  }

  // ============================================================
  // التكليف: مشرف البند فقط
  // ============================================================

  /// يعيد تكليف المشرف الحالي؛ نتحقق من المستند القياسي أولًا،
  /// ثم ندعم بنودًا أُسندت قديمًا عبر سجلات السائق (لمستخدم حُوّل إلى مشرف).
  Future<Map<String, dynamic>?> _getCurrentAssignment(String uid) async {
    final supervisors = _firestore.collection('item_supervisors');

    final standardDoc = await supervisors.doc(widget.itemId).get();
    if (standardDoc.exists) {
      final data = standardDoc.data() ?? <String, dynamic>{};
      if (data['active'] == true &&
          _stringValue(data['supervisorId']) == uid &&
          _stringValue(data['itemId'], fallback: widget.itemId) ==
              widget.itemId &&
          _stringValue(data['projectId']) == widget.projectId) {
        return data;
      }
    }

    // سجلات سابقة قد تستخدم معرّف مستند مختلفًا.
    final oldAssignments = await supervisors
        .where('itemId', isEqualTo: widget.itemId)
        .get();
    for (final doc in oldAssignments.docs) {
      final data = doc.data();
      if (data['active'] == true &&
          _stringValue(data['supervisorId']) == uid &&
          _stringValue(data['projectId']) == widget.projectId) {
        return data;
      }
    }

    return null;
  }

  /// هل هذا البند مسند إلى حساب المشرف في سجلات السائق القديمة؟
  Future<bool> _hasLegacyAssignment(String uid) async {
    try {
      final legacy = await _firestore
          .collection('item_drivers')
          .where('itemId', isEqualTo: widget.itemId)
          .get();

      for (final doc in legacy.docs) {
        final data = doc.data();
        if (_stringValue(data['driverId']) == uid &&
            _stringValue(data['projectId']) == widget.projectId) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('تعذرت قراءة سجلات التكليف القديمة: $e');
    }

    return false;
  }

  Future<void> _loadExecutionData() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('يجب تسجيل الدخول بحساب مشرف البند أولًا.');
      }

      final userDoc =
          await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? <String, dynamic>{};

      final role = _stringValue(userData['role']);

      if (!userDoc.exists || role != 'supervisor') {
        throw Exception(
          role == 'driver'
              ? 'تم استبدال دور السائق بـ «مشرف بند». اطلب من مسؤول '
                  'النظام تحويل حسابك إلى مشرف بند من صفحة المستخدمين، '
                  'ثم أعد فتح هذه الصفحة.'
              : 'هذا الحساب ليس مشرف بند فعلًا.',
        );
      }

      if (userData['active'] != true) {
        throw Exception('حسابك موقوف؛ راجع مسؤول النظام.');
      }

      var assignment = await _getCurrentAssignment(user.uid);

      final legacyAssignment =
          assignment == null && await _hasLegacyAssignment(user.uid);

      if (assignment == null && !legacyAssignment) {
        throw Exception('هذا البند غير مسند إلى حسابك (أو تم إيقاف التكليف).');
      }

      final itemDoc = await _firestore
          .collection('items')
          .doc(widget.itemId)
          .get();
      if (!itemDoc.exists) {
        throw Exception('البند غير موجود.');
      }
      final item = itemDoc.data() ?? <String, dynamic>{};
      if (_stringValue(item['projectId']) != widget.projectId) {
        throw Exception('هذا البند لا يتبع المشروع المحدد.');
      }

      final detailsDoc = await _firestore
          .collection('item_details')
          .doc(widget.itemId)
          .get();

      final details = detailsDoc.data() ?? <String, dynamic>{};

      if (detailsDoc.exists) {
        if (_stringValue(details['projectId']) != widget.projectId) {
          throw Exception('تفاصيل البند لا تتبع المشروع المحدد.');
        }

        final detailsSupervisor = _stringValue(details['supervisorId']);
        final detailsDriver = _stringValue(details['driverId']);

        if (detailsSupervisor.isNotEmpty &&
            detailsSupervisor != user.uid &&
            detailsDriver != user.uid) {
          throw Exception(
            'مشرف البند المسجل في تفاصيل البند لا يطابق حسابك.',
          );
        }
      }

      _defaultWorkingHours = _toDouble(details['defaultWorkingHours']);
      _defaultFuelQuantity = _toDouble(
        details['defaultFuelQuantity'] ?? details['defaultDieselQuantity'],
      );
      _defaultOilQuantity = _toDouble(details['defaultOilQuantity']);

      // الاستهلاك الفعلي المحفوظ.
      final fuel = _toDouble(details['consumedFuelQuantity']);
      final oil = _toDouble(details['consumedOilQuantity']);
      final hours = _toDouble(details['executedWorkingHours']);

      _fuelController.text = fuel == null ? '' : _formatNumber(fuel);
      _oilController.text = oil == null ? '' : _formatNumber(oil);
      _workingHoursController.text =
          hours == null ? '' : _formatNumber(hours);

      // التكاليف الفعلية المحفوظة (من تفاصيل البند أو وثيقته).
      final costSource =
          ProjectCosts.actualTotalOf(details) > 0 ? details : item;

      for (final category in ProjectCosts.categories) {
        final actualUnit =
            ProjectCosts.nonNegative(costSource[category.actualUnitField]);
        final actualTotal =
            ProjectCosts.nonNegative(costSource[category.actualField]);

        _actualUnitControllers[category.key]!.text =
            actualUnit > 0 ? ProjectCosts.toEditText(actualUnit) : '';

        _actualTotalControllers[category.key]!.text =
            actualTotal > 0 ? ProjectCosts.toEditText(actualTotal) : '';

        if (actualTotal > 0 && actualUnit > 0) {
          final expected = _quantityOf(costSource) > 0
              ? actualUnit * _quantityOf(costSource)
              : actualUnit;

          if ((expected - actualTotal).abs() >= 0.01) {
            _manualActualTotals.add(category.key);
          } else {
            _manualActualTotals.remove(category.key);
          }
        } else if (actualTotal > 0) {
          _manualActualTotals.add(category.key);
        } else {
          _manualActualTotals.remove(category.key);
        }
      }

      ProjectCostTotals? totals;
      try {
        totals = await ProjectCostSync.totalsFor(widget.projectId);
      } catch (e) {
        debugPrint('تعذر حساب تكاليف المشروع: $e');
      }

      if (!mounted) return;
      setState(() {
        _itemData = item;
        _detailsData = detailsDoc.exists
            ? details
            : null;
        _assignmentData = assignment;
        _projectTotals = totals;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  static double _quantityOf(Map<String, dynamic> data) {
    final executed = ProjectCosts.nonNegative(data['executedQuantity']);
    if (executed > 0) return executed;
    return ProjectCosts.nonNegative(data['contractQuantity']);
  }

  // ============================================================
  // الحفظ: الاستهلاك + التكاليف الفعلية
  // ============================================================

  Future<void> _saveExecutionData() async {
    if (_saving) return;

    final fuelText = _fuelController.text.trim();
    final oilText = _oilController.text.trim();
    final hoursText = _workingHoursController.text.trim();

    if (fuelText.isEmpty || oilText.isEmpty || hoursText.isEmpty) {
      AppWidgets.showWarning(
        context,
        'يرجى إدخال كمية الوقود والزيت وساعات العمل الفعلية.',
      );
      return;
    }

    final fuel = _parseNonNegative(fuelText);
    final oil = _parseNonNegative(oilText);
    final hours = _parseNonNegative(hoursText);
    if (fuel == null || oil == null || hours == null) {
      AppWidgets.showWarning(context, 'أدخل كميات صحيحة غير سالبة.');
      return;
    }

    // التحقق من أرقام التكاليف إن أدخل المشرف شيئًا منها.
    for (final category in ProjectCosts.categories) {
      final unitText =
          _actualUnitControllers[category.key]?.text.trim() ?? '';
      final totalText =
          _actualTotalControllers[category.key]?.text.trim() ?? '';

      if (unitText.isNotEmpty && _parseNonNegative(unitText) == null) {
        AppWidgets.showWarning(
          context,
          'أدخل تكلفة ${category.shortLabel} الفعلية للوحدة رقمًا صحيحًا.',
        );
        return;
      }

      if (totalText.isNotEmpty && _parseNonNegative(totalText) == null) {
        AppWidgets.showWarning(
          context,
          'أدخل إجمالي ${category.shortLabel} الفعلي رقمًا صحيحًا.',
        );
        return;
      }
    }

    final user = _auth.currentUser;
    if (user == null) {
      AppWidgets.showError(context, 'انتهت جلسة تسجيل الدخول؛ سجل الدخول مجددًا.');
      return;
    }

    setState(() => _saving = true);

    try {
      // إعادة فحص التكليف قبل الحفظ حتى لا يستمر المستخدم بعد تغيير الإسناد.
      final assignment = await _getCurrentAssignment(user.uid);
      if (assignment == null && !await _hasLegacyAssignment(user.uid)) {
        throw Exception(
          'لم يعد هذا البند مسندًا إلى حسابك. حدّث الصفحة أو راجع مدير المشروع.',
        );
      }

      final itemDoc = await _firestore
          .collection('items')
          .doc(widget.itemId)
          .get();
      if (!itemDoc.exists ||
          _stringValue(itemDoc.data()?['projectId']) != widget.projectId) {
        throw Exception('تعذر التحقق من البند أو المشروع.');
      }

      final detailsRef =
          _firestore.collection('item_details').doc(widget.itemId);
      final detailsDoc = await detailsRef.get();
      final currentDetails = detailsDoc.data() ?? <String, dynamic>{};

      if (detailsDoc.exists) {
        final assigned = _stringValue(currentDetails['supervisorId']);
        final legacyAssigned = _stringValue(currentDetails['driverId']);

        if (assigned.isNotEmpty &&
            assigned != user.uid &&
            legacyAssigned != user.uid) {
          throw Exception('تفاصيل البند لم تعد مسندة إلى حسابك.');
        }
      }

      final fuelExceeded =
          _defaultFuelQuantity != null && fuel > _defaultFuelQuantity!;
      final oilExceeded =
          _defaultOilQuantity != null && oil > _defaultOilQuantity!;
      final hoursExceeded =
          _defaultWorkingHours != null && hours > _defaultWorkingHours!;
      final exceedsPlan = fuelExceeded || oilExceeded || hoursExceeded;

      // الاستهلاك الفعلي لا يُرفض إذا تجاوز المخطط؛ يُحفظ ويُعلَّم للمراجعة.
      final detailsUpdate = <String, dynamic>{
        'consumedFuelQuantity': fuel,
        'consumedOilQuantity': oil,
        'executedWorkingHours': hours,
        'fuelExceededPlanned': fuelExceeded,
        'oilExceededPlanned': oilExceeded,
        'workingHoursExceededPlanned': hoursExceeded,
        'consumptionReviewStatus':
            exceedsPlan ? 'pending_review' : 'within_plan',
        'consumptionUpdatedBy': user.uid,
        'consumptionUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final itemUpdate = <String, dynamic>{
        'consumedFuelQuantity': fuel,
        'consumedOilQuantity': oil,
        'executedWorkingHours': hours,
        'consumptionReviewStatus':
            exceedsPlan ? 'pending_review' : 'within_plan',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // التكاليف الفعلية للبند.
      Map<String, dynamic> actualData = const <String, dynamic>{};

      if (_hasActualCostInput) {
        actualData = ProjectCosts.buildActualSaveData(
          totalTexts: {
            for (final entry in _actualTotalControllers.entries)
              entry.key: entry.value.text,
          },
          unitTexts: {
            for (final entry in _actualUnitControllers.entries)
              entry.key: entry.value.text,
          },
          quantity: _costQuantity,
          includeZeros: true,
        );

        detailsUpdate.addAll(actualData);
        itemUpdate.addAll(actualData);

        detailsUpdate[ProjectCosts.actualByField] = user.uid;
        detailsUpdate[ProjectCosts.actualAtField] =
            FieldValue.serverTimestamp();

        itemUpdate[ProjectCosts.actualByField] = user.uid;
        itemUpdate[ProjectCosts.actualAtField] =
            FieldValue.serverTimestamp();
      }

      final batch = _firestore.batch();

      batch.set(detailsRef, detailsUpdate, SetOptions(merge: true));

      batch.set(
        _firestore.collection('items').doc(widget.itemId),
        itemUpdate,
        SetOptions(merge: true),
      );

      await batch.commit();

      // تكاليف المشروع = مجموع بنوده.
      ProjectCostTotals? projectTotals;
      try {
        projectTotals =
            await ProjectCostSync.applyTotals(widget.projectId);

        if (mounted) {
          setState(() => _projectTotals = projectTotals);
        }
      } catch (e) {
        debugPrint('تعذرت مزامنة تكاليف المشروع: $e');
      }

      if (!mounted) return;

      setState(() {
        _detailsData = <String, dynamic>{
          ...currentDetails,
          ...detailsUpdate,
        };
      });

      final actualTotal =
          ProjectCosts.toDouble(actualData[ProjectCosts.actualTotalField]);

      final successMessage = <String>[
        'تم حفظ الاستهلاك الفعلي بنجاح.',
        if (actualTotal > 0)
          'تكلفة البند الفعلية: '
              '${ProjectCosts.formatMoney(actualTotal)}',
        if (projectTotals != null)
          'إجمالي تكلفة المشروع: '
              '${ProjectCosts.formatMoney(projectTotals.displayTotal)}',
      ].join('\n');

      if (exceedsPlan) {
        AppWidgets.showWarning(
          context,
          'تم الحفظ، لكن الاستهلاك تجاوز كمية مخططة واحدة أو أكثر '
          'ويحتاج إلى مراجعة.\n$successMessage',
        );
      } else {
        AppWidgets.showSuccess(context, successMessage);
      }
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showError(context, 'تعذر حفظ بيانات الاستهلاك:\n$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ============================================================
  // العرض
  // ============================================================

  String _itemName(Map<String, dynamic> item) {
    final name = _stringValue(item['name']);
    if (name.isNotEmpty) return name;
    final definition = _stringValue(item['itemDefinitionName']);
    if (definition.isNotEmpty) return definition;
    return _stringValue(item['typeName'], fallback: 'بدون اسم');
  }

  String _assigneeName(Map<String, dynamic> details) {
    final name = _stringValue(details['supervisorName']);
    if (name.isNotEmpty) return name;
    return _stringValue(details['driverName'], fallback: 'غير محدد');
  }

  Widget _buildItemCard() {
    final item = _itemData ?? <String, dynamic>{};
    final details = _detailsData ?? <String, dynamic>{};
    final unit = _stringValue(item['unit'], fallback: '');
    final quantity = _toDouble(item['contractQuantity']);
    final executed = _toDouble(item['executedQuantity']);
    final remaining = quantity == null || executed == null
        ? null
        : (quantity - executed).clamp(0, double.infinity).toDouble();
    final equipmentName =
        _stringValue(details['equipmentName'], fallback: 'غير محددة');
    final equipmentCode = _stringValue(details['equipmentCode'], fallback: '—');
    final equipmentWorkUnit =
        _stringValue(details['equipmentWorkUnit'], fallback: 'غير محددة');
    final meter =
        _toDouble(details['equipmentCurrentMeterAtAssignment']);

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(
            title: _itemName(item),
            subtitle: 'بيانات البند والاستهلاك الفعلي والتكاليف الفعلية',
            icon: Icons.supervisor_account_outlined,
          ),
          AppSpacing.verticalMd,
          AppInfoRow(
            label: 'مشرف البند',
            value: _assigneeName(details),
            icon: Icons.person_outline,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'حالة التكليف',
            value: _assignmentData?['active'] == true
                ? 'نشط'
                : 'نشط من سجل قديم',
            icon: Icons.person_outline,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'نوع البند',
            value: _stringValue(item['typeName'], fallback: 'غير محدد'),
            icon: Icons.category_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'المشروع',
            value: _stringValue(
              item['projectName'],
              fallback: widget.projectId,
            ),
            icon: Icons.business_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'الكمية التعاقدية',
            value: quantity == null
                ? 'غير محددة'
                : '${_formatNumber(quantity)} $unit',
            icon: Icons.assignment_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'كمية تنفيذ المهندس المسجلة',
            value: executed == null
                ? 'لم يسجل بعد'
                : '${_formatNumber(executed)} $unit',
            icon: Icons.engineering_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'المتبقي من الكمية التعاقدية',
            value: remaining == null
                ? 'غير محدد'
                : '${_formatNumber(remaining)} $unit',
            icon: Icons.pending_actions_outlined,
          ),
          const Divider(height: 28),
          const AppSectionTitle(
            title: 'المعدة المسندة',
            icon: Icons.precision_manufacturing_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'اسم المعدة',
            value: equipmentName,
            icon: Icons.construction_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'كود المعدة',
            value: equipmentCode,
            icon: Icons.tag_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'وحدة عمل المعدة',
            value: equipmentWorkUnit,
            icon: Icons.speed_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'قراءة العداد وقت الإسناد',
            value: meter == null ? 'غير مسجلة' : _formatNumber(meter),
            icon: Icons.speed_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildLimitsCard() {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'الكميات المخططة للتكليف',
            icon: Icons.rule_outlined,
          ),
          AppSpacing.verticalMd,
          AppInfoRow(
            label: 'الوقود المخطط',
            value: _defaultFuelQuantity == null
                ? 'غير محدد'
                : '${_formatNumber(_defaultFuelQuantity)} لتر',
            icon: Icons.local_gas_station_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'الزيت المخطط',
            value: _defaultOilQuantity == null
                ? 'غير محدد'
                : '${_formatNumber(_defaultOilQuantity)} لتر',
            icon: Icons.oil_barrel_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'ساعات العمل المخططة',
            value: _defaultWorkingHours == null
                ? 'غير محددة'
                : '${_formatNumber(_defaultWorkingHours)} ساعة',
            icon: Icons.schedule_outlined,
          ),
          AppSpacing.verticalMd,
          const Text(
            'إذا تجاوز الاستهلاك الفعلي المخطط فسيتم حفظه مع علامة للمراجعة، '
            'ولن تُغيّر هذه الصفحة كمية التنفيذ أو قراءة العداد.',
            style: AppTextStyles.bodySecondary,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // التكاليف الفعلية للبند + تكاليف المشروع
  // ============================================================

  Widget _buildCostsCard() {
    final planned = ProjectCosts.breakdownOf(_plannedSource);
    final unit = _stringValue(_itemData?['unit'], fallback: '');

    final rows = <Widget>[];

    for (final category in ProjectCosts.categories) {
      if (rows.isNotEmpty) rows.add(AppSpacing.verticalMd);

      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppNumberField(
                controller: _actualUnitControllers[category.key],
                label:
                    'تكلفة ${category.shortLabel} للوحدة (فعلي)',
                hint: 'للوحدة ال$unit',
                suffixText: ProjectCosts.currency,
                prefixIcon: category.icon,
                onChanged: (_) => _onActualUnitChanged(category.key),
              ),
            ),
            AppSpacing.horizontalMd,
            Expanded(
              child: AppNumberField(
                controller: _actualTotalControllers[category.key],
                label: 'إجمالي ${category.shortLabel} (فعلي)',
                hint: 'محسوب تلقائيًا',
                suffixText: ProjectCosts.currency,
                prefixIcon: Icons.calculate_outlined,
                onChanged: (_) => _onActualTotalChanged(category.key),
              ),
            ),
          ],
        ),
      );
    }

    final plannedTotal = _plannedItemTotal;
    final actualTotal = _actualItemTotal;
    final difference = actualTotal - plannedTotal;

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'تكاليف البند الفعلية',
            subtitle:
                'المواد وأجور العمالة والمعدات والمحروقات. '
                'أدخل تكلفة الوحدة ليُحسب الإجمالي تلقائيًا على '
                'كمية التنفيذ، أو أدخل الإجمالي مباشرة.',
            icon: Icons.account_balance_wallet_outlined,
          ),
          AppSpacing.verticalSm,
          Text(
            'الكمية المحسوب عليها الإجمالي: '
            '${_formatNumber(_costQuantity)} $unit'
            ' — والمخطط لهذا البند من مدير المشروع: '
            '${ProjectCosts.formatMoney(plannedTotal)}',
            style: AppTextStyles.bodySecondary,
          ),
          AppSpacing.verticalMd,
          ...rows,
          AppSpacing.verticalMd,
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.supervisor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppInfoRow(
                  label: 'إجمالي تكلفتك الفعلية لهذا البند',
                  value: ProjectCosts.formatMoney(actualTotal),
                  icon: Icons.payments_outlined,
                ),
                AppSpacing.verticalXs,
                AppInfoRow(
                  label: 'المخطط للبند (إدخال مدير المشروع)',
                  value: ProjectCosts.formatMoney(plannedTotal),
                  icon: Icons.timeline_outlined,
                ),
                if (actualTotal > 0 && plannedTotal > 0) ...[
                  AppSpacing.verticalXs,
                  AppInfoRow(
                    label: difference >= 0
                        ? 'زيادة عن المخطط'
                        : 'أقل من المخطط',
                    value: ProjectCosts.formatMoney(
                      difference.abs(),
                    ),
                    icon: difference > 0
                        ? Icons.trending_up_outlined
                        : Icons.trending_down_outlined,
                  ),
                  if (plannedTotal > 0) ...[
                    AppSpacing.verticalXs,
                    AppProgress(
                      value: (actualTotal / plannedTotal)
                          .clamp(0.0, 1.0)
                          .toDouble(),
                      label: 'الفعلي مقابل المخطط',
                      height: 8,
                    ),
                  ],
                ],
              ],
            ),
          ),
          AppSpacing.verticalMd,
          CostSummaryCard(
            title: 'أقسام التكلفة: الفعلي مقابل المخطط',
            breakdown: ProjectCosts.actualBreakdownOf(
              _detailsData ?? _itemData,
            ),
            reference: planned,
            referenceLabel: 'المخطط',
            total: actualTotal,
            icon: Icons.swap_horiz,
          ),
          AppSpacing.verticalMd,
          _buildProjectCostsCard(),
        ],
      ),
    );
  }

  Widget _buildProjectCostsCard() {
    final totals = _projectTotals;

    if (totals == null) {
      return const AppLoading(message: 'جاري حساب تكاليف المشروع...');
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'تكاليف المشروع بعد حفظك',
            subtitle:
                'مجموع تكاليف كل بنود المشروع، تُحسب تلقائيًا.',
            icon: Icons.business_outlined,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'المخطط للمشروع',
            value: ProjectCosts.formatMoney(totals.total),
            icon: Icons.timeline_outlined,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'الفعلي المسجل في البنود',
            value: ProjectCosts.formatMoney(totals.actualTotal),
            icon: Icons.check_circle_outline,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'إجمالي تكلفة المشروع المعتمد',
            value: ProjectCosts.formatMoney(totals.displayTotal),
            icon: Icons.payments_outlined,
          ),
          AppSpacing.verticalSm,
          Text(
            'عدد بنود المشروع: ${totals.itemCount}، '
            'ولـ ${totals.costedItemCount} بند تكلفة مخططة، '
            'ولـ ${totals.actualItemCount} بند تكلفة فعلية. '
            'تُجمَّع هذه الأرقام تلقائيًا من البنود ولا تُدخل يدويًا.',
            style: AppTextStyles.small,
          ),
        ],
      ),
    );
  }

  Widget _buildActualForm() {
    final details = _detailsData ?? <String, dynamic>{};
    final exceedsPlan = details['fuelExceededPlanned'] == true ||
        details['oilExceededPlanned'] == true ||
        details['workingHoursExceededPlanned'] == true;

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionTitle(
            title: 'الاستهلاك الفعلي',
            icon: Icons.edit_note_outlined,
          ),
          AppSpacing.verticalMd,
          if (exceedsPlan) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.35),
                ),
              ),
              child: const Text(
                'هناك قيمة تجاوزت المخطط السابق. تم حفظها للتوثيق '
                'وهي بحاجة إلى مراجعة.',
                style: AppTextStyles.bodySecondary,
              ),
            ),
            AppSpacing.verticalMd,
          ],
          AppNumberField(
            controller: _fuelController,
            label: 'كمية الوقود المستهلكة فعليًا *',
            hint: 'أدخل إجمالي كمية الوقود المستهلكة',
            suffixText: 'لتر',
            prefixIcon: Icons.local_gas_station_outlined,
          ),
          AppSpacing.verticalMd,
          AppNumberField(
            controller: _oilController,
            label: 'كمية الزيت المستهلكة فعليًا *',
            hint: 'أدخل إجمالي كمية الزيت المستهلكة',
            suffixText: 'لتر',
            prefixIcon: Icons.oil_barrel_outlined,
          ),
          AppSpacing.verticalMd,
          AppNumberField(
            controller: _workingHoursController,
            label: 'ساعات العمل الفعلية *',
            hint: 'أدخل إجمالي ساعات العمل',
            suffixText: 'ساعة',
            prefixIcon: Icons.access_time_outlined,
          ),
          AppSpacing.verticalMd,
          const Text(
            'تُحفظ هذه القيم كإجماليات حالية لهذا التكليف. لا تُدخل قراءة '
            'العداد هنا؛ قراءة العداد لها شاشة مستقلة.',
            style: AppTextStyles.bodySecondary,
          ),
          AppSpacing.verticalLg,
          AppButton(
            label: _saving
                ? 'جارٍ الحفظ...'
                : 'حفظ الاستهلاك والتكاليف الفعلية',
            icon: Icons.save_outlined,
            loading: _saving,
            expanded: true,
            onPressed: _saving ? null : _saveExecutionData,
          ),
          AppSpacing.verticalSm,
          const Text(
            'بعد الحفظ تُحدَّث تكاليف المشروع تلقائيًا من بنوده.',
            style: AppTextStyles.small,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'متابعة البند وتسجيل التكاليف',
      showBackButton: true,
      child: _loading
          ? const AppLoading(
              message: 'جارٍ التحقق من التكليف وتحميل التفاصيل...',
            )
          : _errorMessage != null
              ? AppPage(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            size: 56,
                            color: AppColors.warning,
                          ),
                          AppSpacing.verticalMd,
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.body,
                          ),
                          AppSpacing.verticalLg,
                          AppButton(
                            label: 'إعادة المحاولة',
                            icon: Icons.refresh,
                            expanded: true,
                            onPressed: _loadExecutionData,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : AppPage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildItemCard(),
                      AppSpacing.verticalMd,
                      _buildCostsCard(),
                      AppSpacing.verticalMd,
                      _buildLimitsCard(),
                      AppSpacing.verticalMd,
                      _buildActualForm(),
                      AppSpacing.verticalXl,
                    ],
                  ),
                ),
    );
  }
}

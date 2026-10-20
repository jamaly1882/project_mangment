import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

/// تفاصيل تكليف مشرف البند (أو السائق في السجل القديم).
/// لا تعدّل هذه الصفحة كمية تنفيذ البند أو قراءة العداد؛ تسجل الاستهلاك الفعلي فقط.
class AssignmentDetailsPage extends StatefulWidget {
  final String projectId;
  final String itemId;

  /// true => مشرف البند، false => سجل السائق القديم.
  final bool supervisorMode;

  const AssignmentDetailsPage({
    super.key,
    required this.projectId,
    required this.itemId,
    this.supervisorMode = true,
  });

  @override
  State<AssignmentDetailsPage> createState() =>
      _AssignmentDetailsPageState();
}

class _AssignmentDetailsPageState extends State<AssignmentDetailsPage> {
  // ============================================================
  // نصوص وحقول حسب الوضع
  // ============================================================

  String get _assigneeLabel => widget.supervisorMode ? 'المشرف' : 'السائق';

  String get _collectionName =>
      widget.supervisorMode ? 'item_supervisors' : 'item_drivers';

  String get _idField =>
      widget.supervisorMode ? 'supervisorId' : 'driverId';

  String get _roleValue =>
      widget.supervisorMode ? 'supervisor' : 'driver';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _fuelController = TextEditingController();
  final TextEditingController _oilController = TextEditingController();
  final TextEditingController _workingHoursController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  Map<String, dynamic>? _itemData;
  Map<String, dynamic>? _detailsData;
  Map<String, dynamic>? _assignmentData;

  double? _defaultWorkingHours;
  double? _defaultFuelQuantity;
  double? _defaultOilQuantity;

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
    super.dispose();
  }

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
    return number.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  /// يعيد تكليف المستخدم الحالي؛ نتحقق من المستند القياسي أولًا ثم ندعم السجلات القديمة.
  Future<Map<String, dynamic>?> _getCurrentAssignment(String uid) async {
    final assignments = _firestore.collection(_collectionName);
    final standardDoc = await assignments.doc(widget.itemId).get();
    if (standardDoc.exists) {
      final data = standardDoc.data() ?? <String, dynamic>{};
      if (data['active'] == true &&
          _stringValue(data[_idField]) == uid &&
          _stringValue(data['itemId'], fallback: widget.itemId) == widget.itemId &&
          _stringValue(data['projectId']) == widget.projectId) {
        return data;
      }
    }

    // التوافق مع سجلات سابقة قد تستخدم معرّف مستند مختلفًا.
    final oldAssignments = await assignments
        .where('itemId', isEqualTo: widget.itemId)
        .get();
    for (final doc in oldAssignments.docs) {
      final data = doc.data();
      if (data['active'] == true &&
          _stringValue(data[_idField]) == uid &&
          _stringValue(data['projectId']) == widget.projectId) {
        return data;
      }
    }
    return null;
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
        throw Exception('يجب تسجيل الدخول بحساب $_assigneeLabel أولًا.');
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      if (!userDoc.exists ||
          _stringValue(userData['role']) != _roleValue ||
          userData['active'] != true) {
        throw Exception('هذا الحساب ليس $_assigneeLabel فعالًا.');
      }

      final assignment = await _getCurrentAssignment(user.uid);
      if (assignment == null) {
        throw Exception('هذا التكليف غير مسند إلى حسابك أو تم إيقافه.');
      }

      final itemDoc = await _firestore.collection('items').doc(widget.itemId).get();
      if (!itemDoc.exists) {
        throw Exception('البند غير موجود.');
      }
      final item = itemDoc.data() ?? <String, dynamic>{};
      if (_stringValue(item['projectId']) != widget.projectId) {
        throw Exception('هذا البند لا يتبع المشروع المحدد.');
      }

      final detailsDoc = await _firestore.collection('item_details').doc(widget.itemId).get();
      if (!detailsDoc.exists) {
        throw Exception('لم يحفظ مدير المشروع تفاصيل هذا البند بعد.');
      }
      final details = detailsDoc.data() ?? <String, dynamic>{};
      if (_stringValue(details['projectId']) != widget.projectId) {
        throw Exception('تفاصيل البند لا تتبع المشروع المحدد.');
      }
      if (_stringValue(details[_idField]) != user.uid) {
        throw Exception('$_assigneeLabel المسجل في تفاصيل البند لا يطابق حسابك.');
      }

      final defaultHours = _toDouble(details['defaultWorkingHours']);
      final defaultFuel = _toDouble(
        details['defaultFuelQuantity'] ?? details['defaultDieselQuantity'],
      );
      final defaultOil = _toDouble(details['defaultOilQuantity']);

      final fuel = _toDouble(details['consumedFuelQuantity']);
      final oil = _toDouble(details['consumedOilQuantity']);
      final hours = _toDouble(details['executedWorkingHours']);

      _fuelController.text = fuel == null ? '' : _formatNumber(fuel);
      _oilController.text = oil == null ? '' : _formatNumber(oil);
      _workingHoursController.text = hours == null ? '' : _formatNumber(hours);

      if (!mounted) return;
      setState(() {
        _itemData = item;
        _detailsData = details;
        _assignmentData = assignment;
        _defaultWorkingHours = defaultHours;
        _defaultFuelQuantity = defaultFuel;
        _defaultOilQuantity = defaultOil;
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

  Future<void> _saveExecutionData() async {
    if (_saving) return;

    final fuelText = _fuelController.text.trim();
    final oilText = _oilController.text.trim();
    final hoursText = _workingHoursController.text.trim();

    if (fuelText.isEmpty || oilText.isEmpty || hoursText.isEmpty) {
      AppWidgets.showWarning(context, 'يرجى إدخال كمية الوقود والزيت وساعات العمل الفعلية.');
      return;
    }

    final fuel = _parseNonNegative(fuelText);
    final oil = _parseNonNegative(oilText);
    final hours = _parseNonNegative(hoursText);
    if (fuel == null || oil == null || hours == null) {
      AppWidgets.showWarning(context, 'أدخل كميات صحيحة غير سالبة.');
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      AppWidgets.showError(context, 'انتهت جلسة تسجيل الدخول؛ سجل الدخول مجددًا.');
      return;
    }

    setState(() => _saving = true);
    try {
      // إعادة فحص التكليف قبل الحفظ حتى لا يستمر المستخدم بعد تغيير إسناد البند.
      final assignment = await _getCurrentAssignment(user.uid);
      if (assignment == null) {
        throw Exception('لم يعد هذا التكليف مسندًا إلى حسابك. حدّث الصفحة أو راجع مدير المشروع.');
      }

      final itemDoc = await _firestore.collection('items').doc(widget.itemId).get();
      if (!itemDoc.exists ||
          _stringValue(itemDoc.data()?['projectId']) != widget.projectId) {
        throw Exception('تعذر التحقق من البند أو المشروع.');
      }

      final detailsRef = _firestore.collection('item_details').doc(widget.itemId);
      final detailsDoc = await detailsRef.get();
      final currentDetails = detailsDoc.data() ?? <String, dynamic>{};
      if (!detailsDoc.exists ||
          _stringValue(currentDetails[_idField]) != user.uid) {
        throw Exception('تفاصيل البند لم تعد مسندة إلى حسابك.');
      }

      final fuelExceeded = _defaultFuelQuantity != null && fuel > _defaultFuelQuantity!;
      final oilExceeded = _defaultOilQuantity != null && oil > _defaultOilQuantity!;
      final hoursExceeded = _defaultWorkingHours != null && hours > _defaultWorkingHours!;
      final exceedsPlan = fuelExceeded || oilExceeded || hoursExceeded;

      // الاستهلاك الفعلي لا يُرفض إذا تجاوز المخطط؛ يحفظ ويُعلّم للمراجعة.
      // لا نغيّر executedQuantity ولا أي قراءة عداد في هذا الحفظ.
      await detailsRef.set(
        <String, dynamic>{
          'consumedFuelQuantity': fuel,
          'consumedOilQuantity': oil,
          'executedWorkingHours': hours,
          'fuelExceededPlanned': fuelExceeded,
          'oilExceededPlanned': oilExceeded,
          'workingHoursExceededPlanned': hoursExceeded,
          'consumptionReviewStatus': exceedsPlan ? 'pending_review' : 'within_plan',
          'consumptionUpdatedBy': user.uid,
          'consumptionUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      setState(() {
        _detailsData = <String, dynamic>{
          ...currentDetails,
          'consumedFuelQuantity': fuel,
          'consumedOilQuantity': oil,
          'executedWorkingHours': hours,
          'fuelExceededPlanned': fuelExceeded,
          'oilExceededPlanned': oilExceeded,
          'workingHoursExceededPlanned': hoursExceeded,
          'consumptionReviewStatus': exceedsPlan ? 'pending_review' : 'within_plan',
        };
      });

      if (exceedsPlan) {
        AppWidgets.showWarning(
          context,
          'تم حفظ الاستهلاك الفعلي، لكنه تجاوز كمية مخططة واحدة أو أكثر ويحتاج إلى مراجعة.',
        );
      } else {
        AppWidgets.showSuccess(context, 'تم حفظ الاستهلاك الفعلي بنجاح.');
      }
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showError(context, 'تعذر حفظ بيانات الاستهلاك:\n$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
    final equipmentName = _stringValue(details['equipmentName'], fallback: 'غير محددة');
    final equipmentCode = _stringValue(details['equipmentCode'], fallback: '—');
    final equipmentWorkUnit = _stringValue(details['equipmentWorkUnit'], fallback: 'غير محددة');
    final meter = _toDouble(details['equipmentCurrentMeterAtAssignment']);

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(
            title: _itemName(item),
            subtitle: 'تفاصيل التكليف والاستهلاك الفعلي',
            icon: widget.supervisorMode
                ? Icons.supervisor_account_outlined
                : Icons.local_shipping_outlined,
          ),
          AppSpacing.verticalMd,
          AppInfoRow(
            label: _assigneeLabel,
            value: _assigneeName(details),
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
            value: _stringValue(item['projectName'], fallback: widget.projectId),
            icon: Icons.business_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'الكمية التعاقدية',
            value: quantity == null ? 'غير محددة' : '${_formatNumber(quantity)} $unit',
            icon: Icons.assignment_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'كمية تنفيذ المهندس المسجلة',
            value: executed == null ? 'لم يسجل بعد' : '${_formatNumber(executed)} $unit',
            icon: Icons.engineering_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'المتبقي من الكمية التعاقدية',
            value: remaining == null ? 'غير محدد' : '${_formatNumber(remaining)} $unit',
            icon: Icons.pending_actions_outlined,
          ),
          const Divider(height: 28),
          AppSectionTitle(title: 'المعدة المسندة', icon: Icons.precision_manufacturing_outlined),
          AppSpacing.verticalSm,
          AppInfoRow(label: 'اسم المعدة', value: equipmentName, icon: Icons.construction_outlined),
          AppSpacing.verticalSm,
          AppInfoRow(label: 'كود المعدة', value: equipmentCode, icon: Icons.tag_outlined),
          AppSpacing.verticalSm,
          AppInfoRow(label: 'وحدة عمل المعدة', value: equipmentWorkUnit, icon: Icons.speed_outlined),
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
          const AppSectionTitle(title: 'الكميات المخططة للتكليف', icon: Icons.rule_outlined),
          AppSpacing.verticalMd,
          AppInfoRow(
            label: 'الوقود المخطط',
            value: _defaultFuelQuantity == null ? 'غير محدد' : '${_formatNumber(_defaultFuelQuantity)} لتر',
            icon: Icons.local_gas_station_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'الزيت المخطط',
            value: _defaultOilQuantity == null ? 'غير محدد' : '${_formatNumber(_defaultOilQuantity)} لتر',
            icon: Icons.oil_barrel_outlined,
          ),
          AppSpacing.verticalSm,
          AppInfoRow(
            label: 'ساعات العمل المخططة',
            value: _defaultWorkingHours == null ? 'غير محددة' : '${_formatNumber(_defaultWorkingHours)} ساعة',
            icon: Icons.schedule_outlined,
          ),
          AppSpacing.verticalMd,
          const Text(
            'إذا تجاوز الاستهلاك الفعلي المخطط فسيتم حفظه مع علامة للمراجعة، ولن تُغيّر هذه الصفحة كمية التنفيذ أو قراءة العداد.',
            style: AppTextStyles.bodySecondary,
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
          const AppSectionTitle(title: 'الاستهلاك الفعلي', icon: Icons.edit_note_outlined),
          AppSpacing.verticalMd,
          if (exceedsPlan) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
              ),
              child: const Text(
                'هناك قيمة تجاوزت المخطط السابق. تم حفظها للتوثيق وهي بحاجة إلى مراجعة.',
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
            'تُحفظ هذه القيم كإجماليات حالية لهذا التكليف. لا تُدخل قراءة العداد هنا؛ قراءة العداد لها شاشة مستقلة.',
            style: AppTextStyles.bodySecondary,
          ),
          AppSpacing.verticalLg,
          AppButton(
            label: _saving ? 'جارٍ الحفظ...' : 'حفظ الاستهلاك الفعلي',
            icon: Icons.save_outlined,
            loading: _saving,
            expanded: true,
            onPressed: _saving ? null : _saveExecutionData,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.supervisorMode
          ? 'تفاصيل تكليف مشرف البند'
          : 'تفاصيل تكليف السائق',
      showBackButton: true,
      child: _loading
          ? const AppLoading(message: 'جارٍ التحقق من التكليف وتحميل التفاصيل...')
          : _errorMessage != null
              ? AppPage(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.lock_outline, size: 56, color: AppColors.warning),
                          AppSpacing.verticalMd,
                          Text(_errorMessage!, textAlign: TextAlign.center, style: AppTextStyles.body),
                          AppSpacing.verticalLg,
                          AppButton(label: 'إعادة المحاولة', icon: Icons.refresh, expanded: true, onPressed: _loadExecutionData),
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

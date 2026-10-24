import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/item_approvals.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/costs.dart';
import '../../core/widgets/app_widgets.dart';

// =============================================================
// طلبات البنود: الكميات الإضافية وتمديد الوقت
// =============================================================
// مدير إدارة الجودة يوافق أو يرفض:
//   • كمية إضافية: بحد أقصى 20% من الكمية التعاقدية.
//   • تمديد وقت: عدد أيام يُضاف إلى تاريخ انتهاء البند.
//
// الموافقة تُنسخ إلى وثيقة البند (items/{itemId}) ليقرأها المشرف
// في صفحته مباشرة دون استعلام إضافي.
// =============================================================

class ApprovalsPage extends StatefulWidget {
  /// نوع الطلب: extra_quantity أو time_extension.
  final String kind;

  /// المشاريع المرتبطة بالمدير (فارغة = الكل).
  final List<String> projectIds;

  const ApprovalsPage({
    super.key,
    required this.kind,
    this.projectIds = const <String>[],
  });

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool get _isExtra => widget.kind == ApprovalKind.extraQuantity;

  String get _title => _isExtra ? 'الكميات الإضافية' : 'تمديد الوقت';

  @override
  Widget build(BuildContext context) {
    final linkedOnly = widget.projectIds.isNotEmpty;

    return AppScaffold(
      title: _title,
      showBackButton: true,
      // القائمة تستخدم Expanded فلا بد من تمرير scrollable: false.
      child: AppPage(
        scrollable: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              title: _title,
              subtitle: _isExtra
                  ? 'طلبات تجاوز الكمية التعاقدية. الموافقة تسمح للمشرف '
                      'بإدخال كمية إضافية بحد أقصى '
                      '${maxExtraQuantityPercent.toStringAsFixed(0)}% من التعاقدية.'
                  : 'طلبات تمديد زمن البند بعد انتهاء مدة العقد. '
                      'الموافقة تفتح لواجهة المشرف إدخال الكميات لمدة محددة.',
              icon: _isExtra
                  ? Icons.add_chart_outlined
                  : Icons.more_time_outlined,
            ),
            AppSpacing.verticalLg,
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ItemApprovals.stream(kind: widget.kind),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return AppError(
                      message: 'تعذر تحميل الطلبات:\n${snapshot.error}',
                      onRetry: () => setState(() {}),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const AppLoading(message: 'جاري تحميل الطلبات...');
                  }

                  final approvals = (snapshot.data?.docs ??
                          <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                      .map(ItemApproval.fromDoc)
                      .where(
                        (a) => linkedOnly
                            ? widget.projectIds.contains(a.projectId)
                            : true,
                      )
                      .toList()
                    ..sort((a, b) {
                      if (a.isPending != b.isPending) {
                        return a.isPending ? -1 : 1;
                      }
                      return (b.createdAt ?? DateTime(2000))
                          .compareTo(a.createdAt ?? DateTime(2000));
                    });

                  if (approvals.isEmpty) {
                    return AppEmpty(
                      message: 'لا توجد طلبات $_title حتى الآن.',
                      icon: _isExtra
                          ? Icons.add_chart_outlined
                          : Icons.more_time_outlined,
                    );
                  }

                  return ListView.separated(
                    itemCount: approvals.length,
                    separatorBuilder: (_, __) => AppSpacing.verticalSm,
                    itemBuilder: (context, index) =>
                        _buildCard(approvals[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(ItemApproval approval) {
    final statusColor = approval.status == ApprovalStatus.approved
        ? AppColors.success
        : (approval.status == ApprovalStatus.rejected
            ? AppColors.danger
            : AppColors.warning);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _isExtra
                    ? Icons.add_chart_outlined
                    : Icons.more_time_outlined,
                color: statusColor,
              ),
              AppSpacing.horizontalSm,
              Expanded(
                child: Text(
                  approval.itemName.isEmpty ? 'بند' : approval.itemName,
                  style: AppTextStyles.cardTitle,
                ),
              ),
              AppStatusBadge(
                text: approval.statusLabel,
                color: statusColor,
              ),
            ],
          ),
          if (approval.typeName.isNotEmpty) ...[
            AppSpacing.verticalXs,
            Text(approval.typeName, style: AppTextStyles.bodySecondary),
          ],
          const Divider(height: 20),
          AppInfoRow(
            label: 'الكمية التعاقدية',
            value: '${ProjectCosts.formatNumber(approval.contractQuantity)} '
                '${approval.unit}',
            icon: Icons.assignment_outlined,
          ),
          AppSpacing.verticalXs,
          AppInfoRow(
            label: 'الكمية المنفذة عند الطلب',
            value: '${ProjectCosts.formatNumber(approval.executedQuantity)} '
                '${approval.unit}',
            icon: Icons.done_all,
          ),
          if (_isExtra) ...[
            AppSpacing.verticalXs,
            AppInfoRow(
              label: 'النسبة المطلوبة',
              value: approval.approvedPercent > 0
                  ? '${ProjectCosts.formatNumber(approval.approvedPercent)}% (معتمدة)'
                  : '${ProjectCosts.formatNumber(approval.requestedPercent)}%',
              icon: Icons.percent,
            ),
            AppSpacing.verticalXs,
            AppInfoRow(
              label: 'أقصى كمية مسموحة بعد الموافقة',
              value:
                  '${ProjectCosts.formatNumber(approval.contractQuantity * (1 + maxExtraQuantityPercent / 100))} '
                  '${approval.unit}',
              icon: Icons.speed_outlined,
            ),
          ] else ...[
            AppSpacing.verticalXs,
            AppInfoRow(
              label: 'الأيام المعتمدة',
              value: approval.approvedDays > 0
                  ? '${ProjectCosts.formatNumber(approval.approvedDays)} يوم'
                  : 'لم تُعتمد بعد',
              icon: Icons.event_available_outlined,
            ),
          ],
          if (approval.note.isNotEmpty) ...[
            AppSpacing.verticalXs,
            Text(approval.note, style: AppTextStyles.small),
          ],
          if (approval.isPending) ...[
            AppSpacing.verticalMd,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton(
                  label: 'موافقة',
                  icon: Icons.check_circle_outline,
                  onPressed: () => _isExtra
                      ? _approveExtra(approval)
                      : _approveTime(approval),
                ),
                AppOutlinedButton(
                  label: 'رفض',
                  icon: Icons.cancel_outlined,
                  onPressed: () => _reject(approval),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _approveExtra(ItemApproval approval) async {
    final percent = await _askNumber(
      title: 'الموافقة على كمية إضافية',
      label: 'النسبة من الكمية التعاقدية (%)',
      max: maxExtraQuantityPercent,
      initial: approval.requestedPercent > 0
          ? approval.requestedPercent
          : maxExtraQuantityPercent,
      hint: 'الحد الأقصى $maxExtraQuantityPercent%',
    );

    if (percent == null) return;

    final user = _auth.currentUser;

    try {
      await ItemApprovals.approveExtraQuantity(
        approval: approval,
        percent: percent,
        decidedBy: user?.uid ?? '',
      );

      if (!mounted) return;
      AppWidgets.showSuccess(
        context,
        'تمت الموافقة على ${ProjectCosts.formatNumber(percent)}% '
        'كمية إضافية، وستظهر للمشرف.',
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showError(context, 'تعذر اعتماد الكمية الإضافية:\n$e');
    }
  }

  Future<void> _approveTime(ItemApproval approval) async {
    final days = await _askNumber(
      title: 'تمديد زمن البند',
      label: 'عدد الأيام',
      max: 365,
      initial: 30,
      hint: 'مثال: 15',
    );

    if (days == null || days <= 0) return;

    final user = _auth.currentUser;

    try {
      await ItemApprovals.approveTimeExtension(
        approval: approval,
        days: days,
        decidedBy: user?.uid ?? '',
      );

      if (!mounted) return;
      AppWidgets.showSuccess(
        context,
        'تم تمديد زمن البند ${ProjectCosts.formatNumber(days)} يومًا، '
        'وسيتمكن المشرف من إدخال الكميات.',
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showError(context, 'تعذر اعتماد التمديد:\n$e');
    }
  }

  Future<void> _reject(ItemApproval approval) async {
    final confirmed = await AppWidgets.showConfirmDialog(
      context: context,
      title: 'رفض الطلب',
      message: 'هل تريد رفض طلب ${approval.kindLabel} للبند '
          '"${approval.itemName}"؟',
      confirmText: 'رفض',
      danger: true,
    );

    if (!confirmed) return;

    final user = _auth.currentUser;

    try {
      await ItemApprovals.reject(
        approval: approval,
        decidedBy: user?.uid ?? '',
      );

      if (!mounted) return;
      AppWidgets.showSuccess(context, 'تم رفض الطلب.');
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      AppWidgets.showError(context, 'تعذر رفض الطلب:\n$e');
    }
  }

  /// نافذة إدخال رقم بحد أقصى.
  Future<double?> _askNumber({
    required String title,
    required String label,
    required double max,
    required double initial,
    String? hint,
  }) async {
    final controller = TextEditingController(
      text: ProjectCosts.toEditText(initial),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppNumberField(
                    controller: controller,
                    label: label,
                    hint: hint,
                    prefixIcon: Icons.numbers,
                  ),
                  AppSpacing.verticalXs,
                  Text(
                    'الحد الأقصى: ${ProjectCosts.formatNumber(max)}',
                    style: AppTextStyles.small,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  var value = ProjectCosts.parseOptional(controller.text) ?? 0;
                  if (value > max) value = max;
                  if (value <= 0) return;

                  Navigator.pop(dialogContext, value);
                },
                child: const Text('موافقة'),
              ),
            ],
          ),
        );
      },
    );

    controller.dispose();

    return result;
  }
}

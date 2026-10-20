import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/costs.dart';
import 'app_widgets.dart';

// ============================================================
// حقول إدخال التكاليف الأربعة
// ============================================================

/// يعرض حقول تكلفة المشروع (أو تكلفة الوحدة في البنود)
/// بنفس الترتيب والتنسيق في كل الصفحات.
class CostFieldsEditor extends StatelessWidget {
  /// نص لكل قسم: materials / labor / equipment / fuel
  final Map<String, TextEditingController> controllers;

  final bool enabled;

  /// عند تغيير أي قيمة (لتحديث الإجمالي التلقائي).
  final VoidCallback? onChanged;

  /// عدد الأعمدة حسب العرض المتاح.
  final int columns;

  const CostFieldsEditor({
    super.key,
    required this.controllers,
    this.enabled = true,
    this.onChanged,
    this.columns = 2,
  });

  Widget _field(CostCategory category) {
    return AppNumberField(
      controller: controllers[category.key],
      label: category.label,
      hint: 'أدخل ${category.shortLabel}',
      suffixText: ProjectCosts.currency,
      prefixIcon: category.icon,
      enabled: enabled,
      onChanged: (_) => onChanged?.call(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ProjectCosts.categories;

    if (columns <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < categories.length; i++) ...[
            _field(categories[i]),
            if (i != categories.length - 1) AppSpacing.verticalSm,
          ],
        ],
      );
    }

    final rows = <Widget>[];

    for (int i = 0; i < categories.length; i += 2) {
      final fields = <Widget>[
        Expanded(child: _field(categories[i])),
      ];

      if (i + 1 < categories.length) {
        fields.add(AppSpacing.horizontalMd);
        fields.add(Expanded(child: _field(categories[i + 1])));
      } else {
        // فراغ بنفس العرض لتبقى الأعمدة متساوية.
        fields.add(AppSpacing.horizontalMd);
        fields.add(const Expanded(child: SizedBox.shrink()));
      }

      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: fields,
        ),
      );

      if (i + 2 < categories.length) {
        rows.add(AppSpacing.verticalSm);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

// ============================================================
// بطاقة ملخص التكاليف
// ============================================================

/// تعرض توزيع التكلفة على الأقسام مع الإجمالي،
/// ويمكن إرفاق بيانات مقارنة (مثل التكلفة المخططة للمشروع)
/// لعرض نسبة الاستهلاك من المخطط.
class CostSummaryCard extends StatelessWidget {
  final String title;

  final Map<String, double> breakdown;

  final double? total;

  /// بيانات مرجعية للمقارنة (غالبًا التكلفة المخططة) لنفس الأقسام.
  final Map<String, double>? reference;

  /// اسم العمود المرجعي عند وجود مقارنة.
  final String? referenceLabel;

  /// يحوّل البطاقة إلى بطاقة مصغرة بدون عنوان كبير.
  final bool compact;

  final IconData icon;

  const CostSummaryCard({
    super.key,
    required this.title,
    required this.breakdown,
    this.total,
    this.reference,
    this.referenceLabel,
    this.compact = false,
    this.icon = Icons.payments_outlined,
  });

  double _valueOf(String key) => breakdown[key] ?? 0;

  double _totalValue() {
    if (total != null) return total!;

    double sum = 0;

    for (final category in ProjectCosts.categories) {
      sum += _valueOf(category.key);
    }

    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final totalValue = _totalValue();

    final hasAnyData = totalValue > 0 ||
        (reference?.values.any((value) => value > 0) ?? false);

    final rows = <Widget>[];

    for (final category in ProjectCosts.categories) {
      final value = _valueOf(category.key);

      final planned = reference == null ? null : (reference![category.key] ?? 0);

      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    category.icon,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  AppSpacing.horizontalSm,
                  Expanded(
                    child: Text(
                      category.label,
                      style: compact
                          ? AppTextStyles.small
                          : AppTextStyles.bodySecondary,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    ProjectCosts.formatMoney(value),
                    style: (compact
                            ? AppTextStyles.small
                            : AppTextStyles.body)
                        .copyWith(
                      fontWeight: FontWeight.bold,
                      color: planned != null &&
                              planned > 0 &&
                              value > planned
                          ? AppColors.danger
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (planned != null && planned > 0) ...[
                const SizedBox(height: 6),
                AppProgress(
                  value: planned == 0 ? 0 : (value / planned).clamp(0.0, 1.0).toDouble(),
                  height: 5,
                  progressColor: value > planned
                      ? AppColors.danger
                      : category.color,
                ),
                const SizedBox(height: 3),
                Text(
                  '${referenceLabel ?? 'المخطط'}: '
                  '${ProjectCosts.formatMoney(planned)}',
                  style: AppTextStyles.small,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact)
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: AppColors.primary,
                ),
                AppSpacing.horizontalSm,
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.small.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            )
          else
            AppSectionTitle(
              title: title,
              icon: icon,
            ),
          AppSpacing.verticalSm,
          if (!hasAnyData)
            Text(
              compact
                  ? 'لم تُسجل تكاليف بعد'
                  : 'لم تُسجل تكاليف لهذا البند بعد. '
                      'أضف التكاليف من صفحة تفاصيل البند.',
              style: AppTextStyles.bodySecondary,
            )
          else ...[
            ...rows,
            AppSpacing.verticalSm,
            const Divider(),
            AppSpacing.verticalXs,
            Row(
              children: [
                Expanded(
                  child: Text(
                    'إجمالي التكلفة',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  ProjectCosts.formatMoney(totalValue),
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            if (reference != null) ...[
              AppSpacing.verticalXs,
              Builder(
                builder: (context) {
                  final plannedTotal = reference!.values.fold<double>(
                    0,
                    (sum, value) => sum + value,
                  );

                  if (plannedTotal <= 0) {
                    return const SizedBox.shrink();
                  }

                  final diff = plannedTotal - totalValue;

                  return Text(
                    diff >= 0
                        ? 'متبقٍ من المخطط: ${ProjectCosts.formatMoney(diff)}'
                        : 'تجاوز المخطط بمبلغ: ${ProjectCosts.formatMoney(diff.abs())}',
                    style: AppTextStyles.small.copyWith(
                      color: diff >= 0
                          ? AppColors.success
                          : AppColors.danger,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';
import 'accounting_models.dart';

// ============================================================
// مكوّنات واجهة مشتركة للوحدة المالية
// ============================================================

Color voucherKindColor(VoucherKind kind) {
  return kind == VoucherKind.receipt ? AppColors.success : AppColors.danger;
}

IconData voucherKindIcon(VoucherKind kind) {
  return kind == VoucherKind.receipt
      ? Icons.south_west
      : Icons.north_east;
}

Color paymentMethodColor(PaymentMethod method) {
  if (method == PaymentMethod.cash) return AppColors.success;
  if (method == PaymentMethod.bank) return AppColors.info;
  return AppColors.warning;
}

IconData paymentMethodIcon(PaymentMethod method) {
  if (method == PaymentMethod.cash) return Icons.payments_outlined;
  if (method == PaymentMethod.bank) return Icons.account_balance_outlined;
  return Icons.receipt_outlined;
}

String projectLabelOf(Voucher voucher) {
  final String name = voucher.projectName.trim();
  final String code = voucher.projectCode.trim();

  if (code.isNotEmpty && name.isNotEmpty) return '$code — $name';
  if (name.isNotEmpty) return name;
  if (code.isNotEmpty) return code;
  return 'بدون مشروع';
}

String journalProjectLabel(JournalEntry entry) {
  final String name = entry.projectName.trim();
  final String code = entry.projectCode.trim();

  if (code.isNotEmpty && name.isNotEmpty) return '$code — $name';
  if (name.isNotEmpty) return name;
  if (code.isNotEmpty) return code;
  return 'بدون مشروع';
}

// ============================================================
// شارة صغيرة
// ============================================================

class AccountingBadge extends StatelessWidget {
  const AccountingBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// بطاقة مبلغ/إحصائية مالية
// ============================================================

class AccountingMetricCard extends StatelessWidget {
  const AccountingMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 21, color: color),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.bodySecondary.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.statisticNumber.copyWith(
                fontSize: 21,
                color: color,
              ),
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: AppTextStyles.small,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// سطر معلومة (تسمية / قيمة)
// ============================================================

class AccountingInfoRow extends StatelessWidget {
  const AccountingInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 16, color: AppColors.textLight),
            const SizedBox(width: 6),
          ],
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: AppTextStyles.small.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.start,
              style: AppTextStyles.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// جدول بسيط للتقارير
// ============================================================

class AccountingTable extends StatelessWidget {
  const AccountingTable({
    super.key,
    required this.headers,
    required this.rows,
    this.columnFlex,
    this.emptyText = 'لا توجد بيانات في هذه الفترة',
  });

  final List<String> headers;
  final List<List<Widget>> rows;
  final List<int>? columnFlex;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final List<int> flex = columnFlex ??
        List<int>.generate(headers.length, (_) => 1);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: <Widget>[
                for (int index = 0; index < headers.length; index++)
                  Expanded(
                    flex: flex[index],
                    child: Text(
                      headers[index],
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                emptyText,
                style: AppTextStyles.bodySecondary,
              ),
            )
          else
            for (int rowIndex = 0; rowIndex < rows.length; rowIndex++)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.border.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    for (int index = 0; index < headers.length; index++)
                      Expanded(
                        flex: flex[index],
                        child: index < rows[rowIndex].length
                            ? rows[rowIndex][index]
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ============================================================
// حالة فراغ
// ============================================================

class AccountingEmptyState extends StatelessWidget {
  const AccountingEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.receipt_long_outlined,
    this.actionText,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.cardTitle,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary,
            ),
            if (actionText != null && onAction != null) ...<Widget>[
              const SizedBox(height: 16),
              AppButton(
                text: actionText!,
                icon: Icons.add,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

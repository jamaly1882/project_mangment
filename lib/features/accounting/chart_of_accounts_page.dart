import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';
import 'accounting_models.dart';
import 'accounting_widgets.dart';

// ============================================================
// دليل الحسابات
// ============================================================
//
// عرض مرجعي للحسابات التي تُستخدم في السندات والقيود:
// الأصول، الالتزامات، حقوق الملكية، الإيرادات، المصروفات.
//
// حسابات الصندوق (1000) والبنك (1010) تُختار تلقائيًا حسب
// طريقة الدفع، ولا تظهر في قائمة «الحساب المقابل» في السند.
// ============================================================

class ChartOfAccountsPage extends StatelessWidget {
  const ChartOfAccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'دليل الحسابات',
      child: AppPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const AppPageHeader(
              title: 'دليل الحسابات',
              subtitle:
                  'الحسابات المعتمدة في سندات القبض والصرف والقيود اليومية.',
              icon: Icons.account_tree_outlined,
            ),
            for (final FinanceAccountKind kind in FinanceAccountKind.values)
              _kindSection(kind),
            const SizedBox(height: 8),
            AppCard(
              color: AppColors.info.withValues(alpha: 0.06),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.info_outline,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'عند اختيار طريقة الدفع «نقدًا» يُستخدم حساب '
                      'الصندوق (1000)، وعند «بنك» أو «شيك» يُستخدم '
                      'حساب البنك (1010) تلقائيًا، والحساب الذي تختاره '
                      'في السند هو الطرف الآخر في القيد.',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindSection(FinanceAccountKind kind) {
    final List<FinanceAccount> accounts = financeChartOfAccounts
        .where((account) => account.kind == kind)
        .toList();

    if (accounts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSectionTitle(
            title: kind.label,
            icon: _kindIcon(kind),
          ),
          AppCard(
            padding: const EdgeInsets.all(10),
            child: AccountingTable(
              headers: const <String>['الكود', 'اسم الحساب', 'النوع'],
              columnFlex: const <int>[1, 4, 2],
              rows: accounts.map((account) {
                return <Widget>[
                  Text(
                    account.code,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    account.name,
                    style: AppTextStyles.body.copyWith(fontSize: 12),
                  ),
                  AccountingBadge(
                    label: account.isCash || account.isBank
                        ? 'نقدي'
                        : account.kind.label,
                    color: account.isCash || account.isBank
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                ];
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  IconData _kindIcon(FinanceAccountKind kind) {
    switch (kind) {
      case FinanceAccountKind.asset:
        return Icons.account_balance_wallet_outlined;
      case FinanceAccountKind.liability:
        return Icons.request_quote_outlined;
      case FinanceAccountKind.equity:
        return Icons.pie_chart_outline;
      case FinanceAccountKind.revenue:
        return Icons.trending_up;
      case FinanceAccountKind.expense:
        return Icons.trending_down;
    }
  }
}

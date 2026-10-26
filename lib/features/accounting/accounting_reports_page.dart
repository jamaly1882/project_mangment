import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';
import 'accounting_format.dart';
import 'accounting_models.dart';
import 'accounting_service.dart';
import 'accounting_widgets.dart';
import 'project_budget.dart';
import 'project_budget_page.dart';

// ============================================================
// التقارير المالية للوحدة
// ============================================================
//
// تقرير فترة واحد يجمع:
//   • إجمالي القبض والصرف وصافي الحركة.
//   • أرصدة الصندوق والبنك الحالية.
//   • الحركة حسب طريقة الدفع.
//   • الحركة حسب المشروع.
//   • ميزان المراجعة من القيود اليومية (يشمل قيود السندات).
// ============================================================

class AccountingReportsPage extends StatefulWidget {
  const AccountingReportsPage({
    super.key,
    this.scope = AccountingScope.none,
    this.canViewAllProjects = false,
  });

  /// مشروع المحاسب: تقارير هذا المشروع فقط.
  final AccountingScope scope;

  /// صلاحية عرض ميزانية كل المشاريع (المدير المالي فقط).
  ///
  /// المحاسب غير المربوط لا تُمنح له هذه الصلاحية، فلا يصل إلى
  /// ميزانية أي مشروع حتى يُربط بمشروعه.
  final bool canViewAllProjects;

  @override
  State<AccountingReportsPage> createState() => _AccountingReportsPageState();
}

class _AccountingReportsPageState extends State<AccountingReportsPage> {
  final AccountingService _service = AccountingService();

  /// هل يملك المستخدم صلاحية فتح ميزانية المشاريع؟
  bool get _canOpenBudgets => canAccessProjectBudgets(
        isScopedToProject: widget.scope.isScoped,
        canViewAllProjects: widget.canViewAllProjects,
      );

  late Future<AccountingSnapshot> _future;
  _ReportPeriod _period = _ReportPeriod.thisMonth;

  @override
  void initState() {
    super.initState();
    _future = _service.loadSnapshot(
      projectId: widget.scope.projectId,
    );
  }

  void _reload() {
    setState(() {
      _future = _service.loadSnapshot(
        projectId: widget.scope.projectId,
      );
    });
  }

  _DateRange _range(_ReportPeriod period) {
    final DateTime now = DateTime.now();

    switch (period) {
      case _ReportPeriod.thisMonth:
        return _DateRange(startOfMonth(now), endOfMonth(now));
      case _ReportPeriod.lastMonth:
        final DateTime previous = DateTime(now.year, now.month - 1, 1);
        return _DateRange(
          startOfMonth(previous),
          endOfMonth(previous),
        );
      case _ReportPeriod.thisYear:
        return _DateRange(startOfYear(now), endOfYear(now));
      case _ReportPeriod.all:
        return const _DateRange(null, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'التقارير المالية',
      actions: <Widget>[
        if (_canOpenBudgets)
          IconButton(
            tooltip: 'ميزانية المشاريع',
            icon: const Icon(Icons.pie_chart_outline),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ProjectBudgetPage(
                    scope: widget.scope,
                    canViewAllProjects: widget.canViewAllProjects,
                  ),
                ),
              );
            },
          ),
        IconButton(
          tooltip: 'تحديث',
          icon: const Icon(Icons.refresh),
          onPressed: _reload,
        ),
      ],
      child: FutureBuilder<AccountingSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppError(
              message: 'تعذر تحميل التقارير:\n${snapshot.error}',
              onRetry: _reload,
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const AppLoading(message: 'جاري تحضير التقارير...');
          }

          final AccountingSnapshot data = snapshot.data ??
              const AccountingSnapshot(
                vouchers: <Voucher>[],
                entries: <JournalEntry>[],
                opening: OpeningBalance(),
                movements: <CashMovement>[],
              );

          final _DateRange range = _range(_period);

          final List<Voucher> vouchers = filterVouchers(
            data.vouchers,
            start: range.start,
            end: range.end,
          );
          final List<JournalEntry> entries = filterJournalEntries(
            data.entries,
            start: range.start,
            end: range.end,
          );

          final double receipts = sumVouchers(vouchers, VoucherKind.receipt);
          final double payments = sumVouchers(vouchers, VoucherKind.payment);
          final double net = receipts - payments;

          final double cashBalance = FinanceMath.balance(
            opening: data.opening,
            movements: data.movements,
            filter: MoneyBoxFilter.cash,
          );
          final double bankBalance = FinanceMath.balance(
            opening: data.opening,
            movements: data.movements,
            filter: MoneyBoxFilter.bank,
          );

          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              children: <Widget>[
                AppPageHeader(
                  title: 'التقارير المالية',
                  subtitle: widget.scope.isScoped
                      ? 'ملخص حركة مشروع ${widget.scope.label}، والحركة '
                          'حسب طريقة الدفع، وميزان المراجعة من قيوده.'
                      : 'ملخص حركة الوحدة المالية، والحركة حسب طريقة الدفع '
                          'والمشروع، وميزان المراجعة من القيود اليومية.',
                  icon: Icons.bar_chart,
                ),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _ReportPeriod.values.map((period) {
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: ChoiceChip(
                          label: Text(period.label),
                          selected: _period == period,
                          onSelected: (_) =>
                              setState(() => _period = period),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 14),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final double width = constraints.maxWidth > 700
                        ? (constraints.maxWidth - 20) / 3
                        : (constraints.maxWidth - 10) / 2;

                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'إجمالي القبض',
                            value: formatMoney(receipts, decimals: 0),
                            icon: Icons.south_west,
                            color: AppColors.success,
                            subtitle:
                                '${vouchers.where((v) => v.isReceipt).length} سند قبض',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'إجمالي الصرف',
                            value: formatMoney(payments, decimals: 0),
                            icon: Icons.north_east,
                            color: AppColors.danger,
                            subtitle:
                                '${vouchers.where((v) => v.isPayment).length} سند صرف',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'صافي الحركة',
                            value: formatMoney(net, decimals: 0),
                            icon: Icons.trending_up,
                            color: net >= 0
                                ? AppColors.primary
                                : AppColors.danger,
                            subtitle: 'قبض − صرف',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'رصيد الصندوق',
                            value: formatMoney(cashBalance, decimals: 0),
                            icon: Icons.savings_outlined,
                            color: AppColors.info,
                            subtitle: 'الرصيد الحالي',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'رصيد البنك',
                            value: formatMoney(bankBalance, decimals: 0),
                            icon: Icons.account_balance_outlined,
                            color: AppColors.warning,
                            subtitle: 'بنك وشيكات',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'القيود اليومية',
                            value: '${entries.length}',
                            icon: Icons.menu_book_outlined,
                            color: AppColors.primaryDark,
                            subtitle: 'خلال الفترة',
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 18),

                AppSectionTitle(
                  title: 'الحركة حسب طريقة الدفع',
                  subtitle: _period.description,
                  icon: Icons.credit_card,
                ),

                AppCard(
                  padding: const EdgeInsets.all(10),
                  child: AccountingTable(
                    headers: const <String>['الطريقة', 'قبض', 'صرف', 'الصافي'],
                    columnFlex: const <int>[2, 2, 2, 2],
                    rows: PaymentMethod.values.map((method) {
                      final List<Voucher> ofMethod = vouchers
                          .where((voucher) => voucher.method == method)
                          .toList();
                      final double methodReceipts =
                          sumVouchers(ofMethod, VoucherKind.receipt);
                      final double methodPayments =
                          sumVouchers(ofMethod, VoucherKind.payment);

                      return <Widget>[
                        _cell(method.label),
                        _cell(
                          formatMoney(methodReceipts, decimals: 0),
                          color: AppColors.success,
                        ),
                        _cell(
                          formatMoney(methodPayments, decimals: 0),
                          color: AppColors.danger,
                        ),
                        _cell(
                          formatMoney(
                            methodReceipts - methodPayments,
                            decimals: 0,
                          ),
                          color: methodReceipts - methodPayments >= 0
                              ? AppColors.primary
                              : AppColors.danger,
                          bold: true,
                        ),
                      ];
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 18),

                AppSectionTitle(
                  title: 'الحركة حسب المشروع',
                  subtitle: 'القبض والصرف لكل مشروع في الفترة',
                  icon: Icons.apartment_outlined,
                ),

                AppCard(
                  padding: const EdgeInsets.all(10),
                  child: AccountingTable(
                    headers: const <String>[
                      'المشروع',
                      'قبض',
                      'صرف',
                      'الصافي',
                    ],
                    columnFlex: const <int>[4, 2, 2, 2],
                    rows: _projectRows(vouchers),
                    emptyText: 'لا توجد سندات مرتبطة بمشاريع في الفترة',
                  ),
                ),

                const SizedBox(height: 18),

                AppSectionTitle(
                  title: 'ميزان المراجعة',
                  subtitle:
                      'مجموع المدين والدائن لكل حساب من القيود اليومية '
                      '(تشمل قيود السندات)',
                  icon: Icons.balance,
                ),

                AppCard(
                  padding: const EdgeInsets.all(10),
                  child: AccountingTable(
                    headers: const <String>[
                      'الحساب',
                      'مدين',
                      'دائن',
                      'الرصيد',
                    ],
                    columnFlex: const <int>[4, 2, 2, 2],
                    rows: _trialRows(entries),
                    emptyText: 'لا توجد قيود في الفترة',
                  ),
                ),

                const SizedBox(height: 16),

                Text(
                  'ملاحظة: الرصيد في ميزان المراجعة = مدين − دائن؛ '
                  'الرصيد الموجب مدين (أصول/مصروفات) والسالب دائن '
                  '(التزامات/إيرادات/حقوق ملكية).',
                  style: AppTextStyles.small,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<List<Widget>> _projectRows(List<Voucher> vouchers) {
    final Map<String, _ProjectTotals> totals = <String, _ProjectTotals>{};

    for (final Voucher voucher in vouchers) {
      final String key = voucher.projectId.isEmpty
          ? 'none'
          : voucher.projectId;
      final _ProjectTotals item = totals.putIfAbsent(
        key,
        () => _ProjectTotals(
          label: projectLabelOf(voucher),
        ),
      );

      if (voucher.isReceipt) {
        item.receipts += voucher.amount;
      } else {
        item.payments += voucher.amount;
      }
    }

    final List<_ProjectTotals> list = totals.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    return list.map((item) {
      final double net = item.receipts - item.payments;

      return <Widget>[
        _cell(item.label),
        _cell(
          formatMoney(item.receipts, decimals: 0),
          color: AppColors.success,
        ),
        _cell(
          formatMoney(item.payments, decimals: 0),
          color: AppColors.danger,
        ),
        _cell(
          formatMoney(net, decimals: 0),
          color: net >= 0 ? AppColors.primary : AppColors.danger,
          bold: true,
        ),
      ];
    }).toList();
  }

  List<List<Widget>> _trialRows(List<JournalEntry> entries) {
    final Map<String, _TrialAccount> accounts = <String, _TrialAccount>{};

    for (final JournalEntry entry in entries) {
      for (final JournalLine line in entry.lines) {
        final String key = line.accountCode.isEmpty
            ? line.accountName
            : line.accountCode;
        final _TrialAccount account = accounts.putIfAbsent(
          key,
          () => _TrialAccount(
            code: line.accountCode,
            name: line.accountName,
          ),
        );
        account.debit += line.debit;
        account.credit += line.credit;
      }
    }

    final List<_TrialAccount> list = accounts.values.toList()
      ..sort((a, b) => a.code.compareTo(b.code));

    return list.map((account) {
      final double balance = account.debit - account.credit;

      return <Widget>[
        _cell(
          account.code.isEmpty
              ? account.name
              : '${account.code} — ${account.name}',
        ),
        _cell(
          formatMoney(account.debit, decimals: 0),
          color: AppColors.success,
        ),
        _cell(
          formatMoney(account.credit, decimals: 0),
          color: AppColors.danger,
        ),
        _cell(
          formatMoney(balance, decimals: 0),
          color: balance >= 0 ? AppColors.primary : AppColors.warning,
          bold: true,
        ),
      ];
    }).toList();
  }

  Widget _cell(
    String text, {
    Color? color,
    bool bold = false,
  }) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        fontWeight: bold ? FontWeight.bold : FontWeight.w500,
        color: color ?? AppColors.textPrimary,
      ),
    );
  }
}

// ============================================================
// الفترات
// ============================================================

enum _ReportPeriod {
  thisMonth('هذا الشهر'),
  lastMonth('الشهر الماضي'),
  thisYear('هذه السنة'),
  all('كل الفترات');

  const _ReportPeriod(this.label);

  final String label;

  String get description {
    switch (this) {
      case _ReportPeriod.thisMonth:
        return 'حركة ${formatMonthYear(DateTime.now())}';
      case _ReportPeriod.lastMonth:
        final DateTime previous = DateTime(
          DateTime.now().year,
          DateTime.now().month - 1,
          1,
        );
        return 'حركة ${formatMonthYear(previous)}';
      case _ReportPeriod.thisYear:
        return 'حركة سنة ${DateTime.now().year}';
      case _ReportPeriod.all:
        return 'حركة كل الفترات';
    }
  }
}

class _DateRange {
  const _DateRange(this.start, this.end);

  final DateTime? start;
  final DateTime? end;
}

class _ProjectTotals {
  _ProjectTotals({required this.label});

  final String label;
  double receipts = 0;
  double payments = 0;
}

class _TrialAccount {
  _TrialAccount({required this.code, required this.name});

  final String code;
  final String name;
  double debit = 0;
  double credit = 0;
}

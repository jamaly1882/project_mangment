import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';
import 'accounting_format.dart';
import 'accounting_models.dart';
import 'accounting_service.dart';
import 'accounting_widgets.dart';
import 'vouchers_page.dart';

// ============================================================
// الصندوق — كشف الحركة والرصيد
// ============================================================
//
// يعرض حركة الصندوق النقدي (أو البنك والشيكات، أو الاثنين):
//   • الرصيد الافتتاحي (يُدخله المحاسب مرة واحدة).
//   • الوارد من سندات القبض والقيود اليدوية التي تمسّ الصندوق.
//   • الصادر من سندات الصرف والقيود اليدوية.
//   • الرصيد الجاري بعد كل حركة.
//
// الحركة مشتقّة من السندات والقيود نفسها، فلا تُدخَل مرتين ولا
// تختلف أرقام الصندوق عن أرقام القيود.
// ============================================================

class CashBoxPage extends StatefulWidget {
  const CashBoxPage({
    super.key,
    this.canEdit = true,
    this.scope = AccountingScope.none,
  });

  final bool canEdit;

  /// مشروع المحاسب: صندوق هذا المشروع ورصيده الافتتاحي فقط.
  final AccountingScope scope;

  @override
  State<CashBoxPage> createState() => _CashBoxPageState();
}

class _CashBoxPageState extends State<CashBoxPage> {
  final AccountingService _service = AccountingService();

  late Future<AccountingSnapshot> _future;

  MoneyBoxFilter _filter = MoneyBoxFilter.cash;
  _CashPeriod _period = _CashPeriod.all;
  OpeningBalance _opening = const OpeningBalance();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<AccountingSnapshot> _load() async {
    final AccountingSnapshot snapshot = await _service.loadSnapshot(
      projectId: widget.scope.projectId,
    );
    _opening = snapshot.opening;
    return snapshot;
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _openVouchers(VoucherKind kind) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VouchersPage(
          kind: kind,
          canEdit: widget.canEdit,
          scope: widget.scope,
        ),
      ),
    );

    if (!mounted) return;
    _reload();
  }

  Future<void> _editOpening() async {
    if (!widget.canEdit) return;

    final _OpeningResult? result = await showDialog<_OpeningResult>(
      context: context,
      builder: (_) => _OpeningBalanceDialog(
        opening: _opening,
        scope: widget.scope,
      ),
    );

    if (result == null) return;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppWidgets.showError(context, 'انتهت جلسة الدخول، سجّل الدخول من جديد');
      return;
    }

    try {
      final String userName = await currentAccountingUserName();
      await _service.saveOpeningBalance(
        cash: result.cash,
        bank: result.bank,
        userId: user.uid,
        userName: userName,
        projectId: widget.scope.projectId,
        projectCode: widget.scope.projectCode,
        projectName: widget.scope.projectName,
      );
      if (!mounted) return;
      AppWidgets.showSuccess(context, 'تم حفظ الرصيد الافتتاحي');
      _reload();
    } on AccountingException catch (error) {
      if (mounted) AppWidgets.showError(context, error.message);
    } catch (error) {
      if (mounted) {
        AppWidgets.showError(context, 'تعذر حفظ الرصيد الافتتاحي: $error');
      }
    }
  }

  _DateRange _periodRange(_CashPeriod period) {
    final DateTime now = DateTime.now();

    switch (period) {
      case _CashPeriod.all:
        return const _DateRange(null, null);
      case _CashPeriod.thisMonth:
        return _DateRange(startOfMonth(now), endOfMonth(now));
      case _CashPeriod.lastMonth:
        final DateTime previous = DateTime(now.year, now.month - 1, 1);
        return _DateRange(
          startOfMonth(previous),
          endOfMonth(previous),
        );
      case _CashPeriod.thisYear:
        return _DateRange(startOfYear(now), endOfYear(now));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.scope.isScoped ? 'صندوق المشروع' : 'الصندوق',
      actions: <Widget>[
        if (widget.canEdit)
          PopupMenuButton<String>(
            tooltip: 'إضافة سند',
            icon: const Icon(Icons.add_card),
            onSelected: (value) {
              if (value == 'receipt') {
                _openVouchers(VoucherKind.receipt);
              }
              if (value == 'payment') {
                _openVouchers(VoucherKind.payment);
              }
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'receipt',
                child: Text('سند قبض'),
              ),
              PopupMenuItem<String>(
                value: 'payment',
                child: Text('سند صرف'),
              ),
            ],
          ),
        if (widget.canEdit)
          IconButton(
            tooltip: 'الرصيد الافتتاحي',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _editOpening,
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
              message: 'تعذر تحميل الصندوق:\n${snapshot.error}',
              onRetry: _reload,
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const AppLoading(message: 'جاري تحميل حركة الصندوق...');
          }

          final AccountingSnapshot data =
              snapshot.data ??
              const AccountingSnapshot(
                vouchers: <Voucher>[],
                entries: <JournalEntry>[],
                opening: OpeningBalance(),
                movements: <CashMovement>[],
              );

          final _DateRange range = _periodRange(_period);

          final double balanceBefore = range.start == null
              ? data.opening.of(_filter)
              : FinanceMath.balanceBefore(
                  opening: data.opening,
                  movements: data.movements,
                  filter: _filter,
                  date: range.start!,
                );

          final List<CashMovement> movements = data.movements.where((movement) {
            if (!_filter.matches(movement.method)) return false;
            return inPeriod(movement.date, range.start, range.end);
          }).toList();

          final double totalIn = FinanceMath.totalIn(movements);
          final double totalOut = FinanceMath.totalOut(movements);
          final double closing = balanceBefore + totalIn - totalOut;

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
                  title: 'الصندوق والحركة المالية',
                  subtitle: widget.scope.isScoped
                      ? 'صندوق مشروع ${widget.scope.label}: الرصيد الجاري '
                          'يُحسب من سندات وقيود هذا المشروع، ويُضاف إليه '
                          'رصيده الافتتاحي.'
                      : 'الرصيد الجاري يُحسب من السندات والقيود، '
                          'ويُضاف إليه الرصيد الافتتاحي.',
                  icon: Icons.account_balance_wallet,
                  trailing: _filter == MoneyBoxFilter.cash
                      ? null
                      : TextButton.icon(
                          onPressed: _editOpening,
                          icon: const Icon(Icons.tune, size: 18),
                          label: const Text('الافتتاحي'),
                        ),
                ),

                _filterChips(),
                const SizedBox(height: 8),
                _periodChips(),

                const SizedBox(height: 14),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final double width = constraints.maxWidth > 700
                        ? (constraints.maxWidth - 30) / 4
                        : (constraints.maxWidth - 10) / 2;

                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'الرصيد الافتتاحي للفترة',
                            value: formatMoney(balanceBefore, decimals: 0),
                            icon: Icons.flag_outlined,
                            color: AppColors.textSecondary,
                            subtitle: range.start == null
                                ? 'بداية التسجيل'
                                : formatDate(range.start!),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'إجمالي الوارد',
                            value: formatMoney(totalIn, decimals: 0),
                            icon: Icons.south_west,
                            color: AppColors.success,
                            subtitle: '${movements.where((m) => m.isIn).length} حركة قبض',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'إجمالي الصادر',
                            value: formatMoney(totalOut, decimals: 0),
                            icon: Icons.north_east,
                            color: AppColors.danger,
                            subtitle:
                                '${movements.where((m) => !m.isIn).length} حركة صرف',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'الرصيد الحالي',
                            value: formatMoney(closing, decimals: 0),
                            icon: Icons.savings_outlined,
                            color: closing >= 0
                                ? AppColors.primary
                                : AppColors.danger,
                            subtitle: _filter.label,
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 18),

                AppSectionTitle(
                  title: 'حركة ${_filter.label}',
                  subtitle: movements.isEmpty
                      ? 'لا توجد حركة في هذه الفترة'
                      : '${movements.length} حركة — الرصيد بعد كل حركة',
                  icon: Icons.receipt_long_outlined,
                  trailing: widget.canEdit
                      ? TextButton.icon(
                          onPressed: _editOpening,
                          icon: const Icon(Icons.edit_outlined, size: 17),
                          label: const Text('الافتتاحي'),
                        )
                      : null,
                ),

                if (movements.isEmpty)
                  AppCard(
                    color: AppColors.surface,
                    child: AccountingEmptyState(
                      title: 'لا توجد حركة في هذه الفترة',
                      message: _filter == MoneyBoxFilter.cash
                          ? 'سندات القبض والصرف النقدية تظهر هنا مباشرة.'
                          : 'حركة البنك والشيكات تظهر هنا عند تسجيلها.',
                      icon: Icons.account_balance_wallet_outlined,
                      actionText: widget.canEdit ? 'إضافة سند قبض' : null,
                      onAction: widget.canEdit
                          ? () => _openVouchers(VoucherKind.receipt)
                          : null,
                    ),
                  )
                else
                  ..._movementWidgets(movements, balanceBefore),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _movementWidgets(
    List<CashMovement> movements,
    double balanceBefore,
  ) {
    final List<Widget> widgets = <Widget>[];

    // الحركة مرتّبة تصاعديًا من الخدمة؛ الرصيد الجاري يبدأ من
    // رصيد ما قبل الفترة ثم يتراكم.
    double running = balanceBefore;

    for (final CashMovement movement in movements) {
      running += movement.net;
      widgets.add(_movementCard(movement, running));
    }

    return widgets;
  }

  Widget _movementCard(CashMovement movement, double running) {
    final Color color =
        movement.isIn ? AppColors.success : AppColors.danger;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                movement.isIn ? Icons.south_west : Icons.north_east,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          movement.reference.isEmpty
                              ? movement.category
                              : movement.reference,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.cardTitle.copyWith(
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      AccountingBadge(
                        label: movement.category,
                        color: paymentMethodColor(movement.method),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    movement.description.isEmpty
                        ? movement.category
                        : movement.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatDate(movement.date)}'
                    '${movement.party.trim().isEmpty ? '' : '  •  ${movement.party}'}'
                    '${_filter == MoneyBoxFilter.all ? '  •  ${movement.method.shortLabel}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.small,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  '${movement.isIn ? '+' : '−'}${formatMoney(movement.net.abs(), decimals: 0)}',
                  style: AppTextStyles.cardTitle.copyWith(
                    color: color,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'الرصيد ${formatMoney(running, decimals: 0)}',
                  style: AppTextStyles.small.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: MoneyBoxFilter.values.map((filter) {
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: ChoiceChip(
              label: Text(filter.label),
              selected: _filter == filter,
              onSelected: (_) => setState(() => _filter = filter),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _periodChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _CashPeriod.values.map((period) {
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: ChoiceChip(
              label: Text(period.label),
              selected: _period == period,
              onSelected: (_) => setState(() => _period = period),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ============================================================
// الفترات
// ============================================================

enum _CashPeriod {
  all('كل الفترات'),
  thisMonth('هذا الشهر'),
  lastMonth('الشهر الماضي'),
  thisYear('هذه السنة');

  const _CashPeriod(this.label);

  final String label;
}

class _DateRange {
  const _DateRange(this.start, this.end);

  final DateTime? start;
  final DateTime? end;
}

// ============================================================
// نافذة الرصيد الافتتاحي
// ============================================================

class _OpeningResult {
  const _OpeningResult({required this.cash, required this.bank});

  final double cash;
  final double bank;
}

class _OpeningBalanceDialog extends StatefulWidget {
  const _OpeningBalanceDialog({
    required this.opening,
    this.scope = AccountingScope.none,
  });

  final OpeningBalance opening;
  final AccountingScope scope;

  @override
  State<_OpeningBalanceDialog> createState() => _OpeningBalanceDialogState();
}

class _OpeningBalanceDialogState extends State<_OpeningBalanceDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _cashController;
  late final TextEditingController _bankController;

  @override
  void initState() {
    super.initState();
    _cashController = TextEditingController(
      text: _amountText(widget.opening.cash),
    );
    _bankController = TextEditingController(
      text: _amountText(widget.opening.bank),
    );
  }

  String _amountText(double value) {
    if (value == 0) return '';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _cashController.dispose();
    _bankController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(
      context,
      _OpeningResult(
        cash: parseAmount(_cashController.text),
        bank: parseAmount(_bankController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('الرصيد الافتتاحي'),
        content: SizedBox(
          width: 480,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  widget.scope.isScoped
                      ? 'رصيد صندوق وبنك مشروع ${widget.scope.label} قبل '
                          'أول حركة مسجّلة له. أدخله مرة واحدة، وعدّله إذا '
                          'احتجت تصحيحًا.'
                      : 'رصيد الصندوق والبنك قبل أول حركة مسجّلة في النظام. '
                          'أدخله مرة واحدة، وعدّله إذا احتجت تصحيحًا.',
                  style: AppTextStyles.bodySecondary,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _cashController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    labelText: 'رصيد الصندوق النقدي',
                    suffixText: 'ريال',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) return null;
                    if (parseAmount(value) < 0) {
                      return 'أدخل مبلغًا غير سالب';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bankController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    labelText: 'رصيد البنك',
                    suffixText: 'ريال',
                    prefixIcon: Icon(Icons.account_balance_outlined),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) return null;
                    if (parseAmount(value) < 0) {
                      return 'أدخل مبلغًا غير سالب';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.save_outlined),
            label: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

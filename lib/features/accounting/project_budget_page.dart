import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';
import 'accounting_format.dart';
import 'accounting_models.dart';
import 'accounting_project_field.dart';
import 'accounting_service.dart';
import 'accounting_widgets.dart';
import 'project_budget.dart';

// ============================================================
// ميزانية المشاريع — أصول وخصوم وإيرادات ومصروفات
// ============================================================
//
// الشاشة تعرض:
//   • جدول «ميزانية كل مشروع»: أصول، خصوم، حقوق ملكية، إيرادات،
//     مصروفات، صافي نتيجة، وحالة التوازن لكل مشروع.
//   • تفاصيل ميزانية المشروع المختار: كل قسم وحساباته وما يشمله.
//   • معادلة الميزانية: الأصول = الخصوم + حقوق الملكية.
//
// كل الأرقام مشتقة من قيود اليومية (بما فيها قيود السندات) ومن
// الأرصدة الافتتاحية `finance_settings/opening_<projectId>`،
// فلا يوجد إدخال مكرر في هذه الشاشة.
// ============================================================

class ProjectBudgetPage extends StatefulWidget {
  const ProjectBudgetPage({
    super.key,
    this.scope = AccountingScope.none,
  });

  /// مشروع المحاسب: ميزانية هذا المشروع فقط.
  final AccountingScope scope;

  @override
  State<ProjectBudgetPage> createState() => _ProjectBudgetPageState();
}

class _ProjectBudgetPageState extends State<ProjectBudgetPage> {
  static const String _allProjectsKey = '__all_projects__';

  final AccountingService _service = AccountingService();
  final GlobalKey _detailsKey = GlobalKey();

  late Future<_BudgetData> _future;
  late String _selected;
  _BudgetPeriod _period = _BudgetPeriod.all;

  bool get _isScoped => widget.scope.isScoped;

  @override
  void initState() {
    super.initState();
    _selected = _isScoped ? widget.scope.projectId : _allProjectsKey;
    _future = _load();
  }

  Future<_BudgetData> _load() async {
    final String scopeId = widget.scope.projectId.trim();
    final AccountingSnapshot snapshot =
        await _service.loadSnapshot(projectId: scopeId);

    final Map<String, OpeningBalance> openings =
        <String, OpeningBalance>{};

    if (scopeId.isNotEmpty) {
      // المحاسب المربوط: رصيد مشروعه فقط.
      openings[scopeId] = snapshot.opening;
    } else {
      try {
        openings.addAll(await _service.loadOpeningBalances());
      } catch (_) {
        // نكمل برصيد الوحدة من لقطة القيود.
      }
      openings.putIfAbsent('', () => snapshot.opening);
    }

    List<AccountingProjectOption> projects =
        const <AccountingProjectOption>[];
    try {
      projects = await loadAccountingProjects();
    } catch (_) {
      // قائمة المشاريع مساعدة للعرض؛ القيود تحمل اسم كل مشروع.
    }

    return _BudgetData(
      snapshot: snapshot,
      openings: openings,
      projects: projects,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  void _selectProject(String projectId) {
    if (_selected != projectId) {
      setState(() {
        _selected = projectId;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? detailsContext = _detailsKey.currentContext;
      if (detailsContext == null) return;

      Scrollable.ensureVisible(
        detailsContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        alignment: 0.03,
      );
    });
  }

  DateTime? _asOf() {
    final DateTime now = DateTime.now();

    switch (_period) {
      case _BudgetPeriod.all:
        return null;
      case _BudgetPeriod.thisMonth:
        return endOfMonth(now);
      case _BudgetPeriod.lastMonth:
        return endOfMonth(DateTime(now.year, now.month - 1, 1));
      case _BudgetPeriod.thisYear:
        return endOfYear(now);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'ميزانية المشاريع',
      actions: <Widget>[
        IconButton(
          tooltip: 'تحديث',
          icon: const Icon(Icons.refresh),
          onPressed: _reload,
        ),
      ],
      child: FutureBuilder<_BudgetData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppError(
              message: 'تعذر تحميل ميزانية المشاريع:\n${snapshot.error}',
              onRetry: _reload,
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const AppLoading(
              message: 'جاري حساب ميزانية المشاريع...',
            );
          }

          final _BudgetData data = snapshot.data ?? const _BudgetData.empty();

          final DateTime? asOf = _asOf();

          final List<BudgetProjectRef> refs = _isScoped
              ? <BudgetProjectRef>[
                  BudgetProjectRef(
                    id: widget.scope.projectId,
                    code: widget.scope.projectCode,
                    name: widget.scope.projectName,
                  ),
                ]
              : data.projects
                  .map(
                    (project) => BudgetProjectRef(
                      id: project.id,
                      code: project.code,
                      name: project.name,
                    ),
                  )
                  .toList();

          final List<ProjectBudget> budgets = buildProjectBudgets(
            entries: data.snapshot.entries,
            openings: data.openings,
            projects: refs,
            asOf: asOf,
          );

          final ProjectBudget total = _isScoped && budgets.isNotEmpty
              ? budgets.first
              : buildTotalProjectBudget(
                  entries: data.snapshot.entries,
                  openings: data.openings,
                  asOf: asOf,
                );

          ProjectBudget selected = total;
          String selectedKey = _allProjectsKey;

          if (!_isScoped && _selected != _allProjectsKey) {
            for (final ProjectBudget budget in budgets) {
              if (budget.projectId == _selected) {
                selected = budget;
                selectedKey = _selected;
                break;
              }
            }
          }

          final bool noData = budgets.isEmpty && total.isEmpty;

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
                  title: 'ميزانية المشاريع',
                  subtitle: _isScoped
                      ? 'ميزانية مشروع ${widget.scope.label}: الأصول '
                          'والخصوم وحقوق الملكية والإيرادات والمصروفات، '
                          'وما يشمله كل قسم — مشتقة من قيود المشروع '
                          'ورصيده الافتتاحي.'
                      : 'ميزانية كل مشروع من الأصول والخصوم وحقوق الملكية '
                          'والإيرادات والمصروفات، وما يشمله كل قسم — '
                          'مشتقة من القيود اليومية والأرصدة الافتتاحية.',
                  icon: Icons.pie_chart_outline,
                  trailing: AccountingBadge(
                    label: _isScoped ? widget.scope.label : 'كل المشاريع',
                    color: AppColors.financialManager,
                    icon: Icons.apartment_outlined,
                  ),
                ),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _BudgetPeriod.values.map((period) {
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: ChoiceChip(
                          label: Text(period.label),
                          selected: _period == period,
                          onSelected: (_) {
                            setState(() => _period = period);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 6),
                Text(
                  _period == _BudgetPeriod.all
                      ? 'كل الأرصدة حتى تاريخه، ولا تُستبعد أي قيود.'
                      : '${_period.description}؛ تُحتسب القيود حتى نهاية '
                          'الفترة فقط.',
                  style: AppTextStyles.small,
                ),

                const SizedBox(height: 16),

                if (noData) ...<Widget>[
                  AppCard(
                    child: AccountingEmptyState(
                      title: 'لا توجد بيانات مالية بعد',
                      message: 'سجّل سندات القبض والصرف أو القيود اليدوية، '
                          'وأدخل الرصيد الافتتاحي؛ ستُبنى ميزانية كل مشروع '
                          'تلقائيًا هنا.',
                      icon: Icons.pie_chart_outline,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                if (!_isScoped) ...<Widget>[
                  AppSectionTitle(
                    title: 'ميزانية كل مشروع',
                    subtitle: 'اضغط على المشروع لعرض تفاصيل أقسامه '
                        'وحساباته في الأسفل.',
                    icon: Icons.apartment_outlined,
                  ),
                  AppCard(
                    padding: const EdgeInsets.all(8),
                    child: _BudgetComparisonTable(
                      budgets: budgets,
                      total: total,
                      selectedId: selectedKey,
                      allKey: _allProjectsKey,
                      onSelect: _selectProject,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                AppSectionTitle(
                  key: _detailsKey,
                  title: 'تفاصيل ميزانية: ${selected.label}',
                  subtitle: selected.isTotal
                      ? 'إجمالي كل المشاريع في ميزانية واحدة — اختر '
                          'مشروعًا من الجدول أعلاه لعرض ميزانيته وحده.'
                      : 'عدد القيود الداخلة في الحساب: '
                          '${selected.entriesCount} — '
                          '${_period == _BudgetPeriod.all ? 'كل الفترات' : 'حتى نهاية الفترة'}',
                  icon: Icons.account_balance_outlined,
                  trailing: AccountingBadge(
                    label: selected.isBalanced
                        ? 'متوازنة'
                        : 'فرق ${formatMoney(selected.difference, decimals: 0)}',
                    color: selected.isBalanced
                        ? AppColors.success
                        : AppColors.warning,
                    icon: selected.isBalanced
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                  ),
                ),

                if (!_isScoped) ...<Widget>[
                  AppDropdown<String>(
                    key: ValueKey<String>('budget-project-$selectedKey'),
                    label: 'المشروع المعروض',
                    value: selectedKey,
                    prefixIcon: Icons.apartment_outlined,
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: _allProjectsKey,
                        child: Text('كل المشاريع (الإجمالي)'),
                      ),
                      ...budgets.map((budget) {
                        return DropdownMenuItem<String>(
                          value: budget.projectId,
                          child: Text(
                            budget.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      if (value != null) _selectProject(value);
                    },
                  ),
                  const SizedBox(height: 14),
                ],

                LayoutBuilder(
                  builder: (context, constraints) {
                    final double width = constraints.maxWidth > 760
                        ? (constraints.maxWidth - 20) / 3
                        : (constraints.maxWidth - 10) / 2;

                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'الأصول',
                            value: formatMoney(
                              selected.totalAssets,
                              decimals: 0,
                            ),
                            icon: Icons.account_balance_wallet_outlined,
                            color: AppColors.primary,
                            subtitle: 'ما يملكه المشروع',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'الخصوم',
                            value: formatMoney(
                              selected.totalLiabilities,
                              decimals: 0,
                            ),
                            icon: Icons.request_quote_outlined,
                            color: AppColors.warning,
                            subtitle: 'التزامات على المشروع',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'حقوق الملكية',
                            value: formatMoney(
                              selected.totalEquity,
                              decimals: 0,
                            ),
                            icon: Icons.pie_chart_outline,
                            color: AppColors.info,
                            subtitle: 'مع الأرصدة والنتيجة',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'الإيرادات',
                            value: formatMoney(
                              selected.totalRevenues,
                              decimals: 0,
                            ),
                            icon: Icons.trending_up,
                            color: AppColors.success,
                            subtitle: 'إيرادات المشروع',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'المصروفات',
                            value: formatMoney(
                              selected.totalExpenses,
                              decimals: 0,
                            ),
                            icon: Icons.trending_down,
                            color: AppColors.danger,
                            subtitle: 'مصروفات المشروع',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'صافي النتيجة',
                            value: formatMoney(
                              selected.netResult,
                              decimals: 0,
                            ),
                            icon: selected.netResult >= 0
                                ? Icons.savings_outlined
                                : Icons.trending_down,
                            color: selected.netResult >= 0
                                ? AppColors.success
                                : AppColors.danger,
                            subtitle: 'إيرادات − مصروفات',
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 14),
                _balanceEquationCard(selected),

                if (!selected.isBalanced) ...<Widget>[
                  const SizedBox(height: 10),
                  AppCard(
                    color: AppColors.warning.withValues(alpha: 0.06),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(
                          Icons.info_outline,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'فرق الميزانية ${formatMoney(selected.difference, decimals: 0)} '
                            'ريال. راجع القيود القديمة غير المتوازنة أو '
                            'الحسابات التي لا تتبع دليل الحسابات؛ فكل قيد '
                            'متوازن يحافظ على توازن الميزانية.',
                            style: AppTextStyles.bodySecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                for (final FinanceAccountKind kind in <FinanceAccountKind>[
                  FinanceAccountKind.asset,
                  FinanceAccountKind.liability,
                  FinanceAccountKind.equity,
                  FinanceAccountKind.revenue,
                  FinanceAccountKind.expense,
                ])
                  _BudgetSectionCard(budget: selected, kind: kind),

                const SizedBox(height: 6),
                _sectionsGuide(),

                const SizedBox(height: 14),

                Text(
                  'ملاحظة: الميزانية مشتقة من قيود اليومية (بما فيها '
                  'قيود السندات) والأرصدة الافتتاحية، وتُحدَّث تلقائيًا '
                  'مع كل سند أو قيد جديد. الأرصدة الافتتاحية تظهر ضمن '
                  'حقوق الملكية، وصافي النتيجة (إيرادات − مصروفات) '
                  'يُضاف إلى حقوق الملكية حتى تتحقق معادلة الميزانية.',
                  style: AppTextStyles.small,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _balanceEquationCard(ProjectBudget budget) {
    final Color color =
        budget.isBalanced ? AppColors.success : AppColors.warning;

    return AppCard(
      color: color.withValues(alpha: 0.06),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.balance, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'معادلة الميزانية',
                    style: AppTextStyles.cardTitle,
                  ),
                ),
                AccountingBadge(
                  label: budget.isBalanced
                      ? 'متوازنة'
                      : 'فرق ${formatMoney(budget.difference, decimals: 0)}',
                  color: color,
                  icon: budget.isBalanced
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'الأصول = الخصوم + حقوق الملكية',
              style: AppTextStyles.bodySecondary,
            ),
            const SizedBox(height: 4),
            Text(
              '${formatMoney(budget.totalAssets, decimals: 0)} = '
              '${formatMoney(budget.totalLiabilities, decimals: 0)} + '
              '${formatMoney(budget.totalEquity, decimals: 0)}',
              style: AppTextStyles.cardTitle.copyWith(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'حقوق الملكية = حسابات حقوق الملكية + الأرصدة الافتتاحية '
              '+ صافي نتيجة الفترة (إيرادات − مصروفات).',
              style: AppTextStyles.small,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionsGuide() {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.info_outline,
                  color: AppColors.info,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ماذا يشمل كل قسم؟',
                    style: AppTextStyles.cardTitle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final FinanceAccountKind kind in FinanceAccountKind.values)
              _guideRow(kind),
          ],
        ),
      ),
    );
  }

  Widget _guideRow(FinanceAccountKind kind) {
    final List<FinanceAccount> accounts = financeAccountsOfKind(kind);
    final List<String> names = accounts
        .map((account) => '${account.name} (${account.code})')
        .toList();

    if (kind == FinanceAccountKind.equity) {
      names.add('الأرصدة الافتتاحية');
      names.add('صافي نتيجة الفترة');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(_sectionIcon(kind), size: 18, color: _sectionColor(kind)),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: Text(
              budgetSectionLabel(kind),
              style: AppTextStyles.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              names.join('، '),
              style: AppTextStyles.small,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// جدول ميزانية كل المشاريع
// ============================================================

class _BudgetComparisonTable extends StatelessWidget {
  const _BudgetComparisonTable({
    required this.budgets,
    required this.total,
    required this.selectedId,
    required this.allKey,
    required this.onSelect,
  });

  final List<ProjectBudget> budgets;
  final ProjectBudget total;
  final String selectedId;
  final String allKey;
  final ValueChanged<String> onSelect;

  static const double _projectWidth = 180;
  static const double _amountWidth = 102;
  static const double _statusWidth = 84;
  static const double _actionWidth = 70;

  // + 16 للحشو الأفقي (8 يمينًا و8 يسارًا) في صفوف الجدول.
  static const double _tableWidth = _projectWidth +
      _amountWidth * 6 +
      _statusWidth +
      _actionWidth +
      16;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _tableWidth,
          child: Column(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  children: <Widget>[
                    const SizedBox(
                      width: _projectWidth,
                      child: Text(
                        'المشروع',
                        style: _headerStyle,
                      ),
                    ),
                    _header('الأصول'),
                    _header('الخصوم'),
                    _header('حقوق الملكية'),
                    _header('الإيرادات'),
                    _header('المصروفات'),
                    _header('صافي النتيجة'),
                    const SizedBox(
                      width: _statusWidth,
                      child: Text(
                        'التوازن',
                        style: _headerStyle,
                      ),
                    ),
                    const SizedBox(width: _actionWidth),
                  ],
                ),
              ),
              if (budgets.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'لا توجد مشاريع أو حركات مالية بعد',
                    style: AppTextStyles.bodySecondary,
                  ),
                )
              else
                for (final ProjectBudget budget in budgets)
                  _row(budget),
              _totalRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String title) {
    return SizedBox(
      width: _amountWidth,
      child: Text(
        title,
        textAlign: TextAlign.end,
        style: _headerStyle,
      ),
    );
  }

  Widget _row(ProjectBudget budget) {
    final bool selected =
        budget.projectId == selectedId && !budget.isTotal;

    return InkWell(
      onTap: () => onSelect(budget.projectId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : null,
          border: Border(
            bottom: BorderSide(
              color: AppColors.border.withValues(alpha: 0.7),
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: _projectWidth,
              child: Text(
                budget.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ),
            _amount(budget.totalAssets),
            _amount(budget.totalLiabilities),
            _amount(budget.totalEquity),
            _amount(
              budget.totalRevenues,
              color: AppColors.success,
            ),
            _amount(
              budget.totalExpenses,
              color: AppColors.danger,
            ),
            _amount(
              budget.netResult,
              color: budget.netResult >= 0
                  ? AppColors.success
                  : AppColors.danger,
              bold: true,
            ),
            SizedBox(
              width: _statusWidth,
              child: Tooltip(
                message: budget.isBalanced
                    ? 'الأصول = الخصوم + حقوق الملكية'
                    : 'فرق الميزانية ${formatMoney(budget.difference, decimals: 0)}',
                child: Row(
                  children: <Widget>[
                    Icon(
                      budget.isBalanced
                          ? Icons.check_circle
                          : Icons.warning_amber_rounded,
                      size: 15,
                      color: budget.isBalanced
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        budget.isBalanced ? 'متوازن' : 'فرق',
                        style: AppTextStyles.small.copyWith(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: _actionWidth,
              child: TextButton(
                onPressed: () => onSelect(budget.projectId),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(60, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'تفاصيل',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow() {
    final bool selected = selectedId == allKey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.06)
            : AppColors.primary.withValues(alpha: 0.03),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(9),
        ),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: _projectWidth,
            child: Text(
              'الإجمالي',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryDark,
              ),
            ),
          ),
          _amount(total.totalAssets, bold: true),
          _amount(total.totalLiabilities, bold: true),
          _amount(total.totalEquity, bold: true),
          _amount(total.totalRevenues, bold: true),
          _amount(total.totalExpenses, bold: true),
          _amount(
            total.netResult,
            color: total.netResult >= 0
                ? AppColors.success
                : AppColors.danger,
            bold: true,
          ),
          SizedBox(
            width: _statusWidth,
            child: Icon(
              total.isBalanced
                  ? Icons.check_circle
                  : Icons.warning_amber_rounded,
              size: 15,
              color: total.isBalanced
                  ? AppColors.success
                  : AppColors.warning,
            ),
          ),
          SizedBox(
            width: _actionWidth,
            child: TextButton(
              onPressed: () => onSelect(allKey),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(60, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'تفاصيل',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amount(
    double value, {
    Color? color,
    bool bold = false,
  }) {
    return SizedBox(
      width: _amountWidth,
      child: Text(
        formatMoney(value, decimals: 0),
        textAlign: TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          color: color ??
              (value < 0 ? AppColors.danger : AppColors.textPrimary),
        ),
      ),
    );
  }
}

const TextStyle _headerStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.bold,
  color: AppColors.primaryDark,
);

// ============================================================
// بطاقة قسم من أقسام الميزانية
// ============================================================

class _BudgetSectionCard extends StatelessWidget {
  const _BudgetSectionCard({
    required this.budget,
    required this.kind,
  });

  final ProjectBudget budget;
  final FinanceAccountKind kind;

  @override
  Widget build(BuildContext context) {
    final BudgetSection section = budget.sectionOf(kind);
    final List<BudgetAccountLine> lines = section.activeLines;
    final Color color = _sectionColor(kind);
    final List<String> includes = financeAccountsOfKind(kind)
        .map((account) => '${account.name} (${account.code})')
        .toList();

    if (kind == FinanceAccountKind.equity) {
      includes.add('الأرصدة الافتتاحية');
      includes.add('صافي نتيجة الفترة');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      _sectionIcon(kind),
                      size: 20,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          budgetSectionLabel(kind),
                          style: AppTextStyles.cardTitle,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _sectionDescription(kind),
                          style: AppTextStyles.small,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AccountingBadge(
                    label: formatMoney(section.total, decimals: 0),
                    color: color,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  'يشمل: ${includes.join('، ')}',
                  style: AppTextStyles.small,
                ),
              ),

              const SizedBox(height: 6),

              if (lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'لا توجد حركات على حسابات هذا القسم بعد.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySecondary,
                  ),
                )
              else ...<Widget>[
                const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'الحساب',
                          style: _headerStyle,
                        ),
                      ),
                      SizedBox(
                        width: 116,
                        child: Text(
                          'الرصيد',
                          textAlign: TextAlign.end,
                          style: _headerStyle,
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          'النسبة',
                          textAlign: TextAlign.end,
                          style: _headerStyle,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final BudgetAccountLine line in lines)
                  _BudgetLineRow(
                    line: line,
                    sectionTotal: section.total,
                    color: color,
                  ),
              ],

              const Divider(height: 18),

              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'إجمالي ${budgetSectionLabel(kind)}',
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    formatMoney(section.total, decimals: 0),
                    style: AppTextStyles.cardTitle.copyWith(
                      fontSize: 15,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetLineRow extends StatelessWidget {
  const _BudgetLineRow({
    required this.line,
    required this.sectionTotal,
    required this.color,
  });

  final BudgetAccountLine line;
  final double sectionTotal;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double share = sectionTotal.abs() < 0.005
        ? 0
        : (line.amount / sectionTotal) * 100;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (line.derived) ...<Widget>[
                      const Icon(
                        Icons.auto_awesome,
                        size: 13,
                        color: AppColors.info,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        line.name,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 12.5,
                          fontWeight: line.derived
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: line.derived
                              ? AppColors.info
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (line.code.isNotEmpty)
                  Text(
                    line.code,
                    style: AppTextStyles.small.copyWith(fontSize: 11),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 116,
            child: Text(
              formatMoney(line.amount, decimals: 0),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: line.amount < 0 ? AppColors.danger : color,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${share.toStringAsFixed(0)}%',
              textAlign: TextAlign.end,
              style: AppTextStyles.small.copyWith(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// عناوين الأقسام وألوانها
// ============================================================

Color _sectionColor(FinanceAccountKind kind) {
  switch (kind) {
    case FinanceAccountKind.asset:
      return AppColors.primary;
    case FinanceAccountKind.liability:
      return AppColors.warning;
    case FinanceAccountKind.equity:
      return AppColors.info;
    case FinanceAccountKind.revenue:
      return AppColors.success;
    case FinanceAccountKind.expense:
      return AppColors.danger;
  }
}

IconData _sectionIcon(FinanceAccountKind kind) {
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

String _sectionDescription(FinanceAccountKind kind) {
  switch (kind) {
    case FinanceAccountKind.asset:
      return 'ما يملكه المشروع: النقد في الصندوق والبنك، والذمم '
          'المدينة والمستخلصات المستحقة.';
    case FinanceAccountKind.liability:
      return 'ما على المشروع من التزامات للغير: الموردون والذمم '
          'الدائنة، ومستحقات الرواتب والعمالة.';
    case FinanceAccountKind.equity:
      return 'حق أصحاب المشروع: تمويل واعتمادات المشاريع، والأرصدة '
          'الافتتاحية، وصافي نتيجة الفترة.';
    case FinanceAccountKind.revenue:
      return 'ما اكتسبه المشروع: إيرادات المشاريع والإيرادات الأخرى.';
    case FinanceAccountKind.expense:
      return 'ما أنفقه المشروع: المواد، والعمالة والمقاولون، والمعدات، '
          'والمحروقات، والورشة، والمصروفات الإدارية، ومستخلصات '
          'المقاولين.';
  }
}

// ============================================================
// الفترات ونموذج البيانات
// ============================================================

enum _BudgetPeriod {
  all('كل الفترات', 'كل الأرصدة حتى تاريخه'),
  thisYear('هذه السنة', 'أرصدة حتى نهاية هذه السنة'),
  thisMonth('هذا الشهر', 'أرصدة حتى نهاية هذا الشهر'),
  lastMonth('الشهر الماضي', 'أرصدة حتى نهاية الشهر الماضي');

  const _BudgetPeriod(this.label, this.description);

  final String label;
  final String description;
}

class _BudgetData {
  const _BudgetData({
    required this.snapshot,
    required this.openings,
    required this.projects,
  });

  const _BudgetData.empty()
      : snapshot = const AccountingSnapshot(
          vouchers: <Voucher>[],
          entries: <JournalEntry>[],
          opening: OpeningBalance(),
          movements: <CashMovement>[],
        ),
        openings = const <String, OpeningBalance>{},
        projects = const <AccountingProjectOption>[];

  final AccountingSnapshot snapshot;
  final Map<String, OpeningBalance> openings;
  final List<AccountingProjectOption> projects;
}

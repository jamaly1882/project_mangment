import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';
import '../admin/department_users_page.dart';
import 'accounting_format.dart';
import 'accounting_models.dart';
import 'accounting_reports_page.dart';
import 'accounting_service.dart';
import 'accounting_widgets.dart';
import 'cash_box_page.dart';
import 'chart_of_accounts_page.dart';
import 'journal_entries_page.dart';
import 'project_budget_page.dart';
import 'voucher_form_page.dart';
import 'vouchers_page.dart';

// ============================================================
// لوحة الإدارة المالية — المدير المالي والمحاسب
// ============================================================
//
// • المدير المالي (financial_manager):
//   - ينشئ حساب المحاسب (DepartmentUsersPage) من قسم
//     «مستخدمو الإدارة المالية».
//   - يتابع السندات والصندوق والقيود والتقارير في وضع إشراف
//     (عرض فقط) — الإدخال مسؤولية المحاسب.
//
// • المحاسب (project_accountant، ومعه الحساب القديم
//   accountant / accounts_manager بعد التطبيع):
//   - مسؤول عن كل أعمال الوحدة: سندات القبض والصرف، الصندوق،
//     والقيود اليومية والتقارير.
//
// الرصيد والأرقام كلها مشتقّة من نفس مصدر البيانات:
// vouchers + journal_entries + finance_settings/opening.
// ============================================================

class AccountingDashboardPage extends StatefulWidget {
  const AccountingDashboardPage({
    super.key,
    this.scope = AccountingScope.none,
  });

  /// مشروع المحاسب (فارغ = كل مشاريع الوحدة).
  ///
  /// المدير المالي يفتحها بلا نطاق (إشراف شامل)، والمحاسب تُمرَّر
  /// له وثيقته فيُقيَّد كل شيء بمشروعه.
  final AccountingScope scope;

  @override
  State<AccountingDashboardPage> createState() =>
      _AccountingDashboardPageState();
}

class _AccountingDashboardPageState extends State<AccountingDashboardPage> {
  final AccountingService _service = AccountingService();

  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_DashboardData> _load() async {
    final AccountingSnapshot snapshot =
        await _service.loadSnapshot(projectId: widget.scope.projectId);

    String role = '';
    String userName = '';
    final User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        final DocumentSnapshot<Map<String, dynamic>> doc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
        final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};

        role = AppRoles.normalize(data['role']?.toString());
        userName = (data['name'] ?? '').toString().trim();
      } catch (_) {
        // نكمل ببيانات حساب الدخول.
      }
    }

    if (userName.isEmpty) {
      userName = (user?.displayName ?? '').trim();
    }

    final bool isFinanceManager = role == AppRoles.financialManager;
    final bool canEdit = role == AppRoles.projectAccountant;

    List<_AccountantInfo> accountants = const <_AccountantInfo>[];

    if (isFinanceManager) {
      try {
        final QuerySnapshot<Map<String, dynamic>> users =
            await FirebaseFirestore.instance.collection('users').get();

        accountants = users.docs
            .where((doc) {
              return AppRoles.normalize(doc.data()['role']?.toString()) ==
                  AppRoles.projectAccountant;
            })
            .map((doc) {
              final Map<String, dynamic> data = doc.data();
              final AccountingScope scope = AccountingScope.fromUserData(data);

              return _AccountantInfo(
                name: (data['name'] ?? '').toString().trim(),
                username: (data['username'] ?? '').toString().trim(),
                active: data['active'] != false,
                project: scope.label,
                hasProject: scope.isScoped,
              );
            })
            .toList();
      } catch (_) {
        // القائمة اختيارية للعرض.
      }
    }

    return _DashboardData(
      snapshot: snapshot,
      role: role,
      userName: userName,
      isFinanceManager: isFinanceManager,
      canEdit: canEdit,
      accountants: accountants,
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => page),
    );

    if (!mounted) return;
    _reload();
  }

  Future<void> _openAccountants() async {
    await _open(
      DepartmentUsersPage(
        title: 'مستخدمو الإدارة المالية',
        subtitle:
            'المدير المالي ينشئ حساب المحاسب ويحدد له مشروعه (أو يتركه '
            'لكل المشاريع). المحاسب مسؤول عن سندات الصرف والقبض '
            'والصندوق والقيود اليومية في حدود مشروعه.',
        roles: AppRoles.creatableBy(AppRoles.financialManager),
      ),
    );
  }

  Future<void> _openVoucherForm(VoucherKind kind) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VoucherFormPage(
          kind: kind,
          scope: widget.scope,
        ),
      ),
    );

    if (saved == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'الإدارة المالية',
      actions: <Widget>[
        IconButton(
          tooltip: 'تحديث',
          icon: const Icon(Icons.refresh),
          onPressed: _reload,
        ),
        IconButton(
          tooltip: 'تسجيل الخروج',
          icon: const Icon(Icons.logout),
          onPressed: _logout,
        ),
      ],
      child: FutureBuilder<_DashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppError(
              message: 'تعذر تحميل لوحة الإدارة المالية:\n${snapshot.error}',
              onRetry: _reload,
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const AppLoading(
              message: 'جاري تحميل الحسابات والصندوق...',
            );
          }

          final _DashboardData data = snapshot.data!;

          final List<Voucher> vouchers = data.snapshot.vouchers;
          final List<JournalEntry> entries = data.snapshot.entries;
          final OpeningBalance opening = data.snapshot.opening;
          final List<CashMovement> movements = data.snapshot.movements;

          final double cashBalance = FinanceMath.balance(
            opening: opening,
            movements: movements,
            filter: MoneyBoxFilter.cash,
          );
          final double bankBalance = FinanceMath.balance(
            opening: opening,
            movements: movements,
            filter: MoneyBoxFilter.bank,
          );

          final DateTime now = DateTime.now();
          final List<Voucher> monthVouchers = filterVouchers(
            vouchers,
            start: startOfMonth(now),
            end: endOfMonth(now),
          );
          final double monthReceipts =
              sumVouchers(monthVouchers, VoucherKind.receipt);
          final double monthPayments =
              sumVouchers(monthVouchers, VoucherKind.payment);

          final List<Voucher> receipts =
              vouchers.where((v) => v.isReceipt).toList();
          final List<Voucher> payments =
              vouchers.where((v) => v.isPayment).toList();

          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              children: <Widget>[
                _header(data),

                if (data.canEdit) ...<Widget>[
                  const SizedBox(height: 12),
                  _projectScopeCard(),
                ],

                const SizedBox(height: 16),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final double width = constraints.maxWidth > 760
                        ? (constraints.maxWidth - 30) / 4
                        : (constraints.maxWidth - 10) / 2;

                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'رصيد الصندوق',
                            value: formatMoney(cashBalance, decimals: 0),
                            icon: Icons.savings_outlined,
                            color: cashBalance >= 0
                                ? AppColors.primary
                                : AppColors.danger,
                            subtitle: 'الصندوق النقدي',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'رصيد البنك',
                            value: formatMoney(bankBalance, decimals: 0),
                            icon: Icons.account_balance_outlined,
                            color: AppColors.info,
                            subtitle: 'بنك وشيكات',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'قبض هذا الشهر',
                            value: formatMoney(monthReceipts, decimals: 0),
                            icon: Icons.south_west,
                            color: AppColors.success,
                            subtitle: '${monthVouchers.where((v) => v.isReceipt).length} سند',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: AccountingMetricCard(
                            title: 'صرف هذا الشهر',
                            value: formatMoney(monthPayments, decimals: 0),
                            icon: Icons.north_east,
                            color: AppColors.danger,
                            subtitle: '${monthVouchers.where((v) => v.isPayment).length} سند',
                          ),
                        ),
                      ],
                    );
                  },
                ),

                if (data.isFinanceManager) ...<Widget>[
                  const SizedBox(height: 20),
                  const AppSectionTitle(
                    title: 'مستخدمو الإدارة المالية',
                    subtitle:
                        'أنت من ينشئ حساب المحاسب ويحدد مشروعه؛ وبعده '
                        'يتولى المحاسب سندات وصندوق وقيود ذلك المشروع.',
                    icon: Icons.group,
                  ),
                  AppManagementCard(
                    title: data.accountants.isEmpty
                        ? 'إنشاء حساب المحاسب'
                        : 'المحاسبون (${data.accountants.length})',
                    subtitle: data.accountants.isEmpty
                        ? 'لا يوجد محاسب بعد. أنشئ حسابه ليبدأ العمل على '
                            'سندات الصرف والقبض والصندوق والقيود.'
                        : data.accountants
                            .map((accountant) => accountant.name.isEmpty
                                ? accountant.username
                                : accountant.name)
                            .join('، '),
                    icon: Icons.person_add_alt_1,
                    color: AppColors.projectAccountant,
                    onTap: _openAccountants,
                  ),
                  if (data.accountants.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: data.accountants.map((accountant) {
                          final String name = accountant.name.isEmpty
                              ? accountant.username
                              : accountant.name;
                          final String label = accountant.hasProject
                              ? '$name — ${accountant.project}'
                              : '$name — كل المشاريع';
                          return AccountingBadge(
                            label: accountant.active
                                ? label
                                : '$label (معطّل)',
                            color: accountant.active
                                ? AppColors.success
                                : AppColors.textSecondary,
                            icon: Icons.person_outline,
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 8),
                  AppCard(
                    color: AppColors.info.withValues(alpha: 0.06),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(
                          Icons.visibility_outlined,
                          color: AppColors.info,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'أنت في وضع الإشراف: تعرض السندات والصندوق '
                            'والقيود والتقارير، والإنشاء والتعديل من حساب '
                            'المحاسب.',
                            style: AppTextStyles.bodySecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (data.canEdit) ...<Widget>[
                  const SizedBox(height: 20),
                  const AppSectionTitle(
                    title: 'إجراءات سريعة',
                    icon: Icons.bolt_outlined,
                  ),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: AppButton(
                          text: 'سند قبض',
                          icon: Icons.south_west,
                          onPressed: () =>
                              _openVoucherForm(VoucherKind.receipt),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppButton(
                          text: 'سند صرف',
                          icon: Icons.north_east,
                          onPressed: () =>
                              _openVoucherForm(VoucherKind.payment),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 20),

                const AppSectionTitle(
                  title: 'العمليات المحاسبية',
                  subtitle: 'كل ما هو مسؤول عنه المحاسب في الوحدة',
                  icon: Icons.account_balance_wallet_outlined,
                ),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final double width = constraints.maxWidth > 760
                        ? (constraints.maxWidth - 30) / 3
                        : (constraints.maxWidth - 10) / 2;

                    final List<Widget> cards = <Widget>[
                      AppManagementCard(
                        title: VoucherKind.receipt.plural,
                        subtitle:
                            '${receipts.length} سند — ${formatMoney(sumVouchers(receipts, VoucherKind.receipt), decimals: 0)} ريال',
                        icon: Icons.south_west,
                        color: AppColors.success,
                        onTap: () => _open(
                          VouchersPage(
                            kind: VoucherKind.receipt,
                            canEdit: data.canEdit,
                            scope: widget.scope,
                          ),
                        ),
                      ),
                      AppManagementCard(
                        title: VoucherKind.payment.plural,
                        subtitle:
                            '${payments.length} سند — ${formatMoney(sumVouchers(payments, VoucherKind.payment), decimals: 0)} ريال',
                        icon: Icons.north_east,
                        color: AppColors.danger,
                        onTap: () => _open(
                          VouchersPage(
                            kind: VoucherKind.payment,
                            canEdit: data.canEdit,
                            scope: widget.scope,
                          ),
                        ),
                      ),
                      AppManagementCard(
                        title: 'الصندوق',
                        subtitle:
                            'الرصيد ${formatMoney(cashBalance, decimals: 0)} ريال',
                        icon: Icons.account_balance_wallet,
                        color: AppColors.primary,
                        onTap: () => _open(
                          CashBoxPage(
                            canEdit: data.canEdit,
                            scope: widget.scope,
                          ),
                        ),
                      ),
                      AppManagementCard(
                        title: 'القيود اليومية',
                        subtitle:
                            '${entries.length} قيد — تشمل قيود السندات',
                        icon: Icons.menu_book_outlined,
                        color: AppColors.primaryDark,
                        onTap: () => _open(
                          JournalEntriesPage(
                            canEdit: data.canEdit,
                            scope: widget.scope,
                          ),
                        ),
                      ),
                      AppManagementCard(
                        title: 'ميزانية المشاريع',
                        subtitle:
                            'أصول وخصوم وإيرادات ومصروفات كل مشروع، '
                            'وما يشمله كل قسم',
                        icon: Icons.pie_chart_outline,
                        color: AppColors.financialManager,
                        onTap: () => _open(
                          ProjectBudgetPage(scope: widget.scope),
                        ),
                      ),
                      AppManagementCard(
                        title: 'التقارير المالية',
                        subtitle: 'ملخص الفترة والحركة حسب المشروع والميزان',
                        icon: Icons.bar_chart,
                        color: AppColors.info,
                        onTap: () => _open(
                          AccountingReportsPage(scope: widget.scope),
                        ),
                      ),
                      AppManagementCard(
                        title: 'دليل الحسابات',
                        subtitle:
                            '${financeChartOfAccounts.length} حسابًا معتمدًا',
                        icon: Icons.account_tree_outlined,
                        color: AppColors.warning,
                        onTap: () => _open(const ChartOfAccountsPage()),
                      ),
                    ];

                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: cards
                          .map(
                            (card) => SizedBox(width: width, child: card),
                          )
                          .toList(),
                    );
                  },
                ),

                const SizedBox(height: 20),

                AppSectionTitle(
                  title: 'آخر السندات',
                  subtitle: vouchers.isEmpty
                      ? 'لم تُسجَّل سندات بعد'
                      : 'أحدث ${vouchers.length < 5 ? vouchers.length : 5} سند',
                  icon: Icons.history,
                ),

                if (vouchers.isEmpty)
                  AppCard(
                    child: AccountingEmptyState(
                      title: 'لا توجد سندات بعد',
                      message: data.isFinanceManager
                          ? 'أنشئ حساب المحاسب وحدد له مشروعه ليبدأ '
                              'بتسجيل سندات القبض والصرف.'
                          : 'ابدأ بتسجيل سند قبض أو صرف؛ سيُرحَّل تلقائيًا '
                              'إلى القيود اليومية.',
                      icon: Icons.receipt_long_outlined,
                      actionText: data.canEdit ? 'سند قبض جديد' : null,
                      onAction: data.canEdit
                          ? () => _openVoucherForm(VoucherKind.receipt)
                          : null,
                    ),
                  )
                else
                  for (final Voucher voucher in vouchers.take(5))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        onTap: () => _open(
                          VouchersPage(
                            kind: voucher.kind,
                            canEdit: data.canEdit,
                            scope: widget.scope,
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              voucherKindIcon(voucher.kind),
                              color: voucherKindColor(voucher.kind),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    '${voucher.number} — ${voucher.partyName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '${formatDate(voucher.date)}  •  '
                                    '${voucher.method.shortLabel}',
                                    style: AppTextStyles.small,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              formatMoney(voucher.amount, decimals: 0),
                              style: AppTextStyles.cardTitle.copyWith(
                                fontSize: 14,
                                color: voucherKindColor(voucher.kind),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// بطاقة «مشروع المحاسب»: توضح حدود البيانات المعروضة.
  Widget _projectScopeCard() {
    final bool scoped = widget.scope.isScoped;

    return AppCard(
      color: (scoped ? AppColors.info : AppColors.warning)
          .withValues(alpha: 0.06),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            scoped ? Icons.apartment_outlined : Icons.apartment,
            color: scoped ? AppColors.info : AppColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  scoped
                      ? 'مشروعك: ${widget.scope.label}'
                      : 'لم تُربط بمشروع بعد',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  scoped
                      ? 'كل ما تسجّله من سندات وقيود وصندوق يخصّ هذا '
                          'المشروع فقط، ولا يظهر لك غيره.'
                      : 'تُعرض لك كل مشاريع الوحدة. اطلب من المدير المالي '
                          'ربطك بمشروع لتقتصر أعمالك عليه.',
                  style: AppTextStyles.bodySecondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(_DashboardData data) {
    final String title = data.isFinanceManager
        ? 'لوحة المدير المالي'
        : data.canEdit
            ? 'لوحة المحاسب'
            : 'الإدارة المالية';

    final String subtitle = data.isFinanceManager
        ? 'تنشئ المحاسب وتحدد له مشروعه، وتتابع أعماله: السندات '
            'والصندوق والقيود والتقارير — عرض واعتماد.'
        : data.canEdit
            ? 'مسؤول عن كل أعمال المشروع: سندات القبض والصرف، الصندوق، '
                'والقيود اليومية.'
            : 'عرض حركة الوحدة المالية: السندات والصندوق والقيود.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppPageHeader(
          title: title,
          subtitle: subtitle,
          icon: Icons.account_balance,
          trailing: AccountingBadge(
            label: AppRoles.label(data.role),
            color: data.isFinanceManager
                ? AppColors.financialManager
                : AppColors.projectAccountant,
            icon: Icons.badge_outlined,
          ),
        ),
        AppCard(
          color: AppColors.primary.withValues(alpha: 0.05),
          child: Row(
            children: <Widget>[
              const CircleAvatar(
                radius: 22,
                child: Icon(Icons.person_outline),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      data.userName.isEmpty
                          ? 'مرحبًا بك'
                          : 'مرحبًا ${data.userName}',
                      style: AppTextStyles.cardTitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.isFinanceManager
                          ? 'المحاسب هو من يُدخل السندات والقيود، وأنت تراجع '
                              'وتتابع.'
                          : 'كل سند تحفظه يُرحَّل تلقائيًا إلى قيد يومية '
                              'متوازن.',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// بيانات اللوحة
// ============================================================

class _DashboardData {
  const _DashboardData({
    required this.snapshot,
    required this.role,
    required this.userName,
    required this.isFinanceManager,
    required this.canEdit,
    required this.accountants,
  });

  final AccountingSnapshot snapshot;
  final String role;
  final String userName;
  final bool isFinanceManager;
  final bool canEdit;
  final List<_AccountantInfo> accountants;
}

class _AccountantInfo {
  const _AccountantInfo({
    required this.name,
    required this.username,
    required this.active,
    this.project = '',
    this.hasProject = false,
  });

  final String name;
  final String username;
  final bool active;

  /// اسم مشروع المحاسب («كل مشاريع الوحدة» إن لم يُربط).
  final String project;
  final bool hasProject;
}

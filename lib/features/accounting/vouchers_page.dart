import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';
import 'accounting_format.dart';
import 'accounting_models.dart';
import 'accounting_service.dart';
import 'accounting_widgets.dart';
import 'voucher_form_page.dart';

// ============================================================
// قائمة سندات القبض / سندات الصرف
// ============================================================
//
// تُفتح بنوع السند (قبض أو صرف)، وتعرض:
//   • بحثًا برقم السند أو الجهة أو البيان أو المشروع.
//   • تصفية بطريقة الدفع.
//   • إجمالي السندات وعددها.
//   • إضافة/تعديل/حذف (للمحاسب)، أو عرض فقط (للمدير المالي).
// ============================================================

class VouchersPage extends StatefulWidget {
  const VouchersPage({
    super.key,
    required this.kind,
    this.canEdit = true,
    this.scope = AccountingScope.none,
  });

  final VoucherKind kind;

  /// false = وضع إشراف: عرض السندات دون إضافة أو تعديل.
  final bool canEdit;

  /// مشروع المحاسب: تقتصر القراءة والكتابة عليه.
  final AccountingScope scope;

  @override
  State<VouchersPage> createState() => _VouchersPageState();
}

class _VouchersPageState extends State<VouchersPage> {
  final AccountingService _service = AccountingService();
  final TextEditingController _searchController = TextEditingController();

  late Future<List<Voucher>> _future;
  PaymentMethod? _methodFilter;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _future = _service.loadVouchers(
      kind: widget.kind,
      projectId: widget.scope.projectId,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _service.loadVouchers(
        kind: widget.kind,
        projectId: widget.scope.projectId,
      );
    });
  }

  Future<void> _openForm([Voucher? voucher]) async {
    if (!widget.canEdit) return;

    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VoucherFormPage(
          kind: widget.kind,
          voucher: voucher,
          scope: widget.scope,
        ),
      ),
    );

    if (saved == true) _reload();
  }

  Future<void> _deleteVoucher(Voucher voucher) async {
    final bool confirm = await AppWidgets.showConfirmDialog(
      context: context,
      title: 'حذف ${widget.kind.title}',
      message: 'سيُحذف ${widget.kind.title} رقم ${voucher.number} '
          'ومعه قيد اليومية المرحّل منه نهائيًا.\n\n'
          'المبلغ: ${formatMoneyWithCurrency(voucher.amount)}\n'
          'الجهة: ${voucher.partyName}',
      confirmText: 'حذف',
      danger: true,
    );

    if (!confirm) return;

    try {
      await _service.deleteVoucher(voucher);
      if (!mounted) return;
      AppWidgets.showSuccess(
        context,
        'تم حذف ${widget.kind.title} وقيده المرحّل',
      );
      _reload();
    } on AccountingException catch (error) {
      if (mounted) AppWidgets.showError(context, error.message);
    } catch (error) {
      if (mounted) {
        AppWidgets.showError(context, 'تعذر حذف السند: $error');
      }
    }
  }

  void _showDetails(Voucher voucher) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('${widget.kind.title} — ${voucher.number}'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        AccountingBadge(
                          label: voucher.method.label,
                          color: paymentMethodColor(voucher.method),
                          icon: paymentMethodIcon(voucher.method),
                        ),
                        const SizedBox(width: 6),
                        AccountingBadge(
                          label: 'مرحّل إلى القيود',
                          color: AppColors.success,
                          icon: Icons.check_circle_outline,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AccountingInfoRow(
                      label: 'التاريخ',
                      value: formatDate(voucher.date),
                      icon: Icons.calendar_month,
                    ),
                    AccountingInfoRow(
                      label: 'المبلغ',
                      value: formatMoneyWithCurrency(voucher.amount),
                      icon: Icons.payments_outlined,
                      valueColor: voucherKindColor(voucher.kind),
                    ),
                    AccountingInfoRow(
                      label: widget.kind.partyLabel,
                      value: voucher.partyName,
                      icon: Icons.person_outline,
                    ),
                    AccountingInfoRow(
                      label: 'البيان',
                      value: voucher.description,
                      icon: Icons.notes_outlined,
                    ),
                    AccountingInfoRow(
                      label: 'الحساب المقابل',
                      value: voucher.accountName,
                      icon: Icons.account_tree_outlined,
                    ),
                    if (voucher.method == PaymentMethod.check)
                      AccountingInfoRow(
                        label: 'رقم الشيك',
                        value: voucher.checkNumber,
                        icon: Icons.pin_outlined,
                      ),
                    AccountingInfoRow(
                      label: 'المشروع',
                      value: projectLabelOf(voucher),
                      icon: Icons.apartment_outlined,
                    ),
                    if (voucher.notes.trim().isNotEmpty)
                      AccountingInfoRow(
                        label: 'ملاحظات',
                        value: voucher.notes,
                        icon: Icons.edit_note_outlined,
                      ),
                    AccountingInfoRow(
                      label: 'أنشأه',
                      value: voucher.createdByName.isEmpty
                          ? '—'
                          : voucher.createdByName,
                      icon: Icons.person_pin_outlined,
                    ),
                    AccountingInfoRow(
                      label: 'تاريخ الإنشاء',
                      value: formatDateTime(voucher.createdAt),
                      icon: Icons.schedule,
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إغلاق'),
              ),
              if (widget.canEdit)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _openForm(voucher);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('تعديل'),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.kind.plural,
      actions: <Widget>[
        IconButton(
          tooltip: 'تحديث',
          icon: const Icon(Icons.refresh),
          onPressed: _reload,
        ),
      ],
      floatingActionButton: widget.canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: Text('إضافة ${widget.kind.title}'),
            )
          : null,
      child: FutureBuilder<List<Voucher>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppError(
              message: 'تعذر تحميل ${widget.kind.plural}:\n${snapshot.error}',
              onRetry: _reload,
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return AppLoading(message: 'جاري تحميل ${widget.kind.plural}...');
          }

          final List<Voucher> all = snapshot.data ?? const <Voucher>[];
          final List<Voucher> vouchers = filterVouchers(
            all,
            method: _methodFilter,
            search: _search,
          );

          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: _summaryCard(all),
              ),
              if (widget.scope.isScoped)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.apartment_outlined,
                        size: 16,
                        color: AppColors.info,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'سندات مشروع ${widget.scope.label} فقط',
                          style: AppTextStyles.small,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'بحث برقم السند أو الجهة أو البيان أو المشروع...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                          ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() => _search = value.trim());
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      _methodChip('كل الطرق', null),
                      for (final PaymentMethod method
                          in PaymentMethod.values)
                        _methodChip(method.shortLabel, method),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                    await _future;
                  },
                  child: all.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: <Widget>[
                            AccountingEmptyState(
                              title: 'لا توجد ${widget.kind.plural} بعد',
                              message: widget.canEdit
                                  ? 'ابدأ بإنشاء أول ${widget.kind.title}؛ '
                                      'سيُرقَّم تلقائيًا ويُرحَّل إلى القيود اليومية.'
                                  : 'لم يسجّل المحاسب أي ${widget.kind.title} حتى الآن.',
                              icon: voucherKindIcon(widget.kind),
                              actionText: widget.canEdit
                                  ? 'إضافة ${widget.kind.title}'
                                  : null,
                              onAction: widget.canEdit ? _openForm : null,
                            ),
                          ],
                        )
                      : vouchers.isEmpty
                          ? ListView(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              children: const <Widget>[
                                AccountingEmptyState(
                                  title: 'لا توجد نتائج مطابقة',
                                  message:
                                      'غيّر كلمة البحث أو طريقة الدفع للعثور على السند.',
                                  icon: Icons.search_off,
                                ),
                              ],
                            )
                          : ListView.builder(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                4,
                                14,
                                96,
                              ),
                              itemCount: vouchers.length,
                              itemBuilder: (context, index) =>
                                  _voucherCard(vouchers[index]),
                            ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _methodChip(String label, PaymentMethod? method) {
    final bool selected = _methodFilter == method;

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _methodFilter = method),
      ),
    );
  }

  Widget _summaryCard(List<Voucher> vouchers) {
    final double total = sumVouchers(vouchers, widget.kind);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: voucherKindColor(widget.kind).withValues(alpha: 0.06),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: voucherKindColor(widget.kind).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              voucherKindIcon(widget.kind),
              color: voucherKindColor(widget.kind),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'إجمالي ${widget.kind.plural}',
                  style: AppTextStyles.bodySecondary,
                ),
                const SizedBox(height: 2),
                Text(
                  formatMoneyWithCurrency(total),
                  style: AppTextStyles.cardTitle.copyWith(
                    color: voucherKindColor(widget.kind),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '${vouchers.length}',
                style: AppTextStyles.cardTitle,
              ),
              Text(
                'سند',
                style: AppTextStyles.small,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _voucherCard(Voucher voucher) {
    final Color color = voucherKindColor(voucher.kind);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: () => widget.canEdit ? _openForm(voucher) : _showDetails(voucher),
        child: Row(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(voucherKindIcon(voucher.kind), color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        voucher.number.isEmpty ? 'بدون رقم' : voucher.number,
                        style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
                      ),
                      const SizedBox(width: 8),
                      AccountingBadge(
                        label: voucher.method.shortLabel,
                        color: paymentMethodColor(voucher.method),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    voucher.partyName.isEmpty
                        ? 'بدون جهة'
                        : voucher.partyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatDate(voucher.date)}'
                    '  •  ${projectLabelOf(voucher)}'
                    '${voucher.description.trim().isEmpty ? '' : '\n${voucher.description}'}',
                    maxLines: 2,
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
                  formatMoney(voucher.amount, decimals: 0),
                  style: AppTextStyles.cardTitle.copyWith(color: color),
                ),
                Text(
                  'ريال',
                  style: AppTextStyles.small,
                ),
              ],
            ),
            if (widget.canEdit)
              PopupMenuButton<String>(
                tooltip: 'خيارات السند',
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (value) {
                  if (value == 'view') _showDetails(voucher);
                  if (value == 'edit') _openForm(voucher);
                  if (value == 'delete') _deleteVoucher(voucher);
                },
                itemBuilder: (_) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'view',
                    child: Text('عرض التفاصيل'),
                  ),
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('تعديل السند'),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('حذف السند'),
                  ),
                ],
              )
            else
              IconButton(
                tooltip: 'عرض التفاصيل',
                icon: const Icon(Icons.visibility_outlined, size: 20),
                onPressed: () => _showDetails(voucher),
              ),
          ],
        ),
      ),
    );
  }
}

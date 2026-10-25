import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';
import 'accounting_format.dart';
import 'accounting_models.dart';
import 'accounting_service.dart';
import 'accounting_widgets.dart';
import 'journal_entry_form_page.dart';

// ============================================================
// القيود اليومية
// ============================================================
//
// تعرض قيود السندات المرحّلة تلقائيًا والقيود اليدوية:
//   • بحث برقم القيد أو البيان أو المرجع أو الحساب.
//   • تصفية: الكل / قيود يدوية / قيود السندات.
//   • مجموع المدين والدائن.
//   • إضافة قيد يدوي، وتعديل/حذف القيود اليدوية فقط.
//     قيد السند يُعدَّل من السند نفسه.
// ============================================================

class JournalEntriesPage extends StatefulWidget {
  const JournalEntriesPage({
    super.key,
    this.canEdit = true,
    this.scope = AccountingScope.none,
  });

  final bool canEdit;

  /// مشروع المحاسب: تقتصر القيود على مشروعه.
  final AccountingScope scope;

  @override
  State<JournalEntriesPage> createState() => _JournalEntriesPageState();
}

class _JournalEntriesPageState extends State<JournalEntriesPage> {
  final AccountingService _service = AccountingService();
  final TextEditingController _searchController = TextEditingController();

  late Future<List<JournalEntry>> _future;
  String _search = '';
  String _sourceFilter = 'all'; // all | manual | vouchers

  @override
  void initState() {
    super.initState();
    _future = _service.loadJournalEntries(
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
      _future = _service.loadJournalEntries(
        projectId: widget.scope.projectId,
      );
    });
  }

  Future<void> _openForm([JournalEntry? entry]) async {
    if (!widget.canEdit) return;

    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => JournalEntryFormPage(
          entry: entry,
          scope: widget.scope,
        ),
      ),
    );

    if (saved == true) _reload();
  }

  Future<void> _deleteEntry(JournalEntry entry) async {
    if (!entry.isManual) return;

    final bool confirm = await AppWidgets.showConfirmDialog(
      context: context,
      title: 'حذف القيد اليومي',
      message: 'سيُحذف القيد ${entry.number} نهائيًا، '
          'وسيتأثر رصيد الصندوق إن كان القيد يمسّه.\n\n'
          'البيان: ${entry.description}\n'
          'المبلغ: ${formatMoneyWithCurrency(entry.totalDebit)}',
      confirmText: 'حذف',
      danger: true,
    );

    if (!confirm) return;

    try {
      await _service.deleteJournalEntry(entry);
      if (!mounted) return;
      AppWidgets.showSuccess(context, 'تم حذف القيد اليومي');
      _reload();
    } on AccountingException catch (error) {
      if (mounted) AppWidgets.showError(context, error.message);
    } catch (error) {
      if (mounted) {
        AppWidgets.showError(context, 'تعذر حذف القيد: $error');
      }
    }
  }

  void _showDetails(JournalEntry entry) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: <Widget>[
                Expanded(child: Text('القيد ${entry.number}')),
                AccountingBadge(
                  label: entry.isBalanced ? 'متوازن' : 'غير متوازن',
                  color: entry.isBalanced
                      ? AppColors.success
                      : AppColors.danger,
                ),
              ],
            ),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        AccountingBadge(
                          label: entry.sourceLabel,
                          color: entry.isManual
                              ? AppColors.info
                              : AppColors.primary,
                          icon: entry.isManual
                              ? Icons.edit_note
                              : Icons.receipt_long,
                        ),
                        if (entry.sourceNumber.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 6),
                          AccountingBadge(
                            label: entry.sourceNumber,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    AccountingInfoRow(
                      label: 'التاريخ',
                      value: formatDate(entry.date),
                      icon: Icons.calendar_month,
                    ),
                    AccountingInfoRow(
                      label: 'البيان',
                      value: entry.description,
                      icon: Icons.notes_outlined,
                    ),
                    AccountingInfoRow(
                      label: 'المشروع',
                      value: journalProjectLabel(entry),
                      icon: Icons.apartment_outlined,
                    ),
                    if (entry.reference.trim().isNotEmpty)
                      AccountingInfoRow(
                        label: 'المرجع',
                        value: entry.reference,
                        icon: Icons.tag,
                      ),
                    AccountingInfoRow(
                      label: 'أنشأه',
                      value: entry.createdByName.isEmpty
                          ? '—'
                          : entry.createdByName,
                      icon: Icons.person_pin_outlined,
                    ),
                    const SizedBox(height: 8),
                    AccountingTable(
                      headers: const <String>[
                        'الحساب',
                        'مدين',
                        'دائن',
                      ],
                      columnFlex: const <int>[3, 2, 2],
                      rows: entry.lines.map((line) {
                        return <Widget>[
                          Text(
                            line.accountName.isEmpty
                                ? line.accountCode
                                : line.accountName,
                            style: AppTextStyles.body.copyWith(fontSize: 12),
                          ),
                          Text(
                            line.debit > 0 ? formatMoney(line.debit) : '—',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            line.credit > 0 ? formatMoney(line.credit) : '—',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ];
                      }).toList(),
                      emptyText: 'لا توجد سطور',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Text(
                          'المجموع',
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'مدين: ${formatMoney(entry.totalDebit)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'دائن: ${formatMoney(entry.totalCredit)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
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
              if (widget.canEdit && entry.isManual) ...<Widget>[
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _deleteEntry(entry);
                  },
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.danger,
                  ),
                  label: const Text(
                    'حذف',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _openForm(entry);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('تعديل'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'القيود اليومية',
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
              label: const Text('قيد يدوي'),
            )
          : null,
      child: FutureBuilder<List<JournalEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppError(
              message: 'تعذر تحميل القيود اليومية:\n${snapshot.error}',
              onRetry: _reload,
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const AppLoading(
              message: 'جاري تحميل القيود اليومية...',
            );
          }

          final List<JournalEntry> all =
              snapshot.data ?? const <JournalEntry>[];

          final List<JournalEntry> filtered = filterJournalEntries(
            all,
            search: _search,
          ).where((entry) {
            if (_sourceFilter == 'manual') return entry.isManual;
            if (_sourceFilter == 'vouchers') return !entry.isManual;
            return true;
          }).toList();

          final double debit =
              filtered.fold<double>(0, (sum, entry) => sum + entry.totalDebit);
          final double credit =
              filtered.fold<double>(0, (sum, entry) => sum + entry.totalCredit);

          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: _summaryCard(filtered.length, debit, credit),
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
                          'قيود مشروع ${widget.scope.label} فقط',
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
                    hintText: 'بحث برقم القيد أو البيان أو المرجع أو الحساب...',
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
                      _sourceChip('الكل', 'all'),
                      _sourceChip('قيود يدوية', 'manual'),
                      _sourceChip('قيود السندات', 'vouchers'),
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
                              title: 'لا توجد قيود يومية بعد',
                              message:
                                  'تُنشأ القيود تلقائيًا عند حفظ السندات، '
                                  'ويمكنك إضافة قيد يدوي للتسويات.',
                              icon: Icons.menu_book_outlined,
                              actionText: widget.canEdit ? 'إضافة قيد يدوي' : null,
                              onAction: widget.canEdit ? _openForm : null,
                            ),
                          ],
                        )
                      : filtered.isEmpty
                          ? ListView(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              children: const <Widget>[
                                AccountingEmptyState(
                                  title: 'لا توجد قيود مطابقة',
                                  message:
                                      'غيّر كلمة البحث أو نوع القيد.',
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
                              itemCount: filtered.length,
                              itemBuilder: (context, index) =>
                                  _entryCard(filtered[index]),
                            ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sourceChip(String label, String value) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: _sourceFilter == value,
        onSelected: (_) => setState(() => _sourceFilter = value),
      ),
    );
  }

  Widget _summaryCard(int count, double debit, double credit) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: AppColors.primary.withValues(alpha: 0.05),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _summaryColumn(
              'إجمالي المدين',
              formatMoneyWithCurrency(debit),
              AppColors.success,
            ),
          ),
          Container(
            width: 1,
            height: 42,
            color: AppColors.border,
          ),
          Expanded(
            child: _summaryColumn(
              'إجمالي الدائن',
              formatMoneyWithCurrency(credit),
              AppColors.danger,
            ),
          ),
          Container(
            width: 1,
            height: 42,
            color: AppColors.border,
          ),
          Expanded(
            child: _summaryColumn(
              'عدد القيود',
              '$count',
              AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryColumn(String label, String value, Color color) {
    return Column(
      children: <Widget>[
        Text(
          label,
          style: AppTextStyles.small,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _entryCard(JournalEntry entry) {
    final Color sourceColor =
        entry.isManual ? AppColors.info : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: () => _showDetails(entry),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: sourceColor.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    entry.isManual ? Icons.edit_note : Icons.receipt_long,
                    color: sourceColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.number.isEmpty ? 'قيد بدون رقم' : entry.number,
                        style: AppTextStyles.cardTitle.copyWith(
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.description.isEmpty
                            ? entry.sourceLabel
                            : entry.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySecondary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatMoney(entry.totalDebit, decimals: 0),
                  style: AppTextStyles.cardTitle.copyWith(
                    color: sourceColor,
                  ),
                ),
                if (widget.canEdit && entry.isManual)
                  PopupMenuButton<String>(
                    tooltip: 'خيارات القيد',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (value) {
                      if (value == 'edit') _openForm(entry);
                      if (value == 'delete') _deleteEntry(entry);
                    },
                    itemBuilder: (_) => const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Text('تعديل القيد'),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('حذف القيد'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                AccountingBadge(
                  label: entry.sourceLabel,
                  color: sourceColor,
                  icon: entry.isManual
                      ? Icons.edit_note
                      : Icons.receipt_long,
                ),
                const SizedBox(width: 6),
                AccountingBadge(
                  label: entry.isBalanced ? 'متوازن' : 'غير متوازن',
                  color: entry.isBalanced
                      ? AppColors.success
                      : AppColors.danger,
                ),
                const Spacer(),
                Text(
                  formatDate(entry.date),
                  style: AppTextStyles.small,
                ),
              ],
            ),
            if (!entry.isManual) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'يُعدَّل من ${entry.isFromReceipt ? 'سند القبض' : 'سند الصرف'}'
                '${entry.sourceNumber.isEmpty ? '' : ' ${entry.sourceNumber}'}',
                style: AppTextStyles.small.copyWith(
                  color: AppColors.textLight,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';
import 'accounting_format.dart';
import 'accounting_models.dart';
import 'accounting_project_field.dart';
import 'accounting_service.dart';
import 'accounting_widgets.dart';

// ============================================================
// نموذج إنشاء / تعديل قيد يومية يدوي
// ============================================================
//
// القيود الناتجة عن السندات لا تُعدَّل من هنا (تُعدَّل من السند
// نفسه)؛ هذه الشاشة للقيود اليدوية: التسويات، المصروفات التي
// لا مستند لها، افتتاح الحسابات... إلخ.
//
// القاعدة: مجموع المدين = مجموع الدائن، وكل سطر على حساب واحد
// إما مدين أو دائن.
// ============================================================

class JournalEntryFormPage extends StatefulWidget {
  const JournalEntryFormPage({
    super.key,
    this.entry,
    this.scope = AccountingScope.none,
  });

  /// null = قيد جديد، وإلا قيد يدوي قائم للتعديل.
  final JournalEntry? entry;

  /// مشروع المحاسب: يُثبَّت على القيد ولا يمكن تغييره.
  final AccountingScope scope;

  @override
  State<JournalEntryFormPage> createState() => _JournalEntryFormPageState();
}

class _JournalEntryFormPageState extends State<JournalEntryFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final AccountingService _service = AccountingService();

  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();

  final List<_JournalLineInput> _lines = <_JournalLineInput>[];

  int _nextLineId = 0;
  DateTime _date = DateTime.now();
  String _projectId = '';
  String _projectCode = '';
  String _projectName = '';
  bool _saving = false;

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();

    final JournalEntry? entry = widget.entry;

    if (entry == null && widget.scope.isScoped) {
      _projectId = widget.scope.projectId;
      _projectCode = widget.scope.projectCode;
      _projectName = widget.scope.projectName;
    }

    if (entry != null) {
      _date = entry.date;
      _descriptionController.text = entry.description;
      _referenceController.text = entry.reference;
      _projectId = entry.projectId;
      _projectCode = entry.projectCode;
      _projectName = entry.projectName;

      for (final JournalLine line in entry.lines) {
        final _JournalLineInput input = _JournalLineInput(
          id: _nextLineId++,
          accountCode: line.accountCode,
          isDebit: line.debit >= line.credit,
        );
        input.amount.text = _amountText(
          line.debit > 0 ? line.debit : line.credit,
        );
        input.description.text = line.description;
        _lines.add(input);
      }
    }

    while (_lines.length < 2) {
      _lines.add(_JournalLineInput(id: _nextLineId++));
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _referenceController.dispose();
    for (final _JournalLineInput line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  String _amountText(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  void _addLine() {
    setState(() {
      _lines.add(_JournalLineInput(id: _nextLineId++));
    });
  }

  void _removeLine(int index) {
    if (_lines.length <= 2) return;

    setState(() {
      final _JournalLineInput removed = _lines.removeAt(index);
      removed.dispose();
    });
  }

  List<JournalLine> _buildLines() {
    final List<JournalLine> lines = <JournalLine>[];

    for (final _JournalLineInput input in _lines) {
      final FinanceAccount? account =
          financeAccountByCode(input.accountCode);
      final double amount = parseAmount(input.amount.text);

      if (account == null || amount <= 0) continue;

      lines.add(
        JournalLine(
          accountCode: account.code,
          accountName: account.name,
          description: input.description.text.trim(),
          debit: input.isDebit ? amount : 0,
          credit: input.isDebit ? 0 : amount,
        ),
      );
    }

    return lines;
  }

  double get _totalDebit {
    return _buildLines().fold<double>(0, (sum, line) => sum + line.debit);
  }

  double get _totalCredit {
    return _buildLines().fold<double>(0, (sum, line) => sum + line.credit);
  }

  double get _difference => _totalDebit - _totalCredit;

  bool get _allLinesFilled {
    if (_lines.length < 2) return false;

    for (final _JournalLineInput line in _lines) {
      if (line.accountCode == null || parseAmount(line.amount.text) <= 0) {
        return false;
      }
    }

    return true;
  }

  bool get _isBalanced => _allLinesFilled && _difference.abs() < 0.005;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final List<JournalLine> lines = _buildLines();

    if (lines.length < 2) {
      AppWidgets.showError(
        context,
        'أضف سطرين على الأقل مع الحساب والمبلغ',
      );
      return;
    }

    final double debit =
        lines.fold<double>(0, (sum, line) => sum + line.debit);
    final double credit =
        lines.fold<double>(0, (sum, line) => sum + line.credit);

    if ((debit - credit).abs() >= 0.005) {
      AppWidgets.showError(
        context,
        'القيد غير متوازن: المدين ${formatMoney(debit)} '
        'والدائن ${formatMoney(credit)}',
      );
      return;
    }

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppWidgets.showError(context, 'انتهت جلسة الدخول، سجّل الدخول من جديد');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final JournalEntry entry = JournalEntry(
      id: widget.entry?.id ?? '',
      number: widget.entry?.number ?? '',
      date: _date,
      description: _descriptionController.text.trim(),
      lines: lines,
      sourceType: JournalEntry.manualSource,
      projectId: _projectId,
      projectCode: _projectCode,
      projectName: _projectName,
      reference: _referenceController.text.trim(),
    );

    try {
      final String userName = await currentAccountingUserName();

      if (_isEditing) {
        await _service.updateJournalEntry(
          entry,
          userId: user.uid,
          userName: userName,
          projectId: widget.scope.projectId,
          projectCode: widget.scope.projectCode,
          projectName: widget.scope.projectName,
        );
        if (!mounted) return;
        AppWidgets.showSuccess(context, 'تم تحديث القيد اليومي');
      } else {
        final String number = await _service.createJournalEntry(
          entry,
          userId: user.uid,
          userName: userName,
          projectId: widget.scope.projectId,
          projectCode: widget.scope.projectCode,
          projectName: widget.scope.projectName,
        );
        if (!mounted) return;
        AppWidgets.showSuccess(context, 'تم حفظ القيد برقم $number');
      }

      Navigator.of(context).pop(true);
    } on AccountingException catch (error) {
      if (mounted) AppWidgets.showError(context, error.message);
    } catch (error) {
      if (mounted) {
        AppWidgets.showError(context, 'تعذر حفظ القيد: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _isEditing
          ? 'تعديل ${widget.entry!.number}'
          : 'قيد يومية جديد',
      child: AppPage(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppPageHeader(
                title: _isEditing ? 'تعديل القيد اليومي' : 'قيد يومية جديد',
                subtitle:
                    'القيد اليدوي للتسويات والعمليات التي لا سند لها. '
                    'السندات تُرحَّل تلقائيًا إلى القيود.',
                icon: Icons.menu_book_outlined,
              ),

              if (_isEditing)
                AppCard(
                  color: AppColors.info.withValues(alpha: 0.06),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.menu_book_outlined,
                        color: AppColors.info,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'رقم القيد: ${widget.entry!.number}',
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_isEditing) AppSpacing.verticalLg,

              const AppSectionTitle(
                title: 'بيانات القيد',
                icon: Icons.description_outlined,
              ),

              AppDateField(
                label: 'تاريخ القيد *',
                value: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime(DateTime.now().year + 2, 12, 31),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _date = value);
                },
              ),

              AppSpacing.verticalMd,

              AppTextField(
                controller: _descriptionController,
                label: 'بيان القيد *',
                hint: 'مثال: تسوية صندوق، استحقاق مستخلص، مصروف إداري...',
                prefixIcon: Icons.notes_outlined,
                maxLines: 2,
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'بيان القيد مطلوب';
                  }
                  return null;
                },
              ),

              AppSpacing.verticalMd,

              AppTextField(
                controller: _referenceController,
                label: 'المرجع (اختياري)',
                hint: 'رقم مستند أو مستخلص أو عقد',
                prefixIcon: Icons.tag,
              ),

              AppSpacing.verticalMd,

              AccountingProjectField(
                projectId: _projectId,
                projectCode: _projectCode,
                projectName: _projectName,
                enabled: !_saving && !widget.scope.isScoped,
                allowNoProject: !widget.scope.isScoped,
                label: widget.scope.isScoped
                    ? 'المشروع (مثبت على مشروعك)'
                    : 'المشروع (اختياري)',
                onChanged: (id, code, name) {
                  setState(() {
                    _projectId = id;
                    _projectCode = code;
                    _projectName = name;
                  });
                },
              ),

              AppSpacing.verticalLg,

              AppSectionTitle(
                title: 'سطور القيد',
                subtitle:
                    'كل سطر على حساب واحد: إما مدين أو دائن. '
                    'يجب أن يتساوى مجموع المدين مع مجموع الدائن.',
                icon: Icons.list_alt,
                trailing: TextButton.icon(
                  onPressed: _saving ? null : _addLine,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('سطر'),
                ),
              ),

              for (int index = 0; index < _lines.length; index++)
                _lineCard(index, _lines[index]),

              AppSpacing.verticalMd,

              _balanceCard(),

              AppSpacing.verticalLg,

              AppButton(
                text: _isEditing ? 'حفظ التعديلات' : 'حفظ القيد',
                icon: Icons.save_outlined,
                expanded: true,
                loading: _saving,
                onPressed: _save,
              ),

              AppSpacing.verticalMd,

              AppOutlinedButton(
                text: 'إلغاء',
                expanded: true,
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineCard(int index, _JournalLineInput line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 14,
                  backgroundColor:
                      AppColors.primary.withValues(alpha: 0.11),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'السطر ${index + 1}',
                    style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
                  ),
                ),
                if (_lines.length > 2)
                  IconButton(
                    tooltip: 'حذف السطر',
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppColors.danger,
                    ),
                    onPressed: _saving ? null : () => _removeLine(index),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              key: ValueKey<String>(
                'entry-account-${line.id}-${line.accountCode ?? ''}',
              ),
              initialValue: line.accountCode,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'الحساب *',
                prefixIcon: Icon(Icons.account_tree_outlined),
              ),
              hint: const Text('اختر الحساب'),
              items: financeChartOfAccounts.map((account) {
                return DropdownMenuItem<String>(
                  value: account.code,
                  child: Text(
                    account.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => line.accountCode = value),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'اختر الحساب';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: line.description,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'وصف السطر (اختياري)',
                prefixIcon: Icon(Icons.notes_outlined),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                ChoiceChip(
                  label: const Text('مدين'),
                  selected: line.isDebit,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => line.isDebit = true),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('دائن'),
                  selected: !line.isDebit,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => line.isDebit = false),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: line.amount,
                    textAlign: TextAlign.right,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'المبلغ *',
                      suffixText: 'ريال',
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      if (parseAmount(value) <= 0) {
                        return 'أدخل المبلغ';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _balanceCard() {
    final double debit = _totalDebit;
    final double credit = _totalCredit;
    final bool balanced =
        _allLinesFilled && (debit - credit).abs() < 0.005;
    final Color color = balanced ? AppColors.success : AppColors.warning;

    return AppCard(
      color: color.withValues(alpha: 0.07),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                balanced ? Icons.balance : Icons.warning_amber_outlined,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ميزان القيد',
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
                ),
              ),
              AccountingBadge(
                label: balanced ? 'متوازن' : 'غير متوازن',
                color: color,
                icon: balanced
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
              ),
            ],
          ),
          const SizedBox(height: 10),
          AccountingInfoRow(
            label: 'إجمالي المدين',
            value: formatMoneyWithCurrency(debit),
            icon: Icons.arrow_downward,
            valueColor: AppColors.success,
          ),
          AccountingInfoRow(
            label: 'إجمالي الدائن',
            value: formatMoneyWithCurrency(credit),
            icon: Icons.arrow_upward,
            valueColor: AppColors.danger,
          ),
          const Divider(height: 18),
          Row(
            children: <Widget>[
              Text(
                'الفرق',
                style: AppTextStyles.bodySecondary.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                formatMoneyWithCurrency(debit - credit),
                style: AppTextStyles.cardTitle.copyWith(
                  color: balanced ? AppColors.success : color,
                ),
              ),
            ],
          ),
          if (!balanced) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              _allLinesFilled
                  ? 'عدّل المبالغ حتى يتساوى المدين والدائن.'
                  : 'أكمل الحساب والمبلغ في كل سطر لعرض الميزان.',
              style: AppTextStyles.small,
            ),
          ],
        ],
      ),
    );
  }
}

class _JournalLineInput {
  _JournalLineInput({
    required this.id,
    this.accountCode,
    this.isDebit = true,
  });

  final int id;
  final TextEditingController amount = TextEditingController();
  final TextEditingController description = TextEditingController();

  String? accountCode;
  bool isDebit;

  void dispose() {
    amount.dispose();
    description.dispose();
  }
}

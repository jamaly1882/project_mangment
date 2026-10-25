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
// نموذج إنشاء/تعديل سند القبض أو الصرف
// ============================================================
//
// الحفظ يُرحّل السند تلقائيًا إلى قيد يومية متوازن:
//   • سند قبض:  من ح/ الصندوق أو البنك   مدين
//                إلى ح/ الحساب المختار  دائن
//   • سند صرف:  من ح/ الحساب المختار      مدين
//                إلى ح/ الصندوق أو البنك دائن
//
// التعديل يعدّل القيد نفسه، والحذف (من قائمة السندات) يحذف
// القيد معه — فلا تبقى قيود معلّقة بلا مستند.
// ============================================================

class VoucherFormPage extends StatefulWidget {
  const VoucherFormPage({
    super.key,
    required this.kind,
    this.voucher,
    this.scope = AccountingScope.none,
  });

  final VoucherKind kind;

  /// null = سند جديد، وإلا سند قائم للتعديل.
  final Voucher? voucher;

  /// مشروع المحاسب: يُثبَّت على السند ولا يمكن تغييره.
  final AccountingScope scope;

  @override
  State<VoucherFormPage> createState() => _VoucherFormPageState();
}

class _VoucherFormPageState extends State<VoucherFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final AccountingService _service = AccountingService();

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _partyController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _checkController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  DateTime _date = DateTime.now();
  PaymentMethod _method = PaymentMethod.cash;
  String? _accountCode;
  String _projectId = '';
  String _projectCode = '';
  String _projectName = '';
  bool _saving = false;

  bool get _isEditing => widget.voucher != null;

  @override
  void initState() {
    super.initState();

    final Voucher? voucher = widget.voucher;

    if (voucher == null && widget.scope.isScoped) {
      // المحاسب المربوط بمشروع: يُملأ المشروع تلقائيًا ويُقفل.
      _projectId = widget.scope.projectId;
      _projectCode = widget.scope.projectCode;
      _projectName = widget.scope.projectName;
    }

    if (voucher != null) {
      _date = voucher.date;
      _method = voucher.method;
      _accountCode =
          voucher.accountCode.isEmpty ? null : voucher.accountCode;
      _projectId = voucher.projectId;
      _projectCode = voucher.projectCode;
      _projectName = voucher.projectName;
      _amountController.text = _amountText(voucher.amount);
      _partyController.text = voucher.partyName;
      _descriptionController.text = voucher.description;
      _checkController.text = voucher.checkNumber;
      _notesController.text = voucher.notes;
    }

  }

  @override
  void dispose() {
    _amountController.dispose();
    _partyController.dispose();
    _descriptionController.dispose();
    _checkController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _amountText(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppWidgets.showError(context, 'انتهت جلسة الدخول، سجّل الدخول من جديد');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final FinanceAccount? account = financeAccountByCode(_accountCode);
    final Voucher voucher = Voucher(
      id: widget.voucher?.id ?? '',
      kind: widget.kind,
      number: widget.voucher?.number ?? '',
      date: _date,
      amount: parseAmount(_amountController.text),
      method: _method,
      checkNumber: _checkController.text.trim(),
      partyName: _partyController.text.trim(),
      description: _descriptionController.text.trim(),
      accountCode: _accountCode ?? '',
      accountName: account?.name ?? '',
      projectId: _projectId,
      projectCode: _projectCode,
      projectName: _projectName,
      notes: _notesController.text.trim(),
      journalEntryId: widget.voucher?.journalEntryId ?? '',
    );

    try {
      final String userName = await currentAccountingUserName();

      if (_isEditing) {
        await _service.updateVoucher(
          voucher,
          userId: user.uid,
          userName: userName,
          projectId: widget.scope.projectId,
          projectCode: widget.scope.projectCode,
          projectName: widget.scope.projectName,
        );
        if (!mounted) return;
        AppWidgets.showSuccess(
          context,
          'تم تحديث ${widget.kind.title} وتحديث قيده في القيود اليومية',
        );
      } else {
        final String number = await _service.createVoucher(
          voucher,
          userId: user.uid,
          userName: userName,
          projectId: widget.scope.projectId,
          projectCode: widget.scope.projectCode,
          projectName: widget.scope.projectName,
        );
        if (!mounted) return;
        AppWidgets.showSuccess(
          context,
          'تم حفظ ${widget.kind.title} برقم $number وترحيله إلى القيود اليومية',
        );
      }

      Navigator.of(context).pop(true);
    } on AccountingException catch (error) {
      if (mounted) AppWidgets.showError(context, error.message);
    } catch (error) {
      if (mounted) {
        AppWidgets.showError(
          context,
          'تعذر حفظ السند: ${_friendlyError(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendlyError(Object error) {
    final String text = error.toString();
    if (text.contains('permission-denied')) {
      return 'لا توجد صلاحية للكتابة في قاعدة البيانات (firestore.rules)';
    }
    if (text.contains('unavailable')) {
      return 'تعذر الاتصال بالخدمة، تحقق من الشبكة وأعد المحاولة';
    }
    return text.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final String accountLabel = widget.kind == VoucherKind.receipt
        ? 'الحساب الدائن (مصدر المبلغ) *'
        : 'الحساب المدين (نوع المصروف) *';

    return AppScaffold(
      title: _isEditing
          ? 'تعديل ${widget.kind.title}'
          : '${widget.kind.title} جديد',
      child: AppPage(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppPageHeader(
                title: _isEditing
                    ? 'تعديل ${widget.kind.title}'
                    : 'إضافة ${widget.kind.title}',
                subtitle: widget.scope.isScoped
                    ? 'سند يخصّ مشروع ${widget.scope.label}، ويُرحَّل '
                        'تلقائيًا إلى قيد يومية متوازن بمجرد الحفظ.'
                    : 'يُرقَّم السند تلقائيًا ويُرحَّل إلى قيد يومية متوازن '
                        'بمجرد الحفظ.',
                icon: voucherKindIcon(widget.kind),
              ),

              AppCard(
                color: voucherKindColor(widget.kind).withValues(alpha: 0.06),
                child: Row(
                  children: <Widget>[
                    Icon(
                      voucherKindIcon(widget.kind),
                      color: voucherKindColor(widget.kind),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isEditing
                            ? 'رقم السند: ${widget.voucher!.number}'
                            : 'سيُحدَّد رقم ${widget.kind.title} تلقائيًا '
                                'عند الحفظ.',
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              AppSpacing.verticalLg,

              const AppSectionTitle(
                title: 'بيانات السند',
                icon: Icons.description_outlined,
              ),

              AppDateField(
                label: 'تاريخ السند *',
                value: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime(DateTime.now().year + 2, 12, 31),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _date = value);
                },
              ),

              AppSpacing.verticalMd,

              AppNumberField(
                controller: _amountController,
                label: 'المبلغ *',
                hint: '0.00',
                suffixText: 'ريال',
                prefixIcon: Icons.payments_outlined,
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  if (parseAmount(value) <= 0) {
                    return 'أدخل مبلغًا أكبر من صفر';
                  }
                  return null;
                },
              ),

              AppSpacing.verticalMd,

              DropdownButtonFormField<PaymentMethod>(
                key: ValueKey<String>('voucher-method-${_method.key}'),
                initialValue: _method,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'طريقة الدفع *',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                items: PaymentMethod.values.map((method) {
                  return DropdownMenuItem<PaymentMethod>(
                    value: method,
                    child: Text(method.label),
                  );
                }).toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _method = value);
                      },
              ),

              if (_method == PaymentMethod.check) ...<Widget>[
                AppSpacing.verticalMd,
                AppTextField(
                  controller: _checkController,
                  label: 'رقم الشيك *',
                  prefixIcon: Icons.pin_outlined,
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (_method != PaymentMethod.check) return null;
                    if ((value ?? '').trim().isEmpty) {
                      return 'أدخل رقم الشيك';
                    }
                    return null;
                  },
                ),
              ],

              AppSpacing.verticalMd,

              AppTextField(
                controller: _partyController,
                label: '${widget.kind.partyLabel} *',
                hint: widget.kind == VoucherKind.receipt
                    ? 'اسم الدافع أو الجهة'
                    : 'اسم المستفيد',
                prefixIcon: Icons.person_outline,
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'اسم الجهة مطلوب';
                  }
                  return null;
                },
              ),

              AppSpacing.verticalMd,

              AppTextField(
                controller: _descriptionController,
                label: 'البيان *',
                hint: 'وصف موجز للمبلغ',
                prefixIcon: Icons.notes_outlined,
                maxLines: 2,
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'بيان السند مطلوب';
                  }
                  return null;
                },
              ),

              AppSpacing.verticalMd,

              DropdownButtonFormField<String>(
                key: ValueKey<String>('voucher-account-${_accountCode ?? ''}'),
                initialValue: _accountCode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: accountLabel,
                  prefixIcon: const Icon(Icons.account_tree_outlined),
                ),
                hint: const Text('اختر الحساب من دليل الحسابات'),
                items: voucherCounterAccounts.map((account) {
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
                    : (value) => setState(() => _accountCode = value),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'اختر الحساب المقابل للسند';
                  }
                  return null;
                },
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

              AppSpacing.verticalMd,

              AppTextField(
                controller: _notesController,
                label: 'ملاحظات (اختياري)',
                prefixIcon: Icons.edit_note_outlined,
                maxLines: 2,
              ),

              AppSpacing.verticalLg,

              _entryPreviewCard(),

              AppSpacing.verticalLg,

              AppButton(
                text: _isEditing
                    ? 'حفظ التعديلات'
                    : 'حفظ ${widget.kind.title}',
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

  Widget _entryPreviewCard() {
    final FinanceAccount? selected = financeAccountByCode(_accountCode);
    final FinanceAccount cashOrBank =
        _method.isCash ? cashFinanceAccount : bankFinanceAccount;
    final String counterName = selected?.name ?? 'الحساب المختار';
    final double amount = parseAmount(_amountController.text);

    final bool receipt = widget.kind == VoucherKind.receipt;

    return AppCard(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.account_tree_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'القيد المحاسبي المتوقع',
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
                ),
              ),
              AccountingBadge(
                label: 'متوازن',
                color: AppColors.success,
                icon: Icons.check_circle_outline,
              ),
            ],
          ),
          const SizedBox(height: 10),
          AccountingInfoRow(
            label: 'مدين',
            value: receipt ? cashOrBank.name : counterName,
            icon: Icons.arrow_downward,
            valueColor: AppColors.success,
          ),
          AccountingInfoRow(
            label: 'دائن',
            value: receipt ? counterName : cashOrBank.name,
            icon: Icons.arrow_upward,
            valueColor: AppColors.danger,
          ),
          const Divider(height: 18),
          Row(
            children: <Widget>[
              Text(
                'المبلغ',
                style: AppTextStyles.bodySecondary,
              ),
              const Spacer(),
              Text(
                formatMoneyWithCurrency(amount),
                style: AppTextStyles.cardTitle.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

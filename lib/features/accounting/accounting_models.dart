import 'package:cloud_firestore/cloud_firestore.dart';

// ============================================================
// وحدة الحسابات — النماذج والثوابت
// ============================================================
//
// هذه الطبقة نقيّة (لا تعرف الواجهة): أنواع السندات، طرق
// الدفع، دليل الحسابات، السند، القيد اليومي، حركة الصندوق،
// والرصيد الافتتاحي — إضافة إلى العمليات الحسابية عليها
// (أرصدة الصندوق والبنك) حتى تُختبر بسهولة.
//
// التخزين في Firestore:
//   vouchers/{id}          — سند قبض أو صرف (كل سند يُرحَّل
//                            إلى قيد يومية تلقائيًا).
//   journal_entries/{id}   — قيود اليومية (يدوية أو من سند).
//   finance_counters/main  — عدّادات أرقام السندات والقيود.
//   finance_settings/opening — الرصيد الافتتاحي للصندوق والبنك.
// ============================================================

// ============================================================
// أنواع السندات
// ============================================================

enum VoucherKind {
  receipt(
    key: 'receipt',
    title: 'سند قبض',
    plural: 'سندات القبض',
    numberPrefix: 'قبض',
    partyLabel: 'استلمنا من',
    counterField: 'receipt',
  ),
  payment(
    key: 'payment',
    title: 'سند صرف',
    plural: 'سندات الصرف',
    numberPrefix: 'صرف',
    partyLabel: 'صرفنا إلى',
    counterField: 'payment',
  );

  const VoucherKind({
    required this.key,
    required this.title,
    required this.plural,
    required this.numberPrefix,
    required this.partyLabel,
    required this.counterField,
  });

  /// المفتاح المخزّن في Firestore.
  final String key;

  /// اسم السند المفرد.
  final String title;

  /// الجمع المستخدم في العناوين.
  final String plural;

  /// بادئة رقم السند: قبض-0001 / صرف-0001.
  final String numberPrefix;

  /// تسمية الجهة في نموذج السند.
  final String partyLabel;

  /// حقل العدّاد المقابل في finance_counters.
  final String counterField;

  static VoucherKind fromKey(String? value) {
    return value == VoucherKind.payment.key
        ? VoucherKind.payment
        : VoucherKind.receipt;
  }
}

// ============================================================
// طرق الدفع
// ============================================================

enum PaymentMethod {
  cash(key: 'cash', label: 'نقدًا', shortLabel: 'نقدي'),
  bank(key: 'bank', label: 'تحويل بنكي', shortLabel: 'بنك'),
  check(key: 'check', label: 'شيك', shortLabel: 'شيك');

  const PaymentMethod({
    required this.key,
    required this.label,
    required this.shortLabel,
  });

  final String key;
  final String label;
  final String shortLabel;

  /// هل يمر المبلغ عبر الصندوق النقدي؟
  bool get isCash => this == PaymentMethod.cash;

  /// هل يمر عبر البنك (تحويل أو شيك)؟
  bool get isBankMoney => this != PaymentMethod.cash;

  static PaymentMethod fromKey(String? value) {
    if (value == PaymentMethod.bank.key) return PaymentMethod.bank;
    if (value == PaymentMethod.check.key) return PaymentMethod.check;
    return PaymentMethod.cash;
  }
}

// ============================================================
// صندوق / بنك / الكل
// ============================================================

enum MoneyBoxFilter {
  cash(key: 'cash', label: 'الصندوق النقدي'),
  bank(key: 'bank', label: 'البنك والشيكات'),
  all(key: 'all', label: 'كل الحسابات');

  const MoneyBoxFilter({required this.key, required this.label});

  final String key;
  final String label;

  bool matches(PaymentMethod method) {
    if (this == MoneyBoxFilter.all) return true;
    if (this == MoneyBoxFilter.cash) return method.isCash;
    return method.isBankMoney;
  }
}

// ============================================================
// دليل الحسابات
// ============================================================

const String cashAccountCode = '1000';
const String bankAccountCode = '1010';

enum FinanceAccountKind {
  asset('أصول'),
  liability('التزامات'),
  equity('حقوق ملكية'),
  revenue('إيرادات'),
  expense('مصروفات');

  const FinanceAccountKind(this.label);

  final String label;
}

class FinanceAccount {
  const FinanceAccount({
    required this.code,
    required this.name,
    required this.kind,
  });

  final String code;
  final String name;
  final FinanceAccountKind kind;

  String get label => '$code — $name';

  bool get isCash => code == cashAccountCode;

  bool get isBank => code == bankAccountCode;
}

/// دليل الحسابات المعتمد في الوحدة.
const List<FinanceAccount> financeChartOfAccounts = <FinanceAccount>[
  FinanceAccount(
    code: cashAccountCode,
    name: 'الصندوق (النقدية)',
    kind: FinanceAccountKind.asset,
  ),
  FinanceAccount(
    code: bankAccountCode,
    name: 'البنك',
    kind: FinanceAccountKind.asset,
  ),
  FinanceAccount(
    code: '1100',
    name: 'ذمم مدينة / مستخلصات مستحقة',
    kind: FinanceAccountKind.asset,
  ),
  FinanceAccount(
    code: '2000',
    name: 'موردون وذمم دائنة',
    kind: FinanceAccountKind.liability,
  ),
  FinanceAccount(
    code: '2100',
    name: 'مستحقات رواتب وعمالة',
    kind: FinanceAccountKind.liability,
  ),
  FinanceAccount(
    code: '3000',
    name: 'تمويل واعتمادات المشاريع',
    kind: FinanceAccountKind.equity,
  ),
  FinanceAccount(
    code: '4000',
    name: 'إيرادات المشاريع',
    kind: FinanceAccountKind.revenue,
  ),
  FinanceAccount(
    code: '4100',
    name: 'إيرادات أخرى',
    kind: FinanceAccountKind.revenue,
  ),
  FinanceAccount(
    code: '5000',
    name: 'مصروفات المشاريع',
    kind: FinanceAccountKind.expense,
  ),
  FinanceAccount(
    code: '5100',
    name: 'مواد ومستلزمات',
    kind: FinanceAccountKind.expense,
  ),
  FinanceAccount(
    code: '5200',
    name: 'عمالة ومقاولون',
    kind: FinanceAccountKind.expense,
  ),
  FinanceAccount(
    code: '5300',
    name: 'معدات وآليات',
    kind: FinanceAccountKind.expense,
  ),
  FinanceAccount(
    code: '5400',
    name: 'محروقات وديزل',
    kind: FinanceAccountKind.expense,
  ),
  FinanceAccount(
    code: '5500',
    name: 'ورشة وصيانة',
    kind: FinanceAccountKind.expense,
  ),
  FinanceAccount(
    code: '5600',
    name: 'مصروفات إدارية وعمومية',
    kind: FinanceAccountKind.expense,
  ),
  FinanceAccount(
    code: '5700',
    name: 'مستخلصات مقاولين',
    kind: FinanceAccountKind.expense,
  ),
];

FinanceAccount? financeAccountByCode(String? code) {
  final String value = (code ?? '').trim();
  if (value.isEmpty) return null;

  for (final FinanceAccount account in financeChartOfAccounts) {
    if (account.code == value) return account;
  }

  return null;
}

FinanceAccount get cashFinanceAccount => financeChartOfAccounts.first;

FinanceAccount get bankFinanceAccount => financeChartOfAccounts[1];

/// الحساب المقابل في السند: كل الحسابات ما عدا الصندوق والبنك
/// (لأن أحدهما هو الطرف النقدي الذي يُحدَّد من طريقة الدفع).
List<FinanceAccount> get voucherCounterAccounts {
  return financeChartOfAccounts
      .where((account) => !account.isCash && !account.isBank)
      .toList();
}

// ============================================================
// قراءة التواريخ من Firestore
// ============================================================

DateTime? accountingDateOf(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _text(dynamic value) => (value ?? '').toString();

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(_text(value)) ?? 0;
}

// ============================================================
// السند
// ============================================================

class Voucher {
  const Voucher({
    required this.id,
    required this.kind,
    required this.number,
    required this.date,
    required this.amount,
    required this.method,
    required this.partyName,
    required this.description,
    required this.accountCode,
    required this.accountName,
    this.checkNumber = '',
    this.projectId = '',
    this.projectCode = '',
    this.projectName = '',
    this.notes = '',
    this.journalEntryId = '',
    this.createdByName = '',
    this.createdAt,
  });

  /// معرّف الوثيقة في `vouchers` (فارغ للسند الجديد).
  final String id;

  final VoucherKind kind;
  final String number;
  final DateTime date;
  final double amount;
  final PaymentMethod method;

  /// الجهة: المستلم في سند القبض، والمستفيد في سند الصرف.
  final String partyName;

  /// البيان.
  final String description;

  /// الحساب المقابل: مصدر المبلغ (قبض) أو نوع المصروف (صرف).
  final String accountCode;
  final String accountName;

  final String checkNumber;
  final String projectId;
  final String projectCode;
  final String projectName;
  final String notes;

  /// معرّف قيد اليومية المرحّل من هذا السند.
  final String journalEntryId;

  final String createdByName;
  final DateTime? createdAt;

  bool get isReceipt => kind == VoucherKind.receipt;

  bool get isPayment => kind == VoucherKind.payment;

  factory Voucher.fromMap(String id, Map<String, dynamic> data) {
    final String accountCode = _text(data['accountCode']);
    final FinanceAccount? account = financeAccountByCode(accountCode);

    return Voucher(
      id: id,
      kind: VoucherKind.fromKey(_text(data['kind'])),
      number: _text(data['number']),
      date: accountingDateOf(data['date']) ?? DateTime.now(),
      amount: _double(data['amount']),
      method: PaymentMethod.fromKey(_text(data['method'])),
      checkNumber: _text(data['checkNumber']),
      partyName: _text(data['partyName']),
      description: _text(data['description']),
      accountCode: accountCode,
      accountName: _text(data['accountName']).isNotEmpty
          ? _text(data['accountName'])
          : (account?.name ?? ''),
      projectId: _text(data['projectId']),
      projectCode: _text(data['projectCode']),
      projectName: _text(data['projectName']),
      notes: _text(data['notes']),
      journalEntryId: _text(data['journalEntryId']),
      createdByName: _text(data['createdByName']),
      createdAt: accountingDateOf(data['createdAt']),
    );
  }
}

// ============================================================
// القيد اليومي
// ============================================================

class JournalLine {
  const JournalLine({
    required this.accountCode,
    required this.accountName,
    this.description = '',
    this.debit = 0,
    this.credit = 0,
  });

  final String accountCode;
  final String accountName;
  final String description;
  final double debit;
  final double credit;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'accountCode': accountCode,
      'accountName': accountName,
      'description': description,
      'debit': debit,
      'credit': credit,
    };
  }

  factory JournalLine.fromMap(Map<String, dynamic> data) {
    final String accountCode = _text(data['accountCode']);
    final FinanceAccount? account = financeAccountByCode(accountCode);

    return JournalLine(
      accountCode: accountCode,
      accountName: _text(data['accountName']).isNotEmpty
          ? _text(data['accountName'])
          : (account?.name ?? ''),
      description: _text(data['description']),
      debit: _double(data['debit']),
      credit: _double(data['credit']),
    );
  }
}

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.number,
    required this.date,
    required this.description,
    required this.lines,
    this.sourceType = manualSource,
    this.sourceId = '',
    this.sourceNumber = '',
    this.projectId = '',
    this.projectCode = '',
    this.projectName = '',
    this.reference = '',
    this.createdByName = '',
    this.createdAt,
  });

  static const String manualSource = 'manual';
  static const String receiptSource = 'receipt';
  static const String paymentSource = 'payment';

  final String id;
  final String number;
  final DateTime date;
  final String description;
  final List<JournalLine> lines;

  /// manual / receipt / payment.
  final String sourceType;

  final String sourceId;
  final String sourceNumber;

  final String projectId;
  final String projectCode;
  final String projectName;

  /// مرجع خارجي اختياري.
  final String reference;

  final String createdByName;
  final DateTime? createdAt;

  bool get isManual => sourceType.isEmpty || sourceType == manualSource;

  bool get isFromReceipt => sourceType == receiptSource;

  bool get isFromPayment => sourceType == paymentSource;

  String get sourceLabel {
    if (isManual) return 'قيد يدوي';
    if (isFromReceipt) return 'من سند قبض';
    return 'من سند صرف';
  }

  double get totalDebit {
    return lines.fold<double>(0, (sum, line) => sum + line.debit);
  }

  double get totalCredit {
    return lines.fold<double>(0, (sum, line) => sum + line.credit);
  }

  /// الفرق بين المدين والدائن (يقبل كسر التقريب).
  double get difference => totalDebit - totalCredit;

  bool get isBalanced => difference.abs() < 0.005;

  factory JournalEntry.fromMap(String id, Map<String, dynamic> data) {
    final List<JournalLine> lines = <JournalLine>[];
    final dynamic rawLines = data['lines'];

    if (rawLines is Iterable) {
      for (final dynamic raw in rawLines) {
        if (raw is Map) {
          lines.add(JournalLine.fromMap(Map<String, dynamic>.from(raw)));
        }
      }
    }

    return JournalEntry(
      id: id,
      number: _text(data['number']),
      date: accountingDateOf(data['date']) ?? DateTime.now(),
      description: _text(data['description']),
      lines: lines,
      sourceType: _text(data['sourceType']).isEmpty
          ? manualSource
          : _text(data['sourceType']),
      sourceId: _text(data['sourceId']),
      sourceNumber: _text(data['sourceNumber']),
      projectId: _text(data['projectId']),
      projectCode: _text(data['projectCode']),
      projectName: _text(data['projectName']),
      reference: _text(data['reference']),
      createdByName: _text(data['createdByName']),
      createdAt: accountingDateOf(data['createdAt']),
    );
  }
}

// ============================================================
// حركة الصندوق
// ============================================================

enum CashMovementSource { voucher, journal }

class CashMovement {
  const CashMovement({
    required this.id,
    required this.relatedId,
    required this.reference,
    required this.category,
    required this.source,
    required this.date,
    required this.method,
    required this.description,
    this.party = '',
    this.inAmount = 0,
    this.outAmount = 0,
    this.voucherKind,
    this.projectId = '',
    this.projectName = '',
  });

  /// معرّف فريد للعرض (قد يكون مركّبًا لسطر القيد).
  final String id;

  /// معرّف السند أو القيد المرتبط.
  final String relatedId;

  final String reference;
  final String category;
  final CashMovementSource source;
  final DateTime date;
  final PaymentMethod method;
  final String description;
  final String party;
  final double inAmount;
  final double outAmount;
  final VoucherKind? voucherKind;

  /// المشروع الذي تخصّه الحركة (فارغ للحركات غير المرتبطة).
  final String projectId;
  final String projectName;

  double get net => inAmount - outAmount;

  bool get isIn => inAmount > 0;
}

class OpeningBalance {
  const OpeningBalance({this.cash = 0, this.bank = 0, this.updatedAt});

  final double cash;
  final double bank;
  final DateTime? updatedAt;

  double of(MoneyBoxFilter filter) {
    if (filter == MoneyBoxFilter.cash) return cash;
    if (filter == MoneyBoxFilter.bank) return bank;
    return cash + bank;
  }

  bool get isEmpty => cash == 0 && bank == 0;

  factory OpeningBalance.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const OpeningBalance();

    return OpeningBalance(
      cash: _double(data['cash']),
      bank: _double(data['bank']),
      updatedAt: accountingDateOf(data['updatedAt']),
    );
  }
}

/// يبني حركات الصندوق من السندات والقيود اليدوية.
///
/// قيود السندات لا تدخل هنا لأن السند نفسه هو الحركة؛ وإلا
/// لاحتسب المبلغ مرتين. قيود اليومية اليدوية  التي تمسّ
/// الصندوق أو البنك تُضاف بحسب الطرف المدين/الدائن.
List<CashMovement> buildCashMovements({
  required List<Voucher> vouchers,
  required List<JournalEntry> entries,
}) {
  final List<CashMovement> movements = <CashMovement>[];

  for (final Voucher voucher in vouchers) {
    movements.add(
      CashMovement(
        id: voucher.id,
        relatedId: voucher.id,
        reference: voucher.number,
        category: voucher.kind.title,
        source: CashMovementSource.voucher,
        date: voucher.date,
        method: voucher.method,
        description: voucher.description,
        party: voucher.partyName,
        inAmount: voucher.isReceipt ? voucher.amount : 0,
        outAmount: voucher.isPayment ? voucher.amount : 0,
        voucherKind: voucher.kind,
        projectId: voucher.projectId,
        projectName: voucher.projectName,
      ),
    );
  }

  for (final JournalEntry entry in entries) {
    if (!entry.isManual) continue;

    for (int index = 0; index < entry.lines.length; index++) {
      final JournalLine line = entry.lines[index];
      final bool isCash = line.accountCode == cashAccountCode;
      final bool isBank = line.accountCode == bankAccountCode;

      if (!isCash && !isBank) continue;
      if (line.debit <= 0 && line.credit <= 0) continue;

      movements.add(
        CashMovement(
          id: '${entry.id}#$index',
          relatedId: entry.id,
          reference: entry.number,
          category: 'قيد يومية',
          source: CashMovementSource.journal,
          date: entry.date,
          method: isCash ? PaymentMethod.cash : PaymentMethod.bank,
          description: line.description.isEmpty
              ? entry.description
              : line.description,
          inAmount: line.debit,
          outAmount: line.credit,
          voucherKind: null,
          projectId: entry.projectId,
          projectName: entry.projectName,
        ),
      );
    }
  }

  movements.sort((a, b) {
    final int byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    return a.reference.compareTo(b.reference);
  });

  return movements;
}

/// حركات مشروع معيّن فقط.
///
/// [projectId] فارغ ⇒ تُعاد كل الحركات (لا تصفية بالمشروع).
List<CashMovement> movementsForProject(
  List<CashMovement> movements,
  String projectId,
) {
  final String id = projectId.trim();
  if (id.isEmpty) return movements;

  return movements
      .where((movement) => movement.projectId == id)
      .toList();
}

/// هل الحركة تخصّ المشروع [projectId]؟ (فارغ = تخصّ الجميع)
bool movementBelongsTo(CashMovement movement, String projectId) {
  final String id = projectId.trim();
  return id.isEmpty || movement.projectId == id;
}

// ============================================================
// العمليات الحسابية
// ============================================================

class FinanceMath {
  FinanceMath._();

  static double openingOf(OpeningBalance opening, MoneyBoxFilter filter) {
    return opening.of(filter);
  }

  static double totalIn(Iterable<CashMovement> movements) {
    return movements.fold<double>(0, (sum, movement) => sum + movement.inAmount);
  }

  static double totalOut(Iterable<CashMovement> movements) {
    return movements.fold<double>(0, (sum, movement) => sum + movement.outAmount);
  }

  static double net(Iterable<CashMovement> movements) {
    return movements.fold<double>(0, (sum, movement) => sum + movement.net);
  }

  /// رصيد الصندوق/البنك الحالي = الافتتاحي + الوارد − الصادر.
  static double balance({
    required OpeningBalance opening,
    required List<CashMovement> movements,
    required MoneyBoxFilter filter,
  }) {
    double result = opening.of(filter);

    for (final CashMovement movement in movements) {
      if (!filter.matches(movement.method)) continue;
      result += movement.net;
    }

    return result;
  }

  /// الرصيد قبل تاريخ معيّن (لبداية كشف الفترة).
  static double balanceBefore({
    required OpeningBalance opening,
    required List<CashMovement> movements,
    required MoneyBoxFilter filter,
    required DateTime date,
  }) {
    double result = opening.of(filter);

    for (final CashMovement movement in movements) {
      if (!filter.matches(movement.method)) continue;
      if (!movement.date.isBefore(date)) continue;
      result += movement.net;
    }

    return result;
  }
}

// ============================================================
// تصفية القوائم
// ============================================================

List<Voucher> filterVouchers(
  List<Voucher> vouchers, {
  VoucherKind? kind,
  DateTime? start,
  DateTime? end,
  PaymentMethod? method,
  String? projectId,
  String search = '',
}) {
  final String query = search.trim().toLowerCase();

  return vouchers.where((voucher) {
    if (kind != null && voucher.kind != kind) return false;
    if (method != null && voucher.method != method) return false;
    if (projectId != null && voucher.projectId != projectId) return false;
    if (start != null && voucher.date.isBefore(start)) return false;
    if (end != null && voucher.date.isAfter(end)) return false;

    if (query.isEmpty) return true;

    final String haystack = <String>[
      voucher.number,
      voucher.partyName,
      voucher.description,
      voucher.accountName,
      voucher.projectCode,
      voucher.projectName,
      voucher.checkNumber,
    ].join(' ').toLowerCase();

    return haystack.contains(query);
  }).toList();
}

List<JournalEntry> filterJournalEntries(
  List<JournalEntry> entries, {
  DateTime? start,
  DateTime? end,
  String? projectId,
  String search = '',
}) {
  final String query = search.trim().toLowerCase();

  return entries.where((entry) {
    if (projectId != null && entry.projectId != projectId) return false;
    if (start != null && entry.date.isBefore(start)) return false;
    if (end != null && entry.date.isAfter(end)) return false;

    if (query.isEmpty) return true;

    final String haystack = <String>[
      entry.number,
      entry.description,
      entry.reference,
      entry.projectCode,
      entry.projectName,
      entry.sourceNumber,
      ...entry.lines.map((line) => line.accountName),
    ].join(' ').toLowerCase();

    return haystack.contains(query);
  }).toList();
}

/// مجموع السندات (قبض − صرف).
double netVouchers(List<Voucher> vouchers) {
  double result = 0;

  for (final Voucher voucher in vouchers) {
    result += voucher.isReceipt ? voucher.amount : -voucher.amount;
  }

  return result;
}

/// مجموع نوع واحد من السندات.
double sumVouchers(List<Voucher> vouchers, VoucherKind kind) {
  double result = 0;

  for (final Voucher voucher in vouchers) {
    if (voucher.kind == kind) result += voucher.amount;
  }

  return result;
}

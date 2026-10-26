import 'accounting_models.dart';

// ============================================================
// ميزانية المشروع — أصول وخصوم وحقوق ملكية وإيرادات ومصروفات
// ============================================================
//
// طبقة نقية (بلا Flutter) تُشتق من قيود اليومية والأرصدة
// الافتتاحية، حتى تُختبر الحسابات مباشرة وتُستخدم في صفحة
// «ميزانية المشاريع».
//
// القواعد:
//   • الأصول والمصروفات طبيعتها مدينة:
//       الرصيد = مدين − دائن.
//   • الخصوم وحقوق الملكية والإيرادات طبيعتها دائنة:
//       الرصيد = دائن − مدين.
//   • كل سند مرحّل إلى قيد، فقيود السندات داخلة في الحساب
//     تلقائيًا، ولا حاجة لقراءة السندات منفصلة.
//   • الرصيد الافتتاحي للصندوق والبنك يزيد الأصول، ويُقابله
//     بند حقوق ملكية «أرصدة افتتاحية» حتى تظل الميزانية
//     متوازنة.
//   • صافي نتيجة الفترة (إيرادات − مصروفات) يُضاف إلى حقوق
//     الملكية كبند مشتق، فتصبح المعادلة:
//       الأصول = الخصوم + حقوق الملكية.
// ============================================================

const String budgetUnassignedProjectId = '';

const String budgetUnassignedProjectLabel = 'بدون مشروع';

/// مرجع مشروع تُبنى له ميزانية (يُقرأ من مجموعة `projects`).
class BudgetProjectRef {
  const BudgetProjectRef({
    required this.id,
    this.code = '',
    this.name = '',
  });

  final String id;
  final String code;
  final String name;

  String get label {
    final String trimmedCode = code.trim();
    final String trimmedName = name.trim();

    if (trimmedCode.isNotEmpty && trimmedName.isNotEmpty) {
      return '$trimmedCode — $trimmedName';
    }
    if (trimmedName.isNotEmpty) return trimmedName;
    if (trimmedCode.isNotEmpty) return trimmedCode;
    if (id.isEmpty) return budgetUnassignedProjectLabel;
    return id;
  }
}

/// سطر حساب داخل قسم من الميزانية.
class BudgetAccountLine {
  const BudgetAccountLine({
    required this.code,
    required this.name,
    required this.amount,
    this.derived = false,
  });

  final String code;
  final String name;

  /// الرصيد بالطبيعة الحسابية للقسم (موجب = رصيد طبيعي).
  final double amount;

  /// بند مشتق لا حساب له في دليل الحسابات (أرصدة افتتاحية،
  /// صافي نتيجة الفترة).
  final bool derived;

  bool get hasAmount => amount.abs() >= 0.005;

  String get label => code.isEmpty ? name : '$code — $name';
}

/// قسم من أقسام الميزانية (أصول / خصوم / حقوق ملكية / إيرادات /
/// مصروفات) وما يشمله من حسابات.
class BudgetSection {
  const BudgetSection({required this.kind, required this.lines});

  final FinanceAccountKind kind;

  /// كل حسابات القسم من دليل الحسابات (حتى الصفرية) مع الحسابات
  /// الإضافية التي ظهرت في القيود، ثم البنود المشتقة.
  final List<BudgetAccountLine> lines;

  double get total {
    return lines.fold<double>(0, (sum, line) => sum + line.amount);
  }

  List<BudgetAccountLine> get activeLines {
    return lines.where((line) => line.hasAmount).toList();
  }

  bool get isEmpty => activeLines.isEmpty;

  BudgetAccountLine? lineOf(String code) {
    for (final BudgetAccountLine line in lines) {
      if (line.code == code) return line;
    }
    return null;
  }
}

/// ميزانية مشروع واحد: الأقسام الخمسة ومجاميعها ومعادلة التوازن.
class ProjectBudget {
  const ProjectBudget({
    required this.projectId,
    required this.projectCode,
    required this.projectName,
    required this.sections,
    this.entriesCount = 0,
    this.isTotal = false,
  });

  /// معرّف المشروع (فارغ = حركات بلا مشروع).
  final String projectId;

  final String projectCode;
  final String projectName;

  final List<BudgetSection> sections;

  /// عدد القيود الداخلة في الحساب.
  final int entriesCount;

  /// هل هذه ميزانية إجمالية لكل المشاريع؟
  final bool isTotal;

  String get label {
    if (isTotal) return 'إجمالي كل المشاريع';
    if (projectId.trim().isEmpty) return budgetUnassignedProjectLabel;

    final String trimmedCode = projectCode.trim();
    final String trimmedName = projectName.trim();

    if (trimmedCode.isNotEmpty && trimmedName.isNotEmpty) {
      return '$trimmedCode — $trimmedName';
    }
    if (trimmedName.isNotEmpty) return trimmedName;
    if (trimmedCode.isNotEmpty) return trimmedCode;
    return projectId;
  }

  BudgetSection sectionOf(FinanceAccountKind kind) {
    for (final BudgetSection section in sections) {
      if (section.kind == kind) return section;
    }
    return BudgetSection(kind: kind, lines: const <BudgetAccountLine>[]);
  }

  double get totalAssets => sectionOf(FinanceAccountKind.asset).total;

  double get totalLiabilities =>
      sectionOf(FinanceAccountKind.liability).total;

  /// حقوق الملكية شاملة الأرصدة الافتتاحية وصافي نتيجة الفترة.
  double get totalEquity => sectionOf(FinanceAccountKind.equity).total;

  /// حقوق الملكية من حسابات الدليل فقط (بلا البنود المشتقة).
  double get equityAccountsTotal {
    return sectionOf(FinanceAccountKind.equity)
        .lines
        .where((line) => !line.derived)
        .fold<double>(0, (sum, line) => sum + line.amount);
  }

  /// البنود المشتقة في حقوق الملكية (افتتاحي + صافي النتيجة).
  double get equityDerivedTotal {
    return sectionOf(FinanceAccountKind.equity)
        .lines
        .where((line) => line.derived)
        .fold<double>(0, (sum, line) => sum + line.amount);
  }

  double get totalRevenues => sectionOf(FinanceAccountKind.revenue).total;

  double get totalExpenses => sectionOf(FinanceAccountKind.expense).total;

  /// صافي النتيجة = إيرادات − مصروفات (موجب = ربح).
  double get netResult => totalRevenues - totalExpenses;

  double get totalLiabilitiesAndEquity => totalLiabilities + totalEquity;

  /// فرق الميزانية: الأصول − (الخصوم + حقوق الملكية).
  double get difference => totalAssets - totalLiabilitiesAndEquity;

  bool get isBalanced => difference.abs() < 0.005;

  bool get isEmpty => entriesCount == 0 && sections.every((s) => s.isEmpty);

  int get activeAccountsCount {
    return sections.fold<int>(
      0,
      (sum, section) => sum + section.activeLines.length,
    );
  }
}

/// اسم القسم بالعربية — «الخصوم» هنا بمعنى الالتزامات.
String budgetSectionLabel(FinanceAccountKind kind) {
  switch (kind) {
    case FinanceAccountKind.asset:
      return 'الأصول';
    case FinanceAccountKind.liability:
      return 'الخصوم';
    case FinanceAccountKind.equity:
      return 'حقوق الملكية';
    case FinanceAccountKind.revenue:
      return 'الإيرادات';
    case FinanceAccountKind.expense:
      return 'المصروفات';
  }
}

/// كل حسابات دليل الحسابات التابعة لقسم معيّن.
List<FinanceAccount> financeAccountsOfKind(FinanceAccountKind kind) {
  return financeChartOfAccounts
      .where((account) => account.kind == kind)
      .toList();
}

class _MutableAccountLine {
  _MutableAccountLine({
    required this.code,
    required this.name,
    required this.kind,
  });

  final String code;
  String name;
  final FinanceAccountKind kind;
  double amount = 0;
}

/// تصنيف حساب غير مذكور في الدليل بحسب أول رقم من كوده:
/// 1 أصول، 2 خصوم، 3 حقوق ملكية، 4 إيرادات، 5 مصروفات.
FinanceAccountKind? financeKindByAccountCode(String code) {
  final String value = code.trim();
  if (value.isEmpty) return null;

  switch (value[0]) {
    case '1':
      return FinanceAccountKind.asset;
    case '2':
      return FinanceAccountKind.liability;
    case '3':
      return FinanceAccountKind.equity;
    case '4':
      return FinanceAccountKind.revenue;
    case '5':
      return FinanceAccountKind.expense;
    default:
      return null;
  }
}

/// ميزانية مشروع واحد.
///
/// [projectId]:
///   • نص فارغ = الحركات بلا مشروع فقط.
///   • معرّف مشروع = حركات هذا المشروع فقط.
///   • [isTotal] = true = كل الحركات مهما كان مشروعها.
///
/// [asOf] نهاية الفترة: تُحتسب القيود حتى هذا التاريخ فقط
/// (شاملة)، وتبقى الأرصدة الافتتاحية كما هي.
ProjectBudget buildProjectBudget({
  required List<JournalEntry> entries,
  OpeningBalance opening = const OpeningBalance(),
  String projectId = budgetUnassignedProjectId,
  String projectCode = '',
  String projectName = '',
  DateTime? asOf,
  bool isTotal = false,
}) {
  final Map<String, _MutableAccountLine> accounts =
      <String, _MutableAccountLine>{};
  final String scopeId = projectId.trim();
  int entriesCount = 0;

  for (final JournalEntry entry in entries) {
    if (!isTotal && entry.projectId.trim() != scopeId) continue;
    if (asOf != null && entry.date.isAfter(asOf)) continue;

    entriesCount++;

    for (final JournalLine line in entry.lines) {
      final String code = line.accountCode.trim();
      final FinanceAccount? account = financeAccountByCode(code);
      final FinanceAccountKind? kind =
          account?.kind ?? financeKindByAccountCode(code);
      if (kind == null) continue;

      final double signedAmount =
          (kind == FinanceAccountKind.asset ||
                  kind == FinanceAccountKind.expense)
              ? line.debit - line.credit
              : line.credit - line.debit;

      final String fallbackName = line.accountName.trim();
      final String name = account?.name ??
          (fallbackName.isNotEmpty ? fallbackName : 'حساب $code');
      final String key = code.isEmpty ? 'name:$name' : code;

      final _MutableAccountLine item = accounts.putIfAbsent(
        key,
        () => _MutableAccountLine(code: code, name: name, kind: kind),
      );
      item.amount += signedAmount;
      if (item.name.isEmpty && name.isNotEmpty) item.name = name;
    }
  }

  // الأرصدة الافتتاحية: نقد الصندوق والبنك تُضاف إلى الأصول.
  if (opening.cash != 0) {
    _addOpeningAmount(
      accounts,
      account: cashFinanceAccount,
      amount: opening.cash,
    );
  }
  if (opening.bank != 0) {
    _addOpeningAmount(
      accounts,
      account: bankFinanceAccount,
      amount: opening.bank,
    );
  }

  double totalOf(FinanceAccountKind kind) {
    return accounts.values
        .where((item) => item.kind == kind)
        .fold<double>(0, (sum, item) => sum + item.amount);
  }

  final double revenues = totalOf(FinanceAccountKind.revenue);
  final double expenses = totalOf(FinanceAccountKind.expense);
  final double netResult = revenues - expenses;
  final double openingTotal = opening.cash + opening.bank;

  final List<BudgetSection> sections = <BudgetSection>[];

  for (final FinanceAccountKind kind in FinanceAccountKind.values) {
    final List<BudgetAccountLine> lines = <BudgetAccountLine>[];

    // حسابات الدليل المعتمدة بترتيبها، حتى الصفرية، ليعرف
    // المستخدم ما يمكن أن يشمل عليه القسم.
    for (final FinanceAccount account in financeAccountsOfKind(kind)) {
      final _MutableAccountLine? item = accounts[account.code];
      lines.add(
        BudgetAccountLine(
          code: account.code,
          name: account.name,
          amount: item?.amount ?? 0,
        ),
      );
    }

    // حسابات إضافية ظهرت في القيود وليست في الدليل.
    final List<_MutableAccountLine> extra = accounts.values
        .where((item) {
          return item.kind == kind &&
              financeAccountByCode(item.code) == null;
        })
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));

    for (final _MutableAccountLine item in extra) {
      lines.add(
        BudgetAccountLine(
          code: item.code,
          name: item.name,
          amount: item.amount,
        ),
      );
    }

    // بنود حقوق الملكية المشتقة التي تجعل الميزانية متوازنة.
    if (kind == FinanceAccountKind.equity) {
      if (openingTotal.abs() >= 0.005) {
        lines.add(
          BudgetAccountLine(
            code: '',
            name: 'أرصدة افتتاحية (الصندوق والبنك)',
            amount: openingTotal,
            derived: true,
          ),
        );
      }
      if (netResult.abs() >= 0.005) {
        lines.add(
          BudgetAccountLine(
            code: '',
            name: 'صافي نتيجة الفترة (إيرادات − مصروفات)',
            amount: netResult,
            derived: true,
          ),
        );
      }
    }

    sections.add(BudgetSection(kind: kind, lines: lines));
  }

  return ProjectBudget(
    projectId: scopeId,
    projectCode: projectCode,
    projectName: projectName,
    sections: sections,
    entriesCount: entriesCount,
    isTotal: isTotal,
  );
}

void _addOpeningAmount(
  Map<String, _MutableAccountLine> accounts, {
  required FinanceAccount account,
  required double amount,
}) {
  final _MutableAccountLine item = accounts.putIfAbsent(
    account.code,
    () => _MutableAccountLine(
      code: account.code,
      name: account.name,
      kind: account.kind,
    ),
  );
  item.amount += amount;
}

/// ميزانيات كل المشاريع:
///   • كل مشروع في [projects] حتى لو لم تكن له حركة.
///   • كل مشروع ظهر في القيود ولم يُذكر في القائمة.
///   • «بدون مشروع» إن وُجدت حركات أو رصيد افتتاحي بلا مشروع.
List<ProjectBudget> buildProjectBudgets({
  required List<JournalEntry> entries,
  Map<String, OpeningBalance> openings =
      const <String, OpeningBalance>{},
  List<BudgetProjectRef> projects = const <BudgetProjectRef>[],
  DateTime? asOf,
  bool includeUnassigned = true,
}) {
  final Map<String, BudgetProjectRef> refs = <String, BudgetProjectRef>{};

  void addRef(BudgetProjectRef ref) {
    final String id = ref.id.trim();
    if (id.isEmpty) return;

    final BudgetProjectRef? existing = refs[id];
    if (existing == null) {
      refs[id] = BudgetProjectRef(
        id: id,
        code: ref.code.trim(),
        name: ref.name.trim(),
      );
      return;
    }

    refs[id] = BudgetProjectRef(
      id: id,
      code: existing.code.isNotEmpty ? existing.code : ref.code.trim(),
      name: existing.name.isNotEmpty ? existing.name : ref.name.trim(),
    );
  }

  for (final BudgetProjectRef project in projects) {
    addRef(project);
  }

  for (final JournalEntry entry in entries) {
    addRef(
      BudgetProjectRef(
        id: entry.projectId,
        code: entry.projectCode,
        name: entry.projectName,
      ),
    );
  }

  // مشروع له رصيد افتتاحي فقط (بلا قيود) يبقى ظاهرًا بميزانيته،
  // خاصة إن حُذفت وثيقته من مجموعة `projects`.
  for (final String id in openings.keys) {
    addRef(BudgetProjectRef(id: id));
  }

  final List<BudgetProjectRef> ordered = refs.values.toList()
    ..sort((a, b) => a.label.compareTo(b.label));

  final List<ProjectBudget> budgets = ordered.map((ref) {
    return buildProjectBudget(
      entries: entries,
      opening: openings[ref.id] ?? const OpeningBalance(),
      projectId: ref.id,
      projectCode: ref.code,
      projectName: ref.name,
      asOf: asOf,
    );
  }).toList();

  if (includeUnassigned) {
    final OpeningBalance unassignedOpening =
        openings[budgetUnassignedProjectId] ?? const OpeningBalance();
    final bool hasEntries = entries.any((entry) {
      if (entry.projectId.trim().isNotEmpty) return false;
      if (asOf != null && entry.date.isAfter(asOf)) return false;
      return true;
    });

    if (hasEntries || !unassignedOpening.isEmpty) {
      budgets.add(
        buildProjectBudget(
          entries: entries,
          opening: unassignedOpening,
          projectId: budgetUnassignedProjectId,
          asOf: asOf,
        ),
      );
    }
  }

  return budgets;
}

/// ميزانية إجمالية لكل المشاريع (بكل قيودها وأرصدتها الافتتاحية).
ProjectBudget buildTotalProjectBudget({
  required List<JournalEntry> entries,
  Map<String, OpeningBalance> openings =
      const <String, OpeningBalance>{},
  DateTime? asOf,
}) {
  double cash = 0;
  double bank = 0;

  for (final OpeningBalance opening in openings.values) {
    cash += opening.cash;
    bank += opening.bank;
  }

  return buildProjectBudget(
    entries: entries,
    opening: OpeningBalance(cash: cash, bank: bank),
    isTotal: true,
    asOf: asOf,
  );
}

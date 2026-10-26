import 'package:azal/features/accounting/accounting_models.dart';
import 'package:azal/features/accounting/project_budget.dart';
import 'package:flutter_test/flutter_test.dart';

// ============================================================
// اختبارات ميزانية المشروع
// ============================================================
//
// • اشتقاق أرصدة الأقسام من القيود بالطبيعة المحاسبية.
// • إدخال الرصيد الافتتاحي في الأصول ومقابله في حقوق الملكية.
// • صافي النتيجة داخل حقوق الملكية حتى تتوازن الميزانية.
// • تصفية المشروع وتاريخ نهاية الفترة.
// • تجميع ميزانيات كل المشاريع والإجمالي.

JournalLine _line(
  String code, {
  double debit = 0,
  double credit = 0,
  String name = '',
}) {
  return JournalLine(
    accountCode: code,
    accountName:
        name.isNotEmpty ? name : (financeAccountByCode(code)?.name ?? ''),
    debit: debit,
    credit: credit,
  );
}

JournalEntry _entry({
  String id = 'e1',
  String number = 'قيد-0001',
  DateTime? date,
  required List<JournalLine> lines,
  String projectId = '',
  String projectCode = '',
  String projectName = '',
}) {
  return JournalEntry(
    id: id,
    number: number,
    date: date ?? DateTime(2026, 10, 10),
    description: 'قيد',
    lines: lines,
    projectId: projectId,
    projectCode: projectCode,
    projectName: projectName,
  );
}

void main() {
  group('اشتقاق أقسام الميزانية', () {
    test('قبض نقدي: أصول وإيرادات وصافي نتيجة متوازن', () {
      final ProjectBudget budget = buildProjectBudget(
        entries: <JournalEntry>[
          _entry(
            lines: <JournalLine>[
              _line(cashAccountCode, debit: 150000),
              _line('4000', credit: 150000),
            ],
          ),
        ],
      );

      expect(budget.totalAssets, 150000);
      expect(budget.totalLiabilities, 0);
      expect(budget.totalRevenues, 150000);
      expect(budget.totalExpenses, 0);
      expect(budget.netResult, 150000);
      expect(budget.totalEquity, 150000);
      expect(budget.equityAccountsTotal, 0);
      expect(budget.equityDerivedTotal, 150000);
      expect(budget.difference, 0);
      expect(budget.isBalanced, isTrue);
      expect(budget.entriesCount, 1);

      final BudgetSection assets =
          budget.sectionOf(FinanceAccountKind.asset);
      expect(assets.lineOf(cashAccountCode)?.amount, 150000);
      expect(assets.lineOf(bankAccountCode)?.amount, 0);
    });

    test('صرف من البنك مع رصيد افتتاحي: يظل متوازنًا', () {
      final ProjectBudget budget = buildProjectBudget(
        entries: <JournalEntry>[
          _entry(
            lines: <JournalLine>[
              _line('5100', debit: 50000),
              _line(bankAccountCode, credit: 50000),
            ],
          ),
        ],
        opening: const OpeningBalance(cash: 200000),
      );

      expect(budget.totalAssets, 150000);
      expect(budget.totalExpenses, 50000);
      expect(budget.netResult, -50000);
      expect(budget.totalEquity, 150000);
      expect(budget.difference, 0);
      expect(budget.isBalanced, isTrue);

      final BudgetSection equity =
          budget.sectionOf(FinanceAccountKind.equity);
      expect(equity.activeLines.length, 2);
      expect(
        equity.lines.any((line) => line.derived && line.amount == 200000),
        isTrue,
      );
    });

    test('شراء بالأجل: خصوم تقابلها خسارة في حقوق الملكية', () {
      final ProjectBudget budget = buildProjectBudget(
        entries: <JournalEntry>[
          _entry(
            lines: <JournalLine>[
              _line('5100', debit: 30000),
              _line('2000', credit: 30000),
            ],
          ),
        ],
      );

      expect(budget.totalAssets, 0);
      expect(budget.totalLiabilities, 30000);
      expect(budget.totalEquity, -30000);
      expect(budget.totalLiabilitiesAndEquity, 0);
      expect(budget.netResult, -30000);
      expect(budget.isBalanced, isTrue);
    });

    test('كل حسابات دليل الحسابات تظهر في قسمها ولو كانت صفرية', () {
      final ProjectBudget budget = buildProjectBudget(
        entries: const <JournalEntry>[],
      );

      for (final FinanceAccountKind kind in FinanceAccountKind.values) {
        final List<String> expected = financeAccountsOfKind(kind)
            .map((account) => account.code)
            .toList();
        final BudgetSection section = budget.sectionOf(kind);

        expect(
          section.lines.map((line) => line.code).toList(),
          containsAll(expected),
        );
      }

      expect(budget.isEmpty, isTrue);
      expect(budget.isBalanced, isTrue);
    });

    test('حساب إضافي خارج الدليل يُصنّف بحسب أول رقم من كوده', () {
      final ProjectBudget budget = buildProjectBudget(
        entries: <JournalEntry>[
          _entry(
            lines: <JournalLine>[
              _line('1150', debit: 700, name: 'ذمم أخرى'),
              _line('4000', credit: 700),
            ],
          ),
        ],
      );

      final BudgetSection assets =
          budget.sectionOf(FinanceAccountKind.asset);
      final BudgetAccountLine? extra = assets.lineOf('1150');

      expect(extra, isNotNull);
      expect(extra!.name, 'ذمم أخرى');
      expect(extra.amount, 700);
      expect(budget.totalAssets, 700);
      expect(budget.isBalanced, isTrue);
    });
  });

  group('تصفية المشروع والفترة', () {
    final List<JournalEntry> entries = <JournalEntry>[
      _entry(
        id: 'e1',
        number: 'قيد-0001',
        projectId: 'p1',
        projectCode: '100',
        projectName: 'طريق إب',
        lines: <JournalLine>[
          _line(cashAccountCode, debit: 100),
          _line('4000', credit: 100),
        ],
      ),
      _entry(
        id: 'e2',
        number: 'قيد-0002',
        projectId: 'p2',
        projectCode: '200',
        projectName: 'مدرسة',
        lines: <JournalLine>[
          _line(cashAccountCode, debit: 200),
          _line('4000', credit: 200),
        ],
      ),
      _entry(
        id: 'e3',
        number: 'قيد-0003',
        lines: <JournalLine>[
          _line(cashAccountCode, debit: 50),
          _line('4000', credit: 50),
        ],
      ),
    ];

    test('ميزانية مشروع واحد لا تتأثر بغيره', () {
      final ProjectBudget budget = buildProjectBudget(
        entries: entries,
        projectId: 'p1',
        projectCode: '100',
        projectName: 'طريق إب',
      );

      expect(budget.label, '100 — طريق إب');
      expect(budget.totalAssets, 100);
      expect(budget.totalRevenues, 100);
      expect(budget.entriesCount, 1);
    });

    test('تجميع كل المشاريع مع «بدون مشروع»', () {
      final List<ProjectBudget> budgets = buildProjectBudgets(
        entries: entries,
        projects: const <BudgetProjectRef>[
          BudgetProjectRef(id: 'p1', code: '100', name: 'طريق إب'),
          BudgetProjectRef(id: 'p2', code: '200', name: 'مدرسة'),
          BudgetProjectRef(id: 'p3', code: '300', name: 'بلا حركة'),
        ],
      );

      expect(budgets.length, 4);
      expect(budgets.first.label, '100 — طريق إب');
      expect(budgets[1].label, '200 — مدرسة');
      expect(budgets[2].label, '300 — بلا حركة');
      expect(budgets[2].isEmpty, isTrue);
      expect(budgets.last.label, budgetUnassignedProjectLabel);
      expect(budgets.last.totalAssets, 50);
    });

    test('الإجمالي يجمع كل القيود والأرصدة الافتتاحية', () {
      final ProjectBudget total = buildTotalProjectBudget(
        entries: entries,
        openings: const <String, OpeningBalance>{
          'p1': OpeningBalance(cash: 1000),
          'p2': OpeningBalance(bank: 2000),
          '': OpeningBalance(cash: 300),
        },
      );

      expect(total.isTotal, isTrue);
      expect(total.totalAssets, 3650);
      expect(total.totalRevenues, 350);
      expect(total.netResult, 350);
      expect(total.totalEquity, 3650);
      expect(total.isBalanced, isTrue);
      expect(total.entriesCount, 3);
    });

    test('asOf يستبعد القيود اللاحقة', () {
      final List<JournalEntry> dated = <JournalEntry>[
        _entry(
          id: 'oct',
          date: DateTime(2026, 10, 1),
          lines: <JournalLine>[
            _line(cashAccountCode, debit: 100),
            _line('4000', credit: 100),
          ],
        ),
        _entry(
          id: 'nov',
          date: DateTime(2026, 11, 1),
          lines: <JournalLine>[
            _line(cashAccountCode, debit: 200),
            _line('4000', credit: 200),
          ],
        ),
      ];

      final ProjectBudget budget = buildProjectBudget(
        entries: dated,
        asOf: DateTime(2026, 10, 31, 23, 59, 59),
      );

      expect(budget.entriesCount, 1);
      expect(budget.totalAssets, 100);
      expect(budget.totalRevenues, 100);
    });
  });

  group('صلاحية الوصول إلى ميزانية المشاريع', () {
    test('المحاسب المربوط بمشروع: يفتح ميزانية مشروعه فقط', () {
      expect(
        canAccessProjectBudgets(
          isScopedToProject: true,
          canViewAllProjects: false,
        ),
        isTrue,
      );
    });

    test('المحاسب غير المربوط: لا يصل إلى ميزانية أي مشروع', () {
      expect(
        canAccessProjectBudgets(
          isScopedToProject: false,
          canViewAllProjects: false,
        ),
        isFalse,
      );
    });

    test('المدير المالي: يفتح ميزانية كل المشاريع', () {
      expect(
        canAccessProjectBudgets(
          isScopedToProject: false,
          canViewAllProjects: true,
        ),
        isTrue,
      );
    });
  });

  group('الرصيد الافتتاحي', () {
    test('بلا حركات: أصول وحقوق ملكية متساوية', () {
      final ProjectBudget budget = buildProjectBudget(
        entries: const <JournalEntry>[],
        opening: const OpeningBalance(cash: 500, bank: 1500),
      );

      expect(budget.totalAssets, 2000);
      expect(budget.totalEquity, 2000);
      expect(budget.totalRevenues, 0);
      expect(budget.totalExpenses, 0);
      expect(budget.isBalanced, isTrue);
      expect(budget.isEmpty, isFalse);
      expect(budget.entriesCount, 0);
    });

    test('مشروع له رصيد افتتاحي فقط يظهر ولو لم يكن في قائمة المشاريع', () {
      final List<ProjectBudget> budgets = buildProjectBudgets(
        entries: const <JournalEntry>[],
        openings: const <String, OpeningBalance>{
          'p9': OpeningBalance(cash: 250),
        },
      );

      expect(budgets.length, 1);
      expect(budgets.first.projectId, 'p9');
      expect(budgets.first.label, 'p9');
      expect(budgets.first.totalAssets, 250);
      expect(budgets.first.isBalanced, isTrue);
    });

    test('ميزانية مشروع تستخدم رصيدها الافتتاحي وحده', () {
      final List<ProjectBudget> budgets = buildProjectBudgets(
        entries: const <JournalEntry>[],
        openings: const <String, OpeningBalance>{
          'p1': OpeningBalance(cash: 400),
          'p2': OpeningBalance(cash: 700),
        },
        projects: const <BudgetProjectRef>[
          BudgetProjectRef(id: 'p1', code: '100', name: 'طريق إب'),
          BudgetProjectRef(id: 'p2', code: '200', name: 'مدرسة'),
        ],
      );

      expect(budgets.length, 2);
      expect(
        budgets.firstWhere((b) => b.projectId == 'p1').totalAssets,
        400,
      );
      expect(
        budgets.firstWhere((b) => b.projectId == 'p2').totalAssets,
        700,
      );
    });
  });
}

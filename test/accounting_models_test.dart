import 'package:azal/features/accounting/accounting_models.dart';
import 'package:flutter_test/flutter_test.dart';

// ============================================================
// اختبارات وحدة الحسابات — النماذج والحسابات النقية
// ============================================================

Voucher _voucher({
  required VoucherKind kind,
  required double amount,
  required PaymentMethod method,
  DateTime? date,
  String projectId = '',
  String projectName = '',
  String accountCode = '4000',
  String accountName = 'إيرادات المشاريع',
  String number = 'قبض-0001',
  String party = 'جهة',
  String description = 'بيان',
}) {
  return Voucher(
    id: '$number-${kind.key}',
    kind: kind,
    number: number,
    date: date ?? DateTime(2026, 10, 10),
    amount: amount,
    method: method,
    partyName: party,
    description: description,
    accountCode: accountCode,
    accountName: accountName,
    projectId: projectId,
    projectName: projectName,
  );
}

JournalEntry _entry({
  required String id,
  required List<JournalLine> lines,
  String sourceType = JournalEntry.manualSource,
  DateTime? date,
  String number = 'قيد-0001',
  String description = 'قيد',
  String projectId = '',
}) {
  return JournalEntry(
    id: id,
    number: number,
    date: date ?? DateTime(2026, 10, 10),
    description: description,
    lines: lines,
    sourceType: sourceType,
    projectId: projectId,
  );
}

void main() {
  group('أنواع السندات وطرق الدفع', () {
    test('تحويل مفاتيح السندات', () {
      expect(VoucherKind.fromKey('receipt'), VoucherKind.receipt);
      expect(VoucherKind.fromKey('payment'), VoucherKind.payment);
      expect(VoucherKind.fromKey('anything'), VoucherKind.receipt);
      expect(VoucherKind.receipt.numberPrefix, 'قبض');
      expect(VoucherKind.payment.numberPrefix, 'صرف');
    });

    test('تحويل طرق الدفع', () {
      expect(PaymentMethod.fromKey('cash'), PaymentMethod.cash);
      expect(PaymentMethod.fromKey('bank'), PaymentMethod.bank);
      expect(PaymentMethod.fromKey('check'), PaymentMethod.check);
      expect(PaymentMethod.fromKey(''), PaymentMethod.cash);

      expect(PaymentMethod.cash.isCash, isTrue);
      expect(PaymentMethod.cash.isBankMoney, isFalse);
      expect(PaymentMethod.bank.isCash, isFalse);
      expect(PaymentMethod.bank.isBankMoney, isTrue);
      expect(PaymentMethod.check.isBankMoney, isTrue);
    });

    test('تبويبات الصندوق', () {
      expect(MoneyBoxFilter.cash.matches(PaymentMethod.cash), isTrue);
      expect(MoneyBoxFilter.cash.matches(PaymentMethod.bank), isFalse);
      expect(MoneyBoxFilter.bank.matches(PaymentMethod.check), isTrue);
      expect(MoneyBoxFilter.all.matches(PaymentMethod.cash), isTrue);
      expect(MoneyBoxFilter.all.matches(PaymentMethod.bank), isTrue);
    });
  });

  group('دليل الحسابات', () {
    test('الحسابات النقدية', () {
      expect(financeAccountByCode(cashAccountCode)?.isCash, isTrue);
      expect(financeAccountByCode(bankAccountCode)?.isBank, isTrue);
      expect(financeAccountByCode('9999'), isNull);
    });

    test('الحسابات المقابلة في السند تستثني الصندوق والبنك', () {
      expect(voucherCounterAccounts, isNotEmpty);
      expect(
        voucherCounterAccounts.any((account) => account.code == cashAccountCode),
        isFalse,
      );
      expect(
        voucherCounterAccounts.any((account) => account.code == bankAccountCode),
        isFalse,
      );
      expect(
        voucherCounterAccounts.any((account) => account.code == '4000'),
        isTrue,
      );
    });
  });

  group('الرصيد الافتتاحي', () {
    test('القراءة والقيم', () {
      final OpeningBalance opening = OpeningBalance.fromMap(
        <String, dynamic>{'cash': 500, 'bank': '1500.5'},
      );

      expect(opening.cash, 500);
      expect(opening.bank, 1500.5);
      expect(opening.of(MoneyBoxFilter.cash), 500);
      expect(opening.of(MoneyBoxFilter.bank), 1500.5);
      expect(opening.of(MoneyBoxFilter.all), 2000.5);
      expect(const OpeningBalance().isEmpty, isTrue);
    });
  });

  group('حركة الصندوق', () {
    test('السندات والقيود اليدوية فقط تدخل الحركة', () {
      final List<Voucher> vouchers = <Voucher>[
        _voucher(
          kind: VoucherKind.receipt,
          amount: 1000,
          method: PaymentMethod.cash,
          number: 'قبض-0001',
        ),
        _voucher(
          kind: VoucherKind.payment,
          amount: 400,
          method: PaymentMethod.bank,
          number: 'صرف-0001',
        ),
      ];

      final List<JournalEntry> entries = <JournalEntry>[
        // قيد سند قبض: لا يُحتسب مرتين.
        _entry(
          id: 'auto-receipt',
          sourceType: JournalEntry.receiptSource,
          lines: const <JournalLine>[
            JournalLine(
              accountCode: cashAccountCode,
              accountName: 'الصندوق',
              debit: 1000,
            ),
            JournalLine(
              accountCode: '4000',
              accountName: 'إيرادات',
              credit: 1000,
            ),
          ],
        ),
        // قيد يدوي يمسّ الصندوق: يُحتسب.
        _entry(
          id: 'manual-cash',
          number: 'قيد-0002',
          lines: const <JournalLine>[
            JournalLine(
              accountCode: cashAccountCode,
              accountName: 'الصندوق',
              debit: 250,
              description: 'إيداع',
            ),
            JournalLine(
              accountCode: '3000',
              accountName: 'تمويل',
              credit: 250,
            ),
          ],
        ),
        // قيد يدوي لا يمسّ النقد: لا يُحتسب.
        _entry(
          id: 'manual-expense',
          number: 'قيد-0003',
          lines: const <JournalLine>[
            JournalLine(
              accountCode: '5100',
              accountName: 'مواد',
              debit: 90,
            ),
            JournalLine(
              accountCode: '2000',
              accountName: 'مورّدون',
              credit: 90,
            ),
          ],
        ),
      ];

      final List<CashMovement> movements = buildCashMovements(
        vouchers: vouchers,
        entries: entries,
      );

      expect(movements.length, 3);
      expect(
        movements.any((movement) => movement.id == 'auto-receipt'),
        isFalse,
      );
      expect(
        movements.any((movement) => movement.id == 'manual-expense'),
        isFalse,
      );

      final double cash = FinanceMath.balance(
        opening: const OpeningBalance(cash: 500, bank: 100),
        movements: movements,
        filter: MoneyBoxFilter.cash,
      );
      final double bank = FinanceMath.balance(
        opening: const OpeningBalance(cash: 500, bank: 100),
        movements: movements,
        filter: MoneyBoxFilter.bank,
      );

      // 500 + 1000 (سند قبض) + 250 (قيد) = 1750
      expect(cash, 1750);
      // 100 − 400 (سند صرف بنكي) = −300
      expect(bank, -300);
    });

    test('الرصيد قبل تاريخ معيّن', () {
      final List<CashMovement> movements = <CashMovement>[
        CashMovement(
          id: '1',
          relatedId: '1',
          reference: 'قبض-0001',
          category: 'سند قبض',
          source: CashMovementSource.voucher,
          date: DateTime(2026, 9, 5),
          method: PaymentMethod.cash,
          description: 'سبتمبر',
          inAmount: 100,
        ),
        CashMovement(
          id: '2',
          relatedId: '2',
          reference: 'قبض-0002',
          category: 'سند قبض',
          source: CashMovementSource.voucher,
          date: DateTime(2026, 10, 5),
          method: PaymentMethod.cash,
          description: 'أكتوبر',
          inAmount: 50,
        ),
      ];

      expect(
        FinanceMath.balanceBefore(
          opening: const OpeningBalance(cash: 20),
          movements: movements,
          filter: MoneyBoxFilter.cash,
          date: DateTime(2026, 10, 1),
        ),
        120,
      );
    });

    test('مجموع الوارد والصادر', () {
      final List<CashMovement> movements = <CashMovement>[
        CashMovement(
          id: '1',
          relatedId: '1',
          reference: '1',
          category: 'قبض',
          source: CashMovementSource.voucher,
          date: DateTime(2026, 10, 1),
          method: PaymentMethod.cash,
          description: '',
          inAmount: 700,
        ),
        CashMovement(
          id: '2',
          relatedId: '2',
          reference: '2',
          category: 'صرف',
          source: CashMovementSource.voucher,
          date: DateTime(2026, 10, 2),
          method: PaymentMethod.cash,
          description: '',
          outAmount: 200,
        ),
      ];

      expect(FinanceMath.totalIn(movements), 700);
      expect(FinanceMath.totalOut(movements), 200);
      expect(FinanceMath.net(movements), 500);
    });
  });

  group('توازن القيد', () {
    test('القيد المتوازن وغير المتوازن', () {
      final JournalEntry balanced = _entry(
        id: 'balanced',
        lines: const <JournalLine>[
          JournalLine(
            accountCode: '5100',
            accountName: 'مواد',
            debit: 300,
          ),
          JournalLine(
            accountCode: cashAccountCode,
            accountName: 'الصندوق',
            credit: 300,
          ),
        ],
      );

      final JournalEntry unbalanced = _entry(
        id: 'unbalanced',
        lines: const <JournalLine>[
          JournalLine(
            accountCode: '5100',
            accountName: 'مواد',
            debit: 300,
          ),
          JournalLine(
            accountCode: cashAccountCode,
            accountName: 'الصندوق',
            credit: 200,
          ),
        ],
      );

      expect(balanced.totalDebit, 300);
      expect(balanced.totalCredit, 300);
      expect(balanced.isBalanced, isTrue);
      expect(balanced.difference, 0);
      expect(balanced.isManual, isTrue);
      expect(balanced.sourceLabel, 'قيد يدوي');

      expect(unbalanced.isBalanced, isFalse);
      expect(unbalanced.difference, 100);
    });

    test('قيود السندات ليست يدوية', () {
      final JournalEntry receipt = _entry(
        id: 'r',
        sourceType: JournalEntry.receiptSource,
        lines: const <JournalLine>[],
      );
      final JournalEntry payment = _entry(
        id: 'p',
        sourceType: JournalEntry.paymentSource,
        lines: const <JournalLine>[],
      );

      expect(receipt.isManual, isFalse);
      expect(receipt.isFromReceipt, isTrue);
      expect(receipt.sourceLabel, 'من سند قبض');
      expect(payment.isFromPayment, isTrue);
      expect(payment.sourceLabel, 'من سند صرف');
    });
  });

  group('تصفية السندات', () {
    final List<Voucher> vouchers = <Voucher>[
      _voucher(
        kind: VoucherKind.receipt,
        amount: 1000,
        method: PaymentMethod.cash,
        number: 'قبض-0001',
        party: 'محمد',
        projectId: 'p1',
        projectName: 'طريق إب',
        date: DateTime(2026, 10, 2),
      ),
      _voucher(
        kind: VoucherKind.payment,
        amount: 250,
        method: PaymentMethod.bank,
        number: 'صرف-0001',
        party: 'المورد',
        projectId: 'p2',
        projectName: 'مدرسة',
        date: DateTime(2026, 9, 20),
      ),
    ];

    test('البحث والنوع والطريقة والمشروع', () {
      expect(filterVouchers(vouchers, search: 'محمد').length, 1);
      expect(filterVouchers(vouchers, search: 'صرف-0001').single.amount, 250);
      expect(
        filterVouchers(vouchers, kind: VoucherKind.receipt).length,
        1,
      );
      expect(
        filterVouchers(vouchers, method: PaymentMethod.bank).length,
        1,
      );
      expect(filterVouchers(vouchers, projectId: 'p1').length, 1);
      expect(filterVouchers(vouchers).length, 2);
    });

    test('الفترة الزمنية', () {
      final List<Voucher> october = filterVouchers(
        vouchers,
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31, 23, 59),
      );

      expect(october.length, 1);
      expect(october.single.number, 'قبض-0001');
    });

    test('المجاميع', () {
      expect(sumVouchers(vouchers, VoucherKind.receipt), 1000);
      expect(sumVouchers(vouchers, VoucherKind.payment), 250);
      expect(netVouchers(vouchers), 750);
    });
  });

  group('قراءة السند والقيد من وثيقة', () {
    test('Voucher.fromMap', () {
      final Voucher voucher = Voucher.fromMap(
        'doc-1',
        <String, dynamic>{
          'kind': 'payment',
          'number': 'صرف-0007',
          'date': DateTime(2026, 10, 12),
          'amount': 320.5,
          'method': 'check',
          'checkNumber': '9988',
          'partyName': 'شركة الإسمنت',
          'description': 'شراء إسمنت',
          'accountCode': '5100',
          'accountName': '',
          'projectId': 'p1',
          'projectCode': '100',
          'projectName': 'طريق',
          'journalEntryId': 'j1',
        },
      );

      expect(voucher.kind, VoucherKind.payment);
      expect(voucher.amount, 320.5);
      expect(voucher.method, PaymentMethod.check);
      expect(voucher.accountName, 'مواد ومستلزمات');
      expect(voucher.isPayment, isTrue);
      expect(voucher.projectCode, '100');
    });

    test('JournalEntry.fromMap', () {
      final JournalEntry entry = JournalEntry.fromMap(
        'j1',
        <String, dynamic>{
          'number': 'قيد-0003',
          'date': DateTime(2026, 10, 12),
          'description': 'تسوية',
          'sourceType': 'manual',
          'lines': <Map<String, dynamic>>[
            <String, dynamic>{
              'accountCode': cashAccountCode,
              'debit': 100,
              'credit': 0,
            },
            <String, dynamic>{
              'accountCode': '3000',
              'debit': 0,
              'credit': 100,
            },
          ],
        },
      );

      expect(entry.number, 'قيد-0003');
      expect(entry.lines.length, 2);
      expect(entry.totalDebit, 100);
      expect(entry.totalCredit, 100);
      expect(entry.isBalanced, isTrue);
      expect(entry.lines.first.accountName, 'الصندوق (النقدية)');
    });
  });
}

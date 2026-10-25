import 'package:azal/features/accounting/accounting_models.dart';
import 'package:azal/features/accounting/accounting_service.dart';
import 'package:flutter_test/flutter_test.dart';

// ============================================================
// اختبارات ربط المحاسب بالمشروع
// ============================================================
//
// • AccountingScope: كيف تُقرأ وثيقة `users/{uid}` إلى نطاق
//   مشروع واحد (projectId أو أول عنصر في projectIds).
// • تصفية حركات الصندوق بالمشروع.
// • ربط الأدوار: المحاسب مربوط بمشروع واحد.

CashMovement _movement({
  required String id,
  String projectId = '',
  double inAmount = 0,
  double outAmount = 0,
  PaymentMethod method = PaymentMethod.cash,
}) {
  return CashMovement(
    id: id,
    relatedId: id,
    reference: id,
    category: 'سند',
    source: CashMovementSource.voucher,
    date: DateTime(2026, 10, 1),
    method: method,
    description: '',
    inAmount: inAmount,
    outAmount: outAmount,
    projectId: projectId,
  );
}

void main() {
  group('نطاق المحاسب (AccountingScope)', () {
    test('بلا ربط = كل مشاريع الوحدة', () {
      const AccountingScope scope = AccountingScope.none;

      expect(scope.isScoped, isFalse);
      expect(scope.projectId, '');
      expect(scope.label, 'كل مشاريع الوحدة');
    });

    test('مشروع واحد من projectId', () {
      final AccountingScope scope = AccountingScope.fromUserData(
        <String, dynamic>{
          'role': 'project_accountant',
          'projectId': 'p1',
          'projectCode': '100',
          'projectName': 'طريق إب',
        },
      );

      expect(scope.isScoped, isTrue);
      expect(scope.projectId, 'p1');
      expect(scope.projectCode, '100');
      expect(scope.projectName, 'طريق إب');
      expect(scope.label, '100 — طريق إب');
      expect(scope.role, 'project_accountant');
    });

    test('أول مشروع من projectIds', () {
      final AccountingScope scope = AccountingScope.fromUserData(
        <String, dynamic>{
          'projectIds': <String>['', 'p2', 'p3'],
          'projectNames': <String>['', 'مدرسة', 'سوق'],
        },
      );

      expect(scope.projectId, 'p2');
      expect(scope.projectName, 'مدرسة');
      // بلا كود: الاسم وحده.
      expect(scope.label, 'مدرسة');
    });

    test('projectIds نص مفرد قديم', () {
      final AccountingScope scope = AccountingScope.fromUserData(
        <String, dynamic>{
          'projectIds': 'p9',
          'projectName': 'جسر',
        },
      );

      expect(scope.projectId, 'p9');
      expect(scope.label, 'جسر');
    });

    test('بيانات فارغة أو null', () {
      expect(AccountingScope.fromUserData(null).isScoped, isFalse);
      expect(
        AccountingScope.fromUserData(<String, dynamic>{}).isScoped,
        isFalse,
      );
      expect(
        AccountingScope.fromUserData(
          <String, dynamic>{'projectId': '   '},
        ).isScoped,
        isFalse,
      );
    });

    test('بلا اسم ولا كود يعرض المعرّف', () {
      final AccountingScope scope = AccountingScope.fromUserData(
        <String, dynamic>{'projectId': 'p7'},
      );

      expect(scope.label, 'p7');
    });
  });

  group('تصفية الحركة بالمشروع', () {
    final List<CashMovement> movements = <CashMovement>[
      _movement(id: 'a', projectId: 'p1', inAmount: 500),
      _movement(
        id: 'b',
        projectId: 'p2',
        inAmount: 300,
        method: PaymentMethod.bank,
      ),
      _movement(id: 'c', inAmount: 100),
    ];

    test('فارغ = كل الحركات', () {
      expect(movementsForProject(movements, '').length, 3);
      expect(movementsForProject(movements, '  ').length, 3);
    });

    test('مشروع محدد = حركاته فقط', () {
      final List<CashMovement> scoped =
          movementsForProject(movements, 'p1');

      expect(scoped.length, 1);
      expect(scoped.single.id, 'a');

      expect(movementsForProject(movements, 'p2').single.method,
          PaymentMethod.bank);
      expect(movementsForProject(movements, 'p3'), isEmpty);
    });

    test('حركة بلا مشروع لا تدخل نطاق أي مشروع', () {
      final List<CashMovement> scoped =
          movementsForProject(movements, 'p1');

      expect(scoped.any((m) => m.projectId.isEmpty), isFalse);
    });

    test('movementBelongsTo', () {
      expect(movementBelongsTo(movements[0], 'p1'), isTrue);
      expect(movementBelongsTo(movements[0], 'p2'), isFalse);
      expect(movementBelongsTo(movements[2], 'p9'), isFalse);
      // بلا نطاق: كل الحركة تخصّ الجميع.
      expect(movementBelongsTo(movements[2], ''), isTrue);
    });

    test('الرصيد بعد التصفية يخص المشروع', () {
      final double cash = FinanceMath.balance(
        opening: const OpeningBalance(cash: 1000),
        movements: movementsForProject(movements, 'p1'),
        filter: MoneyBoxFilter.cash,
      );

      // 1000 + 500 (قبض المشروع p1) — حركة p2 البنكية لا تدخل
      // الصندوق النقدي أصلًا، وحركة «بلا مشروع» خارج النطاق.
      expect(cash, 1500);
    });
  });

  group('حركة الصندوق تحمل المشروع', () {
    test('من السند', () {
      final Voucher voucher = Voucher(
        id: 'v1',
        kind: VoucherKind.payment,
        number: 'صرف-0001',
        date: DateTime(2026, 10, 2),
        amount: 250,
        method: PaymentMethod.cash,
        partyName: 'مورّد',
        description: 'شراء',
        accountCode: '5100',
        accountName: 'مواد ومستلزمات',
        projectId: 'p1',
        projectName: 'طريق إب',
      );

      final List<CashMovement> movements = buildCashMovements(
        vouchers: <Voucher>[voucher],
        entries: const <JournalEntry>[],
      );

      expect(movements.single.projectId, 'p1');
      expect(movements.single.projectName, 'طريق إب');
    });

    test('من قيد يدوي', () {
      final JournalEntry entry = JournalEntry(
        id: 'j1',
        number: 'قيد-0001',
        date: DateTime(2026, 10, 3),
        description: 'إيداع',
        projectId: 'p2',
        projectName: 'مدرسة',
        lines: const <JournalLine>[
          JournalLine(
            accountCode: cashAccountCode,
            accountName: 'الصندوق',
            debit: 400,
          ),
          JournalLine(
            accountCode: '3000',
            accountName: 'تمويل',
            credit: 400,
          ),
        ],
      );

      final List<CashMovement> movements = buildCashMovements(
        vouchers: const <Voucher>[],
        entries: <JournalEntry>[entry],
      );

      expect(movements.single.projectId, 'p2');
      expect(movements.single.projectName, 'مدرسة');
      expect(
        movementsForProject(movements, 'p2').single.inAmount,
        400,
      );
    });
  });
}

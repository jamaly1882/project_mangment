import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'accounting_models.dart';

// ============================================================
// خدمة الحسابات — Firestore
// ============================================================
//
// كل عمليات الوحدة المالية تمر من هنا حتى تبقى الصفحات واجهة
// عرض فقط:
//   • إنشاء/تعديل/حذف السندات.
//   • ترحيل كل سند إلى قيد يومية متوازن تلقائيًا.
//   • القيود اليدوية.
//   • قراءة حركة الصندوق والرصيد الافتتاحي.
//
// الربط بالمشروع: المحاسب قد يكون مربوطًا بمشروع واحد (أو بعدة
// مشاريع). كل دوال القراءة والكتابة تقبل [projectId] اختياريًا:
//   • قراءة: تُصفّي السندات والقيود بحسب مشروعها (سند بلا مشروع
//     لا يظهر لمالك مشروع محدد، لأنه خارج نطاقه).
//   • كتابة: تُفرَض هوية مشروع المحاسب على كل سند/قيد/رصيد
//     افتتاحي يكتبه، فلا يستطيع الكاتب تجاوز نطاقه.
// الرصيد الافتتاحي يُحفظ لمشروع مفرد في `finance_settings/opening_<id>`
// (مفتاحات صالحة)، وللاطلاع الكامل يبقى `finance_settings/opening`.

// أرقام السندات والقيود تُولَّد داخل Transactions على وثيقة
// العدّاد `finance_counters/main`، فلا يتكرر رقم ولو أنشأ
// أكثر من مستخدم سندًا في اللحظة نفسها.
// ============================================================

class AccountingException implements Exception {
  const AccountingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// اسم المستخدم الحالي من وثيقة `users/{uid}` (مع بدائل آمنة).
Future<String> currentAccountingUserName() async {
  final User? user = FirebaseAuth.instance.currentUser;
  if (user == null) return '';

  try {
    final DocumentSnapshot<Map<String, dynamic>> doc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final String name = (doc.data()?['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
  } catch (_) {
    // نكمل بالبديل.
  }

  return (user.displayName ?? user.email ?? '').trim();
}

/// معرّف وثيقة صالح: Firestore لا يقبل '/' في معرّف الوثيقة،
/// فيُستبدل بشرطة سفلية، وتُحذف المسافات.
String _documentKeyOf(String value) {
  return value
      .trim()
      .replaceAll('/', '_')
      .replaceAll(RegExp(r'\s+'), '_');
}

/// نطاق المشروع للمستخدم الحالي (المحاسب).
///
/// يقرأ وثيقة `users/{uid}` ويعيد أول مشروع مربوط به:
/// `projectId` المفرد أو أول عنصر في `projectIds`.
/// يعيد [AccountingScope.none] إن لم يوجد ربط (محاسب الوحدة كلها).
class AccountingScope {
  const AccountingScope({
    this.projectId = '',
    this.projectCode = '',
    this.projectName = '',
    this.role = '',
  });

  static const AccountingScope none = AccountingScope();

  final String projectId;
  final String projectCode;
  final String projectName;
  final String role;

  /// هل الحساب مقيّد بمشروع محدد؟
  bool get isScoped => projectId.trim().isNotEmpty;

  /// «100 — طريق إب» أو «كل مشاريع الوحدة».
  String get label {
    if (!isScoped) return 'كل مشاريع الوحدة';
    if (projectCode.isNotEmpty && projectName.isNotEmpty) {
      return '$projectCode — $projectName';
    }
    if (projectName.isNotEmpty) return projectName;
    if (projectCode.isNotEmpty) return projectCode;
    return projectId;
  }

  /// يحوّل بيانات المستخدم (وثيقة `users/{uid}` أو أي Map مشابهة)
  /// إلى نطاق مشروع. يقبل `projectIds` قائمة أو نصًا مفردًا.
  factory AccountingScope.fromUserData(Map<String, dynamic>? data) {
    if (data == null) return none;

    final List<String> ids = <String>[];
    final List<String> names = <String>[];

    void addId(dynamic value) {
      final String id = (value ?? '').toString().trim();
      if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
    }

    final dynamic rawIds = data['projectIds'];
    if (rawIds is Iterable) {
      for (final dynamic value in rawIds) {
        addId(value);
      }
    } else {
      addId(rawIds);
    }
    addId(data['projectId']);

    final dynamic rawNames = data['projectNames'];
    if (rawNames is Iterable) {
      for (final dynamic value in rawNames) {
        names.add((value ?? '').toString().trim());
      }
    } else {
      final String name = (rawNames ?? '').toString().trim();
      if (name.isNotEmpty) names.add(name);
    }
    final String singleName = (data['projectName'] ?? '').toString().trim();
    if (names.isEmpty && singleName.isNotEmpty) names.add(singleName);

    return AccountingScope(
      projectId: ids.isEmpty ? '' : ids.first,
      projectCode: (data['projectCode'] ?? '').toString().trim(),
      projectName: names.isEmpty ? '' : names.first,
      role: (data['role'] ?? '').toString().trim(),
    );
  }
}

/// نطاق المشروع للمستخدم المسجّل دخوله الآن (فارغ إن لم يوجد ربط).
Future<AccountingScope> currentAccountingScope() async {
  final User? user = FirebaseAuth.instance.currentUser;
  if (user == null) return AccountingScope.none;

  try {
    final DocumentSnapshot<Map<String, dynamic>> doc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    return AccountingScope.fromUserData(doc.data());
  } catch (_) {
    return AccountingScope.none;
  }
}

class AccountingSnapshot {
  const AccountingSnapshot({
    required this.vouchers,
    required this.entries,
    required this.opening,
    required this.movements,
    this.scopeProjectId = '',
  });

  final List<Voucher> vouchers;
  final List<JournalEntry> entries;
  final OpeningBalance opening;
  final List<CashMovement> movements;

  /// المشروع الذي قُرئت له هذه البيانات (فارغ = كل الوحدة).
  final String scopeProjectId;

  /// هل القراءة مقيّدة بمشروع واحد؟
  bool get isProjectScoped => scopeProjectId.trim().isNotEmpty;
}

class AccountingService {
  AccountingService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _vouchers =>
      _db.collection('vouchers');

  CollectionReference<Map<String, dynamic>> get _journal =>
      _db.collection('journal_entries');

  DocumentReference<Map<String, dynamic>> get _counterRef =>
      _db.collection('finance_counters').doc('main');

  DocumentReference<Map<String, dynamic>> get _openingRef =>
      _db.collection('finance_settings').doc('opening');

  /// وثيقة الرصيد الافتتاحي لمشروع محدد.
  ///
  /// وثائق Firestore لا تقبل '/' في المعرّف، لذا يُنظَّف [projectId]
  /// قبل استخدامه مفتاحًا (`opening_<id>`)، والباقي كما هو.
  DocumentReference<Map<String, dynamic>> _openingRefFor(String projectId) {
    final String key = _documentKeyOf(projectId);
    return _db.collection('finance_settings').doc('opening_$key');
  }

  // ==========================================================
  // القراءة
  // ==========================================================

  /// يقرأ السندات.
  ///
  /// [projectId] غير الفارغ يقيّد القراءة بسندات هذا المشروع فقط
  /// (سندات بلا مشروع لا تظهر).
  Future<List<Voucher>> loadVouchers({
    VoucherKind? kind,
    String projectId = '',
  }) async {
    Query<Map<String, dynamic>> query = _vouchers;

    if (kind != null) {
      query = query.where('kind', isEqualTo: kind.key);
    }

    final QuerySnapshot<Map<String, dynamic>> snapshot = await query.get();
    final String scope = projectId.trim();
    final List<Voucher> vouchers = snapshot.docs
        .map((doc) => Voucher.fromMap(doc.id, doc.data()))
        // التصفية بالمشروع على العميل (كما بقية الوحدة) حتى لا
        // يحتاج الاستعلام فهرسًا مركّبًا.
        .where((voucher) => scope.isEmpty || voucher.projectId == scope)
        .toList();

    vouchers.sort((a, b) {
      final int byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;

      final DateTime aCreated = a.createdAt ?? DateTime(1970);
      final DateTime bCreated = b.createdAt ?? DateTime(1970);
      final int byCreated = bCreated.compareTo(aCreated);
      if (byCreated != 0) return byCreated;

      return b.number.compareTo(a.number);
    });

    return vouchers;
  }

  /// يقرأ القيود اليومية، ومتى مُرِّر [projectId] يقتصر على قيود
  /// هذا المشروع فقط.
  Future<List<JournalEntry>> loadJournalEntries({
    String projectId = '',
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _journal.get();
    final String scope = projectId.trim();
    final List<JournalEntry> entries = snapshot.docs
        .map((doc) => JournalEntry.fromMap(doc.id, doc.data()))
        .where((entry) => scope.isEmpty || entry.projectId == scope)
        .toList();

    entries.sort((a, b) {
      final int byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;

      final DateTime aCreated = a.createdAt ?? DateTime(1970);
      final DateTime bCreated = b.createdAt ?? DateTime(1970);
      final int byCreated = bCreated.compareTo(aCreated);
      if (byCreated != 0) return byCreated;

      return b.number.compareTo(a.number);
    });

    return entries;
  }

  /// الرصيد الافتتاحي: للمشروع [projectId] إن مُرِّر، وإلا رصيد
  /// الوحدة كاملة.
  Future<OpeningBalance> loadOpeningBalance({
    String projectId = '',
  }) async {
    final DocumentReference<Map<String, dynamic>> ref =
        projectId.trim().isEmpty ? _openingRef : _openingRefFor(projectId);

    final DocumentSnapshot<Map<String, dynamic>> snapshot = await ref.get();
    return OpeningBalance.fromMap(snapshot.data());
  }

  /// كل الأرصدة الافتتاحية دفعة واحدة.
  ///
  /// المفتاح هو معرّف المشروع، والمفتاح الفارغ `''` هو رصيد
  /// الوحدة كاملة (`finance_settings/opening`) — وهو رصيد
  /// الحركات غير المرتبطة بمشروع.
  ///
  /// تُستخدم في «ميزانية المشاريع» لعرض ميزانية كل مشروع مع
  /// رصيده الافتتاحي دون قراءة وثيقة لكل مشروع على حدة.
  Future<Map<String, OpeningBalance>> loadOpeningBalances() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _db.collection('finance_settings').get();
    final Map<String, OpeningBalance> opening = <String, OpeningBalance>{};

    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      final Map<String, dynamic> data = doc.data();
      final bool looksLikeOpening = doc.id == 'opening' ||
          doc.id.startsWith('opening_') ||
          data.containsKey('cash') ||
          data.containsKey('bank');
      if (!looksLikeOpening) continue;

      String projectId = (data['projectId'] ?? '').toString().trim();
      if (projectId.isEmpty && doc.id.startsWith('opening_')) {
        // وثائق قديمة قد لا تحمل حقل projectId، فمعرّف الوثيقة
        // يكون `opening_<projectId>`.
        projectId = doc.id.substring('opening_'.length);
      }

      opening[projectId] = OpeningBalance.fromMap(data);
    }

    return opening;
  }

  /// يقرأ السندات والقيود والرصيد الافتتاحي معًا.
  ///
  /// [projectId] غير الفارغ يقيّد كل شيء بمشروع المحاسب.
  Future<AccountingSnapshot> loadSnapshot({String projectId = ''}) async {
    final String scope = projectId.trim();

    final List<Voucher> vouchers = await loadVouchers(projectId: scope);
    final List<JournalEntry> entries =
        await loadJournalEntries(projectId: scope);
    final OpeningBalance opening =
        await loadOpeningBalance(projectId: scope);

    return AccountingSnapshot(
      vouchers: vouchers,
      entries: entries,
      opening: opening,
      movements: buildCashMovements(vouchers: vouchers, entries: entries),
      scopeProjectId: scope,
    );
  }

  // ==========================================================
  // الرصيد الافتتاحي
  // ==========================================================

  Future<void> saveOpeningBalance({
    required double cash,
    required double bank,
    required String userId,
    required String userName,
    String projectId = '',
    String projectCode = '',
    String projectName = '',
  }) async {
    final String scope = projectId.trim();
    final DocumentReference<Map<String, dynamic>> ref =
        scope.isEmpty ? _openingRef : _openingRefFor(scope);

    await ref.set(
      <String, dynamic>{
        'cash': _round(cash),
        'bank': _round(bank),
        if (scope.isNotEmpty) 'projectId': scope,
        if (scope.isNotEmpty) 'projectCode': projectCode,
        if (scope.isNotEmpty) 'projectName': projectName,
        'updatedBy': userId,
        'updatedByName': userName,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ==========================================================
  // السندات
  // ==========================================================

  /// ينشئ سندًا ويرحّله إلى قيد يومية في عملية ذرّية واحدة.
  ///
  /// يعيد رقم السند بعد توليده (مثل: قبض-0001).
  ///
  /// [projectId] غير الفارغ = نطاق المحاسب: يُفرَض المشروع على السند
  /// وعلى قيده مهما أرسل النموذج، فلا يُسجَّل سند خارج نطاقه.
  Future<String> createVoucher(
    Voucher voucher, {
    required String userId,
    required String userName,
    String projectId = '',
    String projectCode = '',
    String projectName = '',
  }) async {
    voucher = _voucherInScope(
      voucher,
      projectId: projectId,
      projectCode: projectCode,
      projectName: projectName,
    );

    if (voucher.amount <= 0) {
      throw const AccountingException('المبلغ يجب أن يكون أكبر من صفر');
    }
    if (voucher.partyName.trim().isEmpty) {
      throw const AccountingException('اسم الجهة مطلوب');
    }
    if (voucher.accountCode.trim().isEmpty) {
      throw const AccountingException('اختر الحساب المقابل للسند');
    }

    final DocumentReference<Map<String, dynamic>> voucherRef = _vouchers.doc();
    final DocumentReference<Map<String, dynamic>> entryRef = _journal.doc();

    late String number;

    await _db.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> counterSnapshot =
          await transaction.get(_counterRef);
      final _Counters counters = _Counters.fromData(counterSnapshot.data());

      final int sequence = counters.nextFor(voucher.kind);
      number = '${voucher.kind.numberPrefix}-'
          '${sequence.toString().padLeft(4, '0')}';

      counters.journal += 1;
      final String entryNumber =
          'قيد-${counters.journal.toString().padLeft(4, '0')}';

      transaction.set(
        voucherRef,
        _voucherMap(
          voucher: voucher,
          number: number,
          journalEntryId: entryRef.id,
          userId: userId,
          userName: userName,
          creating: true,
        ),
      );

      transaction.set(
        entryRef,
        _entryMap(
          number: entryNumber,
          date: voucher.date,
          description: _voucherEntryDescription(voucher, number),
          lines: _voucherLines(voucher),
          sourceType: voucher.kind.key,
          sourceId: voucherRef.id,
          sourceNumber: number,
          projectId: voucher.projectId,
          projectCode: voucher.projectCode,
          projectName: voucher.projectName,
          reference: number,
          userId: userId,
          userName: userName,
          creating: true,
        ),
      );

      transaction.set(
        _counterRef,
        counters.toMap(),
        SetOptions(merge: true),
      );
    });

    return number;
  }

  /// يعدّل السند وقيده المرحّل منه (ويُنشئ قيدًا إن لم يوجد).
  ///
  /// [projectId] غير الفارغ = نطاق المحاسب، ويُفرَض على السند وقيده.
  Future<void> updateVoucher(
    Voucher voucher, {
    required String userId,
    required String userName,
    String projectId = '',
    String projectCode = '',
    String projectName = '',
  }) async {
    voucher = _voucherInScope(
      voucher,
      projectId: projectId,
      projectCode: projectCode,
      projectName: projectName,
    );

    if (voucher.id.isEmpty) {
      throw const AccountingException('السند غير محمّل للتعديل');
    }
    if (voucher.amount <= 0) {
      throw const AccountingException('المبلغ يجب أن يكون أكبر من صفر');
    }
    if (voucher.partyName.trim().isEmpty) {
      throw const AccountingException('اسم الجهة مطلوب');
    }
    if (voucher.accountCode.trim().isEmpty) {
      throw const AccountingException('اختر الحساب المقابل للسند');
    }

    final DocumentReference<Map<String, dynamic>> entryRef =
        voucher.journalEntryId.isEmpty
            ? _journal.doc()
            : _journal.doc(voucher.journalEntryId);

    await _db.runTransaction((transaction) async {
      String entryNumber = '';
      bool creating = voucher.journalEntryId.isEmpty;
      _Counters? counters;

      if (!creating) {
        final DocumentSnapshot<Map<String, dynamic>> entrySnapshot =
            await transaction.get(entryRef);
        entryNumber = (entrySnapshot.data()?['number'] ?? '').toString().trim();

        if (!entrySnapshot.exists || entryNumber.isEmpty) {
          creating = true;
        }
      }

      if (creating) {
        final DocumentSnapshot<Map<String, dynamic>> counterSnapshot =
            await transaction.get(_counterRef);
        counters = _Counters.fromData(counterSnapshot.data());
        counters.journal += 1;
        entryNumber =
            'قيد-${counters.journal.toString().padLeft(4, '0')}';
      }

      transaction.set(
        _vouchers.doc(voucher.id),
        _voucherMap(
          voucher: voucher,
          number: voucher.number,
          journalEntryId: entryRef.id,
          userId: userId,
          userName: userName,
          creating: false,
        ),
        SetOptions(merge: true),
      );

      transaction.set(
        entryRef,
        _entryMap(
          number: entryNumber,
          date: voucher.date,
          description: _voucherEntryDescription(voucher, voucher.number),
          lines: _voucherLines(voucher),
          sourceType: voucher.kind.key,
          sourceId: voucher.id,
          sourceNumber: voucher.number,
          projectId: voucher.projectId,
          projectCode: voucher.projectCode,
          projectName: voucher.projectName,
          reference: voucher.number,
          userId: userId,
          userName: userName,
          creating: creating,
        ),
        SetOptions(merge: true),
      );

      if (counters != null) {
        transaction.set(
          _counterRef,
          counters.toMap(),
          SetOptions(merge: true),
        );
      }
    });
  }

  /// يحذف السند وقيد اليومية المرحّل منه.
  Future<void> deleteVoucher(Voucher voucher) async {
    if (voucher.id.isEmpty) return;

    final WriteBatch batch = _db.batch();
    batch.delete(_vouchers.doc(voucher.id));

    if (voucher.journalEntryId.isNotEmpty) {
      batch.delete(_journal.doc(voucher.journalEntryId));
    }

    await batch.commit();
  }

  // ==========================================================
  // القيود اليومية
  // ==========================================================

  /// ينشئ قيد يومية يدويًا ويعيد رقمه (مثل: قيد-0007).
  ///
  /// [projectId] غير الفارغ = نطاق المحاسب ويُفرَض على القيد.
  Future<String> createJournalEntry(
    JournalEntry entry, {
    required String userId,
    required String userName,
    String projectId = '',
    String projectCode = '',
    String projectName = '',
  }) async {
    entry = _entryInScope(
      entry,
      projectId: projectId,
      projectCode: projectCode,
      projectName: projectName,
    );

    _validateEntry(entry);
    if (entry.description.trim().isEmpty) {
      throw const AccountingException('بيان القيد مطلوب');
    }

    final DocumentReference<Map<String, dynamic>> entryRef = _journal.doc();
    late String number;

    await _db.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> counterSnapshot =
          await transaction.get(_counterRef);
      final _Counters counters = _Counters.fromData(counterSnapshot.data());

      counters.journal += 1;
      number = 'قيد-${counters.journal.toString().padLeft(4, '0')}';

      transaction.set(
        entryRef,
        _entryMap(
          number: number,
          date: entry.date,
          description: entry.description,
          lines: entry.lines,
          sourceType: JournalEntry.manualSource,
          sourceId: '',
          sourceNumber: '',
          projectId: entry.projectId,
          projectCode: entry.projectCode,
          projectName: entry.projectName,
          reference: entry.reference,
          userId: userId,
          userName: userName,
          creating: true,
        ),
      );

      transaction.set(
        _counterRef,
        counters.toMap(),
        SetOptions(merge: true),
      );
    });

    return number;
  }

  Future<void> updateJournalEntry(
    JournalEntry entry, {
    required String userId,
    required String userName,
    String projectId = '',
    String projectCode = '',
    String projectName = '',
  }) async {
    entry = _entryInScope(
      entry,
      projectId: projectId,
      projectCode: projectCode,
      projectName: projectName,
    );

    if (!entry.isManual) {
      throw const AccountingException(
        'قيد السند يُعدَّل من السند نفسه، لا من القيود اليومية',
      );
    }
    if (entry.id.isEmpty) {
      throw const AccountingException('القيد غير محمّل للتعديل');
    }

    _validateEntry(entry);
    if (entry.description.trim().isEmpty) {
      throw const AccountingException('بيان القيد مطلوب');
    }

    await _journal.doc(entry.id).set(
          _entryMap(
            number: entry.number,
            date: entry.date,
            description: entry.description,
            lines: entry.lines,
            sourceType: JournalEntry.manualSource,
            sourceId: '',
            sourceNumber: '',
            projectId: entry.projectId,
            projectCode: entry.projectCode,
            projectName: entry.projectName,
            reference: entry.reference,
            userId: userId,
            userName: userName,
            creating: false,
          ),
          SetOptions(merge: true),
        );
  }

  Future<void> deleteJournalEntry(JournalEntry entry) async {
    if (!entry.isManual) {
      throw const AccountingException(
        'قيد السند لا يُحذف من هنا؛ احذف السند نفسه',
      );
    }
    if (entry.id.isEmpty) return;

    await _journal.doc(entry.id).delete();
  }

  // ==========================================================
  // بناء الوثائق
  // ==========================================================

  Map<String, dynamic> _voucherMap({
    required Voucher voucher,
    required String number,
    required String journalEntryId,
    required String userId,
    required String userName,
    required bool creating,
  }) {
    final FinanceAccount? account =
        financeAccountByCode(voucher.accountCode);

    return <String, dynamic>{
      'kind': voucher.kind.key,
      'number': number,
      'date': Timestamp.fromDate(voucher.date),
      'amount': _round(voucher.amount),
      'method': voucher.method.key,
      'checkNumber': voucher.checkNumber.trim(),
      'partyName': voucher.partyName.trim(),
      'description': voucher.description.trim(),
      'accountCode': voucher.accountCode.trim(),
      'accountName': voucher.accountName.trim().isNotEmpty
          ? voucher.accountName.trim()
          : (account?.name ?? ''),
      'projectId': voucher.projectId,
      'projectCode': voucher.projectCode,
      'projectName': voucher.projectName,
      'notes': voucher.notes.trim(),
      'journalEntryId': journalEntryId,
      if (creating) 'createdBy': userId,
      if (creating) 'createdByName': userName,
      if (creating) 'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
      'updatedByName': userName,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _entryMap({
    required String number,
    required DateTime date,
    required String description,
    required List<JournalLine> lines,
    required String sourceType,
    required String sourceId,
    required String sourceNumber,
    required String projectId,
    required String projectCode,
    required String projectName,
    required String reference,
    required String userId,
    required String userName,
    required bool creating,
  }) {
    final List<JournalLine> normalized = lines.map((line) {
      return JournalLine(
        accountCode: line.accountCode.trim(),
        accountName: line.accountName.trim(),
        description: line.description.trim(),
        debit: _round(line.debit),
        credit: _round(line.credit),
      );
    }).toList();

    final double totalDebit = normalized.fold<double>(
      0,
      (sum, line) => sum + line.debit,
    );
    final double totalCredit = normalized.fold<double>(
      0,
      (sum, line) => sum + line.credit,
    );

    return <String, dynamic>{
      'number': number,
      'date': Timestamp.fromDate(date),
      'description': description.trim(),
      'lines': normalized.map((line) => line.toMap()).toList(),
      'totalDebit': _round(totalDebit),
      'totalCredit': _round(totalCredit),
      'sourceType': sourceType,
      'sourceId': sourceId,
      'sourceNumber': sourceNumber,
      'projectId': projectId,
      'projectCode': projectCode,
      'projectName': projectName,
      'reference': reference,
      if (creating) 'createdBy': userId,
      if (creating) 'createdByName': userName,
      if (creating) 'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
      'updatedByName': userName,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // ==========================================================
  // نطاق المشروع
  // ==========================================================

  /// يعيد نسخة من السند بمشروع النطاق (إن وُجد نطاق).
  Voucher _voucherInScope(
    Voucher voucher, {
    required String projectId,
    required String projectCode,
    required String projectName,
  }) {
    final String scope = projectId.trim();
    if (scope.isEmpty) return voucher;
    if (voucher.projectId == scope &&
        voucher.projectName == projectName &&
        voucher.projectCode == projectCode) {
      return voucher;
    }

    return Voucher(
      id: voucher.id,
      kind: voucher.kind,
      number: voucher.number,
      date: voucher.date,
      amount: voucher.amount,
      method: voucher.method,
      partyName: voucher.partyName,
      description: voucher.description,
      accountCode: voucher.accountCode,
      accountName: voucher.accountName,
      checkNumber: voucher.checkNumber,
      projectId: scope,
      projectCode: projectCode,
      projectName: projectName,
      notes: voucher.notes,
      journalEntryId: voucher.journalEntryId,
      createdByName: voucher.createdByName,
      createdAt: voucher.createdAt,
    );
  }

  /// يعيد نسخة من القيد بمشروع النطاق (إن وُجد نطاق).
  JournalEntry _entryInScope(
    JournalEntry entry, {
    required String projectId,
    required String projectCode,
    required String projectName,
  }) {
    final String scope = projectId.trim();
    if (scope.isEmpty) return entry;
    if (entry.projectId == scope &&
        entry.projectName == projectName &&
        entry.projectCode == projectCode) {
      return entry;
    }

    return JournalEntry(
      id: entry.id,
      number: entry.number,
      date: entry.date,
      description: entry.description,
      lines: entry.lines,
      sourceType: entry.sourceType,
      sourceId: entry.sourceId,
      sourceNumber: entry.sourceNumber,
      projectId: scope,
      projectCode: projectCode,
      projectName: projectName,
      reference: entry.reference,
      createdByName: entry.createdByName,
      createdAt: entry.createdAt,
    );
  }

  // ==========================================================
  // أدوات داخلية
  // ==========================================================

  /// أسطر القيد الناتجة عن السند: الطرف النقدي مقابل الحساب.
  List<JournalLine> _voucherLines(Voucher voucher) {
    final FinanceAccount cashOrBank = voucher.method.isCash
        ? cashFinanceAccount
        : bankFinanceAccount;
    final FinanceAccount? selected =
        financeAccountByCode(voucher.accountCode);
    final String counterName = voucher.accountName.trim().isNotEmpty
        ? voucher.accountName.trim()
        : (selected?.name ?? 'حساب');
    final String counterCode = voucher.accountCode.trim();
    final double amount = _round(voucher.amount);

    if (voucher.isReceipt) {
      return <JournalLine>[
        JournalLine(
          accountCode: cashOrBank.code,
          accountName: cashOrBank.name,
          description: 'قبض ${voucher.method.label}',
          debit: amount,
        ),
        JournalLine(
          accountCode: counterCode,
          accountName: counterName,
          description: voucher.description.trim(),
          credit: amount,
        ),
      ];
    }

    return <JournalLine>[
      JournalLine(
        accountCode: counterCode,
        accountName: counterName,
        description: voucher.description.trim(),
        debit: amount,
      ),
      JournalLine(
        accountCode: cashOrBank.code,
        accountName: cashOrBank.name,
        description: 'صرف ${voucher.method.label}',
        credit: amount,
      ),
    ];
  }

  String _voucherEntryDescription(Voucher voucher, String number) {
    final String detail = voucher.description.trim();
    final String title = voucher.isReceipt ? 'قبض' : 'صرف';

    if (detail.isEmpty) return '$title $number';
    return '$title $number — $detail';
  }

  void _validateEntry(JournalEntry entry) {
    if (entry.lines.length < 2) {
      throw const AccountingException('القيد يحتاج سطرين على الأقل');
    }

    double debit = 0;
    double credit = 0;

    for (final JournalLine line in entry.lines) {
      if (line.accountCode.trim().isEmpty) {
        throw const AccountingException('اختر الحساب في كل سطور القيد');
      }
      if (line.debit <= 0 && line.credit <= 0) {
        throw const AccountingException(
          'كل سطر يحتاج مبلغًا في المدين أو الدائن',
        );
      }
      if (line.debit > 0 && line.credit > 0) {
        throw const AccountingException(
          'السطر الواحد لا يكون مدينًا ودائنًا في الوقت نفسه',
        );
      }

      debit += line.debit;
      credit += line.credit;
    }

    if (debit <= 0 || credit <= 0) {
      throw const AccountingException(
        'القيد يحتاج طرفًا مدينًا وطرفًا دائنًا',
      );
    }

    if ((debit - credit).abs() >= 0.005) {
      throw AccountingException(
        'القيد غير متوازن: المدين ${_round(debit)} '
        'والدائن ${_round(credit)}',
      );
    }
  }
}

double _round(double value) {
  return (value * 100).round() / 100;
}

// ============================================================
// عدّادات الأرقام
// ============================================================

class _Counters {
  _Counters({
    this.receipt = 0,
    this.payment = 0,
    this.journal = 0,
  });

  int receipt;
  int payment;
  int journal;

  factory _Counters.fromData(Map<String, dynamic>? data) {
    int read(String key) {
      final dynamic value = data?[key];
      if (value is num) return value.toInt();
      return int.tryParse((value ?? '').toString()) ?? 0;
    }

    return _Counters(
      receipt: read('receipt'),
      payment: read('payment'),
      journal: read('journal'),
    );
  }

  int nextFor(VoucherKind kind) {
    if (kind == VoucherKind.receipt) {
      receipt += 1;
      return receipt;
    }

    payment += 1;
    return payment;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'receipt': receipt,
      'payment': payment,
      'journal': journal,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

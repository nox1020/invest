import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/app_database.dart';
import 'package:invest/data/check_repository.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/check_payment.dart';
import 'package:invest/domain/services/backup_payload.dart';
import 'package:invest/domain/services/check_ledger.dart';
import 'package:invest/domain/services/check_payments.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/checks_page.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

BankCheck _item({
  int id = 1,
  String kind = checkKindCheck,
  String direction = checkDirectionReceivable,
  double amount = 1000,
  String status = checkStatusPending,
  String number = '101',
  String party = 'رضا',
  List<CheckPayment> payments = const [],
}) {
  return BankCheck(
    id: id,
    kind: kind,
    direction: direction,
    amount: amount,
    issueDate: '2026-10-01',
    dueDate: '2026-10-20',
    checkNumber: kind == checkKindCheck ? number : '',
    counterparty: party,
    status: status,
    payments: payments,
  );
}

void main() {
  test('partial and full payments work for cheque and deposit', () {
    for (final kind in [checkKindCheck, checkKindDeposit]) {
      final item = _item(kind: kind, amount: 1000, party: 'علی');
      expect(item.canAcceptPayment, isTrue);
      expect(item.remainingAmount, 1000);
      expect(item.paymentState, paymentStateUnpaid);

      final partial = applyCheckPayment(
        item,
        prepareCheckPayment(item: item, amount: 400, paidAt: '2026-10-05'),
      );
      expect(partial.kind, kind);
      expect(partial.status, checkStatusPending);
      expect(partial.recordedPaid, 400);
      expect(partial.remainingAmount, 600);
      expect(partial.paymentState, paymentStatePartial);
      expect(partial.canAcceptPayment, isTrue);

      final settled = settleCheckInFull(partial, paidAt: '2026-10-06');
      expect(settled.payments.last.amount, 600);
      expect(settled.recordedPaid, 1000);
      expect(settled.remainingAmount, 0);
      expect(settled.status, checkStatusCleared);
      expect(settled.paymentState, paymentStatePaid);
      expect(settled.canAcceptPayment, isFalse);
    }
  });

  test('overpayment is rejected and full settlement equals remaining', () {
    final item = _item(amount: 500);
    final partial = applyCheckPayment(
      item,
      prepareCheckPayment(item: item, amount: 200),
    );
    expect(
      () => prepareCheckPayment(item: partial, amount: 400),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          'مبلغ پرداخت از مانده بیشتر است.',
        ),
      ),
    );
    final settled = settleCheckInFull(partial);
    expect(settled.payments.last.amount, 300);
    expect(settled.remainingAmount, 0);
  });

  test('cancelled bounced and endorsed rows reject payments', () {
    for (final status in [
      checkStatusCancelled,
      checkStatusBounced,
      checkStatusEndorsed,
    ]) {
      final item = _item(status: status, amount: 800);
      expect(item.canAcceptPayment, isFalse);
      expect(
        () => prepareCheckPayment(item: item, amount: 100),
        throwsA(isA<ArgumentError>()),
      );
    }
    expect(_item(status: checkStatusCleared, amount: 800).remainingAmount, 0);
    expect(_item(status: checkStatusCancelled, amount: 800).remainingAmount, 0);
    expect(_item(status: checkStatusEndorsed, amount: 800).remainingAmount, 0);
    expect(_item(status: checkStatusBounced, amount: 800).remainingAmount, 800);
  });

  test('ledger totals use remaining so paid amounts are not counted twice', () {
    final today = DateTime(2026, 10, 17);
    final receivable = applyCheckPayment(
      _item(id: 1, amount: 2000),
      prepareCheckPayment(item: _item(id: 1, amount: 2000), amount: 500),
    );
    final payable = applyCheckPayment(
      _item(
          id: 2, direction: checkDirectionPayable, amount: 800, number: '202'),
      prepareCheckPayment(
        item: _item(
            id: 2,
            direction: checkDirectionPayable,
            amount: 800,
            number: '202'),
        amount: 300,
      ),
    );
    final effect = ChequeNavEffect.of([receivable, payable]);
    expect(effect.pendingReceivable, 1500);
    expect(effect.pendingPayable, 500);
    expect(effect.net, 1000);

    final book = CheckLedger.summarize([receivable, payable], today: today);
    expect(book.openReceivable, 1500);
    expect(book.debts, 500);
    expect(book.net, 1000);
  });

  test('prepare accepts a deposit without a cheque number', () {
    final saved = prepareBankCheck(
      BankCheck(
        kind: checkKindDeposit,
        direction: checkDirectionPayable,
        amount: 2500000,
        issueDate: '2026-10-01',
        dueDate: '2026-12-01',
        counterparty: 'مالک',
      ),
    );
    expect(saved.kind, checkKindDeposit);
    expect(saved.checkNumber, '');
    expect(saved.counterparty, 'مالک');
    expect(
      () => prepareBankCheck(
        BankCheck(
          kind: checkKindDeposit,
          direction: checkDirectionReceivable,
          amount: 10,
          issueDate: '2026-10-01',
          dueDate: '2026-10-02',
        ),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          'طرف حساب ودیعه را وارد کنید.',
        ),
      ),
    );
  });

  test('remote-wins merge keeps local kind and payment history', () {
    final local = applyCheckPayment(
      _item(id: 7, kind: checkKindDeposit, party: 'شرکت', amount: 900),
      prepareCheckPayment(
        item: _item(id: 7, kind: checkKindDeposit, party: 'شرکت', amount: 900),
        amount: 150,
      ),
    );
    final remote = BankCheck.fromMap({
      'id': 7,
      'direction': 'receivable',
      'amount': 900,
      'issue_date': '2026-10-01',
      'due_date': '2026-10-20',
      'counterparty': 'شرکت',
      'status': 'pending',
    });
    expect(remote.kindFromServer, isFalse);
    expect(remote.paymentsFromServer, isFalse);
    final merged = mergeRemoteBook(local: [local], remote: [remote]).single;
    expect(merged.kind, checkKindDeposit);
    expect(merged.payments, hasLength(1));
    expect(merged.recordedPaid, 150);
    expect(sameCheckContent(local, remote), isTrue);
  });

  test('backup payload round-trips kind and payments', () {
    final row = applyCheckPayment(
      _item(id: 8, kind: checkKindDeposit, party: 'مالک', amount: 400),
      prepareCheckPayment(
        item: _item(id: 8, kind: checkKindDeposit, party: 'مالک', amount: 400),
        amount: 50,
        note: 'قسط اول',
      ),
    );
    final payload = BackupPayload(
      exportedAt: '2026-11-06T00:00:00',
      settings: AppSettings(),
      assets: const [],
      trades: const [],
      withdrawals: const [],
      checks: [row],
    );
    final restored = BackupPayload.fromJson(payload.toJson()).checks.single;
    expect(restored.kind, checkKindDeposit);
    expect(restored.payments, hasLength(1));
    expect(restored.payments.single.amount, 50);
    expect(restored.payments.single.note, 'قسط اول');
    expect(restored.remainingAmount, 350);
  });

  test('v6 to v7 migration and replaceAll keep payment rows', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: (db, _) async {}),
    );
    addTearDown(db.close);
    await db.execute('''
CREATE TABLE checks (
  id INTEGER PRIMARY KEY,
  direction TEXT NOT NULL,
  amount REAL NOT NULL,
  issue_date TEXT NOT NULL,
  due_date TEXT NOT NULL,
  check_number TEXT NOT NULL DEFAULT '',
  sayad_id TEXT NOT NULL DEFAULT '',
  bank_name TEXT NOT NULL DEFAULT '',
  branch TEXT NOT NULL DEFAULT '',
  counterparty TEXT NOT NULL DEFAULT '',
  purpose TEXT NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT '',
  endorsed_to TEXT NOT NULL DEFAULT '',
  endorsed_for TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  settled_date TEXT,
  archived_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''');
    await db.insert('checks', {
      'id': 11,
      'direction': checkDirectionReceivable,
      'amount': 1000,
      'issue_date': '2026-10-01',
      'due_date': '2026-10-20',
      'check_number': '11',
      'status': checkStatusPending,
      'created_at': '2026-10-01T00:00:00',
      'updated_at': '2026-10-01T00:00:00',
    });
    await AppDatabase.addCheckKindColumn(db);
    await AppDatabase.ensureCheckPaymentsTable(db);
    final cols = await db.rawQuery('PRAGMA table_info(checks)');
    expect(cols.any((c) => c['name'] == 'kind'), isTrue);
    final repo = CheckRepository(db);
    var loaded = (await repo.listAll()).single;
    expect(loaded.kind, checkKindCheck);
    expect(loaded.payments, isEmpty);

    final paid = applyCheckPayment(
      loaded,
      prepareCheckPayment(item: loaded, amount: 250, paidAt: '2026-10-08'),
    );
    await repo.replaceAll([paid]);
    loaded = (await repo.listAll()).single;
    expect(loaded.payments.single.amount, 250);

    // Sync-shaped row without nested payments must not wipe history.
    final remoteShaped = BankCheck.fromMap({
      'id': 11,
      'direction': checkDirectionReceivable,
      'amount': 1000,
      'issue_date': '2026-10-01',
      'due_date': '2026-10-20',
      'check_number': '11',
      'status': checkStatusPending,
      'kind': 'check',
      'created_at': '2026-10-01T00:00:00',
      'updated_at': '2026-10-01T00:00:00',
    });
    expect(remoteShaped.payments, isEmpty);
    await repo.replaceAll([remoteShaped]);
    loaded = (await repo.listAll()).single;
    expect(loaded.payments.single.amount, 250);
  });

  testWidgets('detail sheet offers partial and full payment', (tester) async {
    final item = _item(amount: 2000000, party: 'رضا');
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: 'gregorian')
      ..checks = [item];
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ChecksPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ثبت تراکنش'), findsOneWidget);
    await tester.tap(find.text('رضا'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('check-pay-partial')), findsOneWidget);
    expect(find.byKey(const ValueKey('check-pay-full')), findsOneWidget);
    expect(find.textContaining('تسویه کامل'), findsOneWidget);
  });

  testWidgets('editor can switch to a deposit without sayad fields',
      (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: 'gregorian');
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: CheckEditorPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ثبت تراکنش'), findsOneWidget);
    expect(find.text('شناسه صیادی (۱۶ رقم)'), findsOneWidget);
    await tester.tap(find.text('ودیعه'));
    await tester.pumpAndSettle();
    expect(find.text('شناسه صیادی (۱۶ رقم)'), findsNothing);
    expect(find.text('طرف حساب'), findsOneWidget);
    expect(find.text('تاریخ بازگشت'), findsOneWidget);
  });
}

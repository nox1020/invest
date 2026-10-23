import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/services/check_ledger.dart';
import 'package:invest/domain/services/dashboard_digest.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/checks_page.dart';
import 'package:provider/provider.dart';

BankCheck _c(int id, String dir, double amount, {String? archivedAt, String status = checkStatusPending, String due = '2026-10-25'}) =>
    BankCheck(
      id: id,
      direction: dir,
      amount: amount,
      issueDate: '2026-10-01',
      dueDate: due,
      checkNumber: '$id',
      bankName: 'ملت',
      counterparty: 'طرف $id',
      status: status,
      archivedAt: archivedAt,
    );

/// Let the save's real async work (local DB, prefs) finish, then redraw.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  final today = DateTime(2026, 10, 23);
  final book = [
    _c(1, checkDirectionReceivable, 100),
    _c(2, checkDirectionPayable, 40, archivedAt: '2026-10-22T10:00:00'),
    _c(3, checkDirectionReceivable, 7, archivedAt: '2026-10-22T10:00:00', due: '2026-10-20'),
    _c(4, checkDirectionPayable, 5, status: checkStatusBounced, archivedAt: '2026-10-22'),
  ];

  test('archived cheques leave value, totals, alerts and due lists', () {
    final nav = ChequeNavEffect.of(book);
    expect(nav.pendingReceivable, 100);
    expect(nav.pendingPayable, 0);
    final ledger = CheckLedger.summarize(book, today: today);
    expect(ledger.openReceivable, 100);
    expect(ledger.debts, 0);
    expect(ledger.overdueCount, 0);
    expect(ledger.bouncedPayable, 0);
    expect(ledger.nextDue?.id, 1);
    expect(checksNeedingReminder(book, today: today).map((c) => c.id), [1]);
    expect(upcomingCheques(book, today: '2026-10-23').map((u) => u.check.id), [1]);
  });

  test('archive filter shows only archived; other filters hide them', () {
    expect(filterChecks(book, CheckListFilter.all, today: today).map((c) => c.id), [1]);
    expect(filterChecks(book, CheckListFilter.payable, today: today), isEmpty);
    expect(
      filterChecks(book, CheckListFilter.archived, today: today).map((c) => c.id).toSet(),
      {2, 3, 4},
    );
  });

  test('archive flag round-trips and an older server cannot undo it', () {
    final a = book[1];
    final back = BankCheck.fromMap(a.toMap());
    expect(back.isArchived, isTrue);
    expect(back.archivedAt, a.archivedAt);

    // Server without the field: row comes back with no archived_at key.
    final legacy = Map<String, Object?>.from(a.toMap())..remove('archived_at');
    final fromOld = BankCheck.fromMap(legacy);
    expect(fromOld.archiveFromServer, isFalse);
    expect(sameCheckContent(a, fromOld), isTrue, reason: 'no endless resend');
    final merged = mergeRemoteBook(local: [a], remote: [fromOld]);
    expect(merged.single.isArchived, isTrue);

    // New server that cleared it wins.
    final cleared = BankCheck.fromMap({...a.toMap(), 'archived_at': null});
    expect(cleared.archiveFromServer, isTrue);
    expect(mergeRemoteBook(local: [a], remote: [cleared]).single.isArchived, isFalse);
    expect(sameCheckContent(a, cleared), isFalse, reason: 'pending local archive is pushed');
  });

  test('copyWith keeps or clears the archive and prepare keeps it', () {
    final a = book[1];
    expect(a.copyWith(note: 'x').isArchived, isTrue);
    expect(a.copyWith(clearArchived: true).isArchived, isFalse);
    expect(prepareBankCheck(a).archivedAt, a.archivedAt);
  });

  testWidgets('archive tab lists, explains and restores cheques', (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: 'gregorian')
      ..checks = [
        _c(1, checkDirectionReceivable, 2000000),
        _c(2, checkDirectionPayable, 500000, archivedAt: '2026-10-22T10:00:00'),
      ];
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: ChecksPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('طرف 1'), findsOneWidget);
    expect(find.text('طرف 2'), findsNothing);
    expect(find.text('بایگانی (1)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('check-filter-archived')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('check-archive-note')), findsOneWidget);
    expect(find.text('طرف 2'), findsOneWidget);
    expect(find.text('طرف 1'), findsNothing);
    expect(find.byKey(const ValueKey('check-archived-tag')), findsOneWidget);

    await tester.tap(find.text('طرف 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('check-archive-button')));
    await _settle(tester);
    expect(state.checks.firstWhere((c) => c.id == 2).isArchived, isFalse);
    expect(find.byKey(const ValueKey('check-archive-empty')), findsOneWidget);
  });

  testWidgets('archiving an open cheque asks first, then hides it', (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: 'gregorian')
      ..checks = [_c(1, checkDirectionReceivable, 2000000)];
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: ChecksPage()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('طرف 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('check-archive-button')));
    await tester.pumpAndSettle();
    expect(find.text('بایگانی چک باز'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('check-archive-confirm')));
    await _settle(tester);
    expect(state.checks.single.isArchived, isTrue);
    expect(state.checkLedger.openReceivable, 0);
    expect(find.text('طرف 1'), findsNothing);
  });
}

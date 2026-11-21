import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/services/check_ledger.dart';
import 'package:invest/domain/services/dashboard_digest.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/checks_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  for (var i = 0; i < 24; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (i >= 8 && find.byType(BottomSheet).evaluate().isEmpty) break;
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

    final archiveChip = find.byKey(const ValueKey('check-filter-archived'));
    await tester.ensureVisible(archiveChip);
    await tester.tap(archiveChip);
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

  test('settling a transaction auto-archives it; partial, bounce, and manual restore behave cleanly',
      () async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..useRemote = false
      ..checks = [
        _c(1, checkDirectionReceivable, 1000),
        _c(2, checkDirectionPayable, 800),
        _c(3, checkDirectionReceivable, 500),
        _c(4, checkDirectionPayable, 600),
      ];

    // Partial payment keeps the check active (not archived).
    await state.recordCheckPayment(
      state.checks.firstWhere((c) => c.id == 1),
      amount: 400,
      paidAt: '2026-10-20',
    );
    var c1 = state.checks.firstWhere((c) => c.id == 1);
    expect(c1.status, checkStatusPending);
    expect(c1.isArchived, isFalse);

    // Final payment covering the remainder clears & auto-archives it.
    await state.recordCheckPayment(
      c1,
      amount: 600,
      paidAt: '2026-10-21',
    );
    c1 = state.checks.firstWhere((c) => c.id == 1);
    expect(c1.status, checkStatusCleared);
    expect(c1.isArchived, isTrue);

    // Full settlement button helper auto-archives.
    await state.settleCheckPayment(state.checks.firstWhere((c) => c.id == 2));
    var c2 = state.checks.firstWhere((c) => c.id == 2);
    expect(c2.status, checkStatusCleared);
    expect(c2.isArchived, isTrue);

    // Bounced is NOT handled/settled, so it stays active.
    await state.setCheckStatus(
      state.checks.firstWhere((c) => c.id == 3),
      checkStatusBounced,
    );
    var c3 = state.checks.firstWhere((c) => c.id == 3);
    expect(c3.status, checkStatusBounced);
    expect(c3.isArchived, isFalse);

    // Cancelling marks settled and auto-archives.
    await state.setCheckStatus(
      state.checks.firstWhere((c) => c.id == 4),
      checkStatusCancelled,
    );
    var c4 = state.checks.firstWhere((c) => c.id == 4);
    expect(c4.status, checkStatusCancelled);
    expect(c4.isArchived, isTrue);

    // Explicitly restoring a settled check leaves it unarchived even if edited.
    await state.setCheckArchived(c1, false);
    c1 = state.checks.firstWhere((c) => c.id == 1);
    expect(c1.isArchived, isFalse);
    await state.saveCheck(c1.copyWith(note: 'توضیح بعد از بازگردانی'));
    c1 = state.checks.firstWhere((c) => c.id == 1);
    expect(c1.isArchived, isFalse);

    // Re-opening an archived settled check back to pending unarchives it.
    await state.setCheckStatus(c2, checkStatusPending);
    c2 = state.checks.firstWhere((c) => c.id == 2);
    expect(c2.status, checkStatusPending);
    expect(c2.isArchived, isFalse);
  });

  testWidgets('UI: marking cleared or full-settling moves transaction into archive automatically',
      (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..useRemote = false
      ..settings = AppSettings(calendar: 'gregorian')
      ..checks = [
        _c(1, checkDirectionReceivable, 2000000),
        _c(2, checkDirectionPayable, 1500000),
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

    // Handle check 1 via status button «وصول شده»
    await tester.tap(find.text('طرف 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'وصول شده'));
    await _settle(tester);

    expect(state.checks.firstWhere((c) => c.id == 1).isArchived, isTrue);
    expect(find.text('طرف 1'), findsNothing);
    expect(find.text('بایگانی (1)'), findsOneWidget);

    // Handle check 2 via full settlement «تسویه کامل»
    await tester.tap(find.text('طرف 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('check-pay-full')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('check-pay-full-confirm')));
    await _settle(tester);

    expect(state.checks.firstWhere((c) => c.id == 2).isArchived, isTrue);
    expect(find.text('طرف 2'), findsNothing);
    expect(find.text('بایگانی (2)'), findsOneWidget);

    final archiveChip = find.byKey(const ValueKey('check-filter-archived'));
    await tester.ensureVisible(archiveChip);
    await tester.tap(archiveChip);
    await tester.pumpAndSettle();
    expect(find.text('طرف 1'), findsOneWidget);
    expect(find.text('طرف 2'), findsOneWidget);
  });
}

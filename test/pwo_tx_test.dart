import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/pwo_remote.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/ui/pages/pwo_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pwo_remote_test.dart' show FakePwoServer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('month amount = base + single withdrawals; json round-trip', () {
    final m = PwoMonth(year: 1405, month: 7, amounts: {'p0': 50e6}, txs: [
      PwoTx(id: 1, personId: 'p0', amount: 20e6, note: 'x'),
      PwoTx(id: 2, personId: 'p0', amount: 30000001),
      PwoTx(id: 3, personId: 'p1', amount: 5),
    ]);
    expect(m.of('p0'), 100000001);
    expect(m.baseOf('p0'), 50e6);
    expect(m.total, 100000006);
    expect(m.withinTarget(1e8), isFalse); // 100,000,006 > target
    expect(m.withinTarget(100000006), isTrue); // equal = within
    final l = PwoLedger(months: {m.key: m});
    final d = PwoLedger.decode(l.encode());
    expect(d.months[m.key]!.total, 100000006);
    expect(d.months[m.key]!.txs.first.note, 'x');
    expect(d.personTotal(1405, 'p0'), 100000001);
    expect(d.hasEntries('p1'), isTrue);
  });

  group('UI (device-only mode, small screen)', () {
    Future<void> boot(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      PwoStore.instance.debugReset();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.padding = const FakeViewPadding(bottom: 48, top: 24);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: PwoPage()));
      await tester.pumpAndSettle();
    }

    Future<void> openMonth(WidgetTester tester, String label) async {
      await tester.scrollUntilVisible(find.text(label), 200, alignment: 0.35);
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    void reachable(WidgetTester tester, Key k) {
      final f = find.byKey(k);
      expect(f.hitTestable(), findsOneWidget, reason: '$k not tappable');
      final r = tester.getRect(f);
      final v = tester.view;
      final bottom = v.physicalSize.height -
          (v.viewInsets.bottom > 0 ? v.viewInsets.bottom : v.padding.bottom);
      expect(r.bottom <= bottom + 0.5 && r.left >= 0 && r.right <= 320, isTrue,
          reason: '$k off-screen $r');
    }

    Future<void> addTx(WidgetTester tester, String millions,
        {String note = '', double keyboard = 0}) async {
      await tester.ensureVisible(find.byKey(const ValueKey('pwo-add-tx')));
      await tester.pumpAndSettle();
      reachable(tester, const ValueKey('pwo-add-tx'));
      await tester.tap(find.byKey(const ValueKey('pwo-add-tx')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byKey(const ValueKey('pwo-tx-amount')), millions);
      if (note.isNotEmpty) {
        await tester.enterText(find.byKey(const ValueKey('pwo-tx-note')), note);
      }
      reachable(tester, const ValueKey('pwo-tx-save'));
      await tester.tap(find.byKey(const ValueKey('pwo-tx-save')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
    }

    testWidgets('add two withdrawals to Shahrivar, edit and delete one',
        (tester) async {
      await boot(tester);
      PwoLedger l() => PwoStore.instance.ledger;
      final before = l().months['1405-06']!.of('p0'); // 230.5M
      await openMonth(tester, 'شهریور 1405');
      await addTx(tester, '۱۲٫۵', note: 'خرید');
      await addTx(tester, '0.000001', keyboard: 300);
      var m = l().months['1405-06']!;
      expect(m.txs.length, 2);
      expect(m.of('p0'), before + 12500000 + 1);
      expect(m.baseOf('p0'), before);
      expect(find.text('خرید'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // edit first tx -> 2M
      final id = m.txs.first.id!;
      await tester.ensureVisible(find.byKey(ValueKey('pwo-tx-edit-$id')));
      await tester.tap(find.byKey(ValueKey('pwo-tx-edit-$id')));
      await tester.pumpAndSettle();
      expect(
          tester.widget<TextField>(find.byKey(const ValueKey('pwo-tx-amount')))
              .controller!.text,
          '12.5');
      await tester.enterText(find.byKey(const ValueKey('pwo-tx-amount')), '2');
      await tester.tap(find.byKey(const ValueKey('pwo-tx-save')));
      await tester.pumpAndSettle();
      expect(l().months['1405-06']!.of('p0'), before + 2000000 + 1);

      // delete it (with confirm)
      await tester.ensureVisible(find.byKey(ValueKey('pwo-tx-del-$id')));
      await tester.tap(find.byKey(ValueKey('pwo-tx-del-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pwo-tx-del-confirm')));
      await tester.pumpAndSettle();
      m = l().months['1405-06']!;
      expect(m.txs.length, 1);
      expect(m.of('p0'), before + 1);

      // saving the month form keeps the single withdrawals
      await tester.tap(find.byKey(const ValueKey('pwo-save-month')));
      await tester.pumpAndSettle();
      expect(l().months['1405-06']!.txs.length, 1);
      expect(l().yearTotal(1405), 1786630000 + 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('zero/invalid amount is rejected in Persian', (tester) async {
      await boot(tester);
      await openMonth(tester, 'مرداد 1405');
      await tester.ensureVisible(find.byKey(const ValueKey('pwo-add-tx')));
      await tester.tap(find.byKey(const ValueKey('pwo-add-tx')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pwo-tx-save')));
      await tester.pumpAndSettle();
      expect(find.text('مبلغ برداشت باید بیشتر از صفر باشد.'), findsOneWidget);
      expect(PwoStore.instance.ledger.months['1405-05']!.txs, isEmpty);
    });
  });

  test('server mode: tx sent in toman, summed from snapshot, guard counts txs',
      () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: 'https://vinor.test',
      AppConfig.prefSessionCookie: 'vinor_session=t',
    });
    final store = PwoStore.instance..debugReset();
    final s = FakePwoServer();
    final session = await SessionStore.load();
    final api = InvestApiClient(session, client: MockClient(s.handle))
      ..restoreSessionCookie();
    await store.bindAccount(PwoRemote(api), '0912');
    final mId = s.ws.firstWhere((w) => w['name'] == 'M')['id'].toString();
    await store.addTx(1405, 7, mId, 12500000, note: 'n');
    expect(s.bodies['POST /transactions']!.single['amount'], 12500000);
    expect(store.ledger.months['1405-07']!.of(mId), 12500000);
    final tid = store.ledger.months['1405-07']!.txs.single.id!;
    await store.updateTx(tid, mId, 1000000);
    expect(store.ledger.months['1405-07']!.total, 1000000);
    await store.deleteTx(tid);
    expect(store.ledger.months['1405-07']?.total ?? 0, 0);

    // Account with only transactions on the server: reinstall must not import.
    final s2 = FakePwoServer()..importGuard = false;
    final w = s2.addWithdrawerForTest('M');
    s2.txs.add({'id': 99, 'withdrawer_id': w, 'year': 1405, 'month': 8, 'amount': 7, 'note': ''});
    final api2 = InvestApiClient(session, client: MockClient(s2.handle))
      ..restoreSessionCookie();
    await store.bindAccount(PwoRemote(api2), '0999');
    expect(s2.calls.contains('POST /import'), isFalse);
    expect(store.ledger.yearTotal(1405), 7);
  });
}

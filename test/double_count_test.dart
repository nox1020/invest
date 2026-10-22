import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/double_count.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/ui/widgets/double_count_panel.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _iso(int y, int m, int d) => Jalali(y, m, d).toDateTime().toIso8601String();

PwoLedger _ledger() => PwoLedger(
      people: [PwoPerson(id: 'a', name: 'نفر الف'), PwoPerson(id: 'b', name: 'نفر ب')],
      months: {
        pwoMonthKey(1405, 2): PwoMonth(
            year: 1405, month: 2, amounts: {'a': 30000000, 'b': 20000000},
            txs: [PwoTx(id: 1, personId: 'b', amount: 7000000)]),
      },
    );

void main() {
  test('matches tx, person month, month total in the same Jalali month only', () {
    final l = _ledger();
    final ws = [
      Withdrawal(id: 1, amount: 7000000, createdAt: _iso(1405, 2, 5)), // tx
      Withdrawal(id: 2, amount: 30000000, createdAt: _iso(1405, 2, 9)), // base a
      Withdrawal(id: 3, amount: 27000000, createdAt: _iso(1405, 2, 9)), // b base+tx
      Withdrawal(id: 4, amount: 57000000, createdAt: _iso(1405, 2, 9)), // total
      Withdrawal(id: 5, amount: 7000000, createdAt: _iso(1405, 3, 1)), // other month
      Withdrawal(id: 6, amount: 7000000, createdAt: _iso(1405, 2, 1), status: 'pending'),
      Withdrawal(id: 7, amount: 12345678, createdAt: _iso(1405, 2, 1)),
      Withdrawal(id: 8, amount: 7000000, createdAt: 'bad'),
    ];
    final hits = findDoubleCounts(ws, l);
    expect(hits.map((h) => h.withdrawal.id), [1, 2, 3, 4]);
    expect(hits[0].match, 'برداشت تکی نفر ب');
    expect(hits[1].match, 'مبلغ ماه نفر الف');
    expect(hits[3].match, 'جمع PWO ماه');
    expect(doubleCountDefinitions, contains('PWO'));
  });

  testWidgets('panel warns, hides on "not duplicate", never mutates data', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    final l = _ledger();
    final ws = [Withdrawal(id: 1, amount: 7000000, createdAt: _iso(1405, 2, 5))];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ListView(children: [DoubleCountPanel(withdrawals: ws, ledger: l)]))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dc-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('dc-defs')), findsOneWidget);
    final key = findDoubleCounts(ws, l).single.key;
    await tester.tap(find.byKey(ValueKey('dc-ok-$key')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dc-panel')), findsNothing);
    expect(ws.single.amount, 7000000);
    expect(l.months.values.single.txs.length, 1);
    final p = await SharedPreferences.getInstance();
    expect(p.getStringList(DoubleCountPanel.prefKey), [key]);
    await tester.tap(find.byKey(const ValueKey('dc-unhide')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dc-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

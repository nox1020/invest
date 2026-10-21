import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/ui/pages/pwo_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('seed adds 1405 Excel rows with correct totals', () {
    final l = PwoLedger();
    expect(l.applySeed(), isTrue);
    final ms = l.monthsOf(1405);
    expect(ms.length, 6);
    expect(ms[0].total, 126700000);
    expect(ms[1].total, 583530000);
    expect(ms[5].amounts, [230500000, 37000000, 30000000]);
    expect(l.personTotals(1405), [1239630000, 412000000, 135000000]);
    expect(l.yearTotal(1405), 1786630000);
    expect(l.monthsMeeting(1405), 6);
    expect(ms[0].meets(130000000), isFalse);
  });

  test('seed is idempotent and never overwrites user edits', () {
    final l = PwoLedger();
    l.applySeed();
    l.upsert(PwoMonth(year: 1405, month: 1, amounts: [1, 2, 3]));
    final round = PwoLedger.decode(l.encode());
    expect(round.applySeed(), isFalse);
    expect(round.months['1405-01']!.amounts, [1, 2, 3]);
    final fresh = PwoLedger(
        months: {'1405-02': PwoMonth(year: 1405, month: 2, amounts: [5, 0, 0])});
    fresh.applySeed();
    expect(fresh.months['1405-02']!.total, 5);
    expect(fresh.monthsOf(1405).length, 6);
  });

  test('previous month crosses year and decode tolerates junk', () {
    final l = PwoLedger(months: {
      '1404-12': PwoMonth(year: 1404, month: 12, amounts: [10, 0, 0]),
      '1405-01': PwoMonth(year: 1405, month: 1, amounts: [20, 0, 0]),
    });
    expect(l.previousOf(l.months['1405-01']!)!.total, 10);
    expect(PwoLedger.decode('not json').months, isEmpty);
    final d = PwoLedger.decode('{"target":-5,"names":["X"],"months":[{"y":1,"m":13,"a":[1]}]}');
    expect(d.target, pwoDefaultTarget);
    expect(d.names, ['X', 'A', 'N']);
    expect(d.months, isEmpty);
  });

  testWidgets('PWO page renders seeded data and persists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    PwoStore.instance.debugReset();
    await tester.pumpWidget(const MaterialApp(home: PwoPage()));
    await tester.pumpAndSettle();
    expect(find.text('PWO · برداشت ماهانه'), findsOneWidget);
    expect(find.byKey(const ValueKey('pwo-chart')), findsOneWidget);
    expect(find.text('رسیده به هدف: 6 از 6 ماه'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PwoStore.prefsKey), contains(pwoSeedTag));
  });
}

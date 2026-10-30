import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/ui/pages/pwo_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> boot(WidgetTester tester, {Size size = const Size(320, 568)}) async {
  SharedPreferences.setMockInitialValues({});
  PwoStore.instance.debugReset();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (c) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(c)
                .push(MaterialPageRoute(builder: (_) => PwoPage(today: DateTime(2026, 10, 30)))),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> openMonth(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 200, alignment: 0.35);
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('double-tap Save does not pop the PWO page', (tester) async {
    await boot(tester);
    await openMonth(tester, 'شهریور 1405');
    final save = find.byKey(const ValueKey('pwo-save-month'));
    await tester.tap(save);
    await tester.pump();
    await tester.tap(save, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(PwoPage), findsOneWidget);
  });

  testWidgets('double-tap delete month does not pop the PWO page', (tester) async {
    await boot(tester);
    await openMonth(tester, 'شهریور 1405');
    final del = find.byKey(const ValueKey('pwo-delete-month'));
    await tester.tap(del);
    await tester.pump();
    await tester.tap(del, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(PwoPage), findsOneWidget);
  });

  testWidgets('edit + save keeps exact toman amounts (no rounding)', (tester) async {
    await boot(tester);
    final store = PwoStore.instance;
    await tester.runAsync(() => store.saveMonth(PwoMonth(
        year: 1405, month: 7, amounts: {'p0': 96712345, 'p1': 1234})));
    await tester.pumpAndSettle();
    await openMonth(tester, 'مهر 1405');
    await tester.tap(find.byKey(const ValueKey('pwo-save-month')));
    await tester.pumpAndSettle();
    final m = store.ledger.months['1405-07']!;
    expect(m.of('p0'), 96712345);
    expect(m.of('p1'), 1234);
  });

  testWidgets('editing a historical month retains archived people amounts',
      (tester) async {
    await boot(tester);
    final store = PwoStore.instance;
    // N (p2) has history -> archived; 1405-06 still has N = 30M.
    await tester.runAsync(() => store.removePerson('p2'));
    await tester.pumpAndSettle();
    await openMonth(tester, 'شهریور 1405');
    await tester.enterText(find.byKey(const ValueKey('pwo-amount-0')), '1');
    await tester.tap(find.byKey(const ValueKey('pwo-save-month')));
    await tester.pumpAndSettle();
    final m = store.ledger.months['1405-06']!;
    expect(m.of('p0'), 1000000);
    expect(m.of('p2'), 30000000);
  });

  testWidgets('historical month date is fixed and cannot overwrite another month',
      (tester) async {
    await boot(tester);
    await openMonth(tester, 'شهریور 1405');
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(find.text('ماه و سال بر اساس تاریخ تعیین شده‌اند و قابل تغییر نیستند.'),
        findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('pwo-amount-0')), '2');
    await tester.tap(find.byKey(const ValueKey('pwo-save-month')));
    await tester.pumpAndSettle();
    expect(PwoStore.instance.ledger.months['1405-05']!.of('p0'), 309300000);
    expect(PwoStore.instance.ledger.months['1405-06']!.of('p0'), 2000000);
  });

  test('duplicate active names are rejected locally', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PwoStore.instance..debugReset();
    await store.load();
    expect(() => store.addPerson(' M '), throwsA(isA<ArgumentError>()));
    expect(() => store.setName('p1', 'M'), throwsA(isA<ArgumentError>()));
  });

  testWidgets('12 months chart on a narrow screen paints without overflow',
      (tester) async {
    await boot(tester);
    final store = PwoStore.instance;
    for (var m = 7; m <= 12; m++) {
      await tester.runAsync(() => store.saveMonth(
          PwoMonth(year: 1405, month: m, amounts: {'p0': 5e8 * m})));
    }
    await tester.runAsync(() => store.setTarget(1e13));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('pwo-chart')), findsOneWidget);
  });

  test('chart labels switch to numbers when slots are narrow', () {
    expect(pwoChartLabel(1, 60), 'فروردین');
    expect(pwoChartLabel(2, 20), '۲');
  });

  testWidgets('target validation: too large is rejected with Persian text',
      (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip('تنظیمات PWO'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pwo-target')), '99999999999');
    await tester.tap(find.byKey(const ValueKey('pwo-save-settings')));
    await tester.pumpAndSettle();
    expect(find.textContaining('بیش از حد'), findsOneWidget);
    expect(PwoStore.instance.ledger.target, pwoDefaultTarget);
  });

  testWidgets('current Jalali month appears automatically without add-month button',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    PwoStore.instance.debugReset();
    await tester.pumpWidget(MaterialApp(
        home: PwoPage(today: DateTime(2026, 10, 30))));
    await tester.pumpAndSettle();
    expect(find.text('ثبت ماه'), findsNothing);
    expect(PwoStore.instance.ledger.months['1405-08'], isNull);
    expect(PwoStore.instance.ledger.yearTotal(1405), 1786630000);
    await tester.scrollUntilVisible(find.text('آبان 1405'), 200, alignment: 0.35);
    await tester.ensureVisible(find.text('آبان 1405'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pwo-current-month-placeholder')),
        findsOneWidget);
    await tester.tap(find.text('آبان 1405'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pwo-delete-month')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('pwo-amount-0')), '12');
    await tester.tap(find.byKey(const ValueKey('pwo-save-month')));
    await tester.pumpAndSettle();
    expect(PwoStore.instance.ledger.months['1405-08']!.of('p0'), 12000000);
  });
}

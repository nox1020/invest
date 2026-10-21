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
    expect(ms[5].of('p0'), 230500000);
    expect([for (final p in l.people) l.personTotal(1405, p.id)],
        [1239630000, 412000000, 135000000]);
    expect(l.yearTotal(1405), 1786630000);
    expect(l.monthsMeeting(1405), 6);
  });

  test('seed is idempotent and never overwrites user edits', () {
    final l = PwoLedger()..applySeed();
    l.upsert(PwoMonth(year: 1405, month: 1, amounts: {'p0': 1}));
    final round = PwoLedger.decode(l.encode());
    expect(round.applySeed(), isFalse);
    expect(round.months['1405-01']!.total, 1);
    expect(round.monthsOf(1405).length, 6);
  });

  test('v1 stored format migrates to people', () {
    final l = PwoLedger.decode(
        '{"v":1,"names":["Mo","A","N"],"target":5,"tags":["$pwoSeedTag"],'
        '"months":[{"y":1405,"m":1,"a":[1,2,3]}]}');
    expect(l.people.map((e) => e.name), ['Mo', 'A', 'N']);
    expect(l.months['1405-01']!.of('p2'), 3);
    expect(l.applySeed(), isFalse);
  });

  test('add/remove: archive keeps history, empty person deleted, last stays',
      () {
    final l = PwoLedger()..applySeed();
    final z = l.addPerson('Z');
    expect(l.people.length, 4);
    expect(l.removePerson(z.id), isTrue);
    expect(l.personById(z.id), isNull);
    final before = l.yearTotal(1405);
    expect(l.removePerson('p2'), isTrue);
    expect(l.personById('p2')!.active, isFalse);
    expect(l.yearTotal(1405), before);
    expect(l.personTotal(1405, 'p2'), 135000000);
    expect(l.activePeople.length, 2);
    l.removePerson('p1');
    expect(l.removePerson('p0'), isFalse);
    expect(l.activePeople.single.id, 'p0');
    final d = PwoLedger.decode(l.encode());
    expect(d.personById('p2')!.active, isFalse);
    expect(d.yearTotal(1405), before);
  });

  test('decode tolerates junk and orphan ids', () {
    expect(PwoLedger.decode('not json').months, isEmpty);
    final d = PwoLedger.decode(
        '{"target":-5,"people":[],"months":[{"y":1,"m":13,"a":[1]},{"y":1405,"m":2,"a":{"x9":7}}]}');
    expect(d.target, pwoDefaultTarget);
    expect(d.months.length, 1);
    expect(d.activePeople, isNotEmpty);
    expect(d.yearTotal(1405), 7);
  });

  group('layout on small screens', () {
    Future<void> boot(WidgetTester tester, {double keyboard = 0}) async {
      SharedPreferences.setMockInitialValues({});
      PwoStore.instance.debugReset();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.padding = const FakeViewPadding(bottom: 48, top: 24);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: PwoPage()));
      await tester.pumpAndSettle();
    }

    void setKeyboard(WidgetTester tester, double h) {
      tester.view.viewInsets = FakeViewPadding(bottom: h);
    }

    void expectReachable(WidgetTester tester, Key key, {List<Key> others = const []}) {
      final f = find.byKey(key);
      expect(f.hitTestable(), findsOneWidget, reason: '$key must be tappable');
      final r = tester.getRect(f);
      final view = tester.view;
      final visibleBottom = view.physicalSize.height -
          view.viewInsets.bottom -
          (view.viewInsets.bottom > 0 ? 0 : view.padding.bottom);
      expect(r.bottom <= visibleBottom + 0.5, isTrue,
          reason: '$key bottom ${r.bottom} > $visibleBottom');
      expect(r.left >= 0 && r.right <= view.physicalSize.width, isTrue);
      for (final o in others) {
        final of = find.byKey(o);
        if (of.evaluate().isEmpty) continue;
        expect(r.overlaps(tester.getRect(of)), isFalse, reason: '$key overlaps $o');
      }
    }

    testWidgets('page renders seeded data', (tester) async {
      await boot(tester);
      expect(find.byKey(const ValueKey('pwo-chart')), findsOneWidget);
      expect(find.text('رسیده به هدف: 6 از 6 ماه'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final kb in [0.0, 300.0]) {
      testWidgets('edit month sheet, keyboard=$kb', (tester) async {
        await boot(tester);
        await tester.scrollUntilVisible(find.text('شهریور 1405'), 200);
        await tester.tap(find.text('شهریور 1405'));
        await tester.pumpAndSettle();
        setKeyboard(tester, kb);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expectReachable(tester, const ValueKey('pwo-save-month'),
            others: [const ValueKey('pwo-delete-month')]);
        expectReachable(tester, const ValueKey('pwo-delete-month'));
        await tester.enterText(find.byKey(const ValueKey('pwo-amount-0')), '1');
        await tester.tap(find.byKey(const ValueKey('pwo-save-month')));
        await tester.pumpAndSettle();
        expect(PwoStore.instance.ledger.months['1405-06']!.of('p0'), 1000000);
        expect(PwoStore.instance.ledger.months['1405-06']!.of('p1'), 37000000);
      });

      testWidgets('new month sheet, keyboard=$kb', (tester) async {
        await boot(tester);
        await tester.tap(find.text('ثبت ماه'));
        await tester.pumpAndSettle();
        setKeyboard(tester, kb);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expectReachable(tester, const ValueKey('pwo-save-month'));
      });

      testWidgets('settings sheet with many people, keyboard=$kb', (tester) async {
        await boot(tester);
        for (var i = 0; i < 5; i++) {
          await PwoStore.instance.addPerson('نفر طولانی شماره $i');
        }
        await tester.tap(find.byTooltip('تنظیمات PWO'));
        await tester.pumpAndSettle();
        setKeyboard(tester, kb);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expectReachable(tester, const ValueKey('pwo-save-settings'),
            others: [const ValueKey('pwo-add-person')]);
        expectReachable(tester, const ValueKey('pwo-add-person'));
      });
    }

    testWidgets('add, archive with confirm, and save via settings', (tester) async {
      await boot(tester);
      await tester.tap(find.byTooltip('تنظیمات PWO'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pwo-add-person')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('pwo-new-person')), 'Z');
      await tester.tap(find.byKey(const ValueKey('pwo-add-confirm')));
      await tester.pumpAndSettle();
      expect(PwoStore.instance.ledger.activePeople.length, 4);
      await tester.ensureVisible(find.byKey(const ValueKey('pwo-remove-p2')));
      await tester.tap(find.byKey(const ValueKey('pwo-remove-p2')));
      await tester.pumpAndSettle();
      expect(find.text('بایگانی'), findsOneWidget);
      expectReachable(tester, const ValueKey('pwo-remove-confirm'));
      await tester.tap(find.byKey(const ValueKey('pwo-remove-confirm')));
      await tester.pumpAndSettle();
      final l = PwoStore.instance.ledger;
      expect(l.personById('p2')!.active, isFalse);
      expect(l.yearTotal(1405), 1786630000);
      await tester.enterText(find.byKey(const ValueKey('pwo-target')), '150');
      await tester.tap(find.byKey(const ValueKey('pwo-save-settings')));
      await tester.pumpAndSettle();
      expect(l.target, 150000000);
      expect(tester.takeException(), isNull);
      // New month form shows only active people (M, A, Z).
      await tester.tap(find.text('ثبت ماه'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pwo-amount-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwo-amount-3')), findsNothing);
    });
  });
}

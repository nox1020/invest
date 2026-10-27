import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/biz_remote.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/domain/services/full_export.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/data/write_queue.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/pages/biz_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal in-memory /biz server (computes like vinor biz_api).
class FakeBizServer {
  final trades = <Map<String, dynamic>>[];
  final ops = <int, Map<String, double>>{};
  final pwo = <int, double>{1: 126700000};
  final notes = <int, String>{};
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  int _id = 0;
  bool down = false;

  int year = 1405;

  Map<String, dynamic> snap() {
    final ts = [
      for (final t in trades)
        {
          ...t,
          'profit': (t['sell_amount'] as num) > 0
              ? (t['sell_amount'] as num) - (t['buy_amount'] as num)
              : null,
          'days': null,
        }
    ];
    final months = [
      for (var m = 1; m <= 12; m++)
        () {
          final o = ops[m] ?? const {};
          final s = o['staff'] ?? 0, a = o['ads'] ?? 0, i = o['income'] ?? 0;
          final p = pwo[m] ?? 0;
          return {
            'year': year, 'month': m, 'staff': s, 'ads': a, 'income': i,
            'pwo': p, 'net': i - s - a - p, 'has_ops': ops.containsKey(m), 'note': notes[m] ?? '',
          };
        }()
    ];
    double sum(String k) =>
        months.fold(0.0, (v, m) => v + (m[k] as num).toDouble());
    return {
      'trades': ts,
      'trades_totals': {
        'profit': ts.fold<num>(0, (v, t) => v + ((t['profit'] as num?) ?? 0)),
        'extra_cost': 0,
      },
      'year': year,
      'years': [1405],
      'months': months,
      'months_totals': {
        for (final k in ['staff', 'ads', 'income', 'pwo', 'net']) k: sum(k)
      },
    };
  }

  Future<http.Response> handle(http.Request r) async {
    if (down) throw http.ClientException('offline');
    final path = r.url.path.replaceFirst('/invest/api/v1/biz', '');
    year = int.tryParse(r.url.queryParameters['year'] ?? '') ?? 1405;
    final key = '${r.method} $path';
    calls.add(key);
    final body = r.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    bodies[key] = body;
    final mm = RegExp(r'^/months/(\d+)/(\d+)$').firstMatch(path);
    final tm = RegExp(r'^/trades/(\d+)$').firstMatch(path);
    if (r.method == 'POST' && path == '/trades') {
      trades.add({...body, 'id': ++_id});
    } else if (tm != null && r.method == 'PATCH') {
      final t = trades.firstWhere((t) => t['id'] == int.parse(tm.group(1)!));
      t.addAll(body);
    } else if (tm != null && r.method == 'DELETE') {
      trades.removeWhere((t) => t['id'] == int.parse(tm.group(1)!));
    } else if (mm != null && r.method == 'PUT') {
      final mo = int.parse(mm.group(2)!);
      // Like the server: fields missing from the body keep their value.
      ops[mo] = {
        ...?ops[mo],
        for (final e in body.entries)
          if (e.value is num) e.key: (e.value as num).toDouble()
      };
      if (body['note'] is String) notes[mo] = body['note'] as String;
    } else if (r.method == 'POST' && path == '/import') {
      if (trades.isNotEmpty || ops.isNotEmpty) {
        return http.Response(
            jsonEncode({'success': true, 'written': 0, 'already_has_data': true, 'biz': snap()}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      for (final t in (body['trades'] as List? ?? [])) {
        trades.add({...Map<String, dynamic>.from(t as Map), 'id': ++_id});
      }
      for (final m in (body['months'] as List? ?? [])) {
        final mm2 = Map<String, dynamic>.from(m as Map);
        ops[(mm2['month'] as num).toInt()] = {
          for (final k in ['staff', 'ads', 'income']) k: ((mm2[k] ?? 0) as num).toDouble()
        };
      }
      return http.Response(
          jsonEncode({'success': true, 'written': trades.length + ops.length, 'biz': snap()}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    } else if (mm != null && r.method == 'DELETE') {
      ops.remove(int.parse(mm.group(2)!));
    }
    return http.Response(jsonEncode({'success': true, 'biz': snap()}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

Future<InvestApiClient> _api(FakeBizServer s) async {
  final session = await SessionStore.load();
  return InvestApiClient(session, client: MockClient(s.handle))
    ..restoreSessionCookie();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: 'https://vinor.test',
      AppConfig.prefSessionCookie: 'vinor_session=t',
    });
    BizStore.instance.debugReset();
  });

  test('CRUD in toman; PWO and net come from server; offline edits show at once and sync',
      () async {
    final s = FakeBizServer();
    final store = BizStore.instance;
    await store.bindAccount(BizRemote(await _api(s)), '0912');
    expect(store.snap.months.first.pwo, 126700000);

    await store.addTrade({
      'buy_date': '1405/01/20', 'sell_date': '1405/01/21',
      'buy_amount': 400000000, 'sell_amount': 700000000,
    });
    expect(s.bodies['POST /trades']!['buy_amount'], 400000000);
    expect(store.snap.totalProfit, 300000000);
    final id = store.snap.trades.single.id;
    await store.updateTrade(id, {'sell_amount': 800000000});
    expect(store.snap.totalProfit, 400000000);

    await store.saveMonth(1405, 1,
        {'staff': 18000000, 'ads': 69600000, 'income': 1109000000});
    expect(s.bodies['PUT /months/1405/1']!.containsKey('pwo'), isFalse);
    expect(store.snap.months.first.net, 894700000); // as in the sheet

    // offline: cached snapshot, writes are queued for this account only
    store.debugReset();
    await store.loadOffline();
    expect(store.readOnly, isFalse);
    expect(store.snap.totalProfit, 400000000);
    final before = s.calls.length;
    await expectLater(store.deleteTrade(id), throwsA(isA<WriteQueuedException>()));
    expect(s.calls.length, before); // nothing sent offline
    expect(store.queue.items.single.account, '0912');
    expect(store.snap.trades, isEmpty); // optimistic: shown deleted at once
    expect(store.serverSnap.trades, isNotEmpty); // server copy untouched

    // reconnect: queued delete is sent, then the fresh snapshot shown
    await store.bindAccount(BizRemote(await _api(s)), '0912');
    expect(store.queue.isEmpty, isTrue);
    expect(store.snap.trades, isEmpty);
    await store.clearMonth(1405, 1);
    expect(store.snap.months.first.hasOps, isFalse);

    // switching accounts never shows the previous account's data
    final s2 = FakeBizServer()..pwo.clear();
    await store.bindAccount(BizRemote(await _api(s2)), '0999');
    expect(store.snap.months.first.pwo, 0);
  });

  testWidgets('page shows totals, add trade through dialog', (tester) async {
    final s = FakeBizServer();
    final store = BizStore.instance;
    await tester.runAsync(
        () async => store.bindAccount(BizRemote(await _api(s)), '0912'));
    await tester.pumpWidget(MaterialApp(home: BizPage(store: store)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biz-open-months')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('biz-add-trade')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('biz-f-buy-date')), '1405/02/01');
    await tester.enterText(find.byKey(const ValueKey('biz-f-buy')), '۱۰۰٬۰۰۰٬۰۰۰');
    await tester.enterText(find.byKey(const ValueKey('biz-f-sell-date')), '1405/02/10');
    await tester.enterText(find.byKey(const ValueKey('biz-f-sell')), '150000000');
    await tester.tap(find.byKey(const ValueKey('biz-f-save')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(s.trades.single['buy_amount'], 100000000);
    expect(store.snap.totalProfit, 50000000);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BizMonthsPane(store: store))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biz-total-net')), findsOneWidget);
    expect(find.text('برج 1 · فروردین'), findsOneWidget);
  });

  testWidgets('import button: pasted JSON, then hidden', (tester) async {
    final s = FakeBizServer();
    final store = BizStore.instance;
    await tester.runAsync(
        () async => store.bindAccount(BizRemote(await _api(s)), '0912'));
    await tester.pumpWidget(MaterialApp(home: BizPage(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biz-import')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('biz-import-text')), 'nope');
    await tester.tap(find.byKey(const ValueKey('biz-import-go')));
    await tester.pumpAndSettle();
    expect(s.calls.contains('POST /import'), isFalse);
    await tester.tap(find.byKey(const ValueKey('biz-import')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('biz-import-text')),
        '{"trades":[{"buy_date":"20/01/1405","sell_date":"21/01/1405","buy_amount":100,"sell_amount":175}],'
        '"months":[{"year":1405,"month":7,"income":50}]}');
    await tester.tap(find.byKey(const ValueKey('biz-import-go')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(s.trades.length, 1);
    expect(store.snap.totalProfit, 75);
    expect(find.byKey(const ValueKey('biz-import')), findsNothing);
    // second import never writes
    expect(await tester.runAsync(() => store.importSheet('{"trades":[]}')), 0);
  });

  testWidgets('small phone, billions: no overflow on both tabs and dialogs',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    final s = FakeBizServer()..pwo[1] = 583530000;
    for (var i = 0; i < 3; i++) {
      s.trades.add({
        'id': 100 + i, 'buy_date': '1404/10/10', 'sell_date': '1405/01/28',
        'buy_amount': 2400000000, 'sell_amount': 99999999999,
        'area': 244.8, 'extra_cost': 29000000,
        'title': 'علی - رفیق خانوم غلامی - از ۲۰۰۰ متری سقزدره و توضیح بلند دیگر',
      });
    }
    s.ops[1] = {'staff': 36000000, 'ads': 81900000, 'income': 21440000000};
    final store = BizStore.instance;
    await tester.runAsync(
        () async => store.bindAccount(BizRemote(await _api(s)), '0912'));
    await tester.pumpWidget(MaterialApp(home: BizPage(store: store)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('علی - رفیق خانوم غلامی - از ۲۰۰۰ متری سقزدره و توضیح بلند دیگر').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BizMonthsPane(store: store))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('biz-month-1')), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const ValueKey('biz-month-1')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(320, 568), Size(360, 640), Size(414, 896), Size(800, 1280)]) {
    testWidgets('layout ${size.width.toInt()}x${size.height.toInt()}: no overlap, filter, year nav',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
      addTearDown(tester.view.reset);
      final s = FakeBizServer();
      for (var i = 0; i < 12; i++) {
        s.trades.add({
          'id': 100 + i, 'buy_date': '1405/0${1 + i % 3}/01',
          'sell_date': i == 11 ? '' : '1405/0${2 + i % 3}/10',
          'buy_amount': 1000000000, 'sell_amount': i == 11 ? 0 : 1000000000 + 1000000 * (i + 1),
          'title': 'معامله شمارهٔ $i با عنوان نسبتاً بلند برای تست',
        });
      }
      final store = BizStore.instance;
      await tester.runAsync(
          () async => store.bindAccount(BizRemote(await _api(s)), '0912'));
      await tester.pumpWidget(MaterialApp(home: BizPage(store: store)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // FAB never covers the last row once scrolled to the end, nor the nav bar.
      final fab = find.byKey(const ValueKey('biz-add-trade'));
      expect(fab, findsOneWidget);
      final fabRect = tester.getRect(fab);
      expect(fabRect.bottom, lessThanOrEqualTo(size.height - 48));
      for (var k = 0; k < 6; k++) { await tester.drag(find.byType(RefreshIndicator).last, const Offset(0, -2000)); await tester.pump(); }
      await tester.pumpAndSettle();
      final lastTile = find.textContaining('معامله شمارهٔ').last;
      expect(tester.getRect(lastTile).overlaps(fabRect), isFalse);
      for (var k = 0; k < 6; k++) { await tester.drag(find.byType(RefreshIndicator).first, const Offset(0, 2000)); await tester.pump(); }
      await tester.pumpAndSettle();

      // month filter: totals follow the filter
      await tester.ensureVisible(find.byKey(const ValueKey('biz-filter-1405/02')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('biz-filter-1405/02')));
      await tester.pumpAndSettle();
      // sells in month 02: i = 0,3,6,9 → profits 1,4,7,10 million
      expect(tester.widget<Text>(find.byKey(const ValueKey('biz-trade-count'))).data, '4');
      expect(tester.widget<Text>(find.byKey(const ValueKey('biz-total-profit'))).data,
          formatMoney(22000000));
      await tester.ensureVisible(find.byKey(const ValueKey('biz-filter-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('biz-filter-open')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('biz-trade-count'))).data, '1');
      await tester.ensureVisible(find.byKey(const ValueKey('biz-filter-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('biz-filter-all')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('biz-trade-count'))).data, '12');

      // monthly tab: no FAB, year navigation loads that year
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BizMonthsPane(store: store))));
      await tester.pumpAndSettle();
      expect(fab, findsNothing);
      await tester.tap(find.byKey(const ValueKey('biz-year-prev')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('سال 1404'), findsOneWidget);
      expect(store.snap.year, 1404);
      await tester.scrollUntilVisible(find.text('برج 1 · فروردین'), 200,
          scrollable: find.byType(Scrollable).last);
      expect(find.text('برج 1 · فروردین'), findsOneWidget);
      for (var k = 0; k < 6; k++) { await tester.drag(find.byType(RefreshIndicator).last, const Offset(0, -2000)); await tester.pump(); }
      await tester.pumpAndSettle();
      final last = tester.getRect(find.byKey(const ValueKey('biz-month-12')));
      expect(last.bottom, lessThanOrEqualTo(size.height - 48 + 0.5));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => store.selectYear(1405));
    });
  }

  testWidgets('month shows sold-trade profit, flags mismatch, fills only after confirm',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    final s = FakeBizServer()..pwo.clear();
    s.trades.addAll([
      {'id': 1, 'buy_date': '1405/01/01', 'sell_date': '1405/01/20', 'buy_amount': 100, 'sell_amount': 400100},
      {'id': 2, 'buy_date': '1405/01/01', 'sell_date': '1405/01/25', 'buy_amount': 100, 'sell_amount': 600100},
      {'id': 3, 'buy_date': '1405/01/01', 'sell_date': '1405/02/02', 'buy_amount': 100, 'sell_amount': 900},
    ]);
    s.ops[1] = {'income': 900000, 'staff': 0, 'ads': 0};
    final store = BizStore.instance;
    await tester.runAsync(() async => store.bindAccount(BizRemote(await _api(s)), '0912'));
    expect(tradeProfitInMonth(store.snap.trades, 1405, 1), 1000000);
    expect(incomeMismatch(1000000, 1000000), isFalse);
    expect(incomeMismatch(1000500, 1000000), isFalse); // within 1,000
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BizMonthsPane(store: store))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biz-month-flag-1')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('biz-month-tp-2')), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.byKey(const ValueKey('biz-month-tp-2')), findsOneWidget); // profit w/o ops row
    await tester.scrollUntilVisible(find.byKey(const ValueKey('biz-month-1')), -200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const ValueKey('biz-month-1')));
    await tester.pumpAndSettle();
    // cancel: nothing changes
    await tester.tap(find.byKey(const ValueKey('biz-m-fill')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انصراف').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('biz-m-income'))).controller!.text,
        formatNumber(900000));
    expect(s.calls.where((c) => c.startsWith('PUT')), isEmpty);
    // confirm: field filled, still nothing sent until save
    await tester.tap(find.byKey(const ValueKey('biz-m-fill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biz-m-fill-ok')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('biz-m-income'))).controller!.text,
        formatNumber(1000000));
    expect(s.calls.where((c) => c.startsWith('PUT')), isEmpty);
    await tester.tap(find.byKey(const ValueKey('biz-m-save')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(s.ops[1]!['income'], 1000000);
    expect(find.byKey(const ValueKey('biz-month-flag-1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard card summarises the year and opens the page', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    final s = FakeBizServer()..pwo[1] = 126700000;
    s.trades.addAll([
      {'id': 1, 'buy_date': '1405/01/01', 'sell_date': '1405/01/20', 'buy_amount': 100, 'sell_amount': 400100},
      {'id': 2, 'buy_date': '1405/01/01', 'sell_date': '', 'buy_amount': 100, 'sell_amount': 0},
    ]);
    s.ops[1] = {'income': 900000, 'staff': 0, 'ads': 0};
    final store = BizStore.instance;
    await tester.runAsync(() async => store.bindAccount(BizRemote(await _api(s)), '0912'));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ListView(children: [BizDashboardCard(store: store)]))));
    await tester.pumpAndSettle();
    await tester.runAsync(() => PwoStore.instance.load());
    await tester.pumpAndSettle();
    final tgt = PwoStore.instance.ledger.target;
    expect(tester.widget<Text>(find.byKey(const ValueKey('biz-dash-pwo'))).data,
        formatMoney(126700000));
    expect(tester.widget<Text>(find.byKey(const ValueKey('biz-dash-pwo-hit'))).data,
        126700000 <= tgt ? '1 از 1' : '0 از 1');
    expect(find.text(formatMoney(400000)), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('biz-dash-open'))).data, '1');
    expect(tester.widget<Text>(find.byKey(const ValueKey('biz-dash-mismatch'))).data, '1');
    await tester.tap(find.byKey(const ValueKey('biz-dash-card')));
    await tester.pumpAndSettle();
    expect(find.byType(BizPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('parseBizDate mirrors server rules', () {
    expect(bizDateText(parseBizDate('۱۴۰۵/۲/۱')!), '1405/02/01');
    expect(bizDateText(parseBizDate('1/2/1405')!), '1405/02/01');
    expect(parseBizDate('1405/12/31'), isNull); // 1405 اسفند 29 روز
    expect(parseBizDate('1405/13/01'), isNull);
    expect(parseBizDate('1200/01/01'), isNull);
    expect(parseBizDate('abc'), isNull);
    final p = BizTradePreview.compute(
        parseBizDate('1405/01/01'), parseBizDate('1405/01/11'), 100, 200);
    expect(p.days, 10);
    expect(p.profit, 100);
    expect(p.pct, 50);
    expect(BizTradePreview.compute(parseBizDate('1405/01/01'), null, 100, 0).profit, isNull);
  });

  testWidgets('trade dialog: live preview, invalid date blocked, calendar picker',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    final s = FakeBizServer();
    final store = BizStore.instance;
    await tester.runAsync(() async => store.bindAccount(BizRemote(await _api(s)), '0912'));
    await tester.pumpWidget(MaterialApp(home: BizPage(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biz-add-trade')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('biz-f-buy-date')), '1405/02/01');
    await tester.enterText(find.byKey(const ValueKey('biz-f-buy')), '100000000');
    await tester.enterText(find.byKey(const ValueKey('biz-f-sell-date')), '1405/07/31');
    await tester.pump();
    expect(find.text('تاریخ نامعتبر است.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('biz-f-save')));
    await tester.pump();
    expect(s.trades, isEmpty);
    // calendar picker fills a valid date (initial = buy date)
    await tester.tap(find.byKey(const ValueKey('biz-f-sell-date-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأیید'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('biz-f-sell-date'))).controller!.text,
        '1405/02/01');
    await tester.enterText(find.byKey(const ValueKey('biz-f-sell-date')), '1405/02/11');
    await tester.enterText(find.byKey(const ValueKey('biz-f-sell')), '125000000');
    await tester.pump();
    expect(find.text('11 اردیبهشت 1405'), findsOneWidget);
    expect(
        tester.widget<Text>(find.descendant(
            of: find.byKey(const ValueKey('biz-f-preview')), matching: find.byType(Text))).data,
        'مدت نگهداری 10 روز · سود ${formatMoney(25000000)} (20.0٪)');
    await tester.tap(find.byKey(const ValueKey('biz-f-save')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(s.trades.single['sell_date'], '1405/02/11');
    expect(tester.takeException(), isNull);
  });

  testWidgets('annual export: Excel and PDF from the app bar', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    final s = FakeBizServer();
    s.trades.add({'id': 1, 'buy_date': '1405/01/01', 'sell_date': '1405/01/20',
      'buy_amount': 100, 'sell_amount': 400100});
    final store = BizStore.instance;
    await tester.runAsync(() async => store.bindAccount(BizRemote(await _api(s)), '0912'));
    final got = <String, int>{};
    bizShareOverride = (b, n, m) async => got[n] = b.length;
    addTearDown(() => bizShareOverride = null);
    await tester.pumpWidget(MaterialApp(home: BizPage(store: store)));
    await tester.pumpAndSettle();
    for (final k in ['xlsx', 'pdf']) {
      await tester.tap(find.byKey(const ValueKey('biz-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('biz-export-$k')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
      await tester.pumpAndSettle();
    }
    expect(got.keys, ['ملک-و-دفتر-1405.xlsx', 'ملک-و-دفتر-1405.pdf']);
    expect(got.values.every((v) => v > 500), isTrue);
    expect(s.calls.where((c) => !c.startsWith('GET')), isEmpty); // read-only
    expect(tester.takeException(), isNull);
  });

  test('ads shortcut adds to the month total, keeps staff/income, logs a line', () async {
    final s = FakeBizServer()..pwo.clear();
    s.ops[8] = {'staff': 30, 'ads': 100, 'income': 1000};
    final store = BizStore.instance;
    await store.bindAccount(BizRemote(await _api(s)), '0912');
    await store.addAds(1405, 8, 250, date: '1405/08/03', note: 'دیوار');
    await store.addAds(1405, 8, 50, date: '1405/08/04');
    expect(s.bodies['PUT /months/1405/8']!.keys.toSet(), {'ads', 'note'});
    expect(s.ops[8], {'staff': 30, 'ads': 400, 'income': 1000});
    final m = store.snap.months.firstWhere((x) => x.month == 8);
    expect(m.ads, 400);
    expect(m.net, 1000 - 30 - 400);
    expect(m.note.split('\n'), ['تبلیغات 1405/08/03: 250 — دیوار', 'تبلیغات 1405/08/04: 50']);
    expect(adsLine.hasMatch(m.note.split('\n').first), isTrue);
    expect(() => store.addAds(1405, 8, 0, date: '1405/08/04'), throwsArgumentError);
  });
}

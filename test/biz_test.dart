import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/biz_remote.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/ui/pages/biz_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal in-memory /biz server (computes like vinor biz_api).
class FakeBizServer {
  final trades = <Map<String, dynamic>>[];
  final ops = <int, Map<String, double>>{};
  final pwo = <int, double>{1: 126700000};
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  int _id = 0;
  bool down = false;

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
            'year': 1405, 'month': m, 'staff': s, 'ads': a, 'income': i,
            'pwo': p, 'net': i - s - a - p, 'has_ops': ops.containsKey(m),
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
      'year': 1405,
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
      ops[int.parse(mm.group(2)!)] = {
        for (final e in body.entries) e.key: (e.value as num).toDouble()
      };
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

  test('CRUD in toman; PWO and net come from server; offline cache read-only',
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

    // offline: cached snapshot, writes refused
    store.debugReset();
    await store.loadOffline();
    expect(store.readOnly, isTrue);
    expect(store.snap.totalProfit, 400000000);
    expect(() => store.deleteTrade(id), throwsA(isA<BizReadOnlyException>()));

    await store.bindAccount(BizRemote(await _api(s)), '0912');
    await store.deleteTrade(id);
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
    expect(find.text('سابقه خرید و فروش ملک'), findsOneWidget);
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
    await tester.tap(find.text('جدول ماهانه'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biz-total-net')), findsOneWidget);
    expect(find.text('برج 1 · فروردین'), findsOneWidget);
  });
}

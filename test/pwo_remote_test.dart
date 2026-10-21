import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/pwo_remote.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/ui/pages/pwo_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for Vinor `/pwo` (one account). Never hits the network.
class FakePwoServer {
  double target = 100000000;
  final ws = <Map<String, dynamic>>[];
  final es = <Map<String, dynamic>>[];
  final calls = <String>[];
  final bodies = <String, List<Map<String, dynamic>>>{};
  int _id = 0;
  bool down = false;

  /// Server-side guard (vinor fix): import is a no-op once entries exist.
  bool importGuard = true;
  String? failWith;

  Map<String, dynamic> snap() =>
      {'target': target, 'withdrawers': ws, 'entries': es, 'totals': {}};

  int addWithdrawerForTest(String name) => _w(name);
  void addEntryForTest(int wid, int y, int m, double amt) => _upsert(wid, y, m, amt);

  int _w(String name) {
    for (final w in ws) {
      if (w['name'] == name) return w['id'] as int;
    }
    final id = ++_id;
    ws.add({'id': id, 'name': name, 'sort_order': ws.length, 'archived': false});
    return id;
  }

  void _upsert(int wid, int y, int m, num amt, {bool overwrite = true}) {
    for (final e in es) {
      if (e['withdrawer_id'] == wid && e['year'] == y && e['month'] == m) {
        if (overwrite) e['amount'] = amt;
        return;
      }
    }
    es.add({'id': ++_id, 'withdrawer_id': wid, 'year': y, 'month': m,
      'amount': amt, 'note': '', 'updated_at': ''});
  }

  Future<http.Response> handle(http.Request r) async {
    if (down) throw Exception('offline');
    final path = r.url.path.replaceFirst('/invest/api/v1/pwo', '');
    final key = '${r.method} $path';
    calls.add(key);
    final body = r.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    bodies.putIfAbsent(key, () => []).add(body);
    if (failWith != null) {
      return http.Response(
          jsonEncode({'success': false, 'message': failWith, 'error': 'validation'}),
          400,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }
    Map<String, dynamic> extra = {};
    if (key == 'POST /import' && importGuard && es.isNotEmpty && body['overwrite'] != true) {
      extra = {'written': 0, 'skipped': (body['entries'] as List? ?? []).length};
    } else if (key == 'POST /import') {
      for (final w in (body['withdrawers'] as List? ?? [])) {
        final name = w is Map ? w['name'] as String : w as String;
        final existed = ws.any((x) => x['name'] == name);
        final id = _w(name);
        if (!existed && w is Map && w['archived'] == true) {
          ws.firstWhere((x) => x['id'] == id)['archived'] = true;
        }
      }
      if (body['target'] != null && target == 100000000) {
        target = (body['target'] as num).toDouble();
      }
      for (final e in (body['entries'] as List? ?? [])) {
        _upsert(_w(e['withdrawer'] as String), e['year'] as int,
            e['month'] as int, e['amount'] as num, overwrite: false);
      }
      extra = {'written': 0, 'skipped': 0};
    } else if (key.startsWith('PUT /months/')) {
      final parts = path.split('/');
      final y = int.parse(parts[2]), m = int.parse(parts[3]);
      (body['amounts'] as Map).forEach((k, v) =>
          _upsert(int.parse(k as String), y, m, v as num));
    } else if (key == 'PUT /target') {
      target = (body['target'] as num).toDouble();
    } else if (key == 'POST /withdrawers') {
      _w(body['name'] as String);
    }
    return http.Response(
        jsonEncode({'success': true, 'pwo': snap(), ...extra}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PwoRemote> remoteFor(FakePwoServer s) async {
    final session = await SessionStore.load();
    final api = InvestApiClient(session, client: MockClient(s.handle));
    api.restoreSessionCookie();
    return PwoRemote(api);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: 'https://vinor.test',
      AppConfig.prefSessionCookie: 'vinor_session=t',
    });
    PwoStore.instance.debugReset();
  });

  test('first load imports local data + 1405 seed once, in toman', () async {
    final server = FakePwoServer();
    final store = PwoStore.instance;
    await store.bindAccount(await remoteFor(server), '0912');
    expect(server.calls, ['GET ', 'POST /import']);
    final body = server.bodies['POST /import']!.single;
    final entries = body['entries'] as List;
    expect(entries.length, 18);
    expect(entries.firstWhere((e) =>
        e['withdrawer'] == 'M' && e['month'] == 1)['amount'], 96700000);
    expect(body['overwrite'], false);
    expect(store.ledger.yearTotal(1405), 1786630000);
    expect(store.isRemote, isTrue);

    // Restart: migration flag is kept per account -> plain GET, no re-import.
    store.debugReset();
    await store.bindAccount(await remoteFor(server), '0912');
    expect(server.calls, ['GET ', 'POST /import', 'GET ']);
    expect(store.ledger.yearTotal(1405), 1786630000);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PwoStore.migratedKey('0912')), isTrue);
  });

  test('archived local withdrawers are imported as archived', () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: 'https://vinor.test',
      AppConfig.prefSessionCookie: 'vinor_session=t',
      PwoStore.prefsKey: jsonEncode({
        'v': 2, 'target': 150000000, 'tags': ['seed_1405_v1'],
        'people': [
          {'id': 'p0', 'name': 'M', 'active': true},
          {'id': 'p1', 'name': 'Old', 'active': false},
        ],
        'months': [{'y': 1405, 'm': 7, 'a': {'p0': 5000000, 'p1': 2000000}}],
      }),
    });
    final server = FakePwoServer();
    await PwoStore.instance.bindAccount(await remoteFor(server), '0912');
    final body = server.bodies['POST /import']!.single;
    expect(body['target'], 150000000);
    expect((body['withdrawers'] as List).last, {'name': 'Old', 'archived': true});
    final l = PwoStore.instance.ledger;
    expect(l.people.firstWhere((p) => p.name == 'Old').active, isFalse);
    expect(l.yearTotal(1405), 7000000);
    expect(l.target, 150000000);
  });

  test('account switch: second account never gets the first one\'s data',
      () async {
    final a = FakePwoServer(), b = FakePwoServer();
    final store = PwoStore.instance;
    await store.bindAccount(await remoteFor(a), '0911');
    expect(store.ledger.yearTotal(1405), 1786630000);

    await store.bindAccount(await remoteFor(b), '0922');
    final bodyB = b.bodies['POST /import']!.single;
    expect(bodyB['entries'], isEmpty);
    expect(store.account, '0922');
    expect(store.ledger.months, isEmpty);
    expect(b.es, isEmpty);

    // Account B offline later: its own (empty) cache, not A's.
    b.down = true;
    store.debugReset();
    await store.bindAccount(await remoteFor(b), '0922');
    expect(store.ledger.months, isEmpty);
    expect(store.lastError, isNotNull);

    // Back to A while offline: A's cache shows, with the error.
    a.down = true;
    await store.bindAccount(await remoteFor(a), '0911');
    expect(store.ledger.yearTotal(1405), 1786630000);
    expect(store.showingCache, isTrue);
    expect(store.lastError, 'ارتباط با سرور برقرار نشد (آفلاین).');
  });

  testWidgets('UI millions <-> server toman, and server error text shown',
      (tester) async {
    final server = FakePwoServer();
    final remote = await remoteFor(server);
    await tester.runAsync(
        () => PwoStore.instance.bindAccount(remote, '0912'));
    await tester.pumpWidget(const MaterialApp(home: PwoPage()));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('فروردین 1405'), 200);
    await tester.ensureVisible(find.text('فروردین 1405'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فروردین 1405'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byKey(const ValueKey('pwo-amount-0')))
            .controller!.text,
        '96.7');
    await tester.enterText(find.byKey(const ValueKey('pwo-amount-0')), '12.5');
    await tester.tap(find.byKey(const ValueKey('pwo-save-month')));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    final put = server.bodies['PUT /months/1405/1']!.single['amounts'] as Map;
    final mId = server.ws.firstWhere((w) => w['name'] == 'M')['id'].toString();
    expect(put[mId], 12500000);
    expect(PwoStore.instance.ledger.months['1405-01']!.of(mId), 12500000);

    server.failWith = 'مبلغ نامعتبر است.';
    await tester.tap(find.text('ثبت ماه'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pwo-save-month')));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    // Month may already exist -> confirm replace dialog first.
    if (find.text('جایگزین').evaluate().isNotEmpty) {
      await tester.tap(find.text('جایگزین'));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
    expect(find.text('مبلغ نامعتبر است.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

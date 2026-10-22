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
import 'package:invest/data/write_queue.dart';
import 'package:invest/ui/widgets/pending_writes_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'biz_test.dart' show FakeBizServer;

/// FakeBizServer + Idempotency-Key like the real server, and switchable
/// failure modes (down, or "answer lost after the write was done").
class IdemServer {
  IdemServer(this.inner);
  final FakeBizServer inner;
  final seen = <String>{};
  final keys = <String?>[];
  bool down = false;
  bool loseAnswer = false;
  bool refuseDeletes = false;

  Future<http.Response> handle(http.Request r) async {
    if (down) throw http.ClientException('offline');
    final k = r.headers['Idempotency-Key'];
    if (r.method != 'GET') keys.add(k);
    if (k != null && seen.contains(k)) {
      return http.Response(jsonEncode({'success': true, 'biz': inner.snap(), 'replayed': true}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }
    if (refuseDeletes && r.method == 'DELETE') {
      return http.Response(jsonEncode({'success': false, 'message': 'معامله پیدا نشد.', 'error': 'not_found'}), 404,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }
    final res = await inner.handle(r);
    if (k != null && res.statusCode == 200) seen.add(k);
    if (loseAnswer && r.method != 'GET') {
      loseAnswer = false;
      throw http.ClientException('timeout after commit');
    }
    return res;
  }
}

Future<BizRemote> _remote(IdemServer s) async {
  final session = await SessionStore.load();
  return BizRemote(InvestApiClient(session, client: MockClient(s.handle))
    ..restoreSessionCookie());
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

  final trade = {'buy_date': '1405/01/01', 'buy_amount': 9, 'sell_amount': 0, 'title': 'x'};

  test('queue is per account: another account never sees or sends it', () async {
    final q = WriteQueue('t');
    await q.bind('A');
    await q.add('A', const WriteRequest('POST', '/p', {'a': 1}), 'one');
    expect(() => q.add('B', const WriteRequest('POST', '/p'), 'x'), throwsStateError);
    await q.bind('B');
    expect(q.items, isEmpty);
    var sent = 0;
    await q.flush('A', (r, k) async { sent++; return {}; }); // bound to B
    expect(sent, 0);
    await q.flush('B', (r, k) async { sent++; return {}; });
    expect(sent, 0);
    await q.bind('A');
    expect(q.items.single.label, 'one');
    final key = q.items.single.key;
    final got = <String>[];
    await q.flush('A', (r, k) async { got.add(k); return {}; });
    expect(got, [key]);
    expect(q.isEmpty, isTrue);
  });

  test('offline write is queued, survives restart, sent once on reconnect', () async {
    final s = IdemServer(FakeBizServer());
    final store = BizStore.instance;
    await store.bindAccount(await _remote(s), '0912');
    s.down = true;
    await expectLater(store.addTrade(trade), throwsA(isA<WriteQueuedException>()));
    expect(store.queue.items.length, 1);
    // app restart: queue reloaded from disk for this account
    store.debugReset();
    await store.loadOffline();
    expect(store.queue.items.single.label, contains('ثبت معامله'));
    s.down = false;
    await store.bindAccount(await _remote(s), '0912');
    expect(store.queue.isEmpty, isTrue);
    expect(s.inner.trades.length, 1);
    expect(store.snap.trades.length, 1);
  });

  test('answer lost after the server wrote it: retry reuses the key, no duplicate',
      () async {
    final s = IdemServer(FakeBizServer());
    final store = BizStore.instance;
    await store.bindAccount(await _remote(s), '0912');
    s.loseAnswer = true;
    await expectLater(store.addTrade(trade), throwsA(isA<WriteQueuedException>()));
    expect(s.inner.trades.length, 1); // it did happen
    await store.refresh(); // reconnect
    expect(store.queue.isEmpty, isTrue);
    expect(s.inner.trades.length, 1); // replay did not write again
    expect(s.keys.length, 2);
    expect(s.keys[0], isNotNull);
    expect(s.keys[0], s.keys[1]);
  });

  test('queued writes of account A are not sent when B signs in', () async {
    final a = IdemServer(FakeBizServer()), b = IdemServer(FakeBizServer());
    final store = BizStore.instance;
    await store.bindAccount(await _remote(a), 'A');
    a.down = true;
    await expectLater(store.addTrade(trade), throwsA(isA<WriteQueuedException>()));
    await store.bindAccount(await _remote(b), 'B');
    expect(b.keys, isEmpty);
    expect(b.inner.trades, isEmpty);
    expect(store.queue.items, isEmpty); // B's queue
    a.down = false;
    await store.bindAccount(await _remote(a), 'A');
    expect(a.inner.trades.length, 1);
  });

  test('server refusal stays visible until discarded or retried', () async {
    final s = IdemServer(FakeBizServer());
    final store = BizStore.instance;
    await store.bindAccount(await _remote(s), '0912');
    s.down = true;
    await expectLater(store.deleteTrade(424242), throwsA(isA<WriteQueuedException>()));
    s.down = false;
    s.refuseDeletes = true;
    await store.refresh();
    final w = store.queue.items.single;
    expect(w.error, 'معامله پیدا نشد.'); // kept for the user, not retried blindly
    final n = s.keys.length;
    await store.refresh();
    expect(s.keys.length, n); // waits for the user
    await store.queue.discard(w.key);
    expect(store.queue.isEmpty, isTrue);
  });

  testWidgets('panel shows pending items and discards only after confirm', (tester) async {
    final q = WriteQueue('ui');
    await tester.runAsync(() async {
      await q.bind('A');
      await q.add('A', const WriteRequest('PUT', '/x'), 'جدول ماهانه 1405/1');
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PendingWritesPanel(queue: q))));
    expect(find.byKey(const ValueKey('pending-panel')), findsOneWidget);
    expect(find.text('جدول ماهانه 1405/1'), findsOneWidget);
    final k = q.items.single.key;
    await tester.tap(find.byKey(ValueKey('pending-discard-$k')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    expect(q.items.length, 1);
    await tester.tap(find.byKey(ValueKey('pending-discard-$k')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('pending-discard-ok')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(q.items, isEmpty);
    expect(find.byKey(const ValueKey('pending-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/biz_remote.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/core_outbox.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/optimistic.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/data/write_queue.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/invest_mutations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'biz_test.dart' show FakeBizServer;

/// Records Idempotency-Keys like the server: a repeated key is not re-run.
class KeyedBiz extends FakeBizServer {
  final seenKeys = <String>[];
  final replies = <String, http.Response>{};
  bool dropNextAnswer = false;

  @override
  Future<http.Response> handle(http.Request r) async {
    final k = r.headers['Idempotency-Key'];
    if (k != null) {
      seenKeys.add(k);
      final old = replies[k];
      if (old != null) return http.Response(jsonEncode({'success': true, 'biz': snap()}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }
    final res = await super.handle(r);
    if (k != null) replies[k] = res;
    if (dropNextAnswer) {
      dropNextAnswer = false;
      throw http.ClientException('answer lost'); // written, answer never came
    }
    return res;
  }
}

Future<InvestApiClient> _api(FakeBizServer s) async {
  final session = await SessionStore.load();
  return InvestApiClient(session, client: MockClient(s.handle))..restoreSessionCookie();
}

class FakeCore implements InvestMutations {
  final calls = <String>[];
  final keys = <String?>[];
  int _id = 100;
  bool down = false;
  String? refuse;

  Future<T> _go<T>(String c, T Function() v) async {
    keys.add(IdempotencyScope.nextKey());
    if (down) throw InvestApiException('offline', errorCode: 'network_error');
    if (refuse == c) throw InvestApiException('نامعتبر', statusCode: 400);
    calls.add(c);
    return v();
  }

  @override
  Future<Asset> createAsset({required String name, String symbol = '', double quantity = 0, double avgBuyPrice = 0, double currentPrice = 0, String notes = '', String? buyDate}) =>
      _go('asset.create $name', () => Asset(id: ++_id, name: name));
  @override
  Future<void> updateAsset(Asset asset) => _go('asset.update ${asset.id}', () {});
  @override
  Future<Trade> registerBuy({int? assetId, String? name, String symbol = '', required double quantity, required double buyPrice, double? buyPriceUsd, double? buyUsdTmn, double buyFee = 0, String? buyDate, String buyNote = '', double? currentPrice}) =>
      _go('buy $assetId', () => Trade(id: ++_id, assetId: assetId ?? 0, status: AppConfig.tradeOpen, quantity: quantity, buyPrice: buyPrice));
  @override
  Future<Trade> updateOpenTrade({required int tradeId, required double quantity, required double buyPrice, double? buyPriceUsd, double? buyUsdTmn, double buyFee = 0, String? buyDate, String? buyNote}) =>
      _go('update $tradeId', () => Trade(id: tradeId, assetId: 0, status: AppConfig.tradeOpen, quantity: quantity, buyPrice: buyPrice));
  @override
  Future<Trade> closeTrade({required int tradeId, required double sellPrice, double sellFee = 0, String? sellDate, String sellNote = '', double? quantity, double? sellUsdTmn}) =>
      _go('close $tradeId', () => Trade(id: tradeId, assetId: 0, status: AppConfig.tradeClosed, quantity: 1, buyPrice: 1));
  @override
  Future<void> deleteClosedTrade(int tradeId) => _go('delete $tradeId', () {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: 'https://vinor.test',
      AppConfig.prefSessionCookie: 'vinor_session=t',
    });
    BizStore.instance.debugReset();
    syncOffline.value = false;
  });

  group('snapshot stores (ملک و دفتر / PWO / projects)', () {
    test('offline create then edit then delete-other: shown at once, sent in order with the real id', () async {
      final s = KeyedBiz();
      final store = BizStore.instance;
      await store.bindAccount(BizRemote(await _api(s)), '0912');
      await store.addTrade({'buy_date': '1405/01/01', 'buy_amount': 100, 'sell_amount': 0, 'title': 'A'});
      final keep = store.snap.trades.single.id;

      s.down = true;
      syncOffline.value = true;
      await expectLater(store.addTrade({'buy_date': '1405/02/01', 'buy_amount': 200, 'sell_amount': 0, 'title': 'B'}),
          throwsA(isA<WriteQueuedException>()));
      final b = store.snap.trades.firstWhere((t) => t.raw['title'] == 'B');
      expect(b.id, lessThan(0)); // temp id, shown at once
      expect(b.raw['pending_sync'], isTrue);
      await expectLater(store.updateTrade(b.id, {'sell_date': '1405/03/01', 'sell_amount': 260}),
          throwsA(isA<WriteQueuedException>()));
      expect(store.snap.trades.firstWhere((t) => t.id == b.id).raw['profit'], 60);
      await expectLater(store.deleteTrade(keep), throwsA(isA<WriteQueuedException>()));
      expect(store.snap.trades.map((t) => t.raw['title']), ['B']);
      expect(store.queue.length, 3);

      // reconnect: one POST, PATCH on the server id (not the temp id), DELETE
      s.down = false;
      syncOffline.value = false;
      await store.refresh();
      expect(store.queue.isEmpty, isTrue);
      expect(s.trades.map((t) => t['title']), ['B']);
      expect(s.trades.single['sell_amount'], 260);
      expect(s.calls.where((c) => c.startsWith('PATCH /trades/-')), isEmpty);
      expect(store.snap.trades.single.id, greaterThan(0));
    });

    test('lost answer: the retry reuses the key, the server writes once', () async {
      final s = KeyedBiz();
      final store = BizStore.instance;
      await store.bindAccount(BizRemote(await _api(s)), '0912');
      s.dropNextAnswer = true;
      await expectLater(store.addTrade({'buy_date': '1405/01/01', 'buy_amount': 5, 'sell_amount': 0}),
          throwsA(isA<WriteQueuedException>()));
      expect(s.trades.length, 1); // it did land
      await store.refresh(); // flush resends the same key
      expect(store.queue.isEmpty, isTrue);
      expect(s.trades.length, 1); // never duplicated
      expect(s.seenKeys.toSet().length, 1);
      expect(s.seenKeys.length, 2);
    });

    test('app kill mid-queue: queue and temp ids survive a restart', () async {
      final q = WriteQueue('biz');
      await q.bind('0912');
      final m = createMeta(BizRemote.addTradeReq({'buy_amount': 1}));
      await q.add('0912', BizRemote.addTradeReq({'buy_amount': 1}), 'x', tempId: m.tempId, collection: m.collection);
      await q.add('0912', BizRemote.updateTradeReq(m.tempId!, {'note': 'n'}), 'y');
      final again = WriteQueue('biz'); // fresh process
      await again.bind('0912');
      expect(again.length, 2);
      expect(again.items.first.tempId, m.tempId);
      expect(again.items.first.collection, 'trades');
    });

    test('refused write stays with its reason (never silently dropped)', () async {
      final q = WriteQueue('biz');
      await q.bind('0912');
      await q.add('0912', BizRemote.deleteTradeReq(7), 'حذف');
      await q.flush('0912', (r, k) async => throw InvestApiException('پیدا نشد', statusCode: 409));
      expect(q.items.single.error, contains('پیدا نشد'));
      await q.flush('0912', (r, k) async => {}); // waits for the user
      expect(q.length, 1);
      await q.retry(q.items.single.key);
      await q.flush('0912', (r, k) async => {});
      expect(q.isEmpty, isTrue);
    });

    test('PWO overlay: offline single withdrawal and new person show at once', () {
      final server = {
        'target': 100.0,
        'withdrawers': [{'id': 1, 'name': 'الف', 'archived': false}],
        'entries': [],
        'transactions': [],
      };
      QueuedWrite w(WriteRequest r, {int? tmp}) => QueuedWrite(key: 'k$tmp${r.path}', account: 'a', request: r, label: '', createdAt: '', tempId: tmp);
      final v = overlay(server, [
        w(const WriteRequest('POST', '/invest/api/v1/pwo/withdrawers', {'name': 'ب'}), tmp: -5),
        w(const WriteRequest('POST', '/invest/api/v1/pwo/transactions', {'withdrawer_id': -5, 'year': 1405, 'month': 8, 'amount': 30, 'note': ''}), tmp: -6),
        w(const WriteRequest('PUT', '/invest/api/v1/pwo/target', {'target': 50})),
      ], applyPwo);
      expect((v['withdrawers'] as List).length, 2);
      expect((v['transactions'] as List).single['withdrawer_id'], -5);
      expect(v['target'], 50);
      expect((server['withdrawers'] as List).length, 1); // base untouched
    });

    test('temp ids in later writes are rewritten after the create is sent', () async {
      final q = WriteQueue('pwo');
      await q.bind('0912');
      await q.add('0912', const WriteRequest('POST', '/invest/api/v1/pwo/withdrawers', {'name': 'ب'}), 'p', tempId: -5, collection: 'withdrawers');
      await q.add('0912', const WriteRequest('PATCH', '/invest/api/v1/pwo/withdrawers/-5', {'name': 'پ'}), 'r');
      await q.add('0912', const WriteRequest('PUT', '/invest/api/v1/pwo/months/1405/8', {'amounts': {'-5': 10}}), 'm');
      final sent = <WriteRequest>[];
      await q.flush('0912', (r, k) async {
        sent.add(r);
        return {'withdrawers': [{'id': 1}, {'id': 42}]};
      }, before: {'withdrawers': [{'id': 1}]});
      expect(sent[1].path, '/invest/api/v1/pwo/withdrawers/42');
      expect((sent[2].body!['amounts'] as Map).keys, ['42']);
    });
  });

  group('core outbox (assets / trades / withdrawals)', () {
    test('offline ops apply idempotently, flush in order with tmp→real ids, keys stable', () async {
      final ob = CoreOutbox();
      await ob.bind('0912');
      await ob.add('asset.create', {'tmp': -10, 'lot_tmp': -11, 'name': 'طلا', 'quantity': 2.0, 'avgBuyPrice': 100.0, 'currentPrice': 120.0}, 'a');
      await ob.add('trade.buy', {'tmp': -20, 'assetId': -10, 'quantity': 1.0, 'buyPrice': 130.0}, 'b');
      await ob.add('trade.close', {'tradeId': -20, 'closed_tmp': -21, 'sellPrice': 150.0, 'quantity': 1.0}, 'c');
      await ob.add('wd.create', {'tmp': -30, 'amount': 50.0, 'note': ''}, 'w');

      final book = CoreBook(assets: [], open: [], closed: [], withdrawals: []);
      for (var i = 0; i < 3; i++) {
        for (final op in ob.ops) {
          applyCoreOp(book, op);
        }
        recomputeAssetHoldings(book, {-10});
      }
      expect(book.assets.single.quantity, 2); // lot from create; bought lot sold
      expect(book.open.length, 1);
      expect(book.closed.single.realizedPnl, closeTo(20, 1e-9));
      expect(book.withdrawals.single.amount, 50);

      // restart: ops persisted
      final again = CoreOutbox();
      await again.bind('0912');
      expect(again.length, 4);

      final svc = FakeCore()..down = true;
      Future<int?> send(CoreOp op) => sendCoreOp(svc, op,
          createWithdrawal: (a) async => Withdrawal(id: 9, amount: 50));
      expect(await again.flush(send), isFalse);
      expect(again.ops.first.attempts, 1);
      svc.down = false;
      final firstKeys = List.of(svc.keys);
      expect(await again.flush(send), isTrue);
      expect(svc.calls, ['asset.create طلا', 'buy 101', 'close 102']);
      // the retried op reused its key
      expect(svc.keys[firstKeys.length], firstKeys.first);
      expect(again.idMap, {-10: 101, -20: 102, -30: 9});
    });

    test('refusal keeps the op with its reason', () async {
      final ob = CoreOutbox();
      await ob.bind('0913');
      await ob.add('trade.delete', {'tradeId': 5}, 'd');
      final svc = FakeCore()..refuse = 'delete 5';
      expect(await ob.flush((op) => sendCoreOp(svc, op)), isFalse);
      expect(ob.ops.single.error, 'نامعتبر');
    });

    test('settings pushes coalesce into one pending op', () async {
      final ob = CoreOutbox();
      await ob.bind('0914');
      await ob.add('settings.push', const {}, 's');
      await ob.add('settings.push', const {}, 's');
      expect(ob.length, 1);
    });

    test('Idempotency scope numbers each write of one op', () async {
      final got = <String?>[];
      await IdempotencyScope.run('q-abc', () async {
        got
          ..add(IdempotencyScope.nextKey())
          ..add(IdempotencyScope.nextKey());
      });
      expect(got, ['q-abc-1', 'q-abc-2']);
      expect(IdempotencyScope.nextKey(), isNull);
    });
  });
}

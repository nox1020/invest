import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/account_cache.dart';
import 'package:invest/data/app_database.dart';
import 'package:invest/data/biz_remote.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'biz_test.dart' show FakeBizServer;

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

Future<BizRemote> _biz(FakeBizServer s) async {
  final session = await SessionStore.load();
  return BizRemote(InvestApiClient(session, client: MockClient(s.handle))
    ..restoreSessionCookie());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: 'https://vinor.test',
      AppConfig.prefSessionCookie: 'vinor_session=t',
    });
    BizStore.instance.debugReset();
  });

  test('AccountCache keeps the old keys and the owner of each write', () async {
    final c = AccountCache(keyOf: (a, y) => 'k_${a}_$y', lastAccountKey: 'last');
    await c.write(' 0911 ', 'A', 1);
    expect((await SharedPreferences.getInstance()).getString('k_0911_1'), 'A');
    expect(await c.read('0911', 1), 'A');
    expect(await c.lastAccount(), isNull);
    await c.setLastAccount('0911');
    expect(await c.lastAccount(), '0911');
    await c.clearLastAccount();
    expect(await c.lastAccount(), isNull);
    expect(BizStore.cacheKey('0911', null), 'vplus_biz_cache_v1_0911_cur');
  });

  test('biz: a write that finishes after an account switch never lands in '
      'the new account (memory or cache)', () async {
    final a = FakeBizServer(), b = FakeBizServer()..pwo.clear();
    final store = BizStore.instance;
    await store.bindAccount(await _biz(a), 'A');
    final pending = store.addTrade({'buy_date': '1405/01/01', 'buy_amount': 7, 'sell_amount': 0});
    final switching = store.bindAccount(await _biz(b), 'B');
    await Future.wait([pending, switching]);
    expect(a.trades.length, 1); // A's write did happen on A's server
    expect(store.account, 'B');
    expect(store.snap.trades, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith('vplus_biz_cache_v1_B'))) {
      expect(prefs.getString(k), isNot(contains('"buy_amount":7')), reason: k);
    }
  });

  test('biz: switching accounts clears the previous error banner', () async {
    final a = FakeBizServer()..down = true, b = FakeBizServer();
    final store = BizStore.instance;
    await store.bindAccount(await _biz(a), 'A');
    expect(store.lastError, isNotNull);
    b.down = true;
    final f = store.bindAccount(await _biz(b), 'B');
    expect(store.lastError, isNull); // reset before B's own result
    expect(store.showingCache, isFalse);
    await f;
  });

  test('biz offline: last account without a cache shows nothing, not the '
      'previous account\'s snapshot', () async {
    final store = BizStore.instance;
    await store.bindAccount(await _biz(FakeBizServer()), 'A');
    expect(store.snap.raw, isNotEmpty);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(BizStore.lastAccountKey, 'B');
    await store.loadOffline();
    expect(store.account, 'B');
    expect(store.snap.raw, isEmpty);
    expect(store.showingCache, isTrue);
  });

  test('cheques: server phone differs from the stored one -> old book is '
      'parked under the old phone and not shown/saved as the new one',
      () async {
    final old = BankCheck(
        id: 1, direction: 'received', amount: 5, issueDate: '2026-01-01', dueDate: '2026-02-01');
    SharedPreferences.setMockInitialValues({
      AppConfig.prefSessionCookie: 'vinor_session=x',
      AppConfig.prefUserPhone: '09120000000',
      'check_book_v1_09120000000': jsonEncode([old.toMap()]),
    });
    final db = await databaseFactoryFfi.openDatabase(
        '${inMemoryDatabasePath}_${DateTime.now().microsecondsSinceEpoch}',
        options: OpenDatabaseOptions(
            version: 1, singleInstance: false,
            onCreate: (db, v) async => AppDatabase.migrateFresh(db)));
    AppDatabase.instance.debugOpenDatabase = () async => db;
    addTearDown(() async {
      await AppDatabase.instance.close();
      await db.close();
    });
    final state = AppState(httpClient: MockClient((r) async {
      final p = r.url.path;
      if (p.endsWith('/auth/status')) {
        return _json({'success': true, 'authenticated': true, 'phone': '09121111111'});
      }
      if (p.endsWith('/settings')) {
        return _json({'success': true, 'settings': {'live_prices_enabled': false, 'notifications_enabled': false}});
      }
      if (p.endsWith('/dashboard')) return _json({'success': true, 'metrics': {}, 'growth_series': []});
      return _json({'success': true, 'items': <Object>[]});
    }));
    await state.init();
    expect(state.userPhone, '09121111111');
    expect(state.checks.where((c) => c.amount == 5), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('check_book_v1_09121111111') ?? '[]', isNot(contains('"amount":5')));
    expect(prefs.getString('check_book_v1_09120000000'), contains('"amount":5'));
  });
}

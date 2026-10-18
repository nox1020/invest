import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/data/app_database.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/offline_cache_store.dart';
import 'package:invest/data/remote_invest_service.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/trade_service.dart';
import 'package:invest/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _BookServer {
  _BookServer({this.failPosts = false, this.failDashboard = false});

  final bool failPosts;
  final bool failDashboard;
  final calls = <String>[];
  final assets = <Map<String, dynamic>>[];
  final openTrades = <Map<String, dynamic>>[];
  int _id = 10;

  int get postCount => calls.where((c) => c.startsWith('POST ')).length;

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');
    if (request.method == 'POST' && failPosts) {
      return _json({'success': false, 'message': 'nope'}, 500);
    }
    if (request.method == 'GET' &&
        path.endsWith('/dashboard') &&
        failDashboard) {
      return _json({'success': false, 'message': 'dashboard down'}, 500);
    }
    if (request.method == 'POST' && path.endsWith('/assets')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final item = <String, dynamic>{
        'id': _id++,
        'name': body['name'],
        'symbol': body['symbol'] ?? '',
        'quantity': body['quantity'] ?? 0,
        'avg_buy_price': body['avg_buy_price'] ?? 0,
        'current_price': body['current_price'] ?? 0,
        'notes': body['notes'] ?? '',
      };
      assets.add(item);
      return _json({'success': true, 'item': item});
    }
    if (request.method == 'POST' && path.endsWith('/trades/buy')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final item = <String, dynamic>{
        'id': _id++,
        'asset_id': body['asset_id'],
        'status': 'open',
        'quantity': body['quantity'],
        'buy_price': body['buy_price'],
        'buy_fee': body['buy_fee'] ?? 0,
        'buy_date': body['buy_date'] ?? '',
        'buy_note': body['buy_note'] ?? '',
        'asset_name': body['name'] ?? '',
        'asset_symbol': body['symbol'] ?? '',
        'current_price': body['current_price'] ?? 0,
      };
      openTrades.add(item);
      return _json({'success': true, 'item': item});
    }
    if (request.method == 'GET' && path.endsWith('/settings')) {
      return _json({
        'success': true,
        'settings': {
          'calendar': 'gregorian',
          'live_prices_enabled': false,
          'usdt_api_enabled': false,
          'gold_api_enabled': false,
          'notifications_enabled': false,
          'notify_trades': false,
          'notify_background': false,
        },
      });
    }
    if (request.method == 'GET' && path.endsWith('/dashboard')) {
      return _json({
        'success': true,
        'metrics': {
          'total_value': 0,
          'total_pnl': 0,
          'total_pnl_pct': 0,
          'realized_pnl': 0,
          'unrealized_pnl': 0,
          'open_count': 0,
          'closed_count': 0,
          'year_realized_pnl': 0,
        },
        'gold_fund': <String, dynamic>{},
        'growth_series': <Object>[],
      });
    }
    if (request.method == 'GET' && path.endsWith('/assets')) {
      return _json({'success': true, 'items': assets});
    }
    if (request.method == 'GET' && path.endsWith('/trades/open')) {
      return _json({'success': true, 'items': openTrades});
    }
    if (request.method == 'GET' && path.endsWith('/trades/closed')) {
      return _json({'success': true, 'items': <Object>[]});
    }
    if (request.method == 'GET' && path.endsWith('/withdrawals')) {
      return _json({'success': true, 'items': <Object>[]});
    }
    if (request.method == 'GET' && path.endsWith('/checks')) {
      return _json({'success': true, 'items': <Object>[]});
    }
    return _json({'success': true});
  }

  http.Response _json(Object body, [int status = 200]) {
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
  }
}

Future<AppState> _stateFor(_BookServer server) async {
  final session = await SessionStore.load();
  final state = AppState();
  state.userPhone = '09120000000';
  state.remote = RemoteInvestService(
    InvestApiClient(session, client: MockClient(server.handle)),
  );
  return state;
}

Future<Database> _openDb() {
  final path =
      '${inMemoryDatabasePath}_${DateTime.now().microsecondsSinceEpoch}';
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      singleInstance: false,
      onCreate: (db, version) async {
        await AppDatabase.migrateFresh(db);
      },
    ),
  );
}

DashboardMetrics _metrics() {
  return const DashboardMetrics(
    totalValue: 100,
    totalPnl: 1,
    totalPnlPct: 1,
    realizedPnl: 0,
    unrealizedPnl: 1,
    openCount: 1,
    closedCount: 0,
    yearRealizedPnl: 0,
    yearKey: '2024',
    goldFund: GoldFundMetrics(goldInG: 0, goldOutG: 0, goldHoldingG: 0),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppDatabase.instance.close();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  test('a failed dashboard load keeps the cached book and skips the update prompt',
      () async {
    await OfflineCacheStore.savePortfolio(
      settings: AppSettings(
        calendar: 'gregorian',
        livePricesEnabled: false,
        notificationsEnabled: false,
      ),
      metrics: _metrics(),
      assets: [
        Asset(
          name: 'ذخیره',
          symbol: 'GOLD',
          quantity: 2,
          avgBuyPrice: 10,
          currentPrice: 12,
        ),
      ],
      openTrades: const [],
      closedTrades: const [],
    );
    final server = _BookServer(failDashboard: true);
    final state = await _stateFor(server);

    await state.refresh();

    expect(state.assets.single.name, 'ذخیره');
    expect(state.error, contains('به‌روزرسانی داشبورد انجام نشد'));
    expect(state.error, isNot(contains('به‌روز کنید')));
    expect(state.error, isNot(contains('برنامه را')));
    expect(state.authenticated, isFalse);
    final snap = await OfflineCacheStore.loadPortfolio();
    expect(snap!.assets.single.name, 'ذخیره');
    expect(server.calls.where((c) => c.startsWith('DELETE ')), isEmpty);
  });

  test('empty server lists are filled from sqlite once and a re-login does not duplicate',
      () async {
    final db = await _openDb();
    await AppDatabase.instance.bind(db);
    final local = TradeService(db);
    await local.createAsset(
      name: 'طلا',
      symbol: 'GOLD',
      quantity: 2,
      avgBuyPrice: 1000,
      currentPrice: 1100,
      buyDate: '2024-05-01',
    );

    final server = _BookServer();
    final state = await _stateFor(server);
    await state.refresh();

    expect(state.assets.map((a) => a.name), contains('طلا'));
    expect(state.error, isNull);
    expect(
      server.calls.where((c) => c == 'POST /invest/api/v1/assets'),
      hasLength(1),
    );
    expect(
      server.calls.where((c) => c == 'POST /invest/api/v1/trades/buy'),
      hasLength(1),
    );
    expect((server.assets.single['quantity'] as num).toDouble(), 0);
    expect(server.calls.where((c) => c.startsWith('DELETE ')), isEmpty);
    expect(await db.query('assets'), isNotEmpty);

    final posts = server.postCount;
    await state.refresh();
    expect(server.postCount, posts);
    expect(state.assets.map((a) => a.name), contains('طلا'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('portfolio_upload_pending_v1_09120000000'), isNot(true));
    final snap = await OfflineCacheStore.loadPortfolio();
    expect(snap!.assets.map((a) => a.name), contains('طلا'));
    expect(await db.query('assets'), isNotEmpty);
  });

  test('a failed upload stays on the phone and is retried', () async {
    final db = await _openDb();
    await AppDatabase.instance.bind(db);
    await TradeService(db).createAsset(
      name: 'طلا',
      symbol: 'GOLD',
      quantity: 1,
      avgBuyPrice: 500,
      currentPrice: 500,
      buyDate: '2024-05-01',
    );
    await OfflineCacheStore.savePortfolio(
      settings: AppSettings(
        livePricesEnabled: false,
        notificationsEnabled: false,
      ),
      metrics: _metrics(),
      assets: [
        Asset(name: 'طلا', symbol: 'GOLD', quantity: 1),
      ],
      openTrades: const [],
      closedTrades: const [],
    );

    final server = _BookServer(failPosts: true);
    final state = await _stateFor(server);
    await state.refresh();
    await state.refresh();

    expect(
      server.calls.where((c) => c == 'POST /invest/api/v1/assets'),
      hasLength(2),
    );
    expect(state.assets.map((a) => a.name), contains('طلا'));
    expect(await db.query('assets'), isNotEmpty);
    expect(server.assets, isEmpty);
    expect(server.calls.where((c) => c.startsWith('DELETE ')), isEmpty);
    final snap = await OfflineCacheStore.loadPortfolio();
    expect(snap!.assets.map((a) => a.name), contains('طلا'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('portfolio_upload_pending_v1_09120000000'), isTrue);
  });

  test('a non-empty server book is kept and not replaced by the phone database',
      () async {
    final db = await _openDb();
    await AppDatabase.instance.bind(db);
    await TradeService(db).createAsset(
      name: 'گوشی',
      symbol: 'LOCAL',
      quantity: 1,
      avgBuyPrice: 10,
      currentPrice: 10,
      buyDate: '2024-05-01',
    );
    final server = _BookServer();
    server.assets.add({
      'id': 7,
      'name': 'سرور',
      'symbol': 'SVR',
      'quantity': 3,
      'avg_buy_price': 1,
      'current_price': 1,
      'notes': '',
    });
    final state = await _stateFor(server);

    await state.refresh();

    expect(state.assets.map((a) => a.name), ['سرور']);
    expect(server.postCount, 0);
    expect(server.calls.where((c) => c.startsWith('DELETE ')), isEmpty);
    expect((await db.query('assets')).single['name'], 'گوشی');
  });

  test('an offline snapshot is shown and uploaded when sqlite is empty', () async {
    final db = await _openDb();
    await AppDatabase.instance.bind(db);
    await OfflineCacheStore.savePortfolio(
      settings: AppSettings(
        livePricesEnabled: false,
        notificationsEnabled: false,
      ),
      metrics: _metrics(),
      assets: [
        Asset(
          name: 'سکه',
          symbol: 'COIN',
          quantity: 3,
          avgBuyPrice: 20,
          currentPrice: 21,
        ),
      ],
      openTrades: [
        Trade(
          assetId: 1,
          status: 'open',
          quantity: 3,
          buyPrice: 20,
          buyDate: '2024-02-02',
          assetName: 'سکه',
          assetSymbol: 'COIN',
        ),
      ],
      closedTrades: const [],
    );
    final server = _BookServer();
    final state = await _stateFor(server);

    await state.refresh();

    expect(state.assets.map((a) => a.name), contains('سکه'));
    expect(
      server.calls.where((c) => c == 'POST /invest/api/v1/assets'),
      hasLength(1),
    );
    expect(
      server.calls.where((c) => c == 'POST /invest/api/v1/trades/buy'),
      hasLength(1),
    );
    final posts = server.postCount;
    await state.refresh();
    expect(server.postCount, posts);
    final snap = await OfflineCacheStore.loadPortfolio();
    expect(snap!.assets.map((a) => a.name), contains('سکه'));
  });
}

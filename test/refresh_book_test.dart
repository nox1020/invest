import 'dart:convert';

import 'package:flutter/services.dart';
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
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _BookServer {
  _BookServer({
    this.failPosts = false,
    this.failDashboard = false,
    this.failSideRequests = false,
    this.redirectDashboard = false,
    this.accountShape = false,
  });

  final bool failPosts;
  final bool failDashboard;
  final bool failSideRequests;
  final bool redirectDashboard;
  final bool accountShape;
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
        redirectDashboard) {
      return http.Response(
        '<html>login</html>',
        302,
        headers: {
          'location': 'https://vinor.ir/login',
          'set-cookie': 'vinor_session=wiped; Path=/',
        },
      );
    }
    if (request.method == 'GET' &&
        path.endsWith('/dashboard') &&
        failDashboard) {
      return _json({'success': false, 'message': 'dashboard down'}, 500);
    }
    if (failSideRequests &&
        request.method == 'GET' &&
        (path.endsWith('/insights') ||
            path.endsWith('/checks') ||
            path.endsWith('/checks/reminders') ||
            path.endsWith('/withdrawals') ||
            path.endsWith('/quotes'))) {
      return _json({'success': false, 'message': 'side down'}, 500);
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
        'settings': accountShape ? _accountSettings() : _quietSettings(),
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
      return _json({
        'success': true,
        'items': accountShape ? _accountAssets() : assets,
      });
    }
    if (request.method == 'GET' && path.endsWith('/trades/open')) {
      return _json({
        'success': true,
        'items': accountShape ? _accountOpenTrades() : openTrades,
      });
    }
    if (request.method == 'GET' && path.endsWith('/trades/closed')) {
      return _json({
        'success': true,
        'items': accountShape ? _accountClosedTrades() : <Object>[],
      });
    }
    if (request.method == 'GET' && path.endsWith('/insights')) {
      return _json({
        'success': true,
        'generated_at': '2026-10-18 06:18:00',
        'items': [
          {
            'id': 'alloc-gold',
            'title': 'تمرکز طلا',
            'summary': 'بخش بزرگ',
            'description': 'توضیح',
            'action': 'متنوع کنید',
            'category': 'risk',
            'severity': 'm',
            'priority': 2,
            'related_assets': ['GOLD'],
            'related_trades': <Object>[],
          },
          'skip-me',
        ],
      });
    }
    if (request.method == 'GET' && path.endsWith('/withdrawals')) {
      return _json({'success': true, 'items': <Object>[]});
    }
    if (request.method == 'GET' && path.endsWith('/checks')) {
      return _json({'success': true, 'items': <Object>[]});
    }
    return _json({'success': true});
  }

  Map<String, dynamic> _quietSettings() => {
        'calendar': 'gregorian',
        'live_prices_enabled': false,
        'usdt_api_enabled': false,
        'gold_api_enabled': false,
        'notifications_enabled': false,
        'notify_trades': false,
        'notify_background': false,
      };

  Map<String, dynamic> _accountSettings() => {
        'calendar': 'jalali',
        'currency': 'toman',
        'theme': 'dark',
        'first_run_done': true,
        'goal_roi_pct': null,
        'live_prices_enabled': false,
        'usdt_api_enabled': false,
        'gold_api_enabled': false,
        'gold_auto_update_assets': false,
        'notifications_enabled': false,
        'notify_trades': false,
        'notify_withdrawals': false,
        'notify_price_moves': false,
        'price_refresh_seconds': 60,
        'gold_tmn_per_gram': 3500000.0,
        'usdt_tmn_rate': 60000.0,
        'wallex_markets_url': 'https://api.wallex.ir/v1/markets',
        'persiantoolbox_url': 'https://persiantoolbox.ir/api/market',
        'client_checks': [
          {
            'id': 4,
            'direction': 'receivable',
            'amount': 1500000,
            'issue_date': '2026-10-01',
            'due_date': '2026-11-01',
            'check_number': '1010',
            'sayad_id': '1234567890123456',
            'bank_name': 'ملت',
            'branch': '',
            'counterparty': 'طرف حساب',
            'purpose': 'قرض',
            'note': 'یادداشت',
            'status': 'pending',
            'settled_date': null,
            'days_until_due': 12,
            'created_at': '2026-10-01 08:00:00',
            'updated_at': '2026-10-01 08:00:00',
          },
        ],
        'raw': {
          'calendar': 'jalali',
          'goal_roi_pct': '',
          'price_refresh_seconds': '60',
          'live_prices_enabled': '0',
          'notifications_enabled': '0',
        },
      };

  List<Object> _accountAssets() => [
        {
          'id': 3,
          'name': 'سکه ۱۸',
          'symbol': '',
          'quantity': 1.5,
          'avg_buy_price': 10.0,
          'current_price': 12.0,
          'notes': '',
          'total_value': 18.0,
          'cost_basis': 15.0,
          'unrealized_pnl': 3.0,
          'unrealized_pnl_pct': 20.0,
          'created_at': '2024-01-01 00:00:00',
          'updated_at': '2024-01-02 00:00:00',
        },
        'not-a-row',
        {
          'id': 4,
          'name': 'صندوق',
          'symbol': 'FUND',
          'quantity': 2.0,
          'avg_buy_price': 5.0,
          'current_price': 6.0,
          'notes': '',
          'total_value': 12.0,
          'cost_basis': 10.0,
          'unrealized_pnl': 2.0,
          'unrealized_pnl_pct': 20.0,
          'created_at': '2024-02-01 00:00:00',
          'updated_at': '2024-02-02 00:00:00',
        },
      ];

  List<Map<String, dynamic>> _accountOpenTrades() => [
        {
          'id': 8,
          'asset_id': 3,
          'asset_name': 'سکه ۱۸',
          'asset_symbol': '',
          'status': 'open',
          'quantity': 1.5,
          'buy_price': 10.0,
          'buy_fee': 0.0,
          'buy_date': '2024-01-01',
          'buy_note': '[buy_fx:60000.0]',
          'sell_price': null,
          'sell_fee': 0.0,
          'sell_date': null,
          'sell_note': '',
          'realized_pnl': null,
          'return_pct': null,
          'holding_days': null,
          'current_price': 12.0,
          'current_value': 18.0,
          'created_at': '2024-01-01 00:00:00',
          'updated_at': '2024-01-02 00:00:00',
        },
      ];

  List<Map<String, dynamic>> _accountClosedTrades() => [
        {
          'id': 9,
          'asset_id': 4,
          'asset_name': 'صندوق',
          'asset_symbol': 'FUND',
          'status': 'closed',
          'quantity': 1.0,
          'buy_price': 5.0,
          'buy_fee': 0.0,
          'buy_date': '2024-01-01',
          'buy_note': '',
          'sell_price': 7.0,
          'sell_fee': 0.0,
          'sell_date': '2024-06-01',
          'sell_note': '',
          'realized_pnl': 2.0,
          'return_pct': 40.0,
          'holding_days': 120,
          'current_price': 7.0,
          'current_value': 7.0,
          'created_at': '2024-01-01 00:00:00',
          'updated_at': '2024-06-01 00:00:00',
        },
      ];

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

  test('a non-empty server book replaces an empty cache when other routes fail',
      () async {
    await OfflineCacheStore.savePortfolio(
      settings: AppSettings(
        livePricesEnabled: false,
        notificationsEnabled: false,
      ),
      metrics: _metrics(),
      assets: const [],
      openTrades: const [],
      closedTrades: const [],
    );
    final server = _BookServer(
      failDashboard: true,
      failSideRequests: true,
      accountShape: true,
    );
    final state = await _stateFor(server);

    await state.refresh();

    expect(state.assets.map((a) => a.name), ['سکه ۱۸', 'صندوق']);
    expect(state.assets.first.symbol, isEmpty);
    expect(state.openTrades, hasLength(1));
    expect(state.openTrades.single.sellPrice, isNull);
    expect(state.openTrades.single.holdingDays, isNull);
    expect(state.closedTrades, hasLength(1));
    expect(state.error, contains('به‌روزرسانی داشبورد انجام نشد'));
    expect(state.error, contains('dashboard: InvestApiException/500'));
    expect(state.error, contains('داده‌های سرور نشان داده می‌شود'));
    expect(state.error, isNot(contains('به‌روز کنید')));
    expect(server.postCount, 0);
    final snap = await OfflineCacheStore.loadPortfolio();
    expect(snap!.assets.map((a) => a.name), ['سکه ۱۸', 'صندوق']);
  });

  test('a login redirect does not discard the server book or the session cookie',
      () async {
    SharedPreferences.setMockInitialValues({
      'vinor_session_cookie': 'vinor_session=keep-me',
    });
    final server = _BookServer(
      redirectDashboard: true,
      accountShape: true,
    );
    final state = await _stateFor(server);

    await state.refresh();

    expect(state.assets.map((a) => a.name), contains('سکه ۱۸'));
    expect(state.error, contains('dashboard: InvestApiException/redirect'));
    expect(state.error, contains('داده‌های سرور نشان داده می‌شود'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('vinor_session_cookie'), 'vinor_session=keep-me');
    expect(state.authenticated, isFalse);
  });

  test('shared preferences channel failures do not fail the server book', () async {
    final store = _BrokenPrefsStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
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

    await state.refreshAll(includeQuotes: true);

    expect(state.assets.map((a) => a.name), ['سرور']);
    expect(state.error, isNull);
    expect(store.droppedHeavyKey, isTrue);
    final snap = await OfflineCacheStore.loadPortfolio();
    expect(snap!.assets.map((a) => a.name), ['سرور']);
  });

  test('a broken sqlite file is recreated and the server book stays', () async {
    var opens = 0;
    AppDatabase.instance.debugOpenDatabase = () async {
      opens++;
      if (opens == 1) {
        throw PlatformException(
          code: 'sqlite_error',
          message: 'database disk image is malformed',
        );
      }
      return _openDb();
    };
    final server = _BookServer();
    server.assets.add({
      'id': 8,
      'name': 'سرور',
      'symbol': 'SVR',
      'quantity': 2,
      'avg_buy_price': 4,
      'current_price': 5,
      'notes': '',
    });
    final state = await _stateFor(server);

    await state.refreshAll(includeQuotes: true);

    expect(opens, greaterThanOrEqualTo(2));
    expect(state.assets.map((a) => a.name), ['سرور']);
    expect(state.error, isNull);
    expect(server.postCount, 0);
  });

  test('sqlite that keeps failing does not blank the server book', () async {
    AppDatabase.instance.debugOpenDatabase = () async {
      throw PlatformException(
        code: 'sqlite_error',
        message: 'unable to open database file',
      );
    };
    final server = _BookServer();
    server.assets.add({
      'id': 9,
      'name': 'سرور',
      'symbol': 'SVR',
      'quantity': 1,
      'avg_buy_price': 1,
      'current_price': 1,
      'notes': '',
    });
    final state = await _stateFor(server);

    await state.refresh();

    expect(state.assets.map((a) => a.name), ['سرور']);
    expect(state.error, isNull);
    expect(server.postCount, 0);
  });
}

class _BrokenPrefsStore extends SharedPreferencesStorePlatform {
  final data = <String, Object>{
    'flutter.offline_portfolio_snapshot_v1': 'x' * 32,
    'flutter.vinor_session_cookie': 'vinor_session=keep',
  };

  bool droppedHeavyKey = false;
  bool _poisoned = true;

  @override
  Future<bool> clear() async => true;

  @override
  Future<Map<String, Object>> getAll() async {
    if (_poisoned && data.containsKey('flutter.offline_portfolio_snapshot_v1')) {
      throw PlatformException(
        code: 'channel-error',
        message: 'TransactionTooLargeException: data parcel size',
      );
    }
    return Map<String, Object>.from(data);
  }

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    if (key.endsWith('offline_portfolio_snapshot_v1')) {
      droppedHeavyKey = true;
      _poisoned = false;
    }
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    data[key] = value;
    return true;
  }
}

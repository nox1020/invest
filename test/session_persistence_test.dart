import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/app.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/app_database.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/offline_cache_store.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/app_lock_page.dart';
import 'package:invest/ui/pages/login_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Database? memDb;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SessionStore.debugStoreDirectory = null;
    final path =
        '${inMemoryDatabasePath}_${DateTime.now().microsecondsSinceEpoch}';
    memDb = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, version) async {
          await AppDatabase.migrateFresh(db);
        },
      ),
    );
    final db = memDb!;
    AppDatabase.instance.debugOpenDatabase = () async => db;
  });

  tearDown(() async {
    SessionStore.debugStoreDirectory = null;
    await AppDatabase.instance.close();
    final db = memDb;
    memDb = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  });

  test('session file is used when preferences cannot be read', () async {
    final dir = await Directory.systemTemp.createTemp('vinor-session');
    addTearDown(() => dir.delete(recursive: true));
    SessionStore.debugStoreDirectory = dir;
    await File('${dir.path}/vinor_session.json').writeAsString(jsonEncode({
      AppConfig.prefSessionCookie: 'vinor_session=from-file',
      AppConfig.prefUserPhone: '09123334444',
    }));
    SharedPreferencesStorePlatform.instance = _AlwaysThrowPrefs();
    SharedPreferences.resetStatic();

    final store = await SessionStore.load();

    expect(store.sessionCookie, 'vinor_session=from-file');
    expect(store.phone, '09123334444');
    SharedPreferences.setMockInitialValues({});
  });

  test('a stored session survives a poisoned preferences blob', () async {
    final store = _PoisonedPrefs();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();

    final session = await SessionStore.load();

    expect(session.sessionCookie, 'vinor_session=keep');
    expect(store.droppedHeavyKey, isTrue);
    SharedPreferences.setMockInitialValues({});
  });

  test('bearer retry keeps a cookie the server rejected as a cookie', () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefSessionCookie: 'vinor_session=abc',
      AppConfig.prefUserPhone: '09120000000',
    });
    final seen = <String>[];
    final session = await SessionStore.load();
    final api = InvestApiClient(
      session,
      client: MockClient((request) async {
        seen.add(request.headers['cookie'] ?? '');
        if ((request.headers['cookie'] ?? '').isNotEmpty) {
          return _json({
            'success': false,
            'error': 'session_expired',
            'message': 'expired',
          }, 401);
        }
        expect(request.headers['authorization'], 'Bearer abc');
        return _json({
          'success': true,
          'authenticated': true,
          'phone': '09120000000',
        });
      }),
    );

    final result = await api.checkAuthDetailed();

    expect(result.status, AuthCheckStatus.authenticated);
    expect(result.phone, '09120000000');
    expect(seen, ['vinor_session=abc', '']);
    expect((await SessionStore.load()).sessionCookie, 'vinor_session=abc');
    expect(api.omitSessionCookie, isTrue);
  });

  test('html and transport failures do not clear the session', () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefSessionCookie: 'vinor_session=stay',
      AppConfig.prefUserPhone: '09124445555',
    });
    final session = await SessionStore.load();
    final html = InvestApiClient(
      session,
      client: MockClient((request) async {
        return http.Response('<html>login</html>', 401);
      }),
    );
    expect(
      (await html.checkAuthDetailed()).status,
      AuthCheckStatus.offline,
    );

    final down = InvestApiClient(
      session,
      client: MockClient((request) async {
        throw http.ClientException('dns');
      }),
    );
    expect(
      (await down.checkAuthDetailed()).status,
      AuthCheckStatus.offline,
    );
    expect((await SessionStore.load()).sessionCookie, 'vinor_session=stay');
    expect((await SessionStore.load()).phone, '09124445555');
  });

  testWidgets('cold start offline with a stored session opens the dashboard',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'dash_open_v1': ['gold', 'other', 'fx'],
      AppConfig.prefSessionCookie: 'vinor_session=cold',
      AppConfig.prefUserPhone: '09121112222',
    });
    final state = AppState(
      httpClient: MockClient((request) async {
        throw http.ClientException('offline');
      }),
    );
    addTearDown(() => tester.runAsync(() => state.logout()));

    await tester.runAsync(() async {
      await OfflineCacheStore.savePortfolio(
        settings: AppSettings(calendar: 'gregorian', livePricesEnabled: false),
        metrics: _metrics(),
        assets: [
          Asset(id: 1, name: 'طلای ذخیره‌شده', quantity: 2, currentPrice: 10),
        ],
        openTrades: const [],
        closedTrades: const [],
      );
      await state.init();
    });

    expect(state.authenticated, isTrue);
    expect(state.offline, isTrue);
    expect(state.reauthRequired, isFalse);
    expect(state.userPhone, '09121112222');
    expect(state.assets.single.name, 'طلای ذخیره‌شده');
    expect(
      (await SessionStore.load()).sessionCookie,
      'vinor_session=cold',
    );

    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const InvestApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('داشبورد'), findsWidgets);
    expect(find.textContaining('طلای ذخیره‌شده'), findsWidgets);
  });

  test('a network error during refresh stays logged in', () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefSessionCookie: 'vinor_session=keep-me',
      AppConfig.prefUserPhone: '09120000000',
    });
    var online = true;
    final state = AppState(
      httpClient: MockClient((request) async {
        if (!online) throw http.ClientException('timeout');
        if (request.url.path.endsWith('/auth/status')) {
          return _json({
            'success': true,
            'authenticated': true,
            'phone': '09120000000',
          });
        }
        if (request.url.path.endsWith('/assets')) {
          return _json({
            'success': true,
            'items': [
              {
                'id': 1,
                'name': 'صندوق',
                'symbol': 'F',
                'quantity': 1,
                'avg_buy_price': 1,
                'current_price': 1,
                'notes': '',
              },
            ],
          });
        }
        if (request.url.path.endsWith('/trades/open') ||
            request.url.path.endsWith('/trades/closed') ||
            request.url.path.endsWith('/withdrawals') ||
            request.url.path.endsWith('/checks')) {
          return _json({'success': true, 'items': <Object>[]});
        }
        if (request.url.path.endsWith('/settings')) {
          return _json({
            'success': true,
            'settings': {
              'calendar': 'gregorian',
              'live_prices_enabled': false,
              'notifications_enabled': false,
            },
          });
        }
        if (request.url.path.endsWith('/dashboard')) {
          return _json({
            'success': true,
            'metrics': {
              'total_value': 1,
              'total_pnl': 0,
              'total_pnl_pct': 0,
              'realized_pnl': 0,
              'unrealized_pnl': 0,
              'open_count': 0,
              'closed_count': 0,
              'year_realized_pnl': 0,
            },
            'growth_series': <Object>[],
          });
        }
        return _json({'success': true});
      }),
    );
    addTearDown(() => state.logout());

    await state.init();
    expect(state.authenticated, isTrue);
    expect(state.assets.single.name, 'صندوق');

    online = false;
    await state.refresh();

    expect(state.authenticated, isTrue);
    expect(state.reauthRequired, isFalse);
    expect(state.offline, isTrue);
    expect(state.assets.single.name, 'صندوق');
    expect(
      (await SessionStore.load()).sessionCookie,
      'vinor_session=keep-me',
    );
    expect((await SessionStore.load()).phone, '09120000000');
  });

  test('a definitive 401 keeps the cache and asks to sign in again', () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefSessionCookie: 'vinor_session=old',
      AppConfig.prefUserPhone: '09125556666',
    });
    await OfflineCacheStore.savePortfolio(
      settings: AppSettings(calendar: 'gregorian', livePricesEnabled: false),
      metrics: _metrics(),
      assets: [
        Asset(id: 2, name: 'سکه ذخیره‌شده', quantity: 1, currentPrice: 5),
      ],
      openTrades: const [],
      closedTrades: const [],
    );
    final state = AppState(
      httpClient: MockClient((request) async {
        return _json({
          'success': false,
          'error': 'session_expired',
          'message': 'برای امنیت بیشتر، دوباره وارد شوید',
        }, 401);
      }),
    );
    addTearDown(() => state.logout());

    await state.init();

    expect(state.authenticated, isTrue);
    expect(state.reauthRequired, isTrue);
    expect(state.assets.single.name, 'سکه ذخیره‌شده');
    expect((await SessionStore.load()).sessionCookie, 'vinor_session=old');
    expect((await SessionStore.load()).phone, '09125556666');
  });

  test('manual logout clears the session and nothing else does', () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefSessionCookie: 'vinor_session=bye',
      AppConfig.prefUserPhone: '09127778888',
    });
    final state = AppState(
      httpClient: MockClient((request) async {
        throw http.ClientException('offline');
      }),
    );
    await state.init();
    expect(state.authenticated, isTrue);

    await state.setAppLockPassword('2468');
    expect(await state.unlockApp('2468'), isTrue);
    await state.removeAppLock();
    expect((await SessionStore.load()).sessionCookie, 'vinor_session=bye');
    expect((await SessionStore.load()).phone, '09127778888');

    await state.logout();

    expect(state.authenticated, isFalse);
    expect(state.reauthRequired, isFalse);
    expect(state.userPhone, isNull);
    expect((await SessionStore.load()).sessionCookie, isNull);
    expect((await SessionStore.load()).phone, isNull);
  });

  testWidgets('app lock does not clear the session', (tester) async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefSessionCookie: 'vinor_session=locked',
      AppConfig.prefUserPhone: '09129990000',
    });
    final state = AppState(
      httpClient: MockClient((request) async {
        throw http.ClientException('offline');
      }),
    );
    addTearDown(() => tester.runAsync(() => state.logout()));
    await tester.runAsync(() async {
      await state.setAppLockPassword('1357');
      await state.init();
    });

    expect(state.authenticated, isTrue);
    expect((await SessionStore.load()).sessionCookie, 'vinor_session=locked');

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const InvestApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(AppLockPage), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);

    expect(await state.unlockApp('1357'), isTrue);
    await tester.pump();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect((await SessionStore.load()).sessionCookie, 'vinor_session=locked');
    expect((await SessionStore.load()).phone, '09129990000');
  });
}

DashboardMetrics _metrics() {
  return const DashboardMetrics(
    totalValue: 20,
    totalPnl: 0,
    totalPnlPct: 0,
    realizedPnl: 0,
    unrealizedPnl: 0,
    openCount: 0,
    closedCount: 0,
    yearRealizedPnl: 0,
    yearKey: '2026',
    goldFund: GoldFundMetrics(goldInG: 0, goldOutG: 0, goldHoldingG: 0),
  );
}

http.Response _json(Object body, [int status = 200]) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

class _AlwaysThrowPrefs extends SharedPreferencesStorePlatform {
  @override
  Future<bool> clear() async => true;

  @override
  Future<Map<String, Object>> getAll() async {
    throw PlatformException(code: 'channel-error', message: 'getAll failed');
  }

  @override
  Future<bool> remove(String key) async => true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    return true;
  }
}

class _PoisonedPrefs extends SharedPreferencesStorePlatform {
  final data = <String, Object>{
    'flutter.offline_portfolio_snapshot_v1': 'x' * 32,
    'flutter.vinor_session_cookie': 'vinor_session=keep',
    'flutter.vinor_user_phone': '09120000000',
  };

  bool droppedHeavyKey = false;
  bool _poisoned = true;

  @override
  Future<bool> clear() async => true;

  @override
  Future<Map<String, Object>> getAll() async {
    if (_poisoned &&
        data.containsKey('flutter.offline_portfolio_snapshot_v1')) {
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

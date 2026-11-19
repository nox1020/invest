import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/app.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/app_database.dart';
import 'package:invest/data/offline_cache_store.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/app_lock_page.dart';
import 'package:invest/ui/pages/dashboard_page.dart';
import 'package:invest/ui/pages/login_page.dart';
import 'package:invest/ui/pages/performance_page.dart';
import 'package:invest/ui/pages/settings_page.dart';
import 'package:invest/ui/pages/trades_hub_page.dart';
import 'package:invest/ui/pages/withdrawals_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

DashboardMetrics _sampleMetrics({double value = 50000000}) => DashboardMetrics(
      totalValue: value,
      totalPnl: 5000000,
      totalPnlPct: 11.1,
      realizedPnl: 1000000,
      unrealizedPnl: 4000000,
      openCount: 1,
      closedCount: 0,
      yearRealizedPnl: 1000000,
      yearKey: '1404',
      goldFund: const GoldFundMetrics(goldInG: 0, goldOutG: 0, goldHoldingG: 0),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Database? memDb;

  setUp(() async {
    resetDashboardExpandCache();
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
    AppDatabase.instance.debugOpenDatabase = null;
    final db = memDb;
    memDb = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  });

  testWidgets(
      'cache-first boot renders Dashboard immediately while network auth is still pending',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefSessionCookie: 'vinor_session=fast',
      AppConfig.prefUserPhone: '09121110000',
    });
    await OfflineCacheStore.savePortfolio(
      settings: AppSettings(
        calendar: AppConfig.calendarJalali,
        livePricesEnabled: false,
      ),
      metrics: _sampleMetrics(),
      assets: [
        Asset(id: 1, name: 'طلای کش‌شده', quantity: 2, currentPrice: 25000000),
      ],
      openTrades: const [],
      closedTrades: const [],
    );
    await OfflineCacheStore.saveCommodities(const [
      CommodityQuote(
        id: 'usdt',
        name: 'تتر',
        symbol: 'USDT',
        unit: 'TMN',
        price: 84000,
      ),
    ]);

    final authGate = Completer<http.Response>();
    final state = AppState(
      httpClient: MockClient((request) async {
        final p = request.url.path;
        if (p.endsWith('/auth/status')) return authGate.future;
        if (p.endsWith('/assets')) {
          return _json({
            'success': true,
            'items': [
              {
                'id': 1,
                'name': 'طلای تازه سرور',
                'symbol': 'GOLD',
                'quantity': 2,
                'avg_buy_price': 20000000,
                'current_price': 26000000,
                'notes': '',
              }
            ],
          });
        }
        if (p.endsWith('/settings')) {
          return _json({
            'success': true,
            'settings': {
              'calendar': 'jalali',
              'live_prices_enabled': false,
              'notifications_enabled': false,
            },
          });
        }
        if (p.endsWith('/dashboard')) {
          return _json({
            'success': true,
            'metrics': {
              'total_value': 52000000,
              'total_pnl': 12000000,
              'total_pnl_pct': 30,
              'realized_pnl': 0,
              'unrealized_pnl': 12000000,
              'open_count': 0,
              'closed_count': 0,
              'year_realized_pnl': 0,
            },
            'growth_series': <Object>[],
          });
        }
        return _json({'success': true, 'items': <Object>[]});
      }),
    );
    addTearDown(() async {
      if (!authGate.isCompleted) {
        authGate.complete(_json({'success': true, 'authenticated': false}, 401));
      }
      state.dispose();
    });

    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const InvestApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    late Future<void> initFuture;
    await tester.runAsync(() async {
      initFuture = state.init();
      // Give Stage 1 local reads a brief moment while auth/status stays blocked.
      for (var i = 0; i < 30 && state.loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(state.loading, isFalse);
    expect(state.refreshing, isTrue);
    expect(state.authenticated, isTrue);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);

    await tester.runAsync(() async {
      authGate.complete(_json({
        'success': true,
        'authenticated': true,
        'phone': '09121110000',
      }));
      await initFuture;
    });
    await tester.pump();

    expect(state.refreshing, isFalse);
    expect(state.assets.single.name, 'طلای تازه سرور');
  });

  testWidgets('app lock protects cache-first startup before showing HomeShell',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefSessionCookie: 'vinor_session=locked-fast',
      AppConfig.prefUserPhone: '09129998877',
    });
    await OfflineCacheStore.savePortfolio(
      settings: AppSettings(
        calendar: AppConfig.calendarJalali,
        livePricesEnabled: false,
      ),
      metrics: _sampleMetrics(),
      assets: [Asset(id: 1, name: 'دارایی قفل‌شده', quantity: 1, currentPrice: 10)],
      openTrades: const [],
      closedTrades: const [],
    );

    final authGate = Completer<http.Response>();
    final state = AppState(
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/status')) return authGate.future;
        return _json({'success': true, 'items': <Object>[]});
      }),
    );
    addTearDown(() async {
      if (!authGate.isCompleted) {
        authGate.complete(_json({'success': false}, 401));
      }
      state.dispose();
    });

    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Future<void> initFuture;
    await tester.runAsync(() async {
      await state.setAppLockPassword('1357');
      initFuture = state.init();
      for (var i = 0; i < 30 && state.loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const InvestApp(),
      ),
    );
    await tester.pump();

    expect(state.loading, isFalse);
    expect(find.byType(AppLockPage), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);

    await tester.runAsync(() async {
      expect(await state.unlockApp('1357'), isTrue);
    });
    await tester.pump();
    expect(find.byType(HomeShell), findsOneWidget);

    await tester.runAsync(() async {
      authGate.complete(_json({'success': false}, 401));
      await initFuture;
    });
  });

  test('startup sync fetches portfolio once without duplicate immediate refresh',
      () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefSessionCookie: 'vinor_session=once',
      AppConfig.prefUserPhone: '09120001122',
    });
    final counts = <String, int>{};
    final state = AppState(
      httpClient: MockClient((request) async {
        final p = request.url.path;
        counts[p] = (counts[p] ?? 0) + 1;
        if (p.endsWith('/auth/status')) {
          return _json({
            'success': true,
            'authenticated': true,
            'phone': '09120001122',
          });
        }
        if (p.endsWith('/settings')) {
          return _json({
            'success': true,
            'settings': {
              'calendar': 'gregorian',
              'live_prices_enabled': false,
              'notifications_enabled': false,
            },
          });
        }
        if (p.endsWith('/dashboard')) {
          return _json({
            'success': true,
            'metrics': <String, Object?>{},
            'growth_series': <Object>[],
          });
        }
        return _json({'success': true, 'items': <Object>[]});
      }),
    );
    addTearDown(state.dispose);

    await state.init();
    // Flush microtasks / Timer.run scheduled after init.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(counts['/invest/api/v1/assets'], 1);
    expect(counts['/invest/api/v1/trades/open'], 1);
    expect(counts['/invest/api/v1/trades/closed'], 1);
    expect(counts['/invest/api/v1/dashboard'], 1);
    expect(counts['/invest/api/v1/settings'], 1);
  });

  testWidgets('HomeShell lazily mounts off-screen tabs on first visit only',
      (tester) async {
    resetDashboardExpandCache();
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: AppConfig.calendarJalali)
      ..assets = [
        Asset(id: 1, name: 'طلا', symbol: 'GOLD', quantity: 1, currentPrice: 10),
      ];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump();

    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.byType(WithdrawalsPage), findsNothing);
    expect(find.byType(TradesHubPage), findsNothing);
    expect(find.byType(PerformancePage), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);

    final nav = find.byType(BottomNavigationBar);
    await tester.tap(find.descendant(of: nav, matching: find.text('عملکرد')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(PerformancePage), findsOneWidget);
    expect(find.byType(WithdrawalsPage), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);

    await tester.tap(find.descendant(of: nav, matching: find.text('داشبورد')));
    await tester.pump();
    expect(find.byType(DashboardPage), findsOneWidget);
    // Preserved inside IndexedStack after first visit.
    expect(find.byType(PerformancePage), findsOneWidget);
  });
}

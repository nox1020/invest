import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/performance_aggregator.dart';
import 'package:invest/domain/utils/biz_dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/performance_page.dart';
import 'package:invest/ui/pages/trades_hub_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: 'https://vinor.test',
    });
    BizStore.instance.debugReset();
    ProjectsStore.instance.debugReset();
  });

  tearDown(() {
    BizStore.instance.debugReset();
    ProjectsStore.instance.debugReset();
  });

  group('PerformanceAggregator', () {
    test('aggregates every domain into Jalali months and isolates open capital', () {
      final biz = BizSnapshot({
        'year': 1405,
        'trades': [
          {
            'id': 1,
            'title': 'آپارتمان ونک',
            'buy_date': '1405/01/05',
            'sell_date': '1405/01/25',
            'buy_amount': 1000000000,
            'sell_amount': 1250000000,
            'extra_cost': 50000000, // net profit = 200M
          },
          {
            'id': 2,
            'title': 'زمین دماوند',
            'buy_date': '1405/02/10',
            'sell_date': '',
            'buy_amount': 500000000,
            'sell_amount': 0, // unsold property -> open exposure
          },
        ],
        'months': [
          {
            'year': 1405,
            'month': 1,
            'income': 60000000,
            'staff': 20000000,
            'pwo': 10000000,
            'ads': 5000000,
            'has_ops': true, // office net = +25M
          },
          for (var m = 2; m <= 12; m++) {'year': 1405, 'month': m},
        ],
      });

      final assets = [
        Asset(id: 1, name: 'طلای آب‌شده', symbol: 'GOLD', notes: '[kind:gold]'),
        Asset(id: 2, name: 'تتر', symbol: 'USDT', notes: '[kind:cash]'),
        Asset(id: 3, name: 'بیت‌کوین', symbol: 'BTC', notes: '[kind:crypto]'),
        Asset(id: 4, name: 'فولاد مبارکه', symbol: 'FOOLAD', notes: '[kind:stock]'),
        Asset(id: 5, name: 'دنا پلاس', symbol: 'CAR', notes: '[kind:vehicle]'),
        Asset(id: 6, name: 'شراکت بازرگانی قهوه', symbol: '', notes: '[kind:other]'),
      ];

      // 2026-03-21 == 1405/01/01 (Farvardin 1405)
      // 2026-04-21 == 1405/02/01 (Ordibehesht 1405)
      // 2026-03-20 == 1404/12/29 (Esfand 1404 -> excluded from 1405)
      final closedTrades = [
        Trade(
          id: 10,
          assetId: 1,
          assetName: 'طلای آب‌شده',
          assetSymbol: 'GOLD',
          status: AppConfig.tradeClosed,
          quantity: 10,
          buyPrice: 5000000,
          sellPrice: 6000000,
          realizedPnl: 10000000,
          buyDate: '2026-03-21',
          sellDate: '2026-03-25',
        ),
        Trade(
          id: 11,
          assetId: 5,
          assetName: 'دنا پلاس',
          assetSymbol: 'CAR',
          status: AppConfig.tradeClosed,
          quantity: 1,
          buyPrice: 900000000,
          sellPrice: 980000000,
          realizedPnl: 80000000,
          buyDate: '2026-03-22',
          sellDate: '2026-04-25', // Ordibehesht 1405
        ),
        Trade(
          id: 12,
          assetId: 6,
          assetName: 'شراکت بازرگانی قهوه',
          status: AppConfig.tradeClosed,
          quantity: 1,
          buyPrice: 100000000,
          sellPrice: 90000000,
          realizedPnl: -10000000,
          buyDate: '2026-04-22',
          sellDate: '2026-04-28', // Ordibehesht 1405
        ),
        Trade(
          id: 13,
          assetId: 3,
          assetName: 'بیت‌کوین',
          assetSymbol: 'BTC',
          status: AppConfig.tradeClosed,
          quantity: 1,
          buyPrice: 500000000,
          sellPrice: 600000000,
          realizedPnl: 100000000,
          buyDate: '2026-03-01',
          sellDate: '2026-03-20', // 1404/12/29 -> NOT 1405
        ),
      ];

      final openTrades = [
        Trade(
          id: 20,
          assetId: 2,
          assetName: 'تتر',
          assetSymbol: 'USDT',
          status: AppConfig.tradeOpen,
          quantity: 1000,
          buyPrice: 60000,
          currentPrice: 65000, // unrealized +5M, invested 60M
          buyDate: '2026-03-25', // bought Farvardin 1405
        ),
        Trade(
          id: 21,
          assetId: 4,
          assetName: 'فولاد مبارکه',
          assetSymbol: 'FOOLAD',
          status: AppConfig.tradeOpen,
          quantity: 100,
          buyPrice: 10000,
          currentPrice: 9000, // unrealized -100k, invested 1M
          buyDate: '2026-04-22',
        ),
      ];

      final projects = [
        Project({
          'id': 1,
          'title': 'بازسازی ویلا',
          'work_type': 'پیمانکاری',
          'start_date': '1405/01/10',
          'end_date': '1405/02/15',
          'contract_amount': 400000000,
          'cost': 300000000,
          'profit': 100000000,
          'status': 'finished',
          'archived': false,
        }),
        Project({
          'id': 2,
          'title': 'ساخت سوله',
          'work_type': 'پیمانکاری',
          'start_date': '1405/02/01',
          'contract_amount': 500000000,
          'cost': 200000000,
          'profit': 300000000,
          'status': 'active', // open/running -> NOT in realized profit
          'archived': false,
        }),
        Project({
          'id': 3,
          'title': 'پروژه قدیمی بایگانی',
          'start_date': '1405/01/01',
          'end_date': '1405/01/20',
          'contract_amount': 999000000,
          'cost': 0,
          'profit': 999000000,
          'status': 'finished',
          'archived': true, // excluded
        }),
      ];

      final s = PerformanceAggregator.build(
        year: 1405,
        biz: biz,
        assets: assets,
        openTrades: openTrades,
        closedTrades: closedTrades,
        projects: projects,
      );

      // Total realized net for 1405:
      // office (+25M) + property (+200M) + gold (+10M) + vehicle (+80M) + other (-10M) + projects (+100M) = 405M
      expect(s.totalNetFor(const {}), 405000000);
      expect(s.byDomain[PerfDomain.office]!.net, 25000000);
      expect(s.byDomain[PerfDomain.property]!.net, 200000000);
      expect(s.byDomain[PerfDomain.gold]!.net, 10000000);
      expect(s.byDomain[PerfDomain.vehicle]!.net, 80000000);
      expect(s.byDomain[PerfDomain.other]!.net, -10000000);
      expect(s.byDomain[PerfDomain.projects]!.net, 100000000);
      expect(s.byDomain[PerfDomain.crypto]!.net, 0); // 1404 trade excluded

      // Month 1 (Farvardin): office 25M + property 200M + gold 10M = 235M
      expect(s.months[0].netFor(const {}), 235000000);
      // Month 2 (Ordibehesht): vehicle 80M - other 10M + project 100M = 170M
      expect(s.months[1].netFor(const {}), 170000000);

      // Filtering to single/multiple domains updates totals dynamically:
      expect(s.totalNetFor({PerfDomain.vehicle}), 80000000);
      expect(s.totalNetFor({PerfDomain.gold, PerfDomain.projects}), 110000000);

      // Open / in-progress exposure stays separate:
      // unsold property (500M invested, 0 unrealized) +
      // open USDT (60M invested, +5M unrealized) +
      // open stock (1M invested, -100k unrealized) +
      // active project (200M cost invested, +300M expected)
      expect(s.totalOpenCount, 4);
      expect(s.totalOpenInvested, 761000000);
      expect(s.totalOpenUnrealizedPnl, 304900000);
    });
  });

  group('PerformancePage & TradesHubPage unified UI', () {
    testWidgets('shows all domains, breakdown card, open exposure, filters and month deals without BizStore loaded',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 740);
      addTearDown(tester.view.reset);

      ProjectsStore.instance.debugSet(ProjectsSnapshot({
        'items': [
          {
            'id': 1,
            'title': 'نوسازی مغازه',
            'work_type': 'پیمانکاری',
            'start_date': '1405/01/05',
            'end_date': '1405/01/20',
            'contract_amount': 150000000,
            'cost': 100000000,
            'profit': 50000000,
            'status': 'finished',
            'archived': false,
          },
          {
            'id': 2,
            'title': 'ساخت باغ ویلا',
            'start_date': '1405/01/12',
            'contract_amount': 300000000,
            'cost': 120000000,
            'profit': 180000000,
            'status': 'active',
            'archived': false,
          },
        ],
      }));

      final app = AppState()
        ..settings = AppSettings(calendar: AppConfig.calendarJalali)
        ..assets = [
          Asset(id: 1, name: 'پژو ۲۰۷', symbol: 'CAR', notes: '[kind:vehicle]'),
          Asset(id: 2, name: 'سکه امامی', symbol: 'GOLD', notes: '[kind:gold]'),
        ]
        ..closedTrades = [
          Trade(
            id: 1,
            assetId: 1,
            assetName: 'پژو ۲۰۷',
            status: AppConfig.tradeClosed,
            quantity: 1,
            buyPrice: 700000000,
            sellPrice: 760000000,
            realizedPnl: 60000000,
            buyDate: '2026-03-21',
            sellDate: '2026-03-25', // Farvardin 1405
          ),
        ]
        ..openTrades = [
          Trade(
            id: 2,
            assetId: 2,
            assetName: 'سکه امامی',
            status: AppConfig.tradeOpen,
            quantity: 2,
            buyPrice: 40000000,
            currentPrice: 45000000, // invested 80M, unrealized +10M
            buyDate: '2026-03-22',
          ),
        ];

      // Pin BizStore year to 1405 for deterministic test across years
      BizStore.yearNow = () => 1405;
      addTearDown(() => BizStore.yearNow = currentJalaliYear);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const MaterialApp(
            home: Scaffold(body: PerformancePage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Combined total: vehicle 60M + project 50M = 110M (open gold 80M excluded from realized net!)
      expect(tester.widget<Text>(find.byKey(const ValueKey('biz-total-net'))).data,
          formatMoney(110000000));
      expect(find.byKey(const ValueKey('perf-domain-filters')), findsOneWidget);
      expect(find.byKey(const ValueKey('perf-domain-breakdown')), findsOneWidget);
      expect(find.byKey(const ValueKey('perf-open-exposure')), findsOneWidget);

      // Filter strictly to vehicle -> total net updates to 60M
      await tester.tap(find.byKey(const ValueKey('perf-filter-vehicle')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('biz-total-net'))).data,
          formatMoney(60000000));

      // Clear filter back to all -> 110M
      await tester.tap(find.byKey(const ValueKey('perf-filter-all')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('biz-total-net'))).data,
          formatMoney(110000000));

      // Expand open exposure card -> shows gold & projects rows
      await tester.ensureVisible(find.byKey(const ValueKey('perf-open-exposure')));
      await tester.tap(find.byKey(const ValueKey('perf-open-exposure')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('perf-open-domain-projects')), findsOneWidget);
      expect(find.byKey(const ValueKey('perf-open-domain-gold')), findsOneWidget);

      // Open month 1 deals bottom sheet
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('biz-month-deals-1')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('biz-month-deals-1')));
      await tester.pumpAndSettle();
      expect(find.text('پژو ۲۰۷'), findsOneWidget);
      expect(find.text('سکه امامی'), findsOneWidget);
      expect(find.textContaining('نوسازی مغازه'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('TradesHubPage filters include vehicle, property, and other kinds', (tester) async {
      final app = AppState()
        ..assets = [
          Asset(id: 1, name: 'دنا', notes: '[kind:vehicle]'),
          Asset(id: 2, name: 'طلا', notes: '[kind:gold]'),
        ]
        ..openTrades = [
          Trade(id: 1, assetId: 1, assetName: 'دنا', status: AppConfig.tradeOpen, quantity: 1, buyPrice: 100),
          Trade(id: 2, assetId: 2, assetName: 'طلا', status: AppConfig.tradeOpen, quantity: 1, buyPrice: 50),
        ];

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const MaterialApp(
            home: Scaffold(body: TradesHubPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('خودرو'), findsOneWidget);
      expect(find.text('ملک'), findsOneWidget);
      expect(find.text('سایر'), findsOneWidget);
      await tester.tap(find.text('خودرو'));
      await tester.pumpAndSettle();
      expect(find.text('دنا'), findsOneWidget);
      expect(find.text('طلا'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

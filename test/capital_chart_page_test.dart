import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/year_nav_entry.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/capital_chart_page.dart';
import 'package:invest/ui/widgets/portfolio_value_breakdown.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('capital desk shows economist sections from live NAV',
      (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(
        calendar: AppConfig.calendarGregorian,
        annualWithdrawalPct: 10,
      )
      ..assets = [
        Asset(
          id: 1,
          name: 'Bitcoin',
          symbol: 'BTC',
          quantity: 1,
          avgBuyPrice: 1e9,
          currentPrice: 1.2e9,
          notes: '[kind:crypto]',
        ),
      ]
      ..openTrades = [
        Trade(
          assetId: 1,
          status: AppConfig.tradeOpen,
          quantity: 1,
          buyPrice: 1e9,
          buyPriceUsd: 20000,
          assetName: 'Bitcoin',
          assetSymbol: 'BTC',
          currentPrice: 1.2e9,
        ),
      ]
      ..closedTrades = [
        Trade(
          assetId: 1,
          status: AppConfig.tradeClosed,
          quantity: 1,
          buyPrice: 500000,
          sellPrice: 800000,
          realizedPnl: 300000,
          sellDate: '2026-02-01',
          assetName: 'Bitcoin',
          assetSymbol: 'BTC',
        ),
      ]
      ..metrics = DashboardMetrics(
        totalValue: 1.2e9,
        totalPnl: 0.2e9 + 300000,
        totalPnlPct: 20,
        realizedPnl: 300000,
        unrealizedPnl: 0.2e9,
        openCount: 1,
        closedCount: 1,
        yearRealizedPnl: 300000,
        yearKey: '2026',
        goldFund: const GoldFundMetrics(
          goldInG: 0,
          goldOutG: 0,
          goldHoldingG: 0,
        ),
        growthSeries: const [
          SeriesPoint(date: '2026-01-01', value: 1e9),
          SeriesPoint(date: '2026-03-01', value: 1.2e9),
        ],
      );

    tester.view.physicalSize = const Size(800, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          locale: Locale('fa', 'IR'),
          home: CapitalChartPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('میز سرمایه'), findsWidgets);
    expect(find.text('ارزش پورتفو'), findsOneWidget);
    expect(find.text('ترازنامه'), findsOneWidget);
    expect(find.text('ارزش و سود'), findsOneWidget);
    expect(find.text('تخصیص دارایی'), findsNothing);
    expect(find.text('ظرفیت برداشت'), findsNothing);
    expect(find.text('مسیر سرمایه'), findsOneWidget);
    expect(find.text('سود تحقق‌یافته سال'), findsOneWidget);
    expect(find.text('بهای تمام‌شده'), findsOneWidget);
    expect(find.text('پایان سال‌های گذشته'), findsOneWidget);
    expect(find.text('افزودن سال گذشته'), findsOneWidget);
    expect(find.textContaining('Bitcoin'), findsNothing);
  });

  testWidgets('capital desk shows the open-cheque line in the balance sheet',
      (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: AppConfig.calendarGregorian)
      ..assets = [
        Asset(
          id: 1,
          name: 'Cash',
          quantity: 1,
          avgBuyPrice: 1000,
          currentPrice: 1000,
        ),
      ]
      ..checks = [
        BankCheck(
          direction: checkDirectionReceivable,
          amount: 400,
          issueDate: '2026-10-01',
          dueDate: '2026-12-01',
        ),
        BankCheck(
          direction: checkDirectionPayable,
          amount: 150,
          issueDate: '2026-10-01',
          dueDate: '2026-12-01',
        ),
        BankCheck(
          direction: checkDirectionReceivable,
          amount: 9999,
          issueDate: '2026-09-01',
          dueDate: '2026-09-20',
          status: checkStatusBounced,
        ),
      ]
      ..metrics = const DashboardMetrics(
        totalValue: 1000,
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

    tester.view.physicalSize = const Size(800, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          locale: Locale('fa', 'IR'),
          home: CapitalChartPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('چک‌های باز'), findsOneWidget);
    expect(find.textContaining('شامل چک‌های باز'), findsOneWidget);
    expect(find.textContaining('1,250 تومان'), findsWidgets);
    expect(find.textContaining('+250 تومان'), findsOneWidget);
  });

  testWidgets('capital desk shows YoY growth chart when prior year NAV exists',
      (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..liveUsdt = 100000
      ..settings = AppSettings(
        calendar: AppConfig.calendarGregorian,
        usdtTmnRate: 100000,
        yearNavHistory: const [
          YearNavEntry(
            yearKey: '2025',
            navToman: 1e9,
            navUsd: 10000,
            usdtRate: 100000,
          ),
        ],
      )
      ..assets = [
        Asset(
          id: 1,
          name: 'Bitcoin',
          symbol: 'BTC',
          quantity: 1,
          avgBuyPrice: 1e9,
          currentPrice: 1.2e9,
        ),
      ]
      ..openTrades = [
        Trade(
          assetId: 1,
          status: AppConfig.tradeOpen,
          quantity: 1,
          buyPrice: 1e9,
          currentPrice: 1.2e9,
        ),
      ]
      ..metrics = const DashboardMetrics(
        totalValue: 1.2e9,
        totalPnl: 2e8,
        totalPnlPct: 20,
        realizedPnl: 0,
        unrealizedPnl: 2e8,
        openCount: 1,
        closedCount: 0,
        yearRealizedPnl: 0,
        yearKey: '2026',
        goldFund: GoldFundMetrics(goldInG: 0, goldOutG: 0, goldHoldingG: 0),
      );

    tester.view.physicalSize = const Size(800, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          locale: Locale('fa', 'IR'),
          home: CapitalChartPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('رشد نسبت به پایان 2025'), findsOneWidget);
    expect(find.text('رشد سالانه'), findsOneWidget);
    expect(find.text('2025'), findsWidgets);
    expect(find.textContaining(r'$10,000 · دستی'), findsOneWidget);
  });

  group('value page («ارزش پورتفو») holds every moved detail', () {
    String iso(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    AppState rich({bool offline = false, double? liveUsdt = 100000}) => AppState()
      ..loading = false
      ..authenticated = true
      ..offline = offline
      ..liveUsdt = liveUsdt
      ..usdtLiveAt = liveUsdt == null ? null : DateTime.now()
      ..lastSyncedAt = DateTime.now().subtract(const Duration(minutes: 3))
      ..settings = AppSettings(calendar: AppConfig.calendarGregorian, usdtTmnRate: 90000)
      ..assets = [
        Asset(id: 1, name: 'طلای آب‌شده', symbol: 'GOLD', quantity: 10, avgBuyPrice: 9e6, currentPrice: 1e7),
        Asset(id: 2, name: 'Bitcoin', symbol: 'BTC', quantity: 1, avgBuyPrice: 1e9, currentPrice: 1.2e9),
        Asset(id: 3, name: 'صندوق بی‌قیمت', symbol: 'FND', quantity: 100, avgBuyPrice: 1000, currentPrice: 0),
      ]
      ..openTrades = [
        Trade(assetId: 1, status: AppConfig.tradeOpen, quantity: 10, buyPrice: 9e6, buyPriceUsd: 100, assetName: 'طلای آب‌شده', assetSymbol: 'GOLD', currentPrice: 1e7),
        Trade(assetId: 2, status: AppConfig.tradeOpen, quantity: 1, buyPrice: 1e9, buyPriceUsd: 10000, assetName: 'Bitcoin', assetSymbol: 'BTC', currentPrice: 1.2e9),
        Trade(assetId: 3, status: AppConfig.tradeOpen, quantity: 100, buyPrice: 1000, assetName: 'صندوق بی‌قیمت', assetSymbol: 'FND'),
      ]
      ..metrics = DashboardMetrics(
        totalValue: 1.3e9,
        totalPnl: 2.1e8,
        totalPnlPct: 20,
        realizedPnl: 0,
        unrealizedPnl: 2.1e8,
        openCount: 3,
        closedCount: 0,
        yearRealizedPnl: 0,
        yearKey: '2026',
        goldFund: const GoldFundMetrics(goldInG: 0, goldOutG: 0, goldHoldingG: 0),
        growthSeries: [
          SeriesPoint(date: iso(DateTime.now().subtract(const Duration(days: 40))), value: 1.1e9),
        ],
      );

    Future<void> pump(WidgetTester t, AppState state, {double width = 800, double scale = 1}) async {
      t.view.physicalSize = Size(width, 6000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(textDirection: TextDirection.rtl, child: child!),
          ),
          home: const CapitalChartPage(),
        ),
      ));
      await t.pumpAndSettle();
    }

    setUp(() => ProjectsStore.instance.debugReset());
    tearDown(() => ProjectsStore.instance.debugReset());

    testWidgets('title, status line, hero stats, unpriced banner, composition', (t) async {
      await pump(t, rich());
      expect(find.byKey(const ValueKey('vp-title')), findsOneWidget);
      expect(find.text('میز سرمایه'), findsOneWidget);
      // status: connection + last sync, live rate, price freshness
      expect(find.byKey(const ValueKey('vp-conn')), findsOneWidget);
      expect(find.textContaining('همگام'), findsOneWidget);
      expect(find.textContaining('نرخ زندهٔ تتر'), findsOneWidget);
      expect(find.byKey(const ValueKey('pv-fresh')), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      // hero
      expect(find.byKey(const ValueKey('vp-nav')), findsOneWidget);
      expect(find.byKey(const ValueKey('vp-nav-usd')), findsOneWidget);
      expect(find.text('سود دلاری'), findsOneWidget);
      expect(find.text('سود باز'), findsOneWidget);
      expect(find.text('روند ۳۰ روز'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('vp-trend')), matching: find.text('—')),
        findsNothing,
      );
      // The chart's raw whole-period change is labelled apart from the 30-day trend.
      expect(find.textContaining('تغییر کل دورهٔ نمودار'), findsOneWidget);
      expect(find.text('روند ۳۰ روز'), findsOneWidget); // one trend label in the hero
      final banner = find.byKey(const ValueKey('vp-unpriced'));
      expect(banner, findsOneWidget);
      expect(find.descendant(of: banner, matching: find.textContaining('صندوق بی‌قیمت')), findsOneWidget);
      // composition
      expect(find.text('ترکیب ارزش'), findsOneWidget);
      expect(find.byType(PortfolioValueBreakdown), findsOneWidget);
      expect(find.byKey(const ValueKey('pv-holdings-total')), findsOneWidget);
      expect(find.byKey(const ValueKey('pv-group-crypto')), findsOneWidget);
      // cost basis only once (balance sheet)
      expect(find.text('بهای تمام‌شده'), findsOneWidget);
      // no contracting rows without project data
      expect(find.byKey(const ValueKey('vp-projects')), findsNothing);
    });

    testWidgets('offline: stored rate and offline connection status', (t) async {
      await pump(t, rich(offline: true, liveUsdt: null));
      expect(find.textContaining('نرخ ذخیره‌شدهٔ تتر'), findsOneWidget);
      expect(find.textContaining('نرخ زندهٔ تتر'), findsNothing);
      final state = Provider.of<AppState>(t.element(find.byType(CapitalChartPage)), listen: false);
      expect(state.connectionStatus.isOnline, isFalse);
      expect(find.text(state.connectionStatus.label, findRichText: true), findsNothing); // joined with sync time
      expect(find.textContaining(state.connectionStatus.label), findsOneWidget);
    });

    testWidgets('contracting listed outside the total and follows ProjectsStore', (t) async {
      await pump(t, rich());
      expect(find.text('پیمانکاری (خارج از جمع ارزش)'), findsNothing);
      ProjectsStore.instance.debugSet(ProjectsSnapshot({
        'items': [
          {'id': 1, 'title': 'a', 'status': 'finished', 'contract_amount': 80, 'cost': 30, 'profit': 50, 'archived': false},
          {'id': 2, 'title': 'b', 'status': 'active', 'contract_amount': 999, 'cost': 1, 'profit': 998, 'archived': false},
        ],
      }));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('vp-projects')), findsOneWidget);
      expect(find.text('پیمانکاری (خارج از جمع ارزش)'), findsOneWidget);
      expect(find.text('+50 تومان'), findsOneWidget);
      expect(find.text('+998 تومان'), findsOneWidget);
    });

    testWidgets('fits 320 px with large text', (t) async {
      ProjectsStore.instance.debugSet(ProjectsSnapshot({
        'items': [
          {'id': 1, 'title': 'a', 'status': 'finished', 'contract_amount': 80, 'cost': 30, 'profit': 50, 'archived': false},
        ],
      }));
      await pump(t, rich(), width: 320, scale: 1.4);
      expect(t.takeException(), isNull);
    });
  });
}

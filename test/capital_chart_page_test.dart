import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/year_nav_entry.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/capital_chart_page.dart';
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
}

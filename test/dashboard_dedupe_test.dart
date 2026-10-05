import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/dashboard_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('dashboard avoids duplicating assets allocation desk',
      (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: AppConfig.calendarGregorian)
      ..commodityIndex = [
        const CommodityQuote(
          id: 'usdt',
          name: 'تتر',
          symbol: 'USDT',
          unit: 'TMN',
          price: 100000,
          change24h: 0.2,
        ),
        const CommodityQuote(
          id: 'gold',
          name: 'طلا',
          symbol: 'GOLD',
          unit: 'TMN',
          price: 32000000,
          change24h: -0.4,
        ),
        const CommodityQuote(
          id: 'btc',
          name: 'بیت‌کوین',
          symbol: 'BTC',
          unit: 'TMN',
          price: 8e9,
          change24h: 1.2,
        ),
      ]
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

    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          locale: Locale('fa', 'IR'),
          home: Scaffold(body: DashboardPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ارزش پورتفو'), findsOneWidget);
    expect(find.text('سود و زیان'), findsOneWidget);
    expect(find.text('جزئیات تخصیص در تب معاملات'), findsOneWidget);
    expect(find.text('ترکیب دارایی'), findsNothing);
    expect(find.text('بیت‌کوین'), findsNothing); // crypto tape on Index only
    expect(find.text('تتر'), findsOneWidget);
    expect(find.text('طلا'), findsOneWidget);
    expect(find.text('قابل برداشت'), findsOneWidget);
  });
}

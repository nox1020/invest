import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/dashboard_pnl.dart';

void main() {
  test('total USD PnL is not live FX of Toman PnL', () {
    final assets = [
      Asset(
        id: 1,
        name: 'X',
        quantity: 1,
        avgBuyPrice: 1e9,
        currentPrice: 1.2e9,
      ),
    ];
    final open = [
      Trade(
        assetId: 1,
        status: AppConfig.tradeOpen,
        quantity: 1,
        buyPrice: 1e9,
        buyPriceUsd: 20000,
        currentPrice: 1.2e9,
      ),
    ];
    const usdt = 60000.0;
    final pnl = DashboardCurrencyPnl.compute(
      assets: assets,
      openTrades: open,
      closedTrades: const [],
      usdtTmn: usdt,
      yearKey: '1404',
      calendar: AppConfig.calendarJalali,
    );
    // Toman unrealized +2e8 → FX would be ~3333; registered USD mark is flat.
    expect(pnl.unrealizedUsd, closeTo(0, 1e-6));
    expect(pnl.realizedUsd, 0);
    expect(pnl.totalUsd, closeTo(0, 1e-6));
    expect(pnl.totalUsd == 2e8 / usdt, isFalse);
  });

  test('realized USD uses registered buy vs sell FX (live fallback)', () {
    final closed = [
      Trade(
        assetId: 1,
        status: AppConfig.tradeClosed,
        quantity: 1,
        buyPrice: 1e9,
        buyPriceUsd: 20000,
        sellPrice: 1.2e9,
        sellFee: 0,
        sellDate: '2026-01-15',
        realizedPnl: 2e8,
      ),
    ];
    const usdt = 60000.0;
    final pnl = DashboardCurrencyPnl.compute(
      assets: const [],
      openTrades: const [],
      closedTrades: closed,
      usdtTmn: usdt,
      yearKey: '2026',
      calendar: AppConfig.calendarGregorian,
    );
    // sell 1.2e9/60k = 20k USD − buy 20k = 0
    expect(pnl.realizedUsd, closeTo(0, 1e-6));
    expect(pnl.yearRealizedUsd, closeTo(0, 1e-6));
  });

  test('totalPnlPct uses lifetime invested when closed lots present', () {
    final assets = [
      Asset(id: 1, name: 'A', quantity: 1, avgBuyPrice: 100, currentPrice: 120),
    ];
    final open = [
      Trade(
        assetId: 1,
        status: AppConfig.tradeOpen,
        quantity: 1,
        buyPrice: 100,
      ),
    ];
    final closed = [
      Trade(
        assetId: 1,
        status: AppConfig.tradeClosed,
        quantity: 1,
        buyPrice: 100,
        sellPrice: 130,
        realizedPnl: 30,
      ),
    ];
    final pct = DashboardCurrencyPnl.totalPnlPct(
      totalPnl: 50, // 20 unrealized + 30 realized
      assets: assets,
      openTrades: open,
      closedTrades: closed,
    );
    // invested = 100 open + 100 closed = 200 → 50/200 = 25%
    expect(pct, closeTo(25, 1e-9));
  });
}

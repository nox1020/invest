import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/holding_metrics.dart';

void main() {
  test('holding metrics prefer open lots with fees', () {
    final asset = Asset(
      id: 1,
      name: 'BTC',
      symbol: 'BTC',
      quantity: 2,
      avgBuyPrice: 100, // stale / fee-free row
      currentPrice: 120,
    );
    final open = [
      Trade(
        assetId: 1,
        status: AppConfig.tradeOpen,
        quantity: 2,
        buyPrice: 100,
        buyFee: 10,
        currentPrice: 120,
      ),
    ];
    final m = HoldingMetrics.forAsset(asset, open);
    expect(m.quantity, 2);
    expect(m.costBasis, 210); // 2*100 + 10
    expect(m.marketValue, 240);
    expect(m.unrealizedPnl, 30);
    expect(m.avgBuyPrice, closeTo(105, 1e-9));
    expect(m.unrealizedPnlPct, closeTo(30 / 210 * 100, 1e-6));
  });

  test('activeHoldings skips empty positions', () {
    final assets = [
      Asset(id: 1, name: 'A', quantity: 0, avgBuyPrice: 1, currentPrice: 2),
      Asset(id: 2, name: 'B', quantity: 3, avgBuyPrice: 10, currentPrice: 12),
    ];
    final holdings = HoldingMetrics.activeHoldings(
      assets: assets,
      openTrades: const [],
    );
    expect(holdings, hasLength(1));
    expect(holdings.single.asset.id, 2);
    expect(holdings.single.metrics.marketValue, 36);
  });

  test('portfolio totals equal sum of holdings', () {
    final assets = [
      Asset(id: 1, name: 'A', quantity: 10, avgBuyPrice: 100, currentPrice: 80),
      Asset(id: 2, name: 'B', quantity: 5, avgBuyPrice: 50, currentPrice: 60),
    ];
    final holdings = HoldingMetrics.activeHoldings(
      assets: assets,
      openTrades: const [],
    );
    final value =
        holdings.fold<double>(0, (s, h) => s + h.metrics.marketValue);
    final pnl =
        holdings.fold<double>(0, (s, h) => s + h.metrics.unrealizedPnl);
    final cost =
        holdings.fold<double>(0, (s, h) => s + h.metrics.costBasis);
    expect(value, 800 + 300);
    expect(cost, 1000 + 250);
    expect(pnl, (800 - 1000) + (300 - 250));
  });

  test('avgBuyPriceUsd only when every open lot has USD', () {
    final asset = Asset(
      id: 1,
      name: 'Gold',
      quantity: 2,
      avgBuyPrice: 100,
      currentPrice: 110,
      notes: '[kind:gold][meta:{"buyPriceUsd":9}]',
    );
    final open = [
      Trade(
        assetId: 1,
        status: AppConfig.tradeOpen,
        quantity: 1,
        buyPrice: 100,
        buyPriceUsd: 2,
      ),
      Trade(
        assetId: 1,
        status: AppConfig.tradeOpen,
        quantity: 1,
        buyPrice: 100,
      ),
    ];
    final partial = HoldingMetrics.forAsset(asset, open);
    expect(partial.avgBuyPriceUsd, isNull);
    expect(partial.costBasisUsd, isNull);
    expect(partial.unrealizedPnlUsd(60000), isNull);

    final full = HoldingMetrics.forAsset(asset, [
      open[0],
      Trade(
        assetId: 1,
        status: AppConfig.tradeOpen,
        quantity: 1,
        buyPrice: 100,
        buyPriceUsd: 4,
      ),
    ]);
    expect(full.avgBuyPriceUsd, closeTo(3, 1e-9));
    expect(full.costBasisUsd, closeTo(6, 1e-9));
  });

  test('USD PnL uses registered cost vs live mark, not FX of Toman PnL', () {
    // Buy 1 @ 1e9 TMN / $20k registered. Now 1.2e9 TMN with USDT 60k → $20k mark.
    // Toman PnL = +2e8, but USD PnL must be ~0 (not 2e8/60k).
    final asset = Asset(
      id: 1,
      name: 'X',
      quantity: 1,
      avgBuyPrice: 1e9,
      currentPrice: 1.2e9,
    );
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
    final m = HoldingMetrics.forAsset(asset, open);
    const usdt = 60000.0;
    expect(m.unrealizedPnl, closeTo(2e8, 1));
    expect(m.costBasisUsd, 20000);
    expect(m.marketValueUsd(usdt), closeTo(20000, 1e-6));
    expect(m.unrealizedPnlUsd(usdt), closeTo(0, 1e-6));
    expect(m.unrealizedPnlUsd(usdt)! == 2e8 / usdt, isFalse);
  });
}

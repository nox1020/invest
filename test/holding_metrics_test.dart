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
}

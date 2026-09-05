import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';

const _eps = 1e-9;

/// Mark-to-market holding figures for the assets portfolio tab.
///
/// Prefers open lots (fee-aware cost) when present so totals match the
/// «باز» tab; otherwise falls back to the asset row.
class HoldingMetrics {
  const HoldingMetrics({
    required this.quantity,
    required this.currentPrice,
    required this.avgBuyPrice,
    required this.costBasis,
    required this.marketValue,
    required this.unrealizedPnl,
  });

  final double quantity;
  final double currentPrice;
  final double avgBuyPrice;
  final double costBasis;
  final double marketValue;
  final double unrealizedPnl;

  double get unrealizedPnlPct =>
      costBasis.abs() < _eps ? 0 : unrealizedPnl / costBasis * 100;

  bool get hasPosition => quantity > _eps;

  static HoldingMetrics fromAsset(Asset asset) {
    final qty = asset.quantity;
    final price = asset.currentPrice;
    final avg = asset.avgBuyPrice;
    final cost = qty * avg;
    final value = qty * price;
    return HoldingMetrics(
      quantity: qty,
      currentPrice: price,
      avgBuyPrice: avg,
      costBasis: cost,
      marketValue: value,
      unrealizedPnl: value - cost,
    );
  }

  static HoldingMetrics forAsset(Asset asset, List<Trade> openTrades) {
    final lots = <Trade>[];
    for (final t in openTrades) {
      if (t.assetId == asset.id && t.quantity > _eps) lots.add(t);
    }
    if (lots.isEmpty) return fromAsset(asset);

    final qty = lots.fold<double>(0, (s, t) => s + t.quantity);
    final cost = lots.fold<double>(0, (s, t) => s + t.buyCost);
    final price = asset.currentPrice > 0
        ? asset.currentPrice
        : lots.first.currentPrice;
    final value = qty * price;
    final avg = qty > _eps ? cost / qty : 0.0;
    return HoldingMetrics(
      quantity: qty,
      currentPrice: price,
      avgBuyPrice: avg,
      costBasis: cost,
      marketValue: value,
      unrealizedPnl: value - cost,
    );
  }

  static List<({Asset asset, HoldingMetrics metrics})> activeHoldings({
    required List<Asset> assets,
    required List<Trade> openTrades,
  }) {
    final out = <({Asset asset, HoldingMetrics metrics})>[];
    for (final asset in assets) {
      final m = forAsset(asset, openTrades);
      if (!m.hasPosition) continue;
      out.add((asset: asset, metrics: m));
    }
    out.sort((a, b) => b.metrics.marketValue.compareTo(a.metrics.marketValue));
    return out;
  }
}

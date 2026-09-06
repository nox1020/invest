import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_meta.dart';
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
    this.avgBuyPriceUsd,
    required this.costBasis,
    required this.marketValue,
    required this.unrealizedPnl,
  });

  final double quantity;
  final double currentPrice;
  final double avgBuyPrice;

  /// Weighted unit buy price in USD when every open lot has a stored USD price
  /// (or asset meta for inventory-only holdings).
  final double? avgBuyPriceUsd;
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
    final metaUsd = parseAssetNotes(asset.notes).meta.buyPriceUsd;
    return HoldingMetrics(
      quantity: qty,
      currentPrice: price,
      avgBuyPrice: avg,
      avgBuyPriceUsd:
          (metaUsd != null && metaUsd > 0) ? metaUsd : null,
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

    double? avgUsd;
    var usdQty = 0.0;
    var usdCost = 0.0;
    for (final t in lots) {
      final u = t.buyPriceUsd;
      if (u == null || u <= 0) continue;
      usdQty += t.quantity;
      usdCost += t.quantity * u;
    }
    if (usdQty > _eps && (qty - usdQty).abs() <= _eps) {
      avgUsd = usdCost / usdQty;
    }

    return HoldingMetrics(
      quantity: qty,
      currentPrice: price,
      avgBuyPrice: avg,
      avgBuyPriceUsd: avgUsd,
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

import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_meta.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/utils/buy_usd.dart';
import 'package:invest/domain/utils/money.dart';

const _eps = 1e-9;

/// Mark-to-market holding figures for the assets portfolio tab.
///
/// Prefers open lots (fee-aware cost) when present so totals match the
/// «باز» tab; otherwise falls back to the asset row.
///
/// USD cost uses **registered** buy prices only. USD PnL is
/// `marketValueUsd(live) − costBasisUsd`, never a live FX of Toman PnL.
class HoldingMetrics {
  const HoldingMetrics({
    required this.quantity,
    required this.currentPrice,
    required this.avgBuyPrice,
    this.avgBuyPriceUsd,
    this.avgBuyUsdTmn,
    required this.costBasis,
    this.costBasisUsd,
    required this.marketValue,
    required this.unrealizedPnl,
  });

  final double quantity;
  final double currentPrice;
  final double avgBuyPrice;

  /// Weighted unit buy price in USD when every open lot has a stored USD price
  /// (or asset meta for inventory-only holdings).
  final double? avgBuyPriceUsd;

  /// Quantity-weighted Toman-per-USD rate at buy (stored or implied).
  final double? avgBuyUsdTmn;
  final double costBasis;

  /// Total registered USD cost (`Σ qty·buyPriceUsd`) when coverage is complete.
  final double? costBasisUsd;
  final double marketValue;
  final double unrealizedPnl;

  double get unrealizedPnlPct =>
      costBasis.abs() < _eps ? 0 : unrealizedPnl / costBasis * 100;

  bool get hasPosition => quantity > _eps;

  /// Live mark of the position in USD.
  double? marketValueUsd(double? usdtTmn) =>
      tomanToUsd(marketValue, usdtTmn);

  /// Live unit mark in USD.
  double? currentPriceUsd(double? usdtTmn) =>
      tomanToUsd(currentPrice, usdtTmn);

  /// Registered-cost USD PnL vs live mark. Null when USD cost is incomplete
  /// or the live USDT rate is missing.
  double? unrealizedPnlUsd(double? usdtTmn) {
    final cost = costBasisUsd;
    final value = marketValueUsd(usdtTmn);
    if (cost == null || value == null) return null;
    return value - cost;
  }

  double unrealizedPnlUsdPct(double? usdtTmn) {
    final cost = costBasisUsd;
    final pnl = unrealizedPnlUsd(usdtTmn);
    if (cost == null || pnl == null || cost.abs() < _eps) return 0;
    return pnl / cost * 100;
  }

  static HoldingMetrics fromAsset(Asset asset) {
    final qty = asset.quantity;
    final price = asset.currentPrice;
    final avg = asset.avgBuyPrice;
    final cost = qty * avg;
    final value = qty * price;
    final meta = parseAssetNotes(asset.notes).meta;
    final metaUsd = meta.buyPriceUsd;
    final registeredUsd =
        (metaUsd != null && metaUsd > 0 && qty > _eps) ? metaUsd : null;
    return HoldingMetrics(
      quantity: qty,
      currentPrice: price,
      avgBuyPrice: avg,
      avgBuyPriceUsd: registeredUsd,
      avgBuyUsdTmn: resolveBuyUsdTmn(
        storedFx: meta.buyUsdTmn,
        buyToman: avg,
        buyUsd: registeredUsd,
      ),
      costBasis: cost,
      costBasisUsd: registeredUsd == null ? null : qty * registeredUsd,
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
    double? costUsd;
    var usdQty = 0.0;
    var usdCost = 0.0;
    for (final t in lots) {
      final u = t.buyPriceUsd;
      if (u == null || u <= 0) continue;
      usdQty += t.quantity;
      usdCost += t.quantity * u;
    }
    if (usdQty > _eps && (qty - usdQty).abs() <= _eps) {
      // Only when every open lot has a registered USD unit price.
      avgUsd = usdCost / usdQty;
      costUsd = usdCost;
    }
    // Do not fall back to meta when open lots exist but USD coverage is partial.

    return HoldingMetrics(
      quantity: qty,
      currentPrice: price,
      avgBuyPrice: avg,
      avgBuyPriceUsd: avgUsd,
      avgBuyUsdTmn: _avgBuyUsdTmn(lots, qty),
      costBasis: cost,
      costBasisUsd: costUsd,
      marketValue: value,
      unrealizedPnl: value - cost,
    );
  }

  static double? _avgBuyUsdTmn(List<Trade> lots, double qty) {
    if (qty <= _eps) return null;
    var fxQty = 0.0;
    var fxSum = 0.0;
    for (final t in lots) {
      final fx = t.resolvedBuyUsdTmn;
      if (fx == null || fx <= 0) continue;
      fxQty += t.quantity;
      fxSum += t.quantity * fx;
    }
    if (fxQty > _eps && (qty - fxQty).abs() <= _eps) {
      return fxSum / fxQty;
    }
    return null;
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

  /// Portfolio USD unrealized PnL when every holding has registered USD cost.
  static double? portfolioUnrealizedPnlUsd(
    List<({Asset asset, HoldingMetrics metrics})> holdings,
    double? usdtTmn,
  ) {
    if (holdings.isEmpty) return 0;
    var sum = 0.0;
    for (final h in holdings) {
      final p = h.metrics.unrealizedPnlUsd(usdtTmn);
      if (p == null) return null;
      sum += p;
    }
    return sum;
  }

  static double? portfolioMarketValueUsd(
    List<({Asset asset, HoldingMetrics metrics})> holdings,
    double? usdtTmn,
  ) {
    if (usdtTmn == null || usdtTmn <= 0) return null;
    var sum = 0.0;
    for (final h in holdings) {
      final v = h.metrics.marketValueUsd(usdtTmn);
      if (v == null) return null;
      sum += v;
    }
    return sum;
  }
}

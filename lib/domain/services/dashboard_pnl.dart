import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/utils/dates.dart';

/// USD PnL for the dashboard that respects registered buy USD.
///
/// Unrealized: live mark USD − registered open cost USD.
/// Realized: sell proceeds / live USDT − registered buy USD (fee in Toman
/// only). Returns null when USD coverage is incomplete so the UI does not
/// invent a live FX of Toman PnL.
class DashboardCurrencyPnl {
  const DashboardCurrencyPnl({
    this.unrealizedUsd,
    this.realizedUsd,
    this.yearRealizedUsd,
  });

  final double? unrealizedUsd;
  final double? realizedUsd;
  final double? yearRealizedUsd;

  /// Sum when both legs are defined (empty closed list ⇒ realized = 0).
  double? get totalUsd {
    if (unrealizedUsd == null || realizedUsd == null) return null;
    return unrealizedUsd! + realizedUsd!;
  }

  static DashboardCurrencyPnl compute({
    required List<Asset> assets,
    required List<Trade> openTrades,
    required List<Trade> closedTrades,
    required double? usdtTmn,
    required String yearKey,
    required String calendar,
  }) {
    final holdings = HoldingMetrics.activeHoldings(
      assets: assets,
      openTrades: openTrades,
    );
    final unrealized =
        HoldingMetrics.portfolioUnrealizedPnlUsd(holdings, usdtTmn);

    final realized = _closedPnlUsd(closedTrades, usdtTmn);
    final yearClosed = closedTrades.where((t) {
      final sell = t.sellDate;
      if (sell == null || sell.isEmpty || t.realizedPnl == null) return false;
      return yearPeriodKey(sell, calendar) == yearKey;
    });
    final yearRealized = _closedPnlUsd(yearClosed, usdtTmn);

    return DashboardCurrencyPnl(
      unrealizedUsd: unrealized,
      realizedUsd: realized,
      yearRealizedUsd: yearRealized,
    );
  }

  /// Percent of [totalPnl] vs current open cost basis (inventory).
  static double totalPnlPct({
    required double totalPnl,
    required List<Asset> assets,
    required List<Trade> openTrades,
  }) {
    final holdings = HoldingMetrics.activeHoldings(
      assets: assets,
      openTrades: openTrades,
    );
    final cost = holdings.fold<double>(0, (s, h) => s + h.metrics.costBasis);
    if (cost.abs() < 1e-12) return 0;
    return totalPnl / cost * 100;
  }
}

double? _closedPnlUsd(Iterable<Trade> trades, double? usdtTmn) {
  if (usdtTmn == null || usdtTmn <= 0) return null;
  var sum = 0.0;
  var saw = false;
  for (final t in trades) {
    saw = true;
    final buyUsd = t.buyPriceUsd;
    if (buyUsd == null || buyUsd <= 0) return null;
    final sell = t.sellPrice;
    if (sell == null || sell <= 0) return null;
    final sellNet = t.quantity * sell - t.sellFee;
    sum += sellNet / usdtTmn - t.quantity * buyUsd;
  }
  return saw ? sum : 0.0;
}

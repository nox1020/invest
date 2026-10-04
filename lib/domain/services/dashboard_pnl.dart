import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/utils/dates.dart';

/// USD PnL for the dashboard that respects registered buy USD.
///
/// Unrealized: live mark USD − registered open cost USD (incl. buy fee / FX).
/// Realized: sell proceeds / sell-time FX − registered buy USD cost. Sell FX
/// prefers `[sell_fx]` locked at close; live USDT is only a legacy fallback.
/// Returns null when USD coverage is incomplete so the UI does not invent a
/// live FX of Toman PnL.
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

  /// Percent of [totalPnl] vs lifetime invested (open + closed buy costs).
  ///
  /// Matches Vinor/Python `lifetime_invested` so a fully closed book still
  /// reports ROI against the capital that produced the realized PnL.
  static double totalPnlPct({
    required double totalPnl,
    required List<Asset> assets,
    required List<Trade> openTrades,
    List<Trade> closedTrades = const [],
  }) {
    var invested = 0.0;
    for (final t in openTrades) {
      invested += t.buyCost;
    }
    for (final t in closedTrades) {
      invested += t.buyCost;
    }
    if (invested.abs() < 1e-12) {
      final holdings = HoldingMetrics.activeHoldings(
        assets: assets,
        openTrades: openTrades,
      );
      invested =
          holdings.fold<double>(0, (s, h) => s + h.metrics.costBasis);
    }
    if (invested.abs() < 1e-12) return 0;
    return totalPnl / invested * 100;
  }

  /// Percent of total USD PnL vs registered lifetime USD cost (fees via FX).
  static double? totalUsdPnlPct({
    required double? totalUsdPnl,
    required List<Asset> assets,
    required List<Trade> openTrades,
    required List<Trade> closedTrades,
  }) {
    if (totalUsdPnl == null) return null;
    final holdings = HoldingMetrics.activeHoldings(
      assets: assets,
      openTrades: openTrades,
    );
    var costUsd = 0.0;
    for (final h in holdings) {
      final c = h.metrics.costBasisUsd;
      if (c == null) return null;
      costUsd += c;
    }
    for (final t in closedTrades) {
      final c = t.buyCostUsd;
      if (c == null) return null;
      costUsd += c;
    }
    if (costUsd.abs() < 1e-12) return 0;
    return totalUsdPnl / costUsd * 100;
  }
}

double? _closedPnlUsd(Iterable<Trade> trades, double? usdtTmn) {
  var sum = 0.0;
  var saw = false;
  for (final t in trades) {
    saw = true;
    final buyCost = t.buyCostUsd;
    if (buyCost == null) return null;
    final sell = t.sellPrice;
    if (sell == null || sell <= 0) return null;
    final sellFx = t.sellUsdTmn ?? usdtTmn;
    if (sellFx == null || sellFx <= 0) return null;
    final sellNet = t.quantity * sell - t.sellFee;
    sum += sellNet / sellFx - buyCost;
  }
  return saw ? sum : 0.0;
}

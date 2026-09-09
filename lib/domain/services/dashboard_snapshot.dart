import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/dashboard_pnl.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/services/trade_service.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';

const _eps = 1e-9;

/// Live dashboard figures from overlaid holdings + closed lots.
///
/// [marketValue] / unrealized PnL come from open inventory (same source as
/// the assets tab) so crypto marks stay in sync. Realized totals sum closed
/// trades. USD legs stay null when registered buy USD is incomplete.
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.holdings,
    required this.marketValue,
    required this.costBasis,
    required this.unrealizedPnl,
    required this.realizedPnl,
    required this.yearRealizedPnl,
    required this.yearKey,
    required this.openLotCount,
    required this.closedCount,
    required this.goldHoldingG,
    this.usdtTmn,
    this.unrealizedUsd,
    this.realizedUsd,
    this.yearRealizedUsd,
  });

  final List<({Asset asset, HoldingMetrics metrics})> holdings;
  final double marketValue;
  final double costBasis;
  final double unrealizedPnl;
  final double realizedPnl;
  final double yearRealizedPnl;
  final String yearKey;
  final int openLotCount;
  final int closedCount;
  final double goldHoldingG;
  final double? usdtTmn;
  final double? unrealizedUsd;
  final double? realizedUsd;
  final double? yearRealizedUsd;

  int get holdingCount => holdings.length;

  bool get isEmpty =>
      holdings.isEmpty && closedCount == 0 && marketValue.abs() < _eps;

  double get totalPnl => unrealizedPnl + realizedPnl;

  double get unrealizedPct =>
      costBasis.abs() < _eps ? 0 : unrealizedPnl / costBasis * 100;

  double? get marketValueUsd => tomanToUsd(marketValue, usdtTmn);

  double? get totalUsd {
    if (unrealizedUsd == null || realizedUsd == null) return null;
    return unrealizedUsd! + realizedUsd!;
  }

  bool get usdIncomplete =>
      (holdings.isNotEmpty && unrealizedUsd == null) ||
      (closedCount > 0 && realizedUsd == null);

  static DashboardSnapshot compute({
    required List<Asset> assets,
    required List<Trade> openTrades,
    required List<Trade> closedTrades,
    required double? usdtTmn,
    required String calendar,
    DashboardMetrics? metrics,
  }) {
    final holdings = HoldingMetrics.activeHoldings(
      assets: assets,
      openTrades: openTrades,
    );
    final marketValue =
        holdings.fold<double>(0, (s, h) => s + h.metrics.marketValue);
    final costBasis =
        holdings.fold<double>(0, (s, h) => s + h.metrics.costBasis);
    final unrealized =
        holdings.fold<double>(0, (s, h) => s + h.metrics.unrealizedPnl);

    final realized = closedTrades.fold<double>(
      0,
      (s, t) => s + (t.realizedPnl ?? 0),
    );

    final yearKey = (metrics != null && metrics.yearKey.isNotEmpty)
        ? metrics.yearKey
        : yearPeriodKey(todayIso(), calendar);
    final yearRealized = closedTrades.fold<double>(0, (s, t) {
      final sell = t.sellDate;
      if (sell == null || sell.isEmpty || t.realizedPnl == null) return s;
      if (yearPeriodKey(sell, calendar) != yearKey) return s;
      return s + t.realizedPnl!;
    });

    final currency = DashboardCurrencyPnl.compute(
      assets: assets,
      openTrades: openTrades,
      closedTrades: closedTrades,
      usdtTmn: usdtTmn,
      yearKey: yearKey,
      calendar: calendar,
    );

    var goldG = 0.0;
    var openLots = 0;
    for (final t in openTrades) {
      if (t.quantity <= _eps) continue;
      openLots++;
      if (TradeService.isGoldAsset(t.assetName, t.assetSymbol)) {
        goldG += t.quantity;
      }
    }

    return DashboardSnapshot(
      holdings: holdings,
      marketValue: marketValue,
      costBasis: costBasis,
      unrealizedPnl: unrealized,
      realizedPnl: realized,
      yearRealizedPnl: yearRealized,
      yearKey: yearKey,
      openLotCount: openLots,
      closedCount: closedTrades.length,
      goldHoldingG: goldG,
      usdtTmn: usdtTmn,
      unrealizedUsd: currency.unrealizedUsd,
      realizedUsd: currency.realizedUsd,
      yearRealizedUsd: currency.yearRealizedUsd,
    );
  }
}

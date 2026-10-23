import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/check_ledger.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/services/trade_service.dart';

/// One slice of the portfolio by asset kind.
class ValuationGroup {
  const ValuationGroup({required this.kind, required this.value, required this.count});
  final AssetKind kind;
  final double value;
  final int count;
}

/// The single valuation used by the dashboard card, the chart and the
/// daily snapshot.
///
/// * [holdingsValue] is the market value of open holdings (open lots × live
///   price). This is the basis of the daily series, here and on the server.
/// * [nav] adds open cheques. It is what the card headline shows, but it is
///   never mixed into the trend, so a new or cashed cheque does not move it.
class PortfolioValuation {
  const PortfolioValuation({
    required this.holdings,
    required this.holdingsValue,
    required this.cheques,
    required this.groups,
    required this.unpriced,
    required this.goldValue,
  });

  final List<({Asset asset, HoldingMetrics metrics})> holdings;
  final double holdingsValue;
  final ChequeNavEffect cheques;

  /// Largest first.
  final List<ValuationGroup> groups;

  /// Open holdings without a live price of their own (valued at a lot price,
  /// or at zero when there is none).
  final List<Asset> unpriced;

  /// Market value of gold holdings (inside [holdingsValue]).
  final double goldValue;

  double get nav => holdingsValue + cheques.net;

  static PortfolioValuation of({
    required List<Asset> assets,
    required List<Trade> openTrades,
    Iterable<BankCheck> checks = const [],
  }) {
    final holdings = HoldingMetrics.activeHoldings(assets: assets, openTrades: openTrades);
    var value = 0.0, gold = 0.0;
    final byKind = <AssetKind, double>{};
    final counts = <AssetKind, int>{};
    final unpriced = <Asset>[];
    for (final h in holdings) {
      final v = h.metrics.marketValue;
      value += v;
      final a = h.asset;
      final kind = TradeService.isGoldAsset(a.name, a.symbol, a.notes)
          ? AssetKind.gold
          : detectAssetKind(name: a.name, symbol: a.symbol, notes: a.notes);
      if (kind == AssetKind.gold) gold += v;
      byKind[kind] = (byKind[kind] ?? 0) + v;
      counts[kind] = (counts[kind] ?? 0) + 1;
      if (a.currentPrice <= 0) unpriced.add(a);
    }
    final groups = [
      for (final e in byKind.entries)
        ValuationGroup(kind: e.key, value: e.value, count: counts[e.key] ?? 0),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return PortfolioValuation(
      holdings: holdings,
      holdingsValue: value,
      cheques: ChequeNavEffect.of(checks),
      groups: groups,
      unpriced: unpriced,
      goldValue: gold,
    );
  }
}

/// Change of the holdings value over a fixed window, like for like.
class PortfolioTrend {
  const PortfolioTrend({
    required this.days,
    this.baseDate,
    this.baseValue,
    this.endValue,
    this.netFlows = 0,
    this.points = const [],
  });

  final int days;
  final String? baseDate;
  final double? baseValue;
  final double? endValue;

  /// Money put in (buys) minus money taken out (sells) inside the window.
  /// Removed from the change so a new purchase is not counted as growth.
  final double netFlows;

  /// Series inside the window, today last (for the sparkline).
  final List<SeriesPoint> points;

  bool get hasValue => baseValue != null && baseValue! > 0 && endValue != null;

  double? get change => hasValue ? endValue! - baseValue! - netFlows : null;

  double? get pct => hasValue ? change! / baseValue! * 100 : null;

  /// [series] is the daily holdings-value series (server or local
  /// snapshots); [todayValue] must be the holdings value (no cheques), so the
  /// last point is computed the same way as the stored ones.
  static PortfolioTrend window({
    required List<SeriesPoint> series,
    required double todayValue,
    required String today,
    int days = 30,
    Iterable<Trade> openTrades = const [],
    Iterable<Trade> closedTrades = const [],
  }) {
    final t = DateTime.tryParse(today.length >= 10 ? today.substring(0, 10) : today);
    if (t == null) return PortfolioTrend(days: days);
    final start = _iso(t.subtract(Duration(days: days)));
    final day = _iso(t);
    final past = [
      for (final p in series)
        if (p.date.length >= 10 && p.date.substring(0, 10).compareTo(day) < 0) p,
    ]..sort((a, b) => a.date.compareTo(b.date));

    SeriesPoint? base;
    for (final p in past) {
      if (p.date.substring(0, 10).compareTo(start) <= 0) {
        base = p;
      } else {
        break;
      }
    }
    base ??= past.where((p) => p.date.substring(0, 10).compareTo(start) > 0).firstOrNull;
    final inWindow = [
      if (base != null) base,
      for (final p in past)
        if (p.date.substring(0, 10).compareTo(start) > 0 && !identical(p, base)) p,
      SeriesPoint(date: day, value: todayValue),
    ];
    if (base == null || base.value <= 0) {
      return PortfolioTrend(days: days, endValue: todayValue, points: inWindow);
    }
    final from = base.date.substring(0, 10);
    var flows = 0.0;
    bool inside(String? d) {
      if (d == null || d.length < 10) return false;
      final k = d.substring(0, 10);
      return k.compareTo(from) > 0 && k.compareTo(day) <= 0;
    }

    for (final tr in [...openTrades, ...closedTrades]) {
      if (inside(tr.buyDate)) flows += tr.buyCost;
      if (tr.sellPrice != null && inside(tr.sellDate)) {
        flows -= tr.quantity * tr.sellPrice! - tr.sellFee;
      }
    }
    return PortfolioTrend(
      days: days,
      baseDate: from,
      baseValue: base.value,
      endValue: todayValue,
      netFlows: flows,
      points: inWindow,
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

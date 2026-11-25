import 'dart:math' as math;

import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_meta.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/gold_cash_entry.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/gold_calc.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/services/trade_service.dart';
import 'package:invest/domain/utils/gold_fund_tag.dart';
import 'package:invest/domain/utils/gold_purity.dart';

const _eps = 1e-9;

/// Live 18k quote with the two sides of the market.
///
/// WallGold sends a last buy and a last sell price; when they are missing or
/// implausible both sides are estimated as mid ± [defaultHalfSpreadPct].
class GoldQuote {
  const GoldQuote({
    required this.mid,
    required this.ask,
    required this.bid,
    this.estimated = true,
    this.change24hPct,
  });

  /// Half of the assumed bid/ask spread, percent of mid.
  static const defaultHalfSpreadPct = 0.5;

  static const none = GoldQuote(mid: 0, ask: 0, bid: 0);

  /// 18k Toman/gram (the app's single gold price).
  final double mid;

  /// Price you pay when buying (≥ mid).
  final double ask;

  /// Price you get when selling (≤ mid).
  final double bid;

  /// [ask]/[bid] are estimates, not market prints.
  final bool estimated;
  final double? change24hPct;

  bool get hasPrice => mid > 0;

  double get mazaneh => mazanehFromGram18(mid);

  /// Uses [bid]/[ask] when both are positive, ordered and within 5% of
  /// [mid]; otherwise estimates them.
  static GoldQuote resolve({
    required double? mid,
    double? bid,
    double? ask,
    double? change24hPct,
    double halfSpreadPct = defaultHalfSpreadPct,
  }) {
    final m = (mid != null && mid.isFinite && mid > 0) ? mid : 0.0;
    if (m <= 0) {
      return GoldQuote(mid: 0, ask: 0, bid: 0, change24hPct: change24hPct);
    }
    var lo = bid, hi = ask;
    if (lo != null && hi != null && lo > hi) {
      final t = lo;
      lo = hi;
      hi = t;
    }
    final ok = lo != null &&
        hi != null &&
        lo.isFinite &&
        hi.isFinite &&
        lo > 0 &&
        hi > 0 &&
        lo <= m * 1.0005 &&
        hi >= m * 0.9995 &&
        (hi - lo) / m <= 0.05;
    if (ok) {
      return GoldQuote(
        mid: m,
        ask: math.max(hi, m),
        bid: math.min(lo, m),
        estimated: false,
        change24hPct: change24hPct,
      );
    }
    final h = halfSpreadPct.isFinite && halfSpreadPct >= 0 ? halfSpreadPct / 100 : 0.0;
    return GoldQuote(
      mid: m,
      ask: roundToman(m * (1 + h)),
      bid: roundToman(m * (1 - h)),
      estimated: true,
      change24hPct: change24hPct,
    );
  }
}

/// One gold asset (طلا, not سکه) with its open lots.
class GoldHolding {
  const GoldHolding({
    required this.asset,
    required this.purity,
    required this.lots,
    required this.metrics,
  });

  final Asset asset;

  /// Fraction of 24k (0.75 for 18k).
  final double purity;
  final List<Trade> lots;
  final HoldingMetrics metrics;

  double get grams => metrics.quantity;
  double get grams18 => grams * purity / k18GoldPurity;
  double get value => metrics.marketValue;
  double get cost => metrics.costBasis;

  /// Karat label like `۱۸` (Latin digits; callers apply `fa`).
  String get karatLabel =>
      (purity * 24).toStringAsFixed((purity * 24 - (purity * 24).roundToDouble()).abs() < 0.01 ? 0 : 1);

  List<GoldLot> get calcLots => [
        for (final t in lots)
          if (t.id != null && t.quantity > _eps)
            GoldLot(
              id: t.id!,
              grams: t.quantity,
              buyPrice: t.buyPrice,
              buyFee: t.buyFee,
              buyDate: t.buyDate,
            ),
      ];
}

enum GoldCashRowKind { manual, buy, sell }

/// One line of «گردش نقد صندوق».
class GoldCashRow {
  const GoldCashRow({
    required this.kind,
    required this.date,
    required this.amount,
    required this.balance,
    this.entry,
    this.grams = 0,
    this.assetName = '',
    this.opId = '',
    this.tradeIds = const [],
    this.sortKey = '',
  });

  final GoldCashRowKind kind;
  final String date;

  /// Signed cash effect.
  final double amount;

  /// Fund cash after this row.
  final double balance;
  final GoldCashEntry? entry;
  final double grams;
  final String assetName;
  final String opId;
  final List<int> tradeIds;
  final String sortKey;

  bool get isAuto => kind != GoldCashRowKind.manual;

  GoldCashRow withBalance(double b) => GoldCashRow(
        kind: kind,
        date: date,
        amount: amount,
        balance: b,
        entry: entry,
        grams: grams,
        assetName: assetName,
        opId: opId,
        tradeIds: tradeIds,
        sortKey: sortKey,
      );
}

/// Everything the «صندوق طلا» page shows, computed from the book.
class GoldFundBook {
  const GoldFundBook({
    required this.holdings,
    required this.quote,
    required this.cashRows,
    required this.realized,
    required this.sellCount,
    required this.inG18,
    required this.outG18,
  });

  static const empty = GoldFundBook(
    holdings: [],
    quote: GoldQuote.none,
    cashRows: [],
    realized: 0,
    sellCount: 0,
    inG18: 0,
    outG18: 0,
  );

  final List<GoldHolding> holdings;
  final GoldQuote quote;

  /// Oldest first, each with the running balance.
  final List<GoldCashRow> cashRows;

  /// Σ realized P&L of closed gold lots.
  final double realized;

  /// Closed gold lots.
  final int sellCount;
  final double inG18;
  final double outG18;

  double get holdingG18 => holdings.fold(0.0, (s, h) => s + h.grams18);
  double get value => holdings.fold(0.0, (s, h) => s + h.value);
  double get cost => holdings.fold(0.0, (s, h) => s + h.cost);
  double get unrealized => value - cost;
  double get unrealizedPct => cost <= _eps ? 0 : unrealized / cost * 100;

  /// Fee-inclusive cost per 18k-equivalent gram.
  double get avgCost18 => holdingG18 <= _eps ? 0 : cost / holdingG18;

  double get cash => cashRows.isEmpty ? 0 : cashRows.last.balance;
  double get total => value + cash;
  double get totalPnl => unrealized + realized;

  /// Gold's share of [total] (0–1); null when there is nothing.
  double? get goldShare {
    final t = value + math.max(0, cash);
    if (t <= _eps) return null;
    return value / t;
  }

  bool get hasAnything => holdings.isNotEmpty || cashRows.isNotEmpty || sellCount > 0;

  bool get hasCash => cashRows.isNotEmpty;

  /// Sell price per 18k gram at which the open gold is even after a sell
  /// fee of [sellFeePct].
  double breakEvenSell18(double sellFeePct) {
    final keep = 1 - (sellFeePct > 0 ? sellFeePct / 100 : 0);
    if (avgCost18 <= 0 || keep <= 0) return 0;
    return avgCost18 / keep;
  }

  /// 18k grams the fund cash buys at the ask after [feePct].
  double buyingPowerG18(double feePct) {
    if (cash <= 0 || quote.ask <= 0) return 0;
    return cash / (quote.ask * (1 + math.max(0, feePct) / 100));
  }

  GoldHolding? holdingFor(int assetId) => holdings.where((h) => h.asset.id == assetId).firstOrNull;

  /// The biggest gold holding (default target of the calculator).
  GoldHolding? get mainHolding {
    if (holdings.isEmpty) return null;
    return ([...holdings]..sort((a, b) => b.grams18.compareTo(a.grams18))).first;
  }

  /// Rows that come from [trade] (for the delete warning).
  double cashEffectOf(Trade trade) {
    var v = 0.0;
    if (trade.buyFromGoldFund) v -= trade.buyCost;
    if (trade.soldToGoldFund && trade.sellPrice != null) {
      v += trade.quantity * trade.sellPrice! - trade.sellFee;
    }
    return v;
  }

  static GoldFundBook compute({
    required List<Asset> assets,
    required List<Trade> openTrades,
    required List<Trade> closedTrades,
    required List<GoldCashEntry> ledger,
    GoldQuote quote = GoldQuote.none,
  }) {
    bool isGold(Asset a) => TradeService.isGoldAsset(a.name, a.symbol, a.notes);
    final gold = {
      for (final a in assets)
        if (a.id != null && isGold(a)) a.id!: a
    };
    double purityOf(Asset a) => parseGoldPurityFraction(parseAssetNotes(a.notes).meta.purity) ?? k18GoldPurity;

    final holdings = <GoldHolding>[];
    for (final h in HoldingMetrics.activeHoldings(assets: assets, openTrades: openTrades)) {
      final id = h.asset.id;
      if (id == null || !gold.containsKey(id)) continue;
      holdings.add(GoldHolding(
        asset: h.asset,
        purity: purityOf(h.asset),
        lots: [
          for (final t in openTrades)
            if (t.assetId == id && t.quantity > _eps) t,
        ],
        metrics: h.metrics,
      ));
    }
    holdings.sort((a, b) => b.grams18.compareTo(a.grams18));

    var inG = 0.0, outG = 0.0, realized = 0.0, sells = 0;
    for (final t in [...openTrades, ...closedTrades]) {
      final a = gold[t.assetId];
      if (a == null || t.quantity <= _eps) continue;
      final g18 = t.quantity * purityOf(a) / k18GoldPurity;
      inG += g18;
      if (t.isClosed) {
        outG += g18;
        realized += t.realizedPnl ?? 0;
        sells++;
      }
    }

    // Cash rows: manual entries + tagged trades grouped by operation id.
    final rows = <GoldCashRow>[];
    for (final e in ledger) {
      rows.add(GoldCashRow(
        kind: GoldCashRowKind.manual,
        date: e.date,
        amount: e.amount,
        balance: 0,
        entry: e,
        opId: e.opId,
        sortKey: '${e.date}|${e.kind == GoldCashKind.opening ? 0 : 1}|${e.createdAt}',
      ));
    }
    final buys = <String, _Agg>{};
    final sellsAgg = <String, _Agg>{};
    String nameOf(Trade t) => t.assetName.isNotEmpty ? t.assetName : (gold[t.assetId]?.name ?? '');
    for (final t in [...openTrades, ...closedTrades]) {
      // Only gold (not coins); a tag on anything else is ignored.
      if (t.quantity <= _eps || !gold.containsKey(t.assetId)) continue;
      final bId = goldFundTagId(t.buyNote);
      if (bId != null) {
        final key = bId.isEmpty ? 'b#${t.id}' : bId;
        (buys[key] ??= _Agg(key, t.buyDate, nameOf(t), t.createdAt))
          ..amount -= t.buyCost
          ..grams += t.quantity
          ..ids.add(t.id ?? 0);
      }
      if (t.isClosed && t.sellPrice != null) {
        final sId = goldFundTagId(t.sellNote);
        if (sId != null) {
          final key = sId.isEmpty ? 's#${t.id}' : sId;
          (sellsAgg[key] ??= _Agg(key, t.sellDate ?? t.buyDate, nameOf(t), t.updatedAt))
            ..amount += t.quantity * t.sellPrice! - t.sellFee
            ..grams += t.quantity
            ..ids.add(t.id ?? 0);
        }
      }
    }
    for (final a in buys.values) {
      rows.add(a.row(GoldCashRowKind.buy));
    }
    for (final a in sellsAgg.values) {
      rows.add(a.row(GoldCashRowKind.sell));
    }
    rows.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    var bal = 0.0;
    final withBal = <GoldCashRow>[];
    for (final r in rows) {
      bal += r.amount;
      withBal.add(r.withBalance(bal.abs() < 0.5 ? 0 : bal));
    }

    return GoldFundBook(
      holdings: holdings,
      quote: quote,
      cashRows: withBal,
      realized: realized,
      sellCount: sells,
      inG18: inG,
      outG18: outG,
    );
  }
}

class _Agg {
  _Agg(this.op, String date, this.name, this.created) : date = date.length >= 10 ? date.substring(0, 10) : date;
  final String op;
  final String date;
  final String name;
  final String created;
  double amount = 0;
  double grams = 0;
  final List<int> ids = [];

  GoldCashRow row(GoldCashRowKind kind) => GoldCashRow(
        kind: kind,
        date: date,
        amount: amount,
        balance: 0,
        grams: grams,
        assetName: name,
        opId: op,
        tradeIds: List.unmodifiable(ids),
        // A gap deposit for a buy sorts before it (same date, «1|» < «2|»).
        sortKey: '$date|${kind == GoldCashRowKind.buy ? 2 : 3}|$created',
      );
}

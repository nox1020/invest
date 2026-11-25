import 'dart:math' as math;

/// Pure gold buy/sell arithmetic for the «صندوق طلا» calculator.
///
/// No Flutter, no I/O. Every amount is Toman; weights are grams of the
/// holding's own karat unless a name says `18` (18k-equivalent grams).
///
/// Rounding: money rounds to whole Toman; weights round to the milligram
/// (0.001 g, «سوت»). Buying by amount rounds the weight **down** so the bill
/// never exceeds the amount typed; selling by amount rounds the weight **up**
/// so the cash received is at least the amount typed.

/// Grams in one mithqal (مثقال).
const double gramsPerMithqal = 4.6083;

/// 18k gram price = مظنه ÷ 4.3318 (مظنه is the price of one mithqal of
/// 17-karat (705) gold: 4.6083 × 705/750 = 4.3318).
const double mazanehDivisor = 4.3318;

const double _milli = 1000;
const double _eps = 1e-9;

double gramsToMithqal(double grams) => grams / gramsPerMithqal;
double mithqalToGrams(double mithqal) => mithqal * gramsPerMithqal;

/// 18k Toman/gram from a مظنه quote.
double gram18FromMazaneh(double mazaneh) => mazaneh <= 0 ? 0 : mazaneh / mazanehDivisor;

/// مظنه from an 18k Toman/gram price.
double mazanehFromGram18(double gram18) => gram18 <= 0 ? 0 : gram18 * mazanehDivisor;

/// Fraction of 24k for a karat (`18` → 0.75). Null for nonsense.
double? karatFraction(double karat) {
  if (!karat.isFinite || karat <= 0 || karat > 24) return null;
  return karat / 24;
}

/// Grams of [fromFraction] gold as grams of [toFraction] gold (same pure
/// gold). `convertGoldGrams(1, 1.0, 0.75)` → 1.3333 (one gram of 24k is
/// 1.333 g of 18k).
double convertGoldGrams(double grams, double fromFraction, double toFraction) {
  if (grams <= 0 || fromFraction <= 0 || toFraction <= 0) return 0;
  return grams * fromFraction / toFraction;
}

/// Price per gram of [toFraction] gold from a per-gram price of
/// [fromFraction] gold.
double convertGoldPrice(double price, double fromFraction, double toFraction) {
  if (price <= 0 || fromFraction <= 0 || toFraction <= 0) return 0;
  return price * toFraction / fromFraction;
}

double roundToman(double v) => v.isFinite ? v.roundToDouble() : 0;

/// Round a weight to the milligram.
double roundGrams(double g) => g.isFinite ? (g * _milli).roundToDouble() / _milli : 0;

double floorGrams(double g) => g.isFinite ? ((g * _milli) + 1e-6).floorToDouble() / _milli : 0;

double ceilGrams(double g) => g.isFinite ? ((g * _milli) - 1e-6).ceilToDouble() / _milli : 0;

enum GoldSide { buy, sell }

/// آب‌شده / آنلاین (commission only) or زینتی (making fee, seller profit, VAT).
enum GoldProduct { online, jewelry }

/// Type an amount of Toman or a weight.
enum GoldInputMode { amount, weight }

/// Which open lots a sale closes first.
enum GoldLotOrder { fifo, highestCost, manual }

extension GoldProductX on GoldProduct {
  String get id => this == GoldProduct.online ? 'online' : 'jewelry';
  String get label => this == GoldProduct.online ? 'آب‌شده / آنلاین' : 'زینتی';
  static GoldProduct parse(Object? v) => '$v' == 'jewelry' ? GoldProduct.jewelry : GoldProduct.online;
}

extension GoldLotOrderX on GoldLotOrder {
  String get id => name;
  String get label => switch (this) {
        GoldLotOrder.fifo => 'قدیمی‌ترین اول',
        GoldLotOrder.highestCost => 'گران‌ترین اول',
        GoldLotOrder.manual => 'انتخاب دستی',
      };
  static GoldLotOrder parse(Object? v) =>
      GoldLotOrder.values.firstWhere((e) => e.name == '$v', orElse: () => GoldLotOrder.fifo);
}

/// Percent inputs (5 means 5%). Negative values are treated as zero.
class GoldFees {
  const GoldFees({
    this.feePct = 0,
    this.makingPct = 0,
    this.profitPct = 0,
    this.vatPct = 0,
  });

  /// Commission (online buy/sell) or the shop's deduction (selling).
  final double feePct;

  /// اجرت ساخت — percent of the gold value (jewelry buy only).
  final double makingPct;

  /// سود فروشنده — percent of gold + making (jewelry buy only).
  final double profitPct;

  /// مالیات بر ارزش افزوده — percent of making + profit (jewelry buy only).
  final double vatPct;

  static const onlineDefault = GoldFees(feePct: 0.5);
  static const jewelryDefault = GoldFees(feePct: 0.5, makingPct: 15, profitPct: 7, vatPct: 10);

  static double _p(double v) => v.isFinite && v > 0 ? v / 100 : 0;
  double get fee => _p(feePct);
  double get making => _p(makingPct);
  double get profit => _p(profitPct);
  double get vat => _p(vatPct);

  GoldFees copyWith({double? feePct, double? makingPct, double? profitPct, double? vatPct}) => GoldFees(
        feePct: feePct ?? this.feePct,
        makingPct: makingPct ?? this.makingPct,
        profitPct: profitPct ?? this.profitPct,
        vatPct: vatPct ?? this.vatPct,
      );

  Map<String, dynamic> toJson() => {
        'fee': feePct,
        'making': makingPct,
        'profit': profitPct,
        'vat': vatPct,
      };

  static GoldFees fromJson(Object? raw, GoldFees fallback) {
    if (raw is! Map) return fallback;
    double pick(String k, double d) {
      final v = raw[k];
      if (v is num && v.isFinite && v >= 0 && v <= 100) return v.toDouble();
      return d;
    }

    return GoldFees(
      feePct: pick('fee', fallback.feePct),
      makingPct: pick('making', fallback.makingPct),
      profitPct: pick('profit', fallback.profitPct),
      vatPct: pick('vat', fallback.vatPct),
    );
  }
}

/// Bill multiplier on the gold value for one gram.
///
/// online:  1 + fee
/// jewelry: (1 + making)(1 + profit) + vat × (making + (1 + making) × profit)
///   i.e. invoice = w(p + making·p)(1 + profit) + VAT(making·p·w + profit part)
double buyMultiplier(GoldProduct product, GoldFees fees) {
  if (product == GoldProduct.online) return 1 + fees.fee;
  final m = fees.making, pr = fees.profit, v = fees.vat;
  return (1 + m) * (1 + pr) + v * (m + (1 + m) * pr);
}

/// One open lot as the calculator sees it.
class GoldLot {
  const GoldLot({
    required this.id,
    required this.grams,
    required this.buyPrice,
    this.buyFee = 0,
    this.buyDate = '',
  });

  final int id;

  /// Open quantity in grams of the asset's karat.
  final double grams;

  /// Toman per gram (without fees).
  final double buyPrice;

  /// Fee still attached to the open quantity.
  final double buyFee;
  final String buyDate;

  double get cost => grams * buyPrice + buyFee;
  double get unitCost => grams <= _eps ? 0 : cost / grams;
}

/// Result of a buy calculation.
class GoldBuyQuote {
  const GoldBuyQuote({
    required this.product,
    required this.grams,
    required this.pricePerGram,
    required this.goldValue,
    required this.commission,
    required this.making,
    required this.profit,
    required this.vat,
    required this.total,
    required this.leftover,
    this.midPerGram,
    this.exitPerGram,
    this.exitFeePct = 0,
    this.cashBefore,
    this.holdingBefore = 0,
    this.costBefore = 0,
  });

  static const empty = GoldBuyQuote(
    product: GoldProduct.online,
    grams: 0,
    pricePerGram: 0,
    goldValue: 0,
    commission: 0,
    making: 0,
    profit: 0,
    vat: 0,
    total: 0,
    leftover: 0,
  );

  final GoldProduct product;
  final double grams;
  final double pricePerGram;
  final double goldValue;
  final double commission;
  final double making;
  final double profit;
  final double vat;

  /// Cash paid (sum of the rounded parts above).
  final double total;

  /// Amount typed minus [total] when buying by amount (rounding remainder).
  final double leftover;

  /// Market mid used for the premium (optional).
  final double? midPerGram;

  /// Price you could sell at right now (optional; for the exit numbers).
  final double? exitPerGram;
  final double exitFeePct;
  final double? cashBefore;
  final double holdingBefore;
  final double costBefore;

  bool get isEmpty => grams <= _eps || total <= 0;

  double get fees => commission + making + profit + vat;

  /// Total ÷ grams.
  double get effectivePerGram => grams <= _eps ? 0 : total / grams;

  /// Effective price over the market mid, in percent.
  double? get premiumPct {
    final mid = midPerGram;
    if (mid == null || mid <= 0 || isEmpty) return null;
    return (effectivePerGram / mid - 1) * 100;
  }

  /// Money that does not come back on a resale at gold value (fees).
  double get nonRecoverable => fees;

  /// Fees as a percent of the gold value.
  double get nonRecoverablePct => goldValue <= 0 ? 0 : fees / goldValue * 100;

  double get _exitKeep => 1 - (exitFeePct > 0 ? exitFeePct / 100 : 0);

  /// Sell price per gram at which this purchase breaks even after the sell
  /// fee.
  double get breakEvenSellPrice {
    if (isEmpty || _exitKeep <= 0) return 0;
    return total / (grams * _exitKeep);
  }

  /// Break-even over the current sell price, in percent.
  double? get breakEvenOverExitPct {
    final x = exitPerGram;
    if (x == null || x <= 0 || isEmpty) return null;
    return (breakEvenSellPrice / x - 1) * 100;
  }

  /// Cash if sold right away at [exitPerGram].
  double? get exitValue {
    final x = exitPerGram;
    if (x == null || x <= 0 || isEmpty) return null;
    return roundToman(grams * x * _exitKeep);
  }

  /// Loss if sold right away (negative).
  double? get exitResult {
    final v = exitValue;
    return v == null ? null : v - total;
  }

  double? get cashAfter => cashBefore == null ? null : cashBefore! - total;

  /// Missing cash (0 when enough or unknown).
  double get shortfall {
    final a = cashAfter;
    if (a == null || a >= -0.5) return 0;
    return -a;
  }

  double get holdingAfter => holdingBefore + grams;

  /// Fee-inclusive average after the buy (same rule as inventory sync).
  double get avgBefore => holdingBefore <= _eps ? 0 : costBefore / holdingBefore;
  double get avgAfter => holdingAfter <= _eps ? 0 : (costBefore + total) / holdingAfter;

  /// Amount passed as `buyFee` when recorded (every non-gold part).
  double get recordFee => fees;
}

/// One lot (or part of it) a sale closes.
class GoldLotTake {
  const GoldLotTake({
    required this.lot,
    required this.grams,
    required this.buyFeePart,
    required this.sellFeePart,
    required this.net,
    required this.realized,
  });

  final GoldLot lot;
  final double grams;
  final double buyFeePart;
  final double sellFeePart;

  /// grams × price − sell fee part.
  final double net;
  final double realized;

  bool get closesWholeLot => grams >= lot.grams - _eps;
  double get cost => grams * lot.buyPrice + buyFeePart;
  double get realizedPct => cost <= 0 ? 0 : realized / cost * 100;
}

/// Result of a sell calculation.
class GoldSellQuote {
  const GoldSellQuote({
    required this.grams,
    required this.pricePerGram,
    required this.gross,
    required this.fee,
    required this.net,
    required this.takes,
    required this.available,
    this.cashBefore,
    this.holdingBefore = 0,
    this.costBefore = 0,
  });

  static const empty = GoldSellQuote(
    grams: 0,
    pricePerGram: 0,
    gross: 0,
    fee: 0,
    net: 0,
    takes: [],
    available: 0,
  );

  final double grams;
  final double pricePerGram;
  final double gross;
  final double fee;
  final double net;
  final List<GoldLotTake> takes;

  /// Open grams in the lots offered.
  final double available;
  final double? cashBefore;
  final double holdingBefore;
  final double costBefore;

  bool get isEmpty => grams <= _eps || gross <= 0;

  /// The weight asked for is more than the lots hold.
  bool get exceedsHolding => grams > available + _eps;

  /// Grams the lots actually cover (≤ [grams]).
  double get coveredGrams => takes.fold(0.0, (s, t) => s + t.grams);

  /// Manual picks do not add up to the weight asked for.
  bool get picksMismatch => !isEmpty && (coveredGrams - grams).abs() > 0.0005;

  bool get hasLots => takes.isNotEmpty;

  double get realized => takes.fold(0.0, (s, t) => s + t.realized);
  double get costOut => takes.fold(0.0, (s, t) => s + t.cost);
  double get realizedPct => costOut <= 0 ? 0 : realized / costOut * 100;

  double get effectivePerGram => grams <= _eps ? 0 : net / grams;

  double? get cashAfter => cashBefore == null ? null : cashBefore! + net;

  double get holdingAfter => math.max(0, holdingBefore - coveredGrams);
  double get avgBefore => holdingBefore <= _eps ? 0 : costBefore / holdingBefore;
  double get avgAfter {
    final h = holdingAfter;
    if (h <= _eps) return 0;
    return math.max(0, costBefore - costOut) / h;
  }

  bool get canRecord => !isEmpty && hasLots && !exceedsHolding && !picksMismatch;
}

class GoldCalc {
  GoldCalc._();

  /// Buy [input] Toman (amount mode) or [input] grams (weight mode) at
  /// [pricePerGram] (the price for the asset's karat).
  static GoldBuyQuote buy({
    required GoldProduct product,
    required GoldInputMode mode,
    required double input,
    required double pricePerGram,
    required GoldFees fees,
    double? midPerGram,
    double? exitPerGram,
    double? exitFeePct,
    double? cashBefore,
    double holdingBefore = 0,
    double costBefore = 0,
  }) {
    final k = buyMultiplier(product, fees);
    if (!input.isFinite || input <= 0 || !pricePerGram.isFinite || pricePerGram <= 0 || k <= 0) {
      return GoldBuyQuote(
        product: product,
        grams: 0,
        pricePerGram: pricePerGram > 0 ? pricePerGram : 0,
        goldValue: 0,
        commission: 0,
        making: 0,
        profit: 0,
        vat: 0,
        total: 0,
        leftover: mode == GoldInputMode.amount && input > 0 ? roundToman(input) : 0,
        midPerGram: midPerGram,
        exitPerGram: exitPerGram,
        exitFeePct: exitFeePct ?? fees.feePct,
        cashBefore: cashBefore,
        holdingBefore: holdingBefore,
        costBefore: costBefore,
      );
    }
    var grams = mode == GoldInputMode.weight ? roundGrams(input) : floorGrams(input / (pricePerGram * k));
    var parts = _buyParts(product, grams, pricePerGram, fees);
    if (mode == GoldInputMode.amount) {
      // Whole-Toman rounding of the parts can push one Toman over.
      while (grams > 0 && parts.total > roundToman(input)) {
        grams = roundGrams(grams - 1 / _milli);
        parts = _buyParts(product, grams, pricePerGram, fees);
      }
    }
    return GoldBuyQuote(
      product: product,
      grams: grams,
      pricePerGram: pricePerGram,
      goldValue: parts.gold,
      commission: parts.commission,
      making: parts.making,
      profit: parts.profit,
      vat: parts.vat,
      total: parts.total,
      leftover: mode == GoldInputMode.amount ? math.max(0, roundToman(input) - parts.total) : 0,
      midPerGram: midPerGram,
      exitPerGram: exitPerGram,
      exitFeePct: exitFeePct ?? fees.feePct,
      cashBefore: cashBefore,
      holdingBefore: holdingBefore,
      costBefore: costBefore,
    );
  }

  static ({double gold, double commission, double making, double profit, double vat, double total}) _buyParts(
      GoldProduct product, double grams, double price, GoldFees fees) {
    final gold = roundToman(grams * price);
    if (product == GoldProduct.online) {
      final c = roundToman(gold * fees.fee);
      return (gold: gold, commission: c, making: 0, profit: 0, vat: 0, total: gold + c);
    }
    final making = roundToman(gold * fees.making);
    final profit = roundToman((gold + making) * fees.profit);
    final vat = roundToman((making + profit) * fees.vat);
    return (
      gold: gold,
      commission: 0,
      making: making,
      profit: profit,
      vat: vat,
      total: gold + making + profit + vat,
    );
  }

  /// Sell [input] grams (weight mode) or enough grams for [input] Toman net
  /// (amount mode) at [pricePerGram] minus [feePct].
  ///
  /// [lots] are the asset's open lots; [order] picks which close first.
  /// For [GoldLotOrder.manual], [manualGrams] maps lot id → grams to take
  /// (the weight is then the sum of the picks).
  static GoldSellQuote sell({
    required GoldInputMode mode,
    required double input,
    required double pricePerGram,
    required double feePct,
    List<GoldLot> lots = const [],
    GoldLotOrder order = GoldLotOrder.fifo,
    Map<int, double> manualGrams = const {},
    double? cashBefore,
    double? holdingBefore,
    double? costBefore,
  }) {
    final open = [
      for (final l in lots)
        if (l.grams > _eps) l
    ];
    final available = open.fold(0.0, (s, l) => s + l.grams);
    final hb = holdingBefore ?? available;
    final cb = costBefore ?? open.fold<double>(0.0, (s, l) => s + l.cost);
    final f = feePct.isFinite && feePct > 0 ? feePct / 100 : 0.0;
    final price = pricePerGram.isFinite && pricePerGram > 0 ? pricePerGram : 0.0;

    double grams;
    if (order == GoldLotOrder.manual) {
      grams = 0;
      for (final l in open) {
        final g = manualGrams[l.id];
        if (g != null && g.isFinite && g > 0) grams += math.min(roundGrams(g), l.grams);
      }
      grams = roundGrams(grams);
    } else if (!input.isFinite || input <= 0 || price <= 0 || f >= 1) {
      grams = 0;
    } else if (mode == GoldInputMode.weight) {
      grams = roundGrams(input);
    } else {
      grams = ceilGrams(input / (price * (1 - f)));
    }
    if (grams <= _eps || price <= 0 || f >= 1) {
      return GoldSellQuote(
        grams: 0,
        pricePerGram: price,
        gross: 0,
        fee: 0,
        net: 0,
        takes: const [],
        available: available,
        cashBefore: cashBefore,
        holdingBefore: hb,
        costBefore: cb,
      );
    }
    final gross = roundToman(grams * price);
    final fee = roundToman(gross * f);
    final net = gross - fee;

    // Allocate grams to lots.
    final picks = <({GoldLot lot, double grams})>[];
    if (order == GoldLotOrder.manual) {
      for (final l in open) {
        final g = manualGrams[l.id];
        if (g == null || !g.isFinite || g <= 0) continue;
        picks.add((lot: l, grams: math.min(roundGrams(g), l.grams)));
      }
    } else {
      final sorted = sortLots(open, order);
      var left = grams;
      for (final l in sorted) {
        if (left <= _eps) break;
        final take = math.min(left, l.grams);
        picks.add((lot: l, grams: take >= l.grams - 0.0005 ? l.grams : roundGrams(take)));
        left = roundGrams(left - take);
      }
    }

    // Split the sell fee by weight; the last piece absorbs the remainder.
    final covered = picks.fold(0.0, (s, p) => s + p.grams);
    final takes = <GoldLotTake>[];
    var feeLeft = fee;
    for (var i = 0; i < picks.length; i++) {
      final p = picks[i];
      final last = i == picks.length - 1;
      final share = covered <= _eps ? 0.0 : p.grams / covered;
      final sf = last ? feeLeft : roundToman(fee * share);
      feeLeft -= sf;
      final ratio = p.lot.grams <= _eps ? 0.0 : p.grams / p.lot.grams;
      final bf = p.lot.buyFee * ratio;
      final pieceGross = p.grams * price;
      takes.add(GoldLotTake(
        lot: p.lot,
        grams: p.grams,
        buyFeePart: bf,
        sellFeePart: sf,
        net: pieceGross - sf,
        realized: p.grams * (price - p.lot.buyPrice) - bf - sf,
      ));
    }

    return GoldSellQuote(
      grams: grams,
      pricePerGram: price,
      gross: gross,
      fee: fee,
      net: net,
      takes: takes,
      available: available,
      cashBefore: cashBefore,
      holdingBefore: hb,
      costBefore: cb,
    );
  }

  /// Lots in the order a sale closes them. FIFO: oldest buy date first
  /// (undated last), then lot id. Highest cost: fee-inclusive unit cost,
  /// highest first.
  static List<GoldLot> sortLots(List<GoldLot> lots, GoldLotOrder order) {
    final out = [...lots];
    int byDate(GoldLot a, GoldLot b) {
      final ad = a.buyDate.isEmpty ? '9999' : a.buyDate;
      final bd = b.buyDate.isEmpty ? '9999' : b.buyDate;
      final c = ad.compareTo(bd);
      return c != 0 ? c : a.id.compareTo(b.id);
    }

    if (order == GoldLotOrder.highestCost) {
      out.sort((a, b) {
        final c = b.unitCost.compareTo(a.unitCost);
        return c != 0 ? c : byDate(a, b);
      });
    } else {
      out.sort(byDate);
    }
    return out;
  }
}

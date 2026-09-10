import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/utils/money.dart';

/// Household-index buckets: cash/FX, inflation hedge, then risk assets.
enum IndexQuoteGroup {
  fxLiquidity,
  inflationHedge,
  riskAsset,
  other,
}

enum WallexSort { volume, gainers, losers }

class IndexGroupSpec {
  const IndexGroupSpec({
    required this.group,
    required this.title,
    required this.caption,
  });

  final IndexQuoteGroup group;
  final String title;
  final String caption;
}

const kIndexGroupSpecs = <IndexGroupSpec>[
  IndexGroupSpec(
    group: IndexQuoteGroup.fxLiquidity,
    title: 'ارز و نقدینگی',
    caption: 'لنگر بازار آزاد و ارزهای متقاطع — قیمت‌ها به تومان آزاد',
  ),
  IndexGroupSpec(
    group: IndexQuoteGroup.inflationHedge,
    title: 'پوشش تورم',
    caption: 'طلای ۱۸ عیار و سکه تمام؛ پوشش خانگی، نه شاخص رسمی CPI',
  ),
  IndexGroupSpec(
    group: IndexQuoteGroup.riskAsset,
    title: 'دارایی ریسکی',
    caption: 'رمزارز با نقدشوندگی بالا روی دفتر تومان والکس',
  ),
  IndexGroupSpec(
    group: IndexQuoteGroup.other,
    title: 'سایر',
    caption: 'موارد خارج از سبد اصلی شاخص',
  ),
];

const kFxLiquidityOrder = ['usdt', 'usd', 'eur', 'gbp', 'aed', 'try'];
const kInflationHedgeOrder = ['gold', 'coin'];
const kRiskAssetOrder = ['btc', 'eth'];

IndexQuoteGroup indexGroupForId(String id) => switch (id) {
      'usdt' ||
      'usd' ||
      'eur' ||
      'gbp' ||
      'aed' ||
      'try' =>
        IndexQuoteGroup.fxLiquidity,
      'gold' || 'coin' => IndexQuoteGroup.inflationHedge,
      'btc' || 'eth' => IndexQuoteGroup.riskAsset,
      _ => IndexQuoteGroup.other,
    };

String indexRoleLabel(CommodityQuote quote) => switch (quote.id) {
      'usdt' => 'لنگر بازار آزاد',
      'usd' => 'معادل نقدی دلار',
      'eur' => 'ارز متقاطع · یورو',
      'gbp' => 'ارز متقاطع · پوند',
      'aed' => 'ارز متقاطع · درهم',
      'try' => 'ارز متقاطع · لیر',
      'gold' => 'پوشش تورم · ۱۸ عیار',
      'coin' => 'سکه تمام بهار',
      'btc' => 'دارایی ریسکی',
      'eth' => 'دارایی ریسکی',
      _ => quote.symbol.trim().isEmpty ? 'بازار تومان' : quote.symbol,
    };

class IndexGroupedQuotes {
  const IndexGroupedQuotes({required this.spec, required this.quotes});

  final IndexGroupSpec spec;
  final List<CommodityQuote> quotes;
}

List<IndexGroupedQuotes> groupEssentials(List<CommodityQuote> quotes) {
  final buckets = <IndexQuoteGroup, List<CommodityQuote>>{
    for (final spec in kIndexGroupSpecs) spec.group: <CommodityQuote>[],
  };
  for (final q in quotes) {
    buckets[indexGroupForId(q.id)]!.add(q);
  }
  buckets[IndexQuoteGroup.fxLiquidity] =
      _orderByIds(buckets[IndexQuoteGroup.fxLiquidity]!, kFxLiquidityOrder);
  buckets[IndexQuoteGroup.inflationHedge] = _orderByIds(
    buckets[IndexQuoteGroup.inflationHedge]!,
    kInflationHedgeOrder,
  );
  buckets[IndexQuoteGroup.riskAsset] =
      _orderByIds(buckets[IndexQuoteGroup.riskAsset]!, kRiskAssetOrder);

  return [
    for (final spec in kIndexGroupSpecs)
      if (buckets[spec.group]!.isNotEmpty)
        IndexGroupedQuotes(spec: spec, quotes: buckets[spec.group]!),
  ];
}

List<CommodityQuote> _orderByIds(
  List<CommodityQuote> items,
  List<String> order,
) {
  final byId = <String, CommodityQuote>{};
  final extras = <CommodityQuote>[];
  for (final q in items) {
    if (order.contains(q.id) && !byId.containsKey(q.id)) {
      byId[q.id] = q;
    } else {
      extras.add(q);
    }
  }
  return [
    for (final id in order)
      if (byId[id] != null) byId[id]!,
    ...extras,
  ];
}

class MarketPulse {
  const MarketPulse({
    required this.up,
    required this.down,
    required this.flat,
    required this.sampled,
    required this.headline,
    this.leader,
    this.laggard,
  });

  final int up;
  final int down;
  final int flat;
  final int sampled;
  final String headline;
  final CommodityQuote? leader;
  final CommodityQuote? laggard;

  bool get isEmpty => sampled == 0;
  bool get isGreen => !isEmpty && up > down;
  bool get isRed => !isEmpty && down > up;
}

/// Breadth of 24h moves. [marketLabel] is the Persian subject of the headline.
MarketPulse marketPulse(
  List<CommodityQuote> quotes, {
  String marketLabel = 'بازار',
}) {
  final priced = [
    for (final q in quotes)
      if (q.change24h != null) q,
  ];
  var up = 0;
  var down = 0;
  var flat = 0;
  CommodityQuote? leader;
  CommodityQuote? laggard;
  for (final q in priced) {
    final c = q.change24h!;
    if (c > 0) {
      up++;
    } else if (c < 0) {
      down++;
    } else {
      flat++;
    }
    if (leader == null || c > (leader.change24h ?? double.negativeInfinity)) {
      leader = q;
    }
    if (laggard == null || c < (laggard.change24h ?? double.infinity)) {
      laggard = q;
    }
  }

  if (priced.isEmpty) {
    return MarketPulse(
      up: 0,
      down: 0,
      flat: 0,
      sampled: 0,
      headline: '$marketLabel منتظر دادهٔ تغییر ۲۴ساعته است',
    );
  }

  final n = priced.length;
  final majority = (n / 2).ceil();
  late final String headline;
  if (up > down && up >= majority) {
    headline = leader == null
        ? '$marketLabel سبز است — $up از $n مورد صعودی'
        : '$marketLabel سبز است — $up از $n مورد صعودی · پیشرو ${leader.name}';
  } else if (down > up && down >= majority) {
    headline = laggard == null
        ? 'فشار فروش در $marketLabel — $down از $n مورد نزولی'
        : 'فشار فروش در $marketLabel — $down از $n مورد نزولی · بیشترین افت ${laggard.name}';
  } else if (leader != null && laggard != null && leader.id != laggard.id) {
    headline =
        '$marketLabel متعادل است — پیشرو ${leader.name}، عقب‌مانده ${laggard.name}';
  } else {
    headline = '$marketLabel متعادل است';
  }

  return MarketPulse(
    up: up,
    down: down,
    flat: flat,
    sampled: n,
    headline: headline,
    leader: leader,
    laggard: laggard,
  );
}

/// 0 = 24h low, 1 = 24h high. Null when the book has no usable range.
double? rangePosition(CommodityQuote quote) {
  final p = quote.price;
  final high = quote.high24h;
  final low = quote.low24h;
  if (p == null || high == null || low == null) return null;
  if (high < low) return null;
  if (high == low) return 0.5;
  return ((p - low) / (high - low)).clamp(0.0, 1.0);
}

String? rangeCaption(double? position) {
  if (position == null) return null;
  if (position >= 0.85) return 'نزدیک سقف ۲۴ساعته';
  if (position <= 0.15) return 'نزدیک کف ۲۴ساعته';
  return 'میانه بازه ۲۴ساعته';
}

/// Bid–ask as percent of mid. Null when the book is missing or crossed.
double? relativeSpreadPct(CommodityQuote quote) {
  final bid = quote.bidPrice;
  final ask = quote.askPrice;
  if (bid == null || ask == null || bid <= 0 || ask <= 0) return null;
  if (ask < bid) return null;
  final mid = (bid + ask) / 2;
  if (mid <= 0) return null;
  return (ask - bid) / mid * 100;
}

String? spreadLabel(CommodityQuote quote) {
  final pct = relativeSpreadPct(quote);
  if (pct == null) return null;
  final decimals = pct >= 1 ? 2 : 3;
  return 'اسپرد ${formatNumber(pct, decimals: decimals)}٪';
}

List<CommodityQuote> sortWallexQuotes(
  List<CommodityQuote> quotes,
  WallexSort sort,
) {
  final copy = [...quotes];
  switch (sort) {
    case WallexSort.volume:
      copy.sort(
        (a, b) => (b.quoteVolume24h ?? 0).compareTo(a.quoteVolume24h ?? 0),
      );
    case WallexSort.gainers:
      copy.sort((a, b) {
        final ac = a.change24h ?? double.negativeInfinity;
        final bc = b.change24h ?? double.negativeInfinity;
        return bc.compareTo(ac);
      });
    case WallexSort.losers:
      copy.sort((a, b) {
        final ac = a.change24h ?? double.infinity;
        final bc = b.change24h ?? double.infinity;
        return ac.compareTo(bc);
      });
  }
  return copy;
}

class IndexAnchors {
  const IndexAnchors({this.usd, this.gold, this.gramsPerUsd});

  final CommodityQuote? usd;
  final CommodityQuote? gold;

  /// Grams of 18k gold that one free-market dollar buys.
  final double? gramsPerUsd;

  String? get caption {
    final g = gramsPerUsd;
    if (g == null || g <= 0) return null;
    final decimals = g >= 0.1 ? 3 : 4;
    return 'هر دلار آزاد ≈ ${formatNumber(g, decimals: decimals)} گرم طلای ۱۸ عیار';
  }
}

/// Free-market dollar (USDT, else USD) vs 18k gold — a household hedge ratio.
IndexAnchors indexAnchors(List<CommodityQuote> quotes) {
  CommodityQuote? pick(String id) {
    for (final q in quotes) {
      if (q.id == id && (q.price ?? 0) > 0) return q;
    }
    return null;
  }

  final usd = pick('usdt') ?? pick('usd');
  final gold = pick('gold');
  double? grams;
  if (usd != null && gold != null && gold.price! > 0) {
    grams = usd.price! / gold.price!;
  }
  return IndexAnchors(usd: usd, gold: gold, gramsPerUsd: grams);
}

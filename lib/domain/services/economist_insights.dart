import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/iran_inflation.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/services/index_analytics.dart';
import 'package:invest/domain/utils/money.dart';

/// Household sleeves used by the economist briefing.
enum PortfolioSleeve { gold, cash, crypto, stock, real, other }

enum EconomistInsightTone { note, constructive, watch, caution }

class PortfolioSleeveWeights {
  const PortfolioSleeveWeights({
    required this.totalValue,
    required this.gold,
    required this.cash,
    required this.crypto,
    required this.stock,
    required this.real,
    required this.other,
    required this.holdingCount,
    this.largestName,
    this.largestPct = 0,
  });

  final double totalValue;
  final double gold;
  final double cash;
  final double crypto;
  final double stock;
  final double real;
  final double other;
  final int holdingCount;
  final String? largestName;
  final double largestPct;

  bool get isEmpty => totalValue <= 1e-9 || holdingCount == 0;

  double pctOf(double value) =>
      totalValue <= 1e-9 ? 0 : value / totalValue * 100;

  double get goldPct => pctOf(gold);
  double get cashPct => pctOf(cash);
  double get cryptoPct => pctOf(crypto);
  double get stockPct => pctOf(stock);
  double get realPct => pctOf(real);
  double get otherPct => pctOf(other);
  double get hedgePct => pctOf(gold + real);

  int get activeSleeveCount {
    var n = 0;
    if (goldPct >= 5) n++;
    if (cashPct >= 5) n++;
    if (cryptoPct >= 5) n++;
    if (stockPct >= 5) n++;
    if (realPct >= 5) n++;
    if (otherPct >= 5) n++;
    return n;
  }
}

class EconomistInsight {
  const EconomistInsight({
    required this.id,
    required this.title,
    required this.body,
    required this.action,
    required this.category,
    required this.tone,
    required this.priority,
  });

  final String id;
  final String title;
  final String body;
  final String action;
  final String category;
  final EconomistInsightTone tone;
  final int priority;
}

class EconomistBriefing {
  const EconomistBriefing({
    required this.mix,
    required this.headline,
    required this.insights,
  });

  final PortfolioSleeveWeights mix;
  final String headline;
  final List<EconomistInsight> insights;
}

PortfolioSleeve sleeveForAsset(Asset asset) {
  final kind = detectAssetKind(
    name: asset.name,
    symbol: asset.symbol,
    notes: asset.notes,
  );
  if (kind == AssetKind.gold) return PortfolioSleeve.gold;
  if (kind == AssetKind.cash) return PortfolioSleeve.cash;
  if (kind == AssetKind.crypto) return PortfolioSleeve.crypto;
  if (kind == AssetKind.stock) return PortfolioSleeve.stock;
  if (kind == AssetKind.property || kind == AssetKind.vehicle) {
    return PortfolioSleeve.real;
  }
  final n = asset.name;
  if (n.contains('طلا') || n.contains('سکه')) return PortfolioSleeve.gold;
  if (n.contains('تتر') || n.contains('دلار')) return PortfolioSleeve.cash;
  return PortfolioSleeve.other;
}

PortfolioSleeveWeights portfolioSleeveWeights(
  List<({Asset asset, HoldingMetrics metrics})> holdings,
) {
  var gold = 0.0;
  var cash = 0.0;
  var crypto = 0.0;
  var stock = 0.0;
  var real = 0.0;
  var other = 0.0;
  var total = 0.0;
  String? largestName;
  var largestValue = 0.0;
  for (final h in holdings) {
    final v = h.metrics.marketValue;
    if (v <= 1e-9) continue;
    total += v;
    switch (sleeveForAsset(h.asset)) {
      case PortfolioSleeve.gold:
        gold += v;
      case PortfolioSleeve.cash:
        cash += v;
      case PortfolioSleeve.crypto:
        crypto += v;
      case PortfolioSleeve.stock:
        stock += v;
      case PortfolioSleeve.real:
        real += v;
      case PortfolioSleeve.other:
        other += v;
    }
    if (v > largestValue) {
      largestValue = v;
      largestName = h.asset.name;
    }
  }
  return PortfolioSleeveWeights(
    totalValue: total,
    gold: gold,
    cash: cash,
    crypto: crypto,
    stock: stock,
    real: real,
    other: other,
    holdingCount: holdings.length,
    largestName: largestName,
    largestPct: total <= 1e-9 ? 0 : largestValue / total * 100,
  );
}

CommodityQuote? quoteById(List<CommodityQuote> quotes, String id) {
  for (final q in quotes) {
    if (q.id == id) return q;
  }
  return null;
}

/// Rule-based economist notes: allocation hygiene vs live index + CPI.
/// Not a buy/sell signal.
EconomistBriefing buildEconomistInsights({
  required List<({Asset asset, HoldingMetrics metrics})> holdings,
  required List<CommodityQuote> quotes,
  IranInflationSnapshot? inflation,
  double? unrealizedPnlPct,
  int limit = 6,
}) {
  final mix = portfolioSleeveWeights(holdings);
  final goldQ = quoteById(quotes, 'gold');
  final usdtQ = quoteById(quotes, 'usdt') ?? quoteById(quotes, 'usd');
  final btcQ = quoteById(quotes, 'btc');
  final pulse = marketPulse(quotes, marketLabel: 'بازار');
  final goldCh = goldQ?.change24h;
  final usdCh = usdtQ?.change24h;
  final goldPos = goldQ == null ? null : rangePosition(goldQ);
  final yoy = inflation?.pointToPointPct;
  final monthly = inflation?.monthlyPct;

  final out = <EconomistInsight>[
    _macroBrief(
      mix: mix,
      yoy: yoy,
      goldCh: goldCh,
      usdCh: usdCh,
      pulse: pulse,
    ),
  ];

  if (mix.isEmpty) {
    out.add(
      const EconomistInsight(
        id: 'empty_book',
        title: 'سبد هنوز هسته ندارد',
        body:
            'در اقتصاد ایران قدرت خرید تومان با تورم رسمی و قیمت دارایی‌های پوشش از هم جدا می‌شود. بدون موقعیت باز، اولین کارِ اقتصاددان چیدن دو آستین نقدشونده است: نقدینگی ارزی (تتر/دلار آزاد) برای اختیار معامله، و طلای ۱۸ عیار برای پوشش تورم خانگی. ملک و رمزارز را به مرحله بعد بگذارید.',
        action:
            'یک هسته کوچک نقد + طلا بسازید؛ دارایی غیرنقد را به بعد از شکل‌گیری این دو آستین موکول کنید.',
        category: 'تخصیص',
        tone: EconomistInsightTone.watch,
        priority: 95,
      ),
    );
  }

  if (!mix.isEmpty && mix.hedgePct < 20 && yoy != null && yoy >= 25) {
    out.add(
      EconomistInsight(
        id: 'underhedged_inflation',
        title: 'پوشش تورم پورتفو نازک است',
        body:
            'تورم نقطه‌به‌نقطه ${formatPct(yoy)} است، اما فقط ${_mixPct(mix.hedgePct)} سبد روی طلا، سکه یا دارایی واقعی نشسته. نقد و رمزارز نوسان اسمی می‌دهند؛ سپر خانگی در برابر CPI همان پوشش فلزی و واقعی است.',
        action:
            'وزن آستین پوشش (طلای ۱۸ عیار / سکه / دارایی واقعی نقدشونده) را به حوالی یک‌پنجم تا یک‌سوم سبد نزدیک کنید.',
        category: 'تورم',
        tone: EconomistInsightTone.caution,
        priority: 90,
      ),
    );
  }

  if (!mix.isEmpty && mix.cashPct >= 55) {
    out.add(
      EconomistInsight(
        id: 'cash_heavy',
        title: 'سبد بیش از حد نقد ارزی است',
        body:
            '${_mixPct(mix.cashPct)} پورتفو در تتر/دلار است. این آستین اختیار و نقدشوندگی می‌دهد، اما اگر طلا یا CPI از دلار آزاد جلو بزند، قدرت خرید واقعی همان نقد آب می‌شود.',
        action:
            'بخشی از نقد را به پوشش طلا منتقل کنید تا هسته خانگی دو قطبی (ارز + فلز) شود.',
        category: 'ارز',
        tone: EconomistInsightTone.watch,
        priority: 80,
      ),
    );
  }

  if (!mix.isEmpty && mix.goldPct >= 50) {
    out.add(
      EconomistInsight(
        id: 'gold_concentrated',
        title: 'وزن طلا از هسته متعارف گذشته',
        body:
            '${_mixPct(mix.goldPct)} سبد روی طلا/سکه است. پوشش تورم کار خودش را می‌کند، اما اختیار دلاری و نقدشوندگی روزانه کم می‌شود — مخصوصاً اگر سکه یا آب‌شده در سقف ۲۴ساعته باشد.',
        action:
            'هدف خانگی طلا را حوالی ۳۰ تا ۴۰ درصد بگذارید و یک آستین نقد ارزی برای تعادل نگه دارید.',
        category: 'تخصیص',
        tone: EconomistInsightTone.watch,
        priority: 78,
      ),
    );
  }

  if (!mix.isEmpty && mix.cryptoPct >= 35) {
    out.add(
      EconomistInsight(
        id: 'crypto_overweight',
        title: 'رمزارز جای پوشش تورم را گرفته',
        body:
            '${_mixPct(mix.cryptoPct)} سبد دارایی ریسکی است. بیت‌کوین و آلت‌ها ماهوارهٔ رشدند، نه سپر خانگی در برابر CPI ایران. اگر طلا و نقد نازک باشند، یک روز قرمز دفتر والکس کل قدرت خرید را جابه‌جا می‌کند.',
        action:
            'رمزارز را به ماهواره (زیر یک‌سوم) برگردانید و هسته را طلا + نقد ارزی کنید.',
        category: 'ریسک',
        tone: EconomistInsightTone.caution,
        priority: 88,
      ),
    );
  }

  if (!mix.isEmpty && mix.largestPct >= 60 && mix.largestName != null) {
    out.add(
      EconomistInsight(
        id: 'single_name',
        title: 'تمرکز روی یک نام',
        body:
            '«${mix.largestName}» حدود ${_mixPct(mix.largestPct)} ارزش سبد است. از نگاه تخصیص، این یک شرط واحد است نه سبد؛ شوک همان بازار کل پورتفو را می‌برد.',
        action:
            'وزن این موقعیت را به‌تدریج به دو یا سه آستین اقتصادی (نقد، پوشش، ریسک) پخش کنید.',
        category: 'تخصیص',
        tone: EconomistInsightTone.caution,
        priority: 86,
      ),
    );
  }

  if (!mix.isEmpty &&
      mix.goldPct >= 30 &&
      goldCh != null &&
      goldCh >= 3 &&
      (goldPos == null || goldPos >= 0.8)) {
    out.add(
      EconomistInsight(
        id: 'gold_heat',
        title: 'طلا امروز داغ است؛ تعقیب نکنید',
        body:
            'طلا ${formatPct(goldCh)} در ۲۴ ساعت حرکت کرده و سبد شما از قبل ${_mixPct(mix.goldPct)} روی این آستین است. اقتصاددان در سقف کوتاه‌مدت خرید اضافه نمی‌کند؛ صبر می‌کند تا هیجان روزانه بنشیند.',
        action:
            'خرید تازه طلا را به برگشت از سقف ۲۴ساعته موکول کنید؛ هسته فعلی را نگه دارید.',
        category: 'تورم',
        tone: EconomistInsightTone.watch,
        priority: 72,
      ),
    );
  }

  if (!mix.isEmpty &&
      mix.goldPct < 25 &&
      goldCh != null &&
      goldCh <= -2 &&
      yoy != null &&
      yoy >= 25) {
    out.add(
      EconomistInsight(
        id: 'gold_dip',
        title: 'افت طلا در برابر تورم هنوز بالاست',
        body:
            'طلا ${formatPct(goldCh)} عقب نشسته، در حالی که تورم نقطه‌به‌نقطه ${formatPct(yoy)} است و پوشش شما فقط ${_mixPct(mix.goldPct)} سبد است. این افت کوتاه‌مدت لزوماً پایان فشار قیمتی خانوار نیست.',
        action:
            'اگر هسته پوشش نازک است، این محدوده را برای بازتوازن تدریجی ببینید نه برای خروج از فلز.',
        category: 'تورم',
        tone: EconomistInsightTone.constructive,
        priority: 74,
      ),
    );
  }

  if (!mix.isEmpty && mix.cashPct < 20 && usdCh != null && usdCh >= 2) {
    out.add(
      EconomistInsight(
        id: 'usd_bid',
        title: 'دلار آزاد امروز محکم است',
        body:
            'لنگر تتر/دلار ${formatPct(usdCh)} بالا آمده و نقد ارزی شما فقط ${_mixPct(mix.cashPct)} سبد است. در اقتصاد ایران این آستین اختیار می‌خرد: اگر طلا یا رمزارز قفل شد، نقد آزاد مسیر تعدیل است.',
        action:
            'یک آستین نقد کوچک (۱۵ تا ۲۵ درصد) برای اختیار نگهداری کنید؛ همه را وارد دارایی غیرنقد نکنید.',
        category: 'ارز',
        tone: EconomistInsightTone.note,
        priority: 60,
      ),
    );
  }

  if (!mix.isEmpty && mix.cryptoPct >= 25 && pulse.isRed) {
    final laggard = pulse.laggard?.name;
    out.add(
      EconomistInsight(
        id: 'risk_off',
        title: 'فشار فروش روی دارایی ریسکی',
        body:
            'نبض بازار قرمز است${laggard == null ? '' : ' و بیشترین افت از آنِ $laggard است'}. ${_mixPct(mix.cryptoPct)} سبد شما ماهوارهٔ ریسک است. هسته خانگی باید طلا و نقد باشد تا یک روز والکس کل سبد را نبرد.',
        action:
            'از هسته (طلا/نقد) برای میانگین‌گیری ریسک استفاده نکنید؛ ماهواره را جدا از سپر تورم ببینید.',
        category: 'ریسک',
        tone: EconomistInsightTone.caution,
        priority: 70,
      ),
    );
  }

  if (!mix.isEmpty && mix.realPct >= 70) {
    out.add(
      EconomistInsight(
        id: 'real_illiquid',
        title: 'سبد خوب پوشش می‌دهد اما قفل است',
        body:
            '${_mixPct(mix.realPct)} ارزش روی ملک/خودرو است. این‌ها با تورم خانوار هم‌جهت‌اند، اما با شاخص زنده نمی‌توان آن‌ها را بازتوازن کرد. بدون آستین طلا و تتر، اقتصاددان دستش برای شوک نرخ ارز خالی است.',
        action:
            'یک لایه نقدشونده (تتر + طلای آب‌شده) کنار دارایی واقعی نگه دارید.',
        category: 'تخصیص',
        tone: EconomistInsightTone.watch,
        priority: 68,
      ),
    );
  }

  if (!mix.isEmpty &&
      mix.goldPct >= 15 &&
      mix.goldPct <= 45 &&
      mix.cashPct >= 15 &&
      mix.cashPct <= 50 &&
      mix.cryptoPct < 30 &&
      mix.activeSleeveCount >= 2) {
    out.add(
      EconomistInsight(
        id: 'balanced_core',
        title: 'هسته خانگی شکل گرفته',
        body:
            'ترکیب تقریبی طلا ${_mixPct(mix.goldPct)} و نقد ${_mixPct(mix.cashPct)} به الگوی متعارف اقتصاد خانوار ایران نزدیک است: سپر تورم + اختیار ارزی. ماهواره ریسک ${_mixPct(mix.cryptoPct)} است.',
        action:
            'نسبت هسته را نگه دارید و با نوسان ۲۴ساعته فقط بازتوازن کوچک کنید، نه چرخش کامل سبد.',
        category: 'تخصیص',
        tone: EconomistInsightTone.constructive,
        priority: 40,
      ),
    );
  }

  if (!mix.isEmpty &&
      unrealizedPnlPct != null &&
      unrealizedPnlPct <= -15 &&
      (goldCh ?? 0) > 0) {
    out.add(
      EconomistInsight(
        id: 'drawdown_vs_hedge',
        title: 'زیان شناور در ماهواره است، نه در سپر',
        body:
            'بازده شناور سبد ${formatPct(unrealizedPnlPct)} است در حالی که طلا امروز ${formatPct(goldCh!)} سبز است. اگر پوشش تورم سرجایش باشد، فروش هسته برای میانگین‌گیری دارایی ریسکی خطای تخصیص است.',
        action:
            'هسته طلا/نقد را دست نزنید؛ زیان ماهواره را جدا از تصمیم پوشش تورم ببینید.',
        category: 'ریسک',
        tone: EconomistInsightTone.note,
        priority: 58,
      ),
    );
  }

  if (yoy != null && monthly != null && monthly >= 3 && yoy >= 25) {
    out.add(
      EconomistInsight(
        id: 'cpi_heat',
        title: 'فشار ماهانه CPI هنوز بالاست',
        body:
            'تورم ماهانه ${formatPct(monthly)} و نقطه‌به‌نقطه ${formatPct(yoy)} است. این یعنی سبد مصرف خانوار هر ماه قدرت خرید را می‌برد؛ بازده اسمی پورتفو باید از این مسیر جلو بزند وگرنه «سود تومان» توهم است.',
        action:
            'عملکرد سبد را با تورم نقطه‌به‌نقطه بسنجید، نه فقط با سود تومانی روی داشبورد.',
        category: 'تورم',
        tone: EconomistInsightTone.note,
        priority: 55,
      ),
    );
  }

  if (btcQ?.change24h != null && mix.cryptoPct >= 15 && mix.goldPct < 15) {
    out.add(
      EconomistInsight(
        id: 'btc_without_core',
        title: 'ریسک بدون لنگر خانگی',
        body:
            'بیت‌کوین امروز ${formatPct(btcQ!.change24h!)} است و شما ${_mixPct(mix.cryptoPct)} ریسک دارید، اما پوشش طلا فقط ${_mixPct(mix.goldPct)} است. در اقتصاد تحریم‌زده، رمزارز جایگزین اسکناس آزاد یا طلا نیست.',
        action:
            'اول هسته طلا/نقد را بسازید، بعد اندازه ماهواره ریسک را بالا ببرید.',
        category: 'ریسک',
        tone: EconomistInsightTone.watch,
        priority: 66,
      ),
    );
  }

  out.sort((a, b) => b.priority.compareTo(a.priority));
  final seen = <String>{};
  final unique = <EconomistInsight>[];
  for (final i in out) {
    if (!seen.add(i.id)) continue;
    unique.add(i);
  }
  final insights = unique.take(limit).toList();
  return EconomistBriefing(
    mix: mix,
    headline: insights.isEmpty
        ? 'برای بینش اقتصادی، سبد و شاخص را هم‌زمان می‌سنجم'
        : insights.first.title,
    insights: insights,
  );
}

EconomistInsight _macroBrief({
  required PortfolioSleeveWeights mix,
  required double? yoy,
  required double? goldCh,
  required double? usdCh,
  required MarketPulse pulse,
}) {
  final bits = <String>[];
  if (mix.isEmpty) {
    bits.add('سبد خالی است.');
  } else {
    bits.add(
      'ترکیب فعلی: طلا ${_mixPct(mix.goldPct)}، نقد ${_mixPct(mix.cashPct)}، ریسک ${_mixPct(mix.cryptoPct)}'
      '${mix.realPct >= 5 ? '، دارایی واقعی ${_mixPct(mix.realPct)}' : ''}.',
    );
  }
  if (yoy != null) {
    bits.add(
      'تورم رسمی نقطه‌به‌نقطه ${formatPct(yoy)} است؛ هر بازده اسمی کمتر از این عدد قدرت خرید را کم می‌کند.',
    );
  }
  if (goldCh != null && usdCh != null) {
    bits.add(
      'در ۲۴ ساعت طلا ${formatPct(goldCh)} و دلار آزاد ${formatPct(usdCh)} حرکت کرده است.',
    );
  } else if (!pulse.isEmpty) {
    bits.add(pulse.headline);
  }

  return EconomistInsight(
    id: 'macro_brief',
    title: mix.isEmpty
        ? 'نگاه اقتصاددان به شاخص و سبد'
        : 'نگاه اقتصاددان به پورتفوی شما',
    body: bits.join(' '),
    action:
        'این متن سیگنال خرید و فروش نیست؛ تخصیص هسته خانگی را با تورم و نقدشوندگی تراز می‌کند.',
    category: 'کلان',
    tone: EconomistInsightTone.note,
    priority: 100,
  );
}

String _mixPct(double pct) =>
    '${formatNumber(pct, decimals: pct >= 10 ? 0 : 1)}٪';

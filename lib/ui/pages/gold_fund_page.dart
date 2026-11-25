import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:invest/domain/models/gold_cash_entry.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/gold_calc.dart';
import 'package:invest/domain/services/gold_calc_prefs.dart';
import 'package:invest/domain/services/gold_fund_book.dart';
import 'package:invest/domain/services/gold_price_log.dart';
import 'package:invest/domain/services/trade_service.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/gold/gold_format.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:invest/ui/widgets/gold_calc_sheet.dart';
import 'package:invest/ui/widgets/gold_cash_sheet.dart';
import 'package:invest/ui/widgets/user_error.dart';
import 'package:provider/provider.dart';

/// Opens «صندوق طلا».
Future<void> openGoldFundPage(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GoldFundPage()),
    );

/// Online fee assumed for break-even and buying power until the
/// calculator's remembered online fee is loaded.
const double kGoldDefaultSellFeePct = 0.5;

/// Dashboard row inside the gold section: «صندوق طلا و ماشین‌حساب ›».
class GoldFundEntryRow extends StatelessWidget {
  const GoldFundEntryRow({super.key, required this.fundCash, required this.onTap});

  final double fundCash;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kGold.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kGold.withValues(alpha: 0.45)),
          ),
          child: Row(children: [
            const Icon(Icons.calculate_outlined, color: kGold, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Text('صندوق طلا و ماشین‌حساب',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: kGold, fontSize: 12.5, fontWeight: FontWeight.w800)),
                if (fundCash.abs() >= 0.5)
                  Text('نقد صندوق ${gToman(fundCash)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(10.5)),
              ]),
            ),
            const Icon(Icons.chevron_left, color: kGold, size: 20),
          ]),
        ),
      ),
    );
  }
}

class GoldFundPage extends StatefulWidget {
  const GoldFundPage({super.key});

  @override
  State<GoldFundPage> createState() => _GoldFundPageState();
}

class _GoldFundPageState extends State<GoldFundPage> {
  int _rangeDays = 90;
  bool _allLots = false;
  bool _allCash = false;

  /// The calculator's last online fee (break-even, buying power).
  double _feePct = kGoldDefaultSellFeePct;

  @override
  void initState() {
    super.initState();
    _loadFee();
  }

  Future<void> _loadFee() async {
    try {
      final p = await GoldCalcPrefs.load();
      if (mounted && p.onlineFees.feePct != _feePct) setState(() => _feePct = p.onlineFees.feePct);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final book = state.goldFund;
    final q = book.quote;
    final calendar = state.settings.calendar;
    final pending = state.pendingSyncCount;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('صندوق طلا', key: ValueKey('gf-title')),
              Text('طلا + نقد', style: TextStyle(color: AppTheme.muted, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
          actions: [
            IconButton(
              key: const ValueKey('gf-calc-action'),
              tooltip: 'ماشین‌حساب طلا',
              icon: const Icon(Icons.calculate_outlined),
              onPressed: () => showGoldCalcSheet(context, side: GoldSide.buy, calcOnly: true).then((_) => _loadFee()),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => state.refreshAll(),
          child: ListView(
            key: const ValueKey('gf-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 36),
            children: [
              _Ribbon(state: state, quote: q, pending: pending),
              const SizedBox(height: 10),
              _QuoteStrip(quote: q),
              const SizedBox(height: 10),
              _Hero(book: book, feePct: _feePct),
              const SizedBox(height: 10),
              _Actions(state: state, book: book, onSheetClosed: _loadFee),
              const SizedBox(height: 10),
              if (!book.hasAnything)
                const Padding(
                  key: ValueKey('gf-empty'),
                  padding: EdgeInsets.only(bottom: 10),
                  child: GNote(
                    'هنوز طلایی ثبت نشده. «واریز نقد» پول کنار گذاشته برای طلا را ثبت می‌کند و «خرید طلا» از همین نقد می‌خرد. «فقط محاسبه» چیزی ثبت نمی‌کند.',
                    color: AppTheme.muted,
                    icon: Icons.info_outline,
                  ),
                ),
              _Stats(book: book, feePct: _feePct),
              const SizedBox(height: 10),
              _Flow(book: book),
              const SizedBox(height: 10),
              _ChartCard(
                state: state,
                book: book,
                rangeDays: _rangeDays,
                onRange: (d) => setState(() => _rangeDays = d),
              ),
              const SizedBox(height: 10),
              _Scenario(book: book),
              const SizedBox(height: 14),
              _LotsSection(
                book: book,
                calendar: calendar,
                showAll: _allLots,
                onToggle: () => setState(() => _allLots = !_allLots),
              ),
              const SizedBox(height: 14),
              _CashSection(
                book: book,
                calendar: calendar,
                showAll: _allCash,
                onToggle: () => setState(() => _allCash = !_allCash),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.state, required this.quote, required this.pending});
  final AppState state;
  final GoldQuote quote;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final live = state.liveGold != null && !state.offline;
    final asOf = state.pricesAsOf;
    final ch = quote.change24hPct;
    return Container(
      key: const ValueKey('gf-ribbon'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: live ? AppTheme.positive : kAmber,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              [
                live ? 'قیمت زنده' : 'آخرین قیمت ذخیره‌شده',
                if (asOf != null) agoFa(asOf),
              ].join(' · '),
              style: const TextStyle(color: AppTheme.text, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ]),
          if (ch != null && ch.isFinite) _Chip(text: '۲۴ ساعت ${gPct(ch)}', color: toneOf(ch)),
          if (pending > 0)
            _Chip(
              key: const ValueKey('gf-pending'),
              text: fa('$pending مورد در صف همگام‌سازی'),
              color: kAmber,
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
      );
}

class _QuoteStrip extends StatelessWidget {
  const _QuoteStrip({required this.quote});
  final GoldQuote quote;

  @override
  Widget build(BuildContext context) {
    Widget box(String k, double v, Key key) => Expanded(
          child: Container(
            key: key,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(10)),
              const SizedBox(height: 2),
              GFit(v > 0 ? gToman(v) : '—',
                  style: const TextStyle(color: AppTheme.title, fontSize: 13, fontWeight: FontWeight.w900)),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        box('خرید از بازار (گرم ۱۸)', quote.ask, const ValueKey('gf-ask')),
        const SizedBox(width: 6),
        box('فروش به بازار', quote.bid, const ValueKey('gf-bid')),
        const SizedBox(width: 6),
        box('مظنه (مثقال ۱۷)', quote.hasPrice ? quote.mazaneh : 0, const ValueKey('gf-mazaneh')),
      ]),
      if (quote.hasPrice && quote.estimated)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'قیمت خرید و فروش تخمینی است (میانه ${gToman(quote.mid)} ± ${gNum(GoldQuote.defaultHalfSpreadPct)}٪)؛ در ماشین‌حساب قابل ویرایش است.',
            key: const ValueKey('gf-estimated'),
            style: mutedStyle(10),
          ),
        ),
      if (!quote.hasPrice)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('قیمت طلا هنوز دریافت نشده؛ صفحه را بکشید تا به‌روز شود.', style: mutedStyle(10.5)),
        ),
    ]);
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.book, required this.feePct});
  final GoldFundBook book;
  final double feePct;

  @override
  Widget build(BuildContext context) {
    final share = book.goldShare;
    final cash = book.cash;
    final buyPower = book.buyingPowerG18(feePct);
    return Container(
      key: const ValueKey('gf-hero'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kGold.withValues(alpha: 0.25)),
        gradient: const RadialGradient(
          center: AlignmentDirectional.topEnd,
          radius: 1.3,
          colors: [Color(0xFF4A3C12), Color(0xFF1D2A1C), Color(0xFF101F18)],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.diamond_outlined, color: kGold, size: 15),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('ارزش کل صندوق',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: kGoldText, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          if (share != null)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kGold.withValues(alpha: 0.35)),
                ),
                child: GFit('طلا ${gNum(share * 100, decimals: 1)}٪ · نقد ${gNum((1 - share) * 100, decimals: 1)}٪',
                    key: const ValueKey('gf-split-chip'),
                    style: const TextStyle(color: kGoldText, fontSize: 10.5, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        GFit('${gToman(book.total)} تومان',
            key: const ValueKey('gf-total'),
            style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        GFit(
          'سود کل صندوق ${gSigned(book.totalPnl)} · باز ${gSigned(book.unrealized)} · محقق ${gSigned(book.realized)}',
          style: const TextStyle(color: Color(0xFFCFE3D8), fontSize: 11, fontWeight: FontWeight.w600),
        ),
        if (share != null) ...[
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 8,
              child: Row(children: [
                if (share > 0)
                  Expanded(
                    flex: math.max(1, (share * 1000).round()),
                    child: Container(
                      decoration: const BoxDecoration(gradient: LinearGradient(colors: [kGoldDeep, kGold])),
                    ),
                  ),
                if (share > 0 && share < 1) const SizedBox(width: 2),
                if (share < 1)
                  Expanded(
                    flex: math.max(1, ((1 - share) * 1000).round()),
                    child: Container(color: AppTheme.positive),
                  ),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 9),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _Pocket(
              key: const ValueKey('gf-pocket-gold'),
              color: kGold,
              title: 'طلا',
              amount: gGrams(book.holdingG18),
              amountColor: kGold,
              sub: '${gToman(book.value)} · ≈ ${gNum(gramsToMithqal(book.holdingG18), decimals: 2)} مثقال',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Pocket(
              key: const ValueKey('gf-pocket-cash'),
              color: AppTheme.positive,
              title: 'نقد',
              amount: gToman(cash),
              amountColor: cash < 0 ? AppTheme.negative : AppTheme.positive,
              sub: cash > 0 ? 'قدرت خرید ≈ ${gNum(buyPower, decimals: 2)} گرم' : 'نقدی کنار گذاشته نشده',
            ),
          ),
        ]),
      ]),
    );
  }
}

class _Pocket extends StatelessWidget {
  const _Pocket({
    super.key,
    required this.color,
    required this.title,
    required this.amount,
    required this.amountColor,
    required this.sub,
  });
  final Color color;
  final String title;
  final String amount;
  final Color amountColor;
  final String sub;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.bg.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 5),
            Text(title, style: mutedStyle(10.5, FontWeight.w800)),
          ]),
          const SizedBox(height: 3),
          GFit(amount, style: TextStyle(color: amountColor, fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 1),
          GFit(sub, style: mutedStyle(10)),
        ]),
      );
}

class _Actions extends StatelessWidget {
  const _Actions({required this.state, required this.book, required this.onSheetClosed});
  final AppState state;
  final GoldFundBook book;
  final VoidCallback onSheetClosed;

  @override
  Widget build(BuildContext context) {
    final canWrite = state.canMutate;
    final canSell = canWrite && book.holdings.isNotEmpty;
    Widget ghost(String label, IconData icon, VoidCallback? onTap, Key key) => Expanded(
          child: OutlinedButton.icon(
            key: key,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              foregroundColor: AppTheme.text,
              side: const BorderSide(color: AppTheme.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onTap,
            icon: Icon(icon, size: 16),
            label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
          ),
        );
    return Column(children: [
      Row(children: [
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('gf-buy'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              backgroundColor: AppTheme.positive,
              foregroundColor: AppTheme.bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed:
                canWrite ? () => showGoldCalcSheet(context, side: GoldSide.buy).then((_) => onSheetClosed()) : null,
            icon: const Icon(Icons.add, size: 18),
            label: const FittedBox(fit: BoxFit.scaleDown, child: Text('خرید طلا', maxLines: 1)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('gf-sell'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              backgroundColor: kGold,
              foregroundColor: AppTheme.bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed:
                canSell ? () => showGoldCalcSheet(context, side: GoldSide.sell).then((_) => onSheetClosed()) : null,
            icon: const Icon(Icons.remove, size: 18),
            label: const FittedBox(fit: BoxFit.scaleDown, child: Text('فروش طلا', maxLines: 1)),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        ghost(
            'واریز نقد',
            Icons.south_rounded,
            canWrite ? () => showGoldCashSheet(context, kind: GoldCashKind.deposit) : null,
            const ValueKey('gf-deposit')),
        const SizedBox(width: 6),
        ghost(
            'برداشت نقد',
            Icons.north_rounded,
            canWrite ? () => showGoldCashSheet(context, kind: GoldCashKind.withdraw) : null,
            const ValueKey('gf-withdraw')),
        const SizedBox(width: 6),
        ghost(
            'فقط محاسبه',
            Icons.calculate_outlined,
            () => showGoldCalcSheet(context, side: GoldSide.buy, calcOnly: true).then((_) => onSheetClosed()),
            const ValueKey('gf-calc')),
      ]),
    ]);
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.book, required this.feePct});
  final GoldFundBook book;
  final double feePct;

  @override
  Widget build(BuildContext context) {
    final be = book.breakEvenSell18(feePct);
    final bid = book.quote.bid;
    final beGap = be > 0 && bid > 0 ? (bid / be - 1) * 100 : null;
    Widget st(String k, String v, String s, {Color? c, Key? key}) => Expanded(
          child: Container(
            key: key,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(10.5, FontWeight.w700)),
              const SizedBox(height: 2),
              GFit(v, style: TextStyle(color: c ?? AppTheme.title, fontSize: 14, fontWeight: FontWeight.w900)),
              const SizedBox(height: 1),
              Text(s, maxLines: 2, overflow: TextOverflow.ellipsis, style: mutedStyle(10)),
            ]),
          ),
        );
    final has = book.holdingG18 > 0;
    return Column(children: [
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          st('میانگین قیمت تمام‌شده', has ? gToman(book.avgCost18) : '—', 'هر گرم ۱۸ · با کارمزد',
              key: const ValueKey('gf-avg')),
          const SizedBox(width: 8),
          st('سود باز طلا', has ? gSigned(book.unrealized) : '—',
              has ? '${gPct(book.unrealizedPct)} روی بهای تمام‌شده' : 'لات بازی نیست',
              c: has ? toneOf(book.unrealized) : null, key: const ValueKey('gf-unrealized')),
        ]),
      ),
      const SizedBox(height: 8),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          st(
            'سربه‌سر فروش',
            be > 0 ? gToman(be) : '—',
            beGap == null
                ? 'با کارمزد فروش ${gNum(feePct)}٪'
                : beGap >= 0
                    ? 'قیمت فروش فعلی ${gPct(beGap, sign: false)} بالاتر است'
                    : 'قیمت فروش فعلی ${gPct(-beGap, sign: false)} پایین‌تر است',
            key: const ValueKey('gf-breakeven'),
          ),
          const SizedBox(width: 8),
          st('سود محقق‌شده طلا', gSigned(book.realized),
              book.sellCount == 0 ? 'هنوز فروشی ثبت نشده' : fa('از ${book.sellCount} فروش'),
              c: toneOf(book.realized), key: const ValueKey('gf-realized')),
        ]),
      ),
    ]);
  }
}

class _Flow extends StatelessWidget {
  const _Flow({required this.book});
  final GoldFundBook book;

  @override
  Widget build(BuildContext context) {
    Widget cell(String k, String v, {Color? c, bool last = false}) => Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: last ? null : const BorderDirectional(end: BorderSide(color: AppTheme.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(children: [
              GFit(k, align: Alignment.center, style: mutedStyle(10, FontWeight.w700)),
              const SizedBox(height: 1),
              GFit(v,
                  align: Alignment.center,
                  style: TextStyle(color: c ?? AppTheme.title, fontSize: 13, fontWeight: FontWeight.w900)),
            ]),
          ),
        );
    return Container(
      key: const ValueKey('gf-flow'),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        cell('طلای واردشده', gGrams(book.inG18)),
        cell('طلای خارج‌شده', gGrams(book.outG18)),
        cell('موجودی', gGrams(book.holdingG18), c: kGold, last: true),
      ]),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.state, required this.book, required this.rangeDays, required this.onRange});
  final AppState state;
  final GoldFundBook book;
  final int rangeDays;
  final ValueChanged<int> onRange;

  @override
  Widget build(BuildContext context) {
    final today = todayIso();
    final pts = GoldPriceLog.window(state.goldPriceLog, today, rangeDays);
    final from = pts.isEmpty ? today : pts.first.date;
    final markers = <({String date, bool buy})>[];
    final goldIds = {for (final h in book.holdings) h.asset.id};
    for (final a in state.assets) {
      if (a.id != null && TradeService.isGoldAsset(a.name, a.symbol, a.notes)) goldIds.add(a.id);
    }
    void addMarker(String? d, bool buy) {
      if (d == null || d.length < 10) return;
      final day = d.substring(0, 10);
      if (day.compareTo(from) >= 0 && day.compareTo(today) <= 0) markers.add((date: day, buy: buy));
    }

    for (final t in <Trade>[...state.openTrades, ...state.closedTrades]) {
      if (!goldIds.contains(t.assetId)) continue;
      addMarker(t.buyDate, true);
      if (t.isClosed) addMarker(t.sellDate, false);
    }
    final values = [for (final p in pts) p.mid];
    final hi = values.isEmpty ? 0.0 : values.reduce(math.max);
    final lo = values.isEmpty ? 0.0 : values.reduce(math.min);
    final chg = values.length >= 2 && values.first > 0 ? (values.last / values.first - 1) * 100 : null;
    final avg = book.avgCost18;
    final rangeLabel = switch (rangeDays) { 30 => '۱ ماه', 90 => '۳ ماه', _ => '۱ سال' };

    return Container(
      key: const ValueKey('gf-chart'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(
            child: Text('روند قیمت گرم ۱۸',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.title, fontSize: 13, fontWeight: FontWeight.w800)),
          ),
          SegmentedButton<int>(
            key: const ValueKey('gf-range'),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.padded,
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            segments: const [
              ButtonSegment(value: 30, label: Text('۱ ماه')),
              ButtonSegment(value: 90, label: Text('۳ ماه')),
              ButtonSegment(value: 365, label: Text('۱ سال')),
            ],
            selected: {rangeDays},
            onSelectionChanged: (s) => onRange(s.first),
          ),
        ]),
        const SizedBox(height: 4),
        if (values.length >= 2) ...[
          GFit(
            '$rangeLabel ${chg == null ? '' : gPct(chg)} · بیشینه ${gToman(hi)} · کمینه ${gToman(lo)}',
            style: mutedStyle(10.5),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 110,
            child: CustomPaint(
              key: const ValueKey('gf-chart-paint'),
              size: Size.infinite,
              painter: _GoldChartPainter(points: pts, markers: markers, avg: avg),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 12, runSpacing: 2, children: [
            _legendDot(AppTheme.positive, 'خرید'),
            _legendDot(kGold, 'فروش'),
            if (avg > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 12, height: 1.5, color: AppTheme.muted),
                const SizedBox(width: 4),
                Flexible(child: Text('میانگین خرید شما ${gToman(avg)}', style: mutedStyle(10))),
              ]),
          ]),
        ] else
          Padding(
            key: const ValueKey('gf-chart-empty'),
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'نمودار از قیمت روزانه‌ای ساخته می‌شود که همین گوشی ثبت می‌کند. از امروز هر روز یک نقطه اضافه می‌شود${values.length == 1 ? ' (امروز: ${gToman(values.first)})' : ''}.',
              textAlign: TextAlign.center,
              style: mutedStyle(11),
            ),
          ),
      ]),
    );
  }

  static Widget _legendDot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(t, style: mutedStyle(10)),
      ]);
}

/// Line chart of the logged 18k price, buy/sell dots and the average cost.
class _GoldChartPainter extends CustomPainter {
  _GoldChartPainter({required this.points, required this.markers, required this.avg});

  final List<GoldPricePoint> points;
  final List<({String date, bool buy})> markers;
  final double avg;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.width <= 0 || size.height <= 0) return;
    final t0 = DateTime.parse(points.first.date);
    final t1 = DateTime.parse(points.last.date);
    final span = math.max(1, t1.difference(t0).inDays);
    var lo = points.map((p) => p.mid).reduce(math.min);
    var hi = points.map((p) => p.mid).reduce(math.max);
    if (avg > 0) {
      lo = math.min(lo, avg);
      hi = math.max(hi, avg);
    }
    if (hi - lo < 1) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;
    const r = 4.5;
    final w = size.width - 2 * r, h = size.height - 2 * r;
    // Time runs left to right (LTR) like every chart in the app.
    double x(DateTime d) => r + w * (d.difference(t0).inDays / span);
    double y(double v) => r + h * (1 - (v - lo) / (hi - lo));

    final line = Path();
    for (var i = 0; i < points.length; i++) {
      final p = Offset(x(DateTime.parse(points[i].date)), y(points[i].mid));
      i == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)
      ..lineTo(x(t1), size.height)
      ..lineTo(x(t0), size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kGold.withValues(alpha: 0.35), kGold.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = kGold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    if (avg > 0) {
      final ay = y(avg);
      final dash = Paint()
        ..color = AppTheme.muted
        ..strokeWidth = 1;
      for (var dx = 0.0; dx < size.width; dx += 8) {
        canvas.drawLine(Offset(dx, ay), Offset(math.min(dx + 4, size.width), ay), dash);
      }
    }
    double priceAt(DateTime d) {
      var best = points.first;
      var bestGap = 1 << 30;
      for (final p in points) {
        final g = DateTime.parse(p.date).difference(d).inDays.abs();
        if (g < bestGap) {
          bestGap = g;
          best = p;
        }
      }
      return best.mid;
    }

    for (final m in markers) {
      final d = DateTime.parse(m.date);
      if (d.isBefore(t0) || d.isAfter(t1)) continue;
      final c = Offset(x(d), y(priceAt(d)));
      canvas.drawCircle(c, r, Paint()..color = m.buy ? AppTheme.positive : kGold);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = AppTheme.bg
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GoldChartPainter old) =>
      old.points != points || old.markers.length != markers.length || old.avg != avg;
}

class _Scenario extends StatelessWidget {
  const _Scenario({required this.book});
  final GoldFundBook book;

  @override
  Widget build(BuildContext context) {
    if (book.value <= 0) return const SizedBox.shrink();
    final cash = book.cash;
    final down = book.value * 0.9 + cash, up = book.value * 1.1 + cash;
    final sens = book.total.abs() < 1 ? 0.0 : book.value * 0.1 / book.total * 100;
    Widget cell(String k, String v, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(children: [
              Text(k, style: mutedStyle(10, FontWeight.w700)),
              const SizedBox(height: 1),
              GFit(v, align: Alignment.center, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w900)),
            ]),
          ),
        );
    return Container(
      key: const ValueKey('gf-scenario'),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('اگر قیمت طلا تغییر کند…',
            style: TextStyle(color: AppTheme.title, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Row(children: [
          cell('−۱۰٪', gToman(down), AppTheme.negative),
          const SizedBox(width: 6),
          cell('امروز', gToman(book.total), AppTheme.title),
          const SizedBox(width: 6),
          cell('+۱۰٪', gToman(up), AppTheme.positive),
        ]),
        const SizedBox(height: 5),
        Text('نقد صندوق ثابت می‌ماند؛ هر ۱۰٪ حرکت طلا ≈ ${gNum(sens, decimals: 1)}٪ کل صندوق', style: mutedStyle(10)),
      ]),
    );
  }
}

class _SecHead extends StatelessWidget {
  const _SecHead({required this.eyebrow, required this.title, this.action, this.onAction});
  final String eyebrow;
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(eyebrow,
                  style: const TextStyle(color: AppTheme.positive, fontSize: 10.5, fontWeight: FontWeight.w800)),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.title, fontSize: 15, fontWeight: FontWeight.w900)),
            ]),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(minimumSize: const Size(48, 40), foregroundColor: AppTheme.positive),
              child: Text(action!),
            ),
        ]),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.sub,
    required this.amount,
    required this.amountColor,
    this.trailingSub,
    this.auto = false,
    this.onTap,
    this.divider = true,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String sub;
  final String amount;
  final Color amountColor;
  final String? trailingSub;
  final bool auto;
  final VoidCallback? onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: divider ? const Border(bottom: BorderSide(color: AppTheme.border)) : null,
          ),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15, color: iconColor),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.title, fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                  if (auto) ...[
                    const SizedBox(width: 4),
                    Flexible(
                      flex: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('خودکار',
                              maxLines: 1,
                              style: TextStyle(color: Color(0xFFCFE3D8), fontSize: 9.5, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 1),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(10)),
              ]),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                GFit(amount,
                    align: AlignmentDirectional.centerEnd,
                    style: TextStyle(color: amountColor, fontSize: 12.5, fontWeight: FontWeight.w900)),
                if (trailingSub != null)
                  GFit(trailingSub!, align: AlignmentDirectional.centerEnd, style: mutedStyle(10)),
              ]),
            ),
          ]),
        ),
      );
}

class _LotsSection extends StatelessWidget {
  const _LotsSection({required this.book, required this.calendar, required this.showAll, required this.onToggle});
  final GoldFundBook book;
  final String calendar;
  final bool showAll;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final lots = <({Trade t, GoldHolding h})>[
      for (final h in book.holdings)
        for (final t in h.lots) (t: t, h: h),
    ]..sort((a, b) => b.t.buyDate.compareTo(a.t.buyDate));
    if (lots.isEmpty) return const SizedBox.shrink();
    final oldest = lots.last.t.id;
    final shown = showAll ? lots : lots.take(5).toList();
    return Column(key: const ValueKey('gf-lots'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SecHead(
        eyebrow: 'موجودی',
        title: fa('لات‌های طلا (${lots.length})'),
        action: lots.length > 5 ? (showAll ? 'کمتر' : 'همه ›') : null,
        onAction: onToggle,
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(children: [
          for (var i = 0; i < shown.length; i++)
            Builder(builder: (_) {
              final t = shown[i].t, h = shown[i].h;
              final value = t.quantity * h.asset.currentPrice;
              final pnl = h.asset.currentPrice > 0 ? value - t.buyCost : 0.0;
              final pct = t.buyCost > 0 ? pnl / t.buyCost * 100 : 0.0;
              return _Row(
                key: ValueKey('gf-lot-${t.id}'),
                icon: Icons.diamond_outlined,
                iconColor: kGold,
                title: '${gGrams(t.quantity)} · ${h.asset.name} ${fa(h.karatLabel)}',
                sub: [
                  formatDisplayDate(t.buyDate, calendar),
                  'خرید ${gToman(t.buyPrice)}',
                  if (t.id == oldest && lots.length > 1) 'قدیمی‌ترین',
                  if (t.buyFromGoldFund) 'از صندوق',
                ].join(' · '),
                amount: gSigned(pnl),
                amountColor: toneOf(pnl),
                trailingSub: gPct(pct),
                divider: i < shown.length - 1,
              );
            }),
        ]),
      ),
    ]);
  }
}

class _CashSection extends StatelessWidget {
  const _CashSection({required this.book, required this.calendar, required this.showAll, required this.onToggle});
  final GoldFundBook book;
  final String calendar;
  final bool showAll;
  final VoidCallback onToggle;

  String _title(GoldCashRow r) {
    switch (r.kind) {
      case GoldCashRowKind.buy:
        return 'خرید ${gGrams(r.grams)} طلا';
      case GoldCashRowKind.sell:
        return 'فروش ${gGrams(r.grams)} طلا';
      case GoldCashRowKind.manual:
        final e = r.entry!;
        final base = GoldCashKind.label(e.kind);
        return e.note.isEmpty ? base : '$base · ${e.note}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = book.cashRows.reversed.toList();
    return Column(key: const ValueKey('gf-cash'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SecHead(
        eyebrow: 'نقد',
        title: 'گردش نقد صندوق',
        action: rows.length > 6 ? (showAll ? 'کمتر' : 'همه ›') : null,
        onAction: onToggle,
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'هنوز گردشی نیست. واریز نقد و خرید/فروش طلا از این صفحه اینجا با مانده ثبت می‌شود.',
                  textAlign: TextAlign.center,
                  style: mutedStyle(11),
                ),
              )
            : Column(children: [
                for (var i = 0; i < (showAll ? rows.length : math.min(6, rows.length)); i++)
                  Builder(builder: (ctx) {
                    final r = rows[i];
                    final inflow = r.amount >= 0;
                    return _Row(
                      key: ValueKey('gf-cash-${r.entry?.id ?? r.opId}'),
                      icon: r.kind == GoldCashRowKind.buy
                          ? Icons.diamond_outlined
                          : inflow
                              ? Icons.south_rounded
                              : Icons.north_rounded,
                      iconColor: inflow ? AppTheme.positive : AppTheme.negative,
                      title: _title(r),
                      auto: r.isAuto,
                      sub: '${formatDisplayDate(r.date, calendar)} · مانده ${gToman(r.balance)}',
                      amount: gSigned(r.amount),
                      amountColor: toneOf(r.amount),
                      divider: i < (showAll ? rows.length : math.min(6, rows.length)) - 1,
                      onTap: () => _openRow(ctx, r),
                    );
                  }),
              ]),
      ),
    ]);
  }

  Future<void> _openRow(BuildContext context, GoldCashRow r) async {
    final state = context.read<AppState>();
    if (r.isAuto) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(_title(r)),
            content: Text(
              '${r.assetName.isEmpty ? '' : '${r.assetName} · '}${formatDisplayDate(r.date, calendar)}\n'
              'این ردیف از معامله‌های طلای ثبت‌شده از صندوق می‌آید. برای تغییرش، معامله را در تب معاملات ویرایش یا حذف کنید.',
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('باشه'))],
          ),
        ),
      );
      return;
    }
    final e = r.entry!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(_title(r)),
          content: Text(
            '${gSigned(e.amount)} تومان · ${formatDisplayDate(e.date, calendar)}'
            '${e.withdrawalMirrored ? '\nدر تب «نقدینگی» هم ثبت شده بود؛ آن ردیف جداست و با این حذف نمی‌شود.' : ''}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بستن')),
            TextButton(
              key: const ValueKey('gf-cash-delete'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.negative),
              onPressed: state.canMutate ? () => Navigator.pop(ctx, true) : null,
              child: const Text('حذف این ردیف'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await state.deleteGoldCashEntry(e.id);
    } catch (err) {
      if (context.mounted) showUserError(context, err);
    }
  }
}

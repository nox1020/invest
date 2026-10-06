import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/services/chart_series.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/services/index_analytics.dart';
import 'package:invest/domain/services/year_nav_compare.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/home_tabs.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/pages/capital_chart_page.dart';
import 'package:invest/ui/pages/quote_detail_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/sparkline.dart';
import 'package:provider/provider.dart';

/// Portfolio home — one calm composition, same ledger, clearer hierarchy.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) => const _DashboardBody();
}

class _DashboardBody extends StatefulWidget {
  const _DashboardBody();

  @override
  State<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<_DashboardBody>
    with SingleTickerProviderStateMixin {
  bool _usd = false;
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    )..forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  Animation<double> _fade(double begin, double end) {
    return CurvedAnimation(
      parent: _enter,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  Animation<Offset> _slide(double begin, double end) {
    return Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _enter,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final usdt = state.liveUsdt ?? state.settings.usdtTmnRate;
    final snap = DashboardSnapshot.compute(
      assets: state.assets,
      openTrades: state.openTrades,
      closedTrades: state.closedTrades,
      usdtTmn: usdt,
      calendar: state.settings.calendar,
      metrics: state.metrics,
    );
    final growth = ensureChartSeries(
      state.metrics?.growthSeries ?? const [],
      todayValue: snap.marketValue,
    );
    final spark = [
      for (final p in downsampleSeries(growth, maxPoints: 40)) p.value,
    ];
    final quotes = _spotlightQuotes(state);

    if (snap.isEmpty && state.assets.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => state.refreshAll(),
        child: _EmptyDashboard(
          offline: state.offline,
          onRetry: () => state.tryGoOnline(),
        ),
      );
    }

    final anchors = indexAnchors(state.commodityIndex);
    final yoy = YearNavCompare.fromHistory(
      currentNav: snap.marketValue,
      currentYearKey: snap.yearKey,
      history: state.settings.yearNavHistory,
      liveUsdt: usdt,
    );

    Widget stage({
      required double a,
      required double b,
      required Widget child,
    }) {
      return FadeTransition(
        opacity: _fade(a, b),
        child: SlideTransition(position: _slide(a, b), child: child),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF142820),
            AppTheme.bg,
            Color(0xFF0C1511),
          ],
          stops: [0, 0.28, 1],
        ),
      ),
      child: RefreshIndicator(
        color: AppTheme.positive,
        backgroundColor: AppTheme.card,
        onRefresh: () => state.refreshAll(includeQuotes: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: shellPagePadding(),
          children: [
            stage(
              a: 0,
              b: 0.35,
              child: _StatusRibbon(
                offline: state.offline,
                lastSyncedAt: state.lastSyncedAt,
                openLots: snap.openLotCount,
                holdings: snap.holdingCount,
              ),
            ),
            const SizedBox(height: 14),
            stage(
              a: 0.05,
              b: 0.45,
              child: _NavHero(
                snap: snap,
                spark: spark,
                onOpenCharts: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CapitalChartPage(),
                    ),
                  );
                },
              ),
            ),
            if (quotes.isNotEmpty) ...[
              const SizedBox(height: 18),
              stage(
                a: 0.18,
                b: 0.55,
                child: _MarketAnchors(
                  quotes: quotes,
                  caption: anchors.caption,
                  onOpenIndex: () => openHomeTab(context, HomeTabs.index),
                ),
              ),
            ],
            const SizedBox(height: 26),
            stage(
              a: 0.28,
              b: 0.65,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionLabel(
                    title: 'سود و زیان',
                    subtitle: 'عملکرد زنده پورتفو',
                    trailing: _FxToggle(
                      usd: _usd,
                      onChanged: (v) => setState(() => _usd = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_usd && snap.usdIncomplete)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: _HintBanner(
                        text:
                            'دلار فقط با بهای خرید ثبت‌شده محاسبه می‌شود. برای لات‌های بدون دلار، «—» می‌بینید.',
                      ),
                    ),
                  _PnlLedger(snap: snap, usd: _usd, yoy: yoy),
                  if (snap.goldHoldingG > 0) ...[
                    const SizedBox(height: 12),
                    _GoldStrip(grams: snap.goldHoldingG),
                  ],
                ],
              ),
            ),
            if (snap.holdings.isNotEmpty) ...[
              const SizedBox(height: 26),
              stage(
                a: 0.4,
                b: 0.78,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SectionLabel(
                      title: 'ترکیب',
                      subtitle: 'نگاه سریع به وزن‌ها',
                    ),
                    const SizedBox(height: 12),
                    _CompositionTeaser(
                      holdings: snap.holdings,
                      total: snap.marketValue,
                      onOpenAssets: () => _openTradesTab(context),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 26),
            stage(
              a: 0.5,
              b: 0.9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SectionLabel(
                    title: 'میان‌بر',
                    subtitle: 'دسترسی سریع',
                  ),
                  const SizedBox(height: 12),
                  _LiquidityDesk(
                    snap: snap,
                    withdrawable: state.withdrawableAmount,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

void _openTradesTab(BuildContext context) {
  openHomeTab(context, HomeTabs.trades);
}

List<CommodityQuote> _spotlightQuotes(AppState state) {
  const order = ['usdt', 'gold'];
  final byId = {for (final q in state.commodityIndex) q.id: q};
  final out = <CommodityQuote>[];
  for (final id in order) {
    final q = byId[id];
    if (q?.price != null && q!.price! > 0) out.add(q);
  }
  return out;
}

class _StatusRibbon extends StatelessWidget {
  const _StatusRibbon({
    required this.offline,
    required this.lastSyncedAt,
    required this.openLots,
    required this.holdings,
  });

  final bool offline;
  final DateTime? lastSyncedAt;
  final int openLots;
  final int holdings;

  @override
  Widget build(BuildContext context) {
    final syncLabel = offline
        ? 'آفلاین'
        : lastSyncedAt == null
            ? 'همگام'
            : 'به‌روز ${_shortTime(lastSyncedAt!)}';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: offline
                ? AppTheme.negative.withValues(alpha: 0.12)
                : AppTheme.positive.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: offline
                  ? AppTheme.negative.withValues(alpha: 0.35)
                  : AppTheme.positive.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                offline ? Icons.cloud_off_outlined : Icons.check_circle_outline,
                size: 14,
                color: offline ? AppTheme.negative : AppTheme.positive,
              ),
              const SizedBox(width: 6),
              Text(
                syncLabel,
                style: TextStyle(
                  color: offline ? AppTheme.negative : AppTheme.positive,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Text(
          '$holdings دارایی · $openLots لات باز',
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  static String _shortTime(DateTime t) {
    final local = t.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _NavHero extends StatelessWidget {
  const _NavHero({
    required this.snap,
    required this.spark,
    required this.onOpenCharts,
  });

  final DashboardSnapshot snap;
  final List<double> spark;
  final VoidCallback onOpenCharts;

  @override
  Widget build(BuildContext context) {
    final usd = snap.marketValueUsd;
    final up = snap.unrealizedPnl >= 0;
    final tone = up ? AppTheme.positive : AppTheme.negative;
    final usdPnl = snap.unrealizedUsd;
    final sparkPct = sparkDeltaPct(spark);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenCharts,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Color(0xFF245A44),
                Color(0xFF17362A),
                Color(0xFF101F18),
              ],
              stops: [0, 0.5, 1],
            ),
            border: Border.all(
              color: AppTheme.border.withValues(alpha: 0.7),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                Positioned(
                  left: -40,
                  top: -50,
                  child: IgnorePointer(
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tone.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                ),
                if (spark.length >= 2)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 88,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.28,
                        child: Sparkline(
                          values: spark,
                          color: tone,
                          height: 88,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'ارزش پورتفو',
                            style: TextStyle(
                              color: AppTheme.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'میز سرمایه',
                            style: TextStyle(
                              color: AppTheme.muted.withValues(alpha: 0.95),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 12,
                            color: AppTheme.muted.withValues(alpha: 0.9),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 40,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            formatMoney(snap.marketValue),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            style: const TextStyle(
                              color: AppTheme.title,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                              letterSpacing: -0.6,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 26,
                        child: usd == null
                            ? const SizedBox.shrink()
                            : Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  formatUsd(usd),
                                  textAlign: TextAlign.right,
                                  textDirection: TextDirection.ltr,
                                  style: const TextStyle(
                                    color: Color(0xFFE8CF7A),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _HeroStat(
                              label: 'سود باز',
                              value: formatCompactToman(
                                snap.unrealizedPnl,
                                showSign: true,
                              ),
                              sub: formatPct(snap.unrealizedPct),
                              tone: tone,
                            ),
                          ),
                          Expanded(
                            child: _HeroStat(
                              label: 'دلار',
                              value: usdPnl == null
                                  ? '—'
                                  : formatUsd(
                                      usdPnl,
                                      compact: true,
                                      showSign: true,
                                    ),
                              tone: usdPnl == null
                                  ? AppTheme.muted
                                  : (usdPnl >= 0
                                      ? AppTheme.positive
                                      : AppTheme.negative),
                              ltr: usdPnl != null,
                            ),
                          ),
                          Expanded(
                            child: spark.length >= 2
                                ? _HeroStat(
                                    label: 'روند',
                                    value: formatPct(sparkPct),
                                    tone: sparkPct >= 0
                                        ? AppTheme.positive
                                        : AppTheme.negative,
                                  )
                                : _HeroStat(
                                    label: 'بهای تمام‌شده',
                                    value: formatCompactToman(snap.costBasis),
                                    tone: AppTheme.muted,
                                  ),
                          ),
                        ],
                      ),
                      if (spark.length >= 2) ...[
                        const SizedBox(height: 14),
                        Sparkline(values: spark, color: tone, height: 40),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.tone,
    this.sub,
    this.ltr = false,
  });

  final String label;
  final String value;
  final String? sub;
  final Color tone;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppTheme.muted.withValues(alpha: 0.95),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            value,
            textDirection: ltr ? TextDirection.ltr : null,
            style: TextStyle(
              color: tone,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(
            sub!,
            style: TextStyle(
              color: tone.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _MarketAnchors extends StatelessWidget {
  const _MarketAnchors({
    required this.quotes,
    this.caption,
    this.onOpenIndex,
  });

  final List<CommodityQuote> quotes;
  final String? caption;
  final VoidCallback? onOpenIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(
          title: 'لنگرها',
          subtitle: 'بازار مرجع',
          actionLabel: onOpenIndex == null ? null : 'شاخص',
          onAction: onOpenIndex,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < quotes.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: _AnchorTile(quote: quotes[i])),
            ],
          ],
        ),
        if (caption != null && caption!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            caption!,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _AnchorTile extends StatelessWidget {
  const _AnchorTile({required this.quote});
  final CommodityQuote quote;

  @override
  Widget build(BuildContext context) {
    final up = quote.isUp;
    final down = quote.isDown;
    final tone = up
        ? AppTheme.positive
        : down
            ? AppTheme.negative
            : AppTheme.muted;
    return Material(
      color: AppTheme.card.withValues(alpha: 0.86),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => openQuoteDetail(context, quote),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border.withValues(alpha: 0.85)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Icon(quote.icon, size: 16, color: tone),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      quote.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                quote.formatPrice(compact: true),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppTheme.title,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                quote.change24h == null ? '—' : formatPct(quote.change24h!),
                style: TextStyle(
                  color: tone,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PnlLedger extends StatelessWidget {
  const _PnlLedger({
    required this.snap,
    required this.usd,
    required this.yoy,
  });

  final DashboardSnapshot snap;
  final bool usd;
  final YearNavCompare yoy;

  @override
  Widget build(BuildContext context) {
    final yearSpec = yoy.hasPrior
        ? _PnlSpec(
            title: 'رشد سال',
            caption: 'نسبت به پایان ${yoy.priorYearKey}',
            toman: yoy.deltaToman,
            usd: yoy.deltaUsd,
            pct: yoy.pct,
          )
        : _PnlSpec(
            title: snap.yearKey.isEmpty ? 'امسال' : 'امسال ${snap.yearKey}',
            caption:
                'سود تحقق‌یافته · برای مقایسه، پایان سال قبل را در میز سرمایه بزنید',
            toman: snap.yearRealizedPnl,
            usd: snap.yearRealizedUsd,
          );
    final items = [
      _PnlSpec(
        title: 'سود باز',
        caption: 'علامت‌گذاری به بازار',
        toman: snap.unrealizedPnl,
        usd: snap.unrealizedUsd,
        pct: snap.unrealizedPct,
      ),
      _PnlSpec(
        title: 'تحقق‌یافته',
        caption: 'تمام معاملات بسته‌شده',
        toman: snap.realizedPnl,
        usd: snap.realizedUsd,
      ),
      yearSpec,
    ];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: Column(
        key: ValueKey(usd),
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _PnlLedgerRow(spec: items[i], showUsd: usd),
          ],
        ],
      ),
    );
  }
}

class _PnlSpec {
  const _PnlSpec({
    required this.title,
    required this.caption,
    required this.toman,
    this.usd,
    this.pct,
  });
  final String title;
  final String caption;
  final double toman;
  final double? usd;
  final double? pct;
}

class _PnlLedgerRow extends StatelessWidget {
  const _PnlLedgerRow({required this.spec, required this.showUsd});
  final _PnlSpec spec;
  final bool showUsd;

  @override
  Widget build(BuildContext context) {
    final missing = showUsd && spec.usd == null;
    final value = showUsd ? spec.usd : spec.toman;
    final tone = missing || value == null
        ? AppTheme.muted
        : value > 0
            ? AppTheme.positive
            : value < 0
                ? AppTheme.negative
                : AppTheme.title;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.card.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 42,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  spec.title,
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  spec.caption,
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  missing
                      ? '—'
                      : showUsd
                          ? formatUsd(spec.usd!, compact: true, showSign: true)
                          : formatCompactToman(spec.toman, showSign: true),
                  style: TextStyle(
                    color: tone,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              if (!showUsd && spec.pct != null) ...[
                const SizedBox(height: 3),
                Text(
                  formatPct(spec.pct!),
                  style: TextStyle(
                    color: tone,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GoldStrip extends StatelessWidget {
  const _GoldStrip({required this.grams});
  final double grams;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            const Color(0xFFE0C46A).withValues(alpha: 0.16),
            AppTheme.card,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE0C46A).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.diamond_outlined, color: Color(0xFFE0C46A), size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'موجودی طلا · پوشش تورم',
              textAlign: TextAlign.right,
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ),
          Text(
            formatGrams(grams),
            style: const TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompositionTeaser extends StatelessWidget {
  const _CompositionTeaser({
    required this.holdings,
    required this.total,
    required this.onOpenAssets,
  });

  final List<({Asset asset, HoldingMetrics metrics})> holdings;
  final double total;
  final VoidCallback onOpenAssets;

  @override
  Widget build(BuildContext context) {
    if (holdings.isEmpty) return const SizedBox.shrink();
    final top = holdings.first;
    final share = total <= 0 ? 0.0 : top.metrics.marketValue / total * 100;
    final kind = detectAssetKind(
      name: top.asset.name,
      symbol: top.asset.symbol,
      notes: top.asset.notes,
    );
    final label = top.asset.symbol.trim().isEmpty
        ? top.asset.name
        : top.asset.symbol;
    return Material(
      color: AppTheme.card.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpenAssets,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border.withValues(alpha: 0.85)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 13,
                    color: AppTheme.muted.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${holdings.length} موقعیت باز',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: AppTheme.title,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'بیشترین وزن: $label · ${formatNumber(share, decimals: 1)}٪ · ${kind.label}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: kind.color.withValues(alpha: 0.18),
                    child: Icon(kind.icon, color: kind.color, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (share / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: AppTheme.border,
                  color: kind.color,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'جزئیات تخصیص در تب معاملات',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: AppTheme.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiquidityDesk extends StatelessWidget {
  const _LiquidityDesk({required this.snap, required this.withdrawable});

  final DashboardSnapshot snap;
  final double withdrawable;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LiquidityCell(
            label: 'لات باز',
            value: '${snap.openLotCount}',
            hint: 'موقعیت فعال',
            onTap: () => _openTradesTab(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LiquidityCell(
            label: 'بسته‌شده',
            value: '${snap.closedCount}',
            hint: 'تاریخچه',
            onTap: () => _openTradesTab(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LiquidityCell(
            label: 'قابل برداشت',
            value: formatCompactToman(withdrawable),
            hint: 'سهمیه سالانه',
            emphasize: true,
            onTap: () => openHomeTab(context, HomeTabs.withdrawals),
          ),
        ),
      ],
    );
  }
}

class _LiquidityCell extends StatelessWidget {
  const _LiquidityCell({
    required this.label,
    required this.value,
    required this.hint,
    this.onTap,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final String hint;
  final VoidCallback? onTap;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.card.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: emphasize
                  ? const Color(0xFFE0C46A).withValues(alpha: 0.35)
                  : AppTheme.border.withValues(alpha: 0.85),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: emphasize ? const Color(0xFFE0C46A) : AppTheme.title,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hint,
                style: const TextStyle(color: AppTheme.muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.title,
    this.subtitle,
    this.trailing,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                title,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppTheme.title,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: AppTheme.muted.withValues(alpha: 0.95),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.positive,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(actionLabel!),
          ),
        if (trailing != null) ...[
          const SizedBox(width: 4),
          trailing!,
        ],
      ],
    );
  }
}

class _FxToggle extends StatelessWidget {
  const _FxToggle({required this.usd, required this.onChanged});
  final bool usd;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FxChip(
            label: 'تومان',
            selected: !usd,
            onTap: () => onChanged(false),
          ),
          _FxChip(
            label: 'دلار',
            selected: usd,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _FxChip extends StatelessWidget {
  const _FxChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE0C46A).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE0C46A).withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: const TextStyle(
          color: AppTheme.muted,
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard({
    required this.offline,
    required this.onRetry,
  });

  final bool offline;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: shellPagePadding(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.16),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 30, 22, 30),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF245A44), Color(0xFF13251C)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              Icon(
                offline
                    ? Icons.cloud_off_outlined
                    : Icons.account_balance_outlined,
                size: 42,
                color: AppTheme.muted,
              ),
              const SizedBox(height: 16),
              Text(
                offline
                    ? 'هنوز داده‌ای برای نمایش آفلاین ذخیره نشده است'
                    : 'پورتفوی خالی است',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.title,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                offline
                    ? 'پس از اتصال، دارایی‌ها اینجا جمع می‌شوند.'
                    : 'دارایی را از تب معاملات ثبت کنید تا ارزش، سود و ترکیب اینجا دیده شود.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.muted,
                  height: 1.45,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              if (offline)
                OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('تلاش برای اتصال'),
                )
              else
                OutlinedButton(
                  onPressed: () => openHomeTab(context, HomeTabs.trades),
                  child: const Text('رفتن به معاملات'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/services/chart_series.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/services/index_analytics.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/home_tabs.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/pages/asset_detail_page.dart';
import 'package:invest/ui/pages/capital_chart_page.dart';
import 'package:invest/ui/pages/quote_detail_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/allocation_donut.dart';
import 'package:invest/ui/widgets/sparkline.dart';
import 'package:provider/provider.dart';

/// Economist-style portfolio desk: same data, clearer hierarchy.
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
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic));
    _enter.forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
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

    return RefreshIndicator(
      onRefresh: () => state.refreshAll(includeQuotes: true),
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: shellPagePadding(),
            children: [
              _StatusRibbon(
                offline: state.offline,
                lastSyncedAt: state.lastSyncedAt,
                openLots: snap.openLotCount,
                holdings: snap.holdingCount,
              ),
              const SizedBox(height: 12),
              _NavHero(
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
              if (quotes.isNotEmpty) ...[
                const SizedBox(height: 16),
                _MarketTape(
                  quotes: quotes,
                  caption: anchors.caption,
                ),
              ],
              const SizedBox(height: 20),
              _SectionLabel(
                eyebrow: 'عملکرد',
                title: 'سود و زیان',
                trailing: _FxToggle(
                  usd: _usd,
                  onChanged: (v) => setState(() => _usd = v),
                ),
              ),
              const SizedBox(height: 10),
              if (_usd && snap.usdIncomplete)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: _HintBanner(
                    text:
                        'دلار فقط با بهای خرید ثبت‌شده محاسبه می‌شود. برای لات‌های بدون دلار، «—» می‌بینید.',
                  ),
                ),
              _PnlLedger(snap: snap, usd: _usd),
              if (snap.goldHoldingG > 0) ...[
                const SizedBox(height: 10),
                _GoldStrip(grams: snap.goldHoldingG),
              ],
              if (snap.holdings.isNotEmpty) ...[
                const SizedBox(height: 22),
                _SectionLabel(
                  eyebrow: 'ساختار',
                  title: 'ترکیب دارایی',
                  actionLabel: 'همه',
                  onAction: () => _openTradesTab(context),
                ),
                const SizedBox(height: 10),
                _AllocationPanel(
                  holdings: snap.holdings,
                  total: snap.marketValue,
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < snap.holdings.take(4).length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _HoldingRow(
                    asset: snap.holdings[i].asset,
                    metrics: snap.holdings[i].metrics,
                    share: snap.marketValue <= 0
                        ? 0
                        : snap.holdings[i].metrics.marketValue /
                            snap.marketValue,
                    usdt: usdt,
                    rank: i + 1,
                  ),
                ],
              ],
              const SizedBox(height: 22),
              const _SectionLabel(
                eyebrow: 'نقدینگی',
                title: 'فعالیت',
              ),
              const SizedBox(height: 10),
              _LiquidityDesk(
                snap: snap,
                withdrawable: state.withdrawableAmount,
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

void _openTradesTab(BuildContext context) {
  openHomeTab(context, HomeTabs.trades);
}

List<CommodityQuote> _spotlightQuotes(AppState state) {
  const order = ['usdt', 'gold', 'btc', 'eth'];
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
        _MiniTag(
          icon: offline ? Icons.cloud_off_outlined : Icons.sync_outlined,
          label: syncLabel,
          tone: offline ? AppTheme.negative : AppTheme.muted,
        ),
        const Spacer(),
        Text(
          '$holdings دارایی · $openLots لات باز',
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 11,
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

class _MiniTag extends StatelessWidget {
  const _MiniTag({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: tone),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: tone,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
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
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Color(0xFF1C3F30),
                Color(0xFF13251C),
                Color(0xFF101C16),
              ],
              stops: [0, 0.55, 1],
            ),
            border: Border.all(color: AppTheme.border),
          ),
          child: Stack(
            children: [
              if (spark.length >= 2)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.22,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 56),
                        child: Sparkline(
                          values: spark,
                          color: tone,
                          height: 120,
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.bg.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: const Text(
                            'NAV',
                            style: TextStyle(
                              color: AppTheme.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'ارزش پورتفو',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: AppTheme.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.north_east_rounded,
                          size: 16,
                          color: AppTheme.muted.withValues(alpha: 0.8),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        formatMoney(snap.marketValue),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        style: const TextStyle(
                          color: AppTheme.title,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    if (usd != null) ...[
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          formatUsd(usd),
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Color(0xFFE0C46A),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: AppTheme.bg.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.border.withValues(alpha: 0.85),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _DeltaCell(
                              label: 'سود باز',
                              value: formatCompactToman(
                                snap.unrealizedPnl,
                                showSign: true,
                              ),
                              sub: formatPct(snap.unrealizedPct),
                              tone: tone,
                            ),
                          ),
                          _VRule(color: AppTheme.border.withValues(alpha: 0.9)),
                          if (usdPnl != null) ...[
                            Expanded(
                              child: _DeltaCell(
                                label: 'دلار',
                                value: formatUsd(
                                  usdPnl,
                                  compact: true,
                                  showSign: true,
                                ),
                                tone: usdPnl >= 0
                                    ? AppTheme.positive
                                    : AppTheme.negative,
                                ltr: true,
                              ),
                            ),
                            _VRule(
                              color: AppTheme.border.withValues(alpha: 0.9),
                            ),
                          ],
                          if (spark.length >= 2)
                            Expanded(
                              child: _DeltaCell(
                                label: 'روند',
                                value: formatPct(sparkPct),
                                tone: sparkPct >= 0
                                    ? AppTheme.positive
                                    : AppTheme.negative,
                              ),
                            )
                          else
                            Expanded(
                              child: _DeltaCell(
                                label: 'بهای تمام‌شده',
                                value: formatCompactToman(snap.costBasis),
                                tone: AppTheme.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (spark.length >= 2) ...[
                      const SizedBox(height: 12),
                      Sparkline(values: spark, color: tone, height: 44),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeltaCell extends StatelessWidget {
  const _DeltaCell({
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
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            value,
            textDirection: ltr ? TextDirection.ltr : null,
            style: TextStyle(
              color: tone,
              fontSize: 13,
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

class _VRule extends StatelessWidget {
  const _VRule({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: color,
    );
  }
}

class _MarketTape extends StatelessWidget {
  const _MarketTape({required this.quotes, this.caption});

  final List<CommodityQuote> quotes;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel(
          eyebrow: 'بازار',
          title: 'لنگرهای قیمت',
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < quotes.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, thickness: 1, color: AppTheme.border),
                _TapeRow(quote: quotes[i]),
              ],
            ],
          ),
        ),
        if (caption != null && caption!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            caption!,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _TapeRow extends StatelessWidget {
  const _TapeRow({required this.quote});
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
    return InkWell(
      onTap: () => openQuoteDetail(context, quote),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          children: [
            Icon(quote.icon, size: 16, color: tone),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                quote.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  quote.formatPrice(compact: true),
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                if (quote.change24h != null)
                  Text(
                    formatPct(quote.change24h!),
                    style: TextStyle(
                      color: tone,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PnlLedger extends StatelessWidget {
  const _PnlLedger({required this.snap, required this.usd});

  final DashboardSnapshot snap;
  final bool usd;

  @override
  Widget build(BuildContext context) {
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
      _PnlSpec(
        title: snap.yearKey.isEmpty ? 'امسال' : 'امسال ${snap.yearKey}',
        caption: 'سود تحقق‌یافته دوره',
        toman: snap.yearRealizedPnl,
        usd: snap.yearRealizedUsd,
      ),
    ];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: Container(
        key: ValueKey(usd),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, thickness: 1, color: AppTheme.border),
              _PnlLedgerRow(spec: items[i], showUsd: usd),
            ],
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  spec.title,
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.caption,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
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
                    fontSize: 15,
                  ),
                ),
              ),
              if (!showUsd && spec.pct != null) ...[
                const SizedBox(height: 2),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            const Color(0xFFE0C46A).withValues(alpha: 0.12),
            AppTheme.card,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE0C46A).withValues(alpha: 0.28),
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

class _AllocationPanel extends StatelessWidget {
  const _AllocationPanel({required this.holdings, required this.total});

  final List<({Asset asset, HoldingMetrics metrics})> holdings;
  final double total;

  @override
  Widget build(BuildContext context) {
    final slices = <AllocationSlice>[];
    for (final h in holdings) {
      if (h.metrics.marketValue <= 0) continue;
      final kind = detectAssetKind(
        name: h.asset.name,
        symbol: h.asset.symbol,
        notes: h.asset.notes,
      );
      slices.add(
        AllocationSlice(
          label: h.asset.symbol.trim().isEmpty ? h.asset.name : h.asset.symbol,
          share: total <= 0 ? 0 : h.metrics.marketValue / total,
          color: kind.color,
        ),
      );
    }
    final top = slices.isEmpty ? null : slices.first;
    final topShare = top == null ? 0.0 : top.share * 100;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Row(
            textDirection: TextDirection.ltr,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  AllocationDonut(slices: slices, size: 104),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${holdings.length}',
                        style: const TextStyle(
                          color: AppTheme.title,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const Text(
                        'موقعیت',
                        style: TextStyle(
                          color: AppTheme.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (top != null) ...[
                      const Text(
                        'بیشترین وزن',
                        style: TextStyle(
                          color: AppTheme.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${top.label} · ${formatNumber(topShare, decimals: 1)}٪',
                        style: const TextStyle(
                          color: AppTheme.title,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    for (final s in slices.take(4))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: s.color,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${s.label}  ${formatNumber(s.share * 100, decimals: 1)}٪',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({
    required this.asset,
    required this.metrics,
    required this.share,
    required this.usdt,
    required this.rank,
  });

  final Asset asset;
  final HoldingMetrics metrics;
  final double share;
  final double? usdt;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final kind = detectAssetKind(
      name: asset.name,
      symbol: asset.symbol,
      notes: asset.notes,
    );
    final usd = metrics.marketValueUsd(usdt);
    final tone =
        metrics.unrealizedPnl >= 0 ? AppTheme.positive : AppTheme.negative;
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => openAssetDetail(context, asset: asset),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kind.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        color: kind.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          asset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: AppTheme.title,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${formatNumber(share * 100, decimals: 1)}٪ از پورتفو',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        usd != null
                            ? formatUsd(usd, compact: true)
                            : formatCompactToman(metrics.marketValue),
                        style: const TextStyle(
                          color: AppTheme.title,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        formatPct(metrics.unrealizedPnlPct),
                        style: TextStyle(
                          color: tone,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: share.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: AppTheme.border,
                  color: kind.color.withValues(alpha: 0.85),
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
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _LiquidityCell(
                label: 'لات باز',
                value: '${snap.openLotCount}',
                hint: 'موقعیت فعال',
                onTap: () => _openTradesTab(context),
              ),
            ),
            Container(width: 1, color: AppTheme.border),
            Expanded(
              child: _LiquidityCell(
                label: 'بسته‌شده',
                value: '${snap.closedCount}',
                hint: 'تاریخچه',
                onTap: () => _openTradesTab(context),
              ),
            ),
            Container(width: 1, color: AppTheme.border),
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
        ),
      ),
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
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
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: emphasize ? const Color(0xFFE0C46A) : AppTheme.title,
                fontWeight: FontWeight.w800,
                fontSize: 14,
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
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.eyebrow,
    required this.title,
    this.trailing,
    this.actionLabel,
    this.onAction,
  });

  final String eyebrow;
  final String title;
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
                eyebrow,
                style: TextStyle(
                  color: AppTheme.muted.withValues(alpha: 0.9),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppTheme.title,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
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
        borderRadius: BorderRadius.circular(10),
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
        borderRadius: BorderRadius.circular(10),
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
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF1C3F30), Color(0xFF13251C)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              Icon(
                offline
                    ? Icons.cloud_off_outlined
                    : Icons.account_balance_outlined,
                size: 40,
                color: AppTheme.muted,
              ),
              const SizedBox(height: 14),
              Text(
                offline
                    ? 'هنوز داده‌ای برای نمایش آفلاین ذخیره نشده است'
                    : 'پورتفوی خالی است',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.title,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 18),
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

import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/services/chart_series.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/holding_metrics.dart';
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

class _DashboardBodyState extends State<_DashboardBody> {
  bool _usd = false;

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

    return RefreshIndicator(
      onRefresh: () => state.refreshAll(includeQuotes: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: shellPagePadding(),
        children: [
          _HeroNetWorth(
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
            const SizedBox(height: 14),
            _QuoteStrip(quotes: quotes),
          ],
          const SizedBox(height: 18),
          _SectionHead(
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
          _PnlGrid(snap: snap, usd: _usd),
          if (snap.goldHoldingG > 0) ...[
            const SizedBox(height: 10),
            _GoldBar(grams: snap.goldHoldingG),
          ],
          if (snap.holdings.isNotEmpty) ...[
            const SizedBox(height: 18),
            _SectionHead(
              title: 'ترکیب دارایی',
              actionLabel: 'همه',
              onAction: () => _openTradesTab(context),
            ),
            const SizedBox(height: 10),
            _AllocationCard(holdings: snap.holdings, total: snap.marketValue),
            const SizedBox(height: 10),
            for (var i = 0; i < snap.holdings.take(4).length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _HoldingTile(
                asset: snap.holdings[i].asset,
                metrics: snap.holdings[i].metrics,
                share: snap.marketValue <= 0
                    ? 0
                    : snap.holdings[i].metrics.marketValue / snap.marketValue,
                usdt: usdt,
              ),
            ],
          ],
          const SizedBox(height: 18),
          const _SectionHead(title: 'فعالیت'),
          const SizedBox(height: 10),
          _ActivityRow(snap: snap, withdrawable: state.withdrawableAmount),
        ],
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
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
        Icon(
          offline ? Icons.cloud_off_outlined : Icons.account_balance_wallet_outlined,
          size: 44,
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
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          offline
              ? 'پس از اتصال، دارایی‌ها اینجا جمع می‌شوند.'
              : 'دارایی را از تب معاملات ثبت کنید تا ارزش، سود و نمودار اینجا دیده شود.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.muted, height: 1.4),
        ),
        const SizedBox(height: 18),
        if (offline)
          Center(
            child: OutlinedButton(
              onPressed: onRetry,
              child: const Text('تلاش برای اتصال'),
            ),
          )
        else
          Center(
            child: OutlinedButton(
              onPressed: () => openHomeTab(context, HomeTabs.trades),
              child: const Text('رفتن به معاملات'),
            ),
          ),
      ],
    );
  }
}

class _HeroNetWorth extends StatelessWidget {
  const _HeroNetWorth({
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
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF1A3A2C), Color(0xFF12201A)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.show_chart_rounded, size: 18, color: AppTheme.muted),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'ارزش پورتفو',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                formatCompactToman(snap.marketValue),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppTheme.title,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              if (usd != null) ...[
                const SizedBox(height: 4),
                Text(
                  formatUsd(usd, compact: true),
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: Color(0xFFE8C547),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Pill(
                    text:
                        '${formatCompactToman(snap.unrealizedPnl, showSign: true)}  ${formatPct(snap.unrealizedPct)}',
                    color: tone,
                  ),
                  if (usdPnl != null)
                    _Pill(
                      text: formatUsd(usdPnl, compact: true, showSign: true),
                      color: usdPnl >= 0 ? AppTheme.positive : AppTheme.negative,
                    ),
                  if (spark.length >= 2)
                    _Pill(
                      text: 'روند ${formatPct(sparkPct)}',
                      color: sparkPct >= 0 ? AppTheme.positive : AppTheme.negative,
                    ),
                ],
              ),
              if (spark.length >= 2) ...[
                const SizedBox(height: 10),
                Sparkline(
                  values: spark,
                  color: tone,
                  height: 52,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuoteStrip extends StatelessWidget {
  const _QuoteStrip({required this.quotes});
  final List<CommodityQuote> quotes;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: quotes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final q = quotes[i];
          final up = q.isUp;
          final down = q.isDown;
          final tone = up
              ? AppTheme.positive
              : down
                  ? AppTheme.negative
                  : AppTheme.muted;
          return Material(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => openQuoteDetail(context, q),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 148,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Icon(q.icon, size: 14, color: tone),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            q.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      q.formatPrice(compact: true),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.title,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    if (q.change24h != null)
                      Text(
                        formatPct(q.change24h!),
                        style: TextStyle(
                          color: tone,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PnlGrid extends StatelessWidget {
  const _PnlGrid({required this.snap, required this.usd});

  final DashboardSnapshot snap;
  final bool usd;

  @override
  Widget build(BuildContext context) {
    final items = [
      _PnlSpec(
        title: 'سود باز',
        toman: snap.unrealizedPnl,
        usd: snap.unrealizedUsd,
        pct: snap.unrealizedPct,
      ),
      _PnlSpec(
        title: 'تحقق‌یافته',
        toman: snap.realizedPnl,
        usd: snap.realizedUsd,
      ),
      _PnlSpec(
        title: snap.yearKey.isEmpty ? 'امسال' : 'امسال ${snap.yearKey}',
        toman: snap.yearRealizedPnl,
        usd: snap.yearRealizedUsd,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _PnlTile(spec: items[i], showUsd: usd)),
        ],
      ],
    );
  }
}

class _PnlSpec {
  const _PnlSpec({
    required this.title,
    required this.toman,
    this.usd,
    this.pct,
  });
  final String title;
  final double toman;
  final double? usd;
  final double? pct;
}

class _PnlTile extends StatelessWidget {
  const _PnlTile({required this.spec, required this.showUsd});
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
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            spec.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              missing
                  ? '—'
                  : showUsd
                      ? formatUsd(spec.usd!, compact: true, showSign: true)
                      : formatCompactToman(spec.toman, showSign: true),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: tone,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          if (!showUsd && spec.pct != null) ...[
            const SizedBox(height: 4),
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
    );
  }
}

class _GoldBar extends StatelessWidget {
  const _GoldBar({required this.grams});
  final double grams;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.diamond_outlined, color: Color(0xFFE8C547), size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'موجودی طلا',
              textAlign: TextAlign.right,
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ),
          Text(
            formatGrams(grams),
            style: const TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllocationCard extends StatelessWidget {
  const _AllocationCard({required this.holdings, required this.total});

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
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          AllocationDonut(slices: slices, size: 92),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in slices.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: s.color,
                            shape: BoxShape.circle,
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
    );
  }
}

class _HoldingTile extends StatelessWidget {
  const _HoldingTile({
    required this.asset,
    required this.metrics,
    required this.share,
    required this.usdt,
  });

  final Asset asset;
  final HoldingMetrics metrics;
  final double share;
  final double? usdt;

  @override
  Widget build(BuildContext context) {
    final kind = detectAssetKind(
      name: asset.name,
      symbol: asset.symbol,
      notes: asset.notes,
    );
    final usd = metrics.marketValueUsd(usdt);
    final tone = metrics.unrealizedPnl >= 0 ? AppTheme.positive : AppTheme.negative;
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => openAssetDetail(context, asset: asset),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: kind.color.withValues(alpha: 0.18),
                child: Icon(kind.icon, color: kind.color, size: 16),
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
                      style: const TextStyle(color: AppTheme.muted, fontSize: 11),
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
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.snap, required this.withdrawable});

  final DashboardSnapshot snap;
  final double withdrawable;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            label: 'لات باز',
            value: '${snap.openLotCount}',
            onTap: () => _openTradesTab(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            label: 'بسته‌شده',
            value: '${snap.closedCount}',
            onTap: () => _openTradesTab(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            label: 'قابل برداشت',
            value: formatCompactToman(withdrawable),
            onTap: () => openHomeTab(context, HomeTabs.withdrawals),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                label,
                style: const TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.title,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({
    required this.title,
    this.trailing,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Widget? trailing;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
        if (trailing != null) trailing!,
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
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppTheme.accent;
          return AppTheme.card;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return AppTheme.muted;
        }),
      ),
      segments: const [
        ButtonSegment(value: false, label: Text('تومان')),
        ButtonSegment(value: true, label: Text('دلار')),
      ],
      selected: {usd},
      onSelectionChanged: (v) => onChanged(v.first),
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
        color: const Color(0xFFE8C547).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8C547).withValues(alpha: 0.28)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

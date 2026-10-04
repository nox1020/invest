import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/services/dashboard_pnl.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/services/withdrawal_allowance.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/allocation_donut.dart';
import 'package:invest/ui/widgets/dual_currency_chart.dart';
import 'package:invest/ui/widgets/sparkline.dart';
import 'package:provider/provider.dart';

String _plainPct(num value) => '${formatNumber(value, decimals: 1)}٪';

/// Economist capital desk — opened from the dashboard NAV hero.
class CapitalChartPage extends StatefulWidget {
  const CapitalChartPage({super.key});

  @override
  State<CapitalChartPage> createState() => _CapitalChartPageState();
}

class _CapitalChartPageState extends State<CapitalChartPage>
    with SingleTickerProviderStateMixin {
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
    final calendar = state.settings.calendar;
    final snap = DashboardSnapshot.compute(
      assets: state.assets,
      openTrades: state.openTrades,
      closedTrades: state.closedTrades,
      usdtTmn: usdt,
      calendar: calendar,
      metrics: state.metrics,
    );
    final growth = state.capitalGrowthSeries;
    final year = state.yearRealizedChartSeries;
    final allowance = state.withdrawalAllowance;
    final spark = [for (final p in growth) p.value];
    final sparkPct = sparkDeltaPct(spark);
    final lifetimePct = DashboardCurrencyPnl.totalPnlPct(
      totalPnl: snap.totalPnl,
      assets: state.assets,
      openTrades: state.openTrades,
      closedTrades: state.closedTrades,
    );
    final usdNav = snap.marketValueUsd;
    final usdYear =
        tomanToUsd(snap.yearRealizedPnl, usdt);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('میز سرمایه'),
      ),
      body: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
            children: [
              _StatusRibbon(
                offline: state.offline,
                holdings: snap.holdingCount,
                openLots: snap.openLotCount,
                yearLabel: WithdrawalAllowance.yearCaption(
                  snap.yearKey,
                  calendar,
                ),
              ),
              const SizedBox(height: 12),
              _NavHero(
                snap: snap,
                usdNav: usdNav,
                spark: spark,
                sparkPct: sparkPct,
                lifetimePct: lifetimePct,
              ),
              const SizedBox(height: 20),
              const _SectionLabel(
                eyebrow: 'ترازنامه',
                title: 'ارزش و سود',
              ),
              const SizedBox(height: 10),
              _BalanceSheet(snap: snap, lifetimePct: lifetimePct),
              const SizedBox(height: 20),
              const _SectionLabel(
                eyebrow: 'ترکیب',
                title: 'تخصیص دارایی',
              ),
              const SizedBox(height: 10),
              _AllocationPanel(holdings: snap.holdings),
              if (snap.goldHoldingG > 0) ...[
                const SizedBox(height: 12),
                _GoldSleeve(grams: snap.goldHoldingG),
              ],
              const SizedBox(height: 20),
              const _SectionLabel(
                eyebrow: 'نقدینگی',
                title: 'ظرفیت برداشت',
              ),
              const SizedBox(height: 10),
              _LiquidityPanel(allowance: allowance),
              const SizedBox(height: 20),
              const _SectionLabel(
                eyebrow: 'روند',
                title: 'مسیر سرمایه',
              ),
              const SizedBox(height: 10),
              _ChartCard(
                title: 'ارزش کل سرمایه',
                caption: spark.length >= 2
                    ? 'تغییر دوره ${formatPct(sparkPct)}'
                    : 'سری روزانه از اسنپ‌شات‌های معتبر',
                child: DualCurrencyChart(
                  points: growth,
                  calendar: calendar,
                  usdtRate: usdt,
                ),
              ),
              const SizedBox(height: 16),
              _ChartCard(
                title: 'سود تحقق‌یافته سال',
                caption: [
                  if (snap.yearKey.isNotEmpty)
                    WithdrawalAllowance.yearCaption(snap.yearKey, calendar),
                  if (usdYear != null) formatUsd(usdYear, showSign: true),
                ].join(' · '),
                child: year.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 36),
                        child: Text(
                          'در این سال معامله بسته‌شده‌ای نیست',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.muted),
                        ),
                      )
                    : DualCurrencyChart(
                        points: year,
                        calendar: calendar,
                        usdtRate: usdt,
                        lineColor: const Color(0xFF5B8DEF),
                      ),
              ),
              const SizedBox(height: 16),
              const _Footnote(
                text:
                    'NAV از موجودی زنده محاسبه می‌شود. بازده کل روی سرمایهٔ طول عمر '
                    '(خرید باز + بسته) است. گرم طلا معادل ۱۸ عیار گزارش می‌شود.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRibbon extends StatelessWidget {
  const _StatusRibbon({
    required this.offline,
    required this.holdings,
    required this.openLots,
    required this.yearLabel,
  });

  final bool offline;
  final int holdings;
  final int openLots;
  final String yearLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          offline ? Icons.cloud_off_outlined : Icons.insights_outlined,
          size: 14,
          color: offline ? AppTheme.negative : AppTheme.muted,
        ),
        const SizedBox(width: 6),
        Text(
          offline ? 'آفلاین' : 'میز سرمایه',
          style: TextStyle(
            color: offline ? AppTheme.negative : AppTheme.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Text(
          '$yearLabel · $holdings دارایی · $openLots لات',
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.title,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _NavHero extends StatelessWidget {
  const _NavHero({
    required this.snap,
    required this.usdNav,
    required this.spark,
    required this.sparkPct,
    required this.lifetimePct,
  });

  final DashboardSnapshot snap;
  final double? usdNav;
  final List<double> spark;
  final double sparkPct;
  final double lifetimePct;

  @override
  Widget build(BuildContext context) {
    final up = snap.totalPnl >= 0;
    final tone = up ? AppTheme.positive : AppTheme.negative;
    return Container(
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
                  opacity: 0.18,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Sparkline(
                      values: spark,
                      color: tone,
                      height: 110,
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
                const Row(
                  children: [
                    _Pill(text: 'NAV'),
                    SizedBox(width: 8),
                    Expanded(
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
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  formatMoney(snap.marketValue),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                if (usdNav != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    formatUsd(usdNav!),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Color(0xFFE8C547),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.bg.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.border.withValues(alpha: 0.85),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _HeroStat(
                          label: 'سود کل',
                          value: formatCompactToman(
                            snap.totalPnl,
                            showSign: true,
                          ),
                          tone: tone,
                        ),
                      ),
                      _VRule(),
                      Expanded(
                        child: _HeroStat(
                          label: 'بازده عمر',
                          value: formatPct(lifetimePct),
                          tone: tone,
                        ),
                      ),
                      _VRule(),
                      Expanded(
                        child: _HeroStat(
                          label: 'روند',
                          value: spark.length >= 2
                              ? formatPct(sparkPct)
                              : '—',
                          tone: spark.length < 2
                              ? AppTheme.muted
                              : (sparkPct >= 0
                                  ? AppTheme.positive
                                  : AppTheme.negative),
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

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bg.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.muted,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
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
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tone,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _VRule extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: AppTheme.border.withValues(alpha: 0.9),
    );
  }
}

class _BalanceSheet extends StatelessWidget {
  const _BalanceSheet({required this.snap, required this.lifetimePct});

  final DashboardSnapshot snap;
  final double lifetimePct;

  @override
  Widget build(BuildContext context) {
    final unrealTone =
        snap.unrealizedPnl >= 0 ? AppTheme.positive : AppTheme.negative;
    final realTone =
        snap.realizedPnl >= 0 ? AppTheme.positive : AppTheme.negative;
    final totalTone =
        snap.totalPnl >= 0 ? AppTheme.positive : AppTheme.negative;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          _LedgerRow(
            label: 'بهای تمام‌شده',
            value: formatMoney(snap.costBasis),
            caption: 'موجودی باز · با کارمزد خرید',
            tone: AppTheme.muted,
            showDivider: true,
          ),
          _LedgerRow(
            label: 'ارزش بازار (NAV)',
            value: formatMoney(snap.marketValue),
            caption: snap.marketValueUsd == null
                ? 'علامت زنده تومانی'
                : 'معادل ${formatUsd(snap.marketValueUsd!)}',
            tone: AppTheme.title,
            showDivider: true,
          ),
          _LedgerRow(
            label: 'سود شناور',
            value: formatMoney(snap.unrealizedPnl, showSign: true),
            caption: formatPct(snap.unrealizedPct),
            tone: unrealTone,
            showDivider: true,
          ),
          _LedgerRow(
            label: 'سود تحقق‌یافته',
            value: formatMoney(snap.realizedPnl, showSign: true),
            caption: 'سال ${snap.yearKey}: ${formatMoney(snap.yearRealizedPnl, showSign: true)}',
            tone: realTone,
            showDivider: true,
          ),
          _LedgerRow(
            label: 'سود کل / بازده عمر',
            value: formatMoney(snap.totalPnl, showSign: true),
            caption: 'بازده ${formatPct(lifetimePct)} روی سرمایه طول عمر',
            tone: totalTone,
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.label,
    required this.value,
    required this.caption,
    required this.tone,
    required this.showDivider,
  });

  final String label;
  final String value;
  final String caption;
  final Color tone;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppTheme.border))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: tone,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.title,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllocationPanel extends StatelessWidget {
  const _AllocationPanel({required this.holdings});

  final List<({Asset asset, HoldingMetrics metrics})> holdings;

  @override
  Widget build(BuildContext context) {
    if (holdings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Text(
          'موقعیت بازی برای تخصیص نیست',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.muted),
        ),
      );
    }

    final total =
        holdings.fold<double>(0, (s, h) => s + h.metrics.marketValue);
    final slices = <AllocationSlice>[];
    final rows = <_AllocRowData>[];
    for (final h in holdings) {
      final mv = h.metrics.marketValue;
      if (mv <= 0) continue;
      final kind = detectAssetKind(
        name: h.asset.name,
        symbol: h.asset.symbol,
        notes: h.asset.notes,
      );
      final label = h.asset.symbol.trim().isEmpty
          ? h.asset.name
          : h.asset.symbol;
      final share = total <= 0 ? 0.0 : mv / total;
      slices.add(AllocationSlice(label: label, share: share, color: kind.color));
      rows.add(
        _AllocRowData(
          label: label,
          name: h.asset.name,
          share: share,
          value: mv,
          color: kind.color,
          pnl: h.metrics.unrealizedPnl,
        ),
      );
    }
    final top = rows.take(6).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              AllocationDonut(slices: slices, size: 96),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${holdings.length} موقعیت',
                      style: const TextStyle(
                        color: AppTheme.title,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      top.isEmpty
                          ? '—'
                          : 'بزرگ‌ترین سهم: ${top.first.label} ${_plainPct(top.first.share * 100)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatMoney(total),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppTheme.title,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppTheme.border),
            _AllocRow(data: top[i]),
          ],
        ],
      ),
    );
  }
}

class _AllocRowData {
  const _AllocRowData({
    required this.label,
    required this.name,
    required this.share,
    required this.value,
    required this.color,
    required this.pnl,
  });

  final String label;
  final String name;
  final double share;
  final double value;
  final Color color;
  final double pnl;
}

class _AllocRow extends StatelessWidget {
  const _AllocRow({required this.data});
  final _AllocRowData data;

  @override
  Widget build(BuildContext context) {
    final pnlTone = data.pnl >= 0 ? AppTheme.positive : AppTheme.negative;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatCompactToman(data.value),
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatCompactToman(data.pnl, showSign: true),
                  style: TextStyle(
                    color: pnlTone,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  data.name,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: data.share.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: AppTheme.border,
                    color: data.color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _plainPct(data.share * 100),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoldSleeve extends StatelessWidget {
  const _GoldSleeve({required this.grams});
  final double grams;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.diamond_outlined, color: Color(0xFFE0C46A), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'آستین طلا (معادل ۱۸ عیار)',
                  style: TextStyle(
                    color: AppTheme.title,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatGrams(grams),
                  style: const TextStyle(
                    color: Color(0xFFE8C547),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
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

class _LiquidityPanel extends StatelessWidget {
  const _LiquidityPanel({required this.allowance});
  final WithdrawalAllowance allowance;

  @override
  Widget build(BuildContext context) {
    final used = allowance.usedAnnualFraction;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _LiqCell(
                  label: 'قابل برداشت',
                  value: formatCompactToman(allowance.available),
                  tone: AppTheme.positive,
                ),
              ),
              Expanded(
                child: _LiqCell(
                  label: 'باقیمانده سقف',
                  value: formatCompactToman(allowance.remainingAnnual),
                  tone: AppTheme.title,
                ),
              ),
              Expanded(
                child: _LiqCell(
                  label: 'برداشت امسال',
                  value: formatCompactToman(allowance.yearWithdrawn),
                  tone: AppTheme.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: used.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppTheme.border,
              color: used > 0.85 ? AppTheme.negative : AppTheme.positive,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'مصرف کوتای ${allowance.annualPct}٪ · '
            '${WithdrawalAllowance.yearCaption(allowance.yearKey, allowance.calendar)}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _LiqCell extends StatelessWidget {
  const _LiqCell({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.muted, fontSize: 10),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tone,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.child,
    this.caption,
  });

  final String title;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          if (caption != null && caption!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(
        color: AppTheme.muted,
        fontSize: 11,
        height: 1.45,
      ),
    );
  }
}

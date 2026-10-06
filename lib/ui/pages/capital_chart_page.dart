import 'package:flutter/material.dart';
import 'package:invest/domain/models/year_nav_entry.dart';
import 'package:invest/domain/services/dashboard_pnl.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/withdrawal_allowance.dart';
import 'package:invest/domain/services/year_nav_compare.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dual_currency_chart.dart';
import 'package:invest/ui/widgets/sparkline.dart';
import 'package:invest/ui/widgets/user_error.dart';
import 'package:provider/provider.dart';

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
              const SizedBox(height: 20),
              const _SectionLabel(
                eyebrow: 'مقایسه',
                title: 'پایان سال‌های گذشته',
              ),
              const SizedBox(height: 10),
              _YearNavDesk(
                history: state.settings.yearNavHistory,
                currentNav: snap.marketValue,
                currentYearKey: snap.yearKey,
                calendar: calendar,
                usdt: usdt,
                readOnly: state.readOnlyOffline,
              ),
              const SizedBox(height: 16),
              const _Footnote(
                text:
                    'NAV از موجودی زنده محاسبه می‌شود. برای مقایسهٔ سالانه، فقط '
                    'یک عدد پایان‌سال (تومان) کافی است؛ معادل دلاری از نرخ تتر '
                    'محاسبه می‌شود. تخصیص در تب معاملات و برداشت در تب برداشت است.',
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

class _YearNavDesk extends StatelessWidget {
  const _YearNavDesk({
    required this.history,
    required this.currentNav,
    required this.currentYearKey,
    required this.calendar,
    required this.usdt,
    required this.readOnly,
  });

  final List<YearNavEntry> history;
  final double currentNav;
  final String currentYearKey;
  final String calendar;
  final double? usdt;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final yoy = YearNavCompare.fromHistory(
      currentNav: currentNav,
      currentYearKey: currentYearKey,
      history: history,
      liveUsdt: usdt,
    );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          if (yoy.hasPrior)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'رشد نسبت به پایان ${yoy.priorYearKey}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatMoney(yoy.deltaToman, showSign: true),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: yoy.deltaToman > 0
                                ? AppTheme.positive
                                : yoy.deltaToman < 0
                                    ? AppTheme.negative
                                    : AppTheme.title,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            formatPct(yoy.pct),
                            if (yoy.deltaUsd != null)
                              formatUsd(yoy.deltaUsd!, showSign: true),
                          ].join(' · '),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 18, 14, 10),
              child: Text(
                'مثلاً سال ۱۴۰۴ → ۱ میلیارد تومان. فقط یک عدد؛ دلار خودکار است.',
                textAlign: TextAlign.right,
                style: TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.4),
              ),
            )
          else
            for (var i = 0; i < history.length; i++) ...[
              if (i > 0 || yoy.hasPrior)
                const Divider(height: 1, thickness: 1, color: AppTheme.border),
              _YearNavRow(
                entry: history[i],
                usdt: usdt,
                calendar: calendar,
                readOnly: readOnly,
              ),
            ],
          const Divider(height: 1, thickness: 1, color: AppTheme.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: readOnly
                    ? null
                    : () => _showYearNavEditor(context, usdt: usdt),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('افزودن سال گذشته'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _YearNavRow extends StatelessWidget {
  const _YearNavRow({
    required this.entry,
    required this.usdt,
    required this.calendar,
    required this.readOnly,
  });

  final YearNavEntry entry;
  final double? usdt;
  final String calendar;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final usd = entry.navUsdWith(usdt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
      child: Row(
        children: [
          if (!readOnly)
            IconButton(
              tooltip: 'حذف',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('حذف سال ${entry.yearKey}؟'),
                    content: const Text(
                      'این عدد پایان‌سال از تاریخچه حذف می‌شود.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('انصراف'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('حذف'),
                      ),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                try {
                  await context.read<AppState>().deleteYearNav(entry.yearKey);
                } catch (e) {
                  if (context.mounted) showUserError(context, e);
                }
              },
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          Expanded(
            child: InkWell(
              onTap: readOnly
                  ? null
                  : () => _showYearNavEditor(
                        context,
                        usdt: usdt,
                        existing: entry,
                      ),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      WithdrawalAllowance.yearCaption(entry.yearKey, calendar),
                      style: const TextStyle(
                        color: AppTheme.title,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatMoney(entry.navToman),
                      style: const TextStyle(
                        color: AppTheme.title,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      usd == null
                          ? 'دلار: نرخ تتر نیست'
                          : formatUsd(usd),
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showYearNavEditor(
  BuildContext context, {
  required double? usdt,
  YearNavEntry? existing,
}) async {
  final state = context.read<AppState>();
  final currentYear = yearPeriodKeyHint(state);
  final prior = YearNavList.priorYearKey(currentYear);
  final yearCtrl = TextEditingController(
    text: existing?.yearKey.isNotEmpty == true
        ? existing!.yearKey
        : (prior.isNotEmpty ? prior : ''),
  );
  final navCtrl = TextEditingController(
    text: existing == null
        ? ''
        : existing.navToman
            .toStringAsFixed(0)
            .replaceAll(RegExp(r'\.0+$'), ''),
  );

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(existing == null ? 'افزودن سال گذشته' : 'ویرایش سال'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: yearCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: 'سال',
                hintText: prior.isEmpty ? '۱۴۰۴' : prior,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: navCtrl,
              keyboardType: TextInputType.text,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: 'ارزش پایان سال (تومان)',
                hintText: '۱ میلیارد یا 1000000000',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              usdt == null || usdt <= 0
                  ? 'نرخ تتر در دسترس نیست؛ فقط تومان ذخیره می‌شود.'
                  : 'معادل دلاری خودکار با تتر ${formatMoney(usdt)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ذخیره'),
          ),
        ],
      );
    },
  );

  final yearRaw = yearCtrl.text;
  final navRaw = navCtrl.text;
  yearCtrl.dispose();
  navCtrl.dispose();
  if (ok != true || !context.mounted) return;

  final year = YearNavList.normalizeYearKey(yearRaw);
  final nav = parseTomanAmount(navRaw);
  if (year.isEmpty || nav == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سال و یک عدد تومان معتبر وارد کنید.')),
      );
    }
    return;
  }

  try {
    await state.upsertYearNav(yearKey: year, navToman: nav);
  } catch (e) {
    if (context.mounted) showUserError(context, e);
  }
}

String yearPeriodKeyHint(AppState state) {
  final fromMetrics = state.metrics?.yearKey;
  if (fromMetrics != null && fromMetrics.isNotEmpty) return fromMetrics;
  return yearPeriodKey(todayIso(), state.settings.calendar);
}

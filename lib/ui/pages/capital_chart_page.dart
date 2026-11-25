import 'package:flutter/material.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/domain/models/year_nav_entry.dart';
import 'package:invest/domain/services/connection_status.dart';
import 'package:invest/domain/services/portfolio_trend.dart';
import 'package:invest/domain/services/portfolio_valuation.dart';
import 'package:invest/domain/services/dashboard_pnl.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/withdrawal_allowance.dart';
import 'package:invest/domain/services/year_nav_compare.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:invest/ui/widgets/dual_currency_chart.dart';
import 'package:invest/ui/pages/gold_fund_page.dart';
import 'package:invest/ui/widgets/portfolio_value_breakdown.dart';
import 'package:invest/ui/widgets/sparkline.dart' show sparkDeltaPct;
import 'package:invest/ui/widgets/user_error.dart';
import 'package:provider/provider.dart';

/// «ارزش پورتفو» (formerly «میز سرمایه») — opened from the compact dashboard
/// value card. Holds every value detail: connection/rate/freshness, the
/// hero, «ترکیب ارزش», the balance sheet (with contracting kept outside the
/// total), charts and past year-ends.
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
      checks: state.checks,
      goldFundCash: state.goldFundCash,
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
    final usdYear = tomanToUsd(snap.yearRealizedPnl, usdt);
    // Same 30-day number as the dashboard card (one trend in the app).
    final trend = portfolioTrend30(
      snap: snap,
      growthSeries: state.metrics?.growthSeries ?? const [],
      openTrades: state.openTrades,
      closedTrades: state.closedTrades,
    );
    final projStore = ProjectsStore.instance;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ارزش پورتفو', key: ValueKey('vp-title')),
            Text('میز سرمایه',
                style: TextStyle(color: AppTheme.muted, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
        bottom: state.refreshing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  key: ValueKey('vp-loading'),
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: AppTheme.positive,
                ),
              )
            : null,
      ),
      body: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: RefreshIndicator(
            key: const ValueKey('vp-refresh'),
            onRefresh: () => state.refreshAll(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
              children: [
                _StatusRibbon(
                  status: state.connectionStatus,
                  lastSyncedAt: state.lastSyncedAt,
                  usdt: snap.usdtTmn,
                  usdIsLive: state.usdtIsLive && !state.offline,
                  pricesAsOf: state.pricesAsOf,
                  holdings: snap.holdingCount,
                  openLots: snap.openLotCount,
                  yearLabel: WithdrawalAllowance.yearCaption(
                    snap.yearKey,
                    calendar,
                  ),
                ),
                const SizedBox(height: 12),
                if (snap.holdingCount == 0 && !snap.chequeNav.affectsNav)
                  const Padding(
                    key: ValueKey('vp-empty'),
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'هنوز دارایی ثبت نشده — از تب معاملات دارایی اضافه کنید تا ارزش و ترکیب اینجا دیده شود.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.muted, fontSize: 12.5),
                    ),
                  ),
                _NavHero(
                  snap: snap,
                  trend: trend,
                  lifetimePct: lifetimePct,
                ),
                if (snap.holdingCount > 0 || (snap.valuation?.goldFundCash ?? 0).abs() >= 0.5) ...[
                  const SizedBox(height: 20),
                  const _SectionLabel(
                    eyebrow: 'ترکیب',
                    title: 'ترکیب ارزش',
                  ),
                  const SizedBox(height: 10),
                  PortfolioValueBreakdown(
                    snap: snap,
                    onOpenGoldFund: () => openGoldFundPage(context),
                  ),
                ],
                const SizedBox(height: 20),
                const _SectionLabel(
                  eyebrow: 'ترازنامه',
                  title: 'ارزش و سود',
                ),
                const SizedBox(height: 10),
                ListenableBuilder(
                  listenable: projStore,
                  builder: (context, _) => _BalanceSheet(
                    snap: snap,
                    lifetimePct: lifetimePct,
                    trend: trend,
                    projects: projStore.loaded && projStore.snap.hasData
                        ? projStore.snap.totals
                        : null,
                  ),
                ),
                const SizedBox(height: 20),
                const _SectionLabel(
                  eyebrow: 'روند',
                  title: 'مسیر سرمایه',
                ),
                const SizedBox(height: 10),
                _ChartCard(
                  title: 'ارزش دارایی‌ها · بدون چک',
                  // Whole chart period (raw values), labelled apart from the
                  // like-for-like «روند ۳۰ روز» in the hero.
                  caption: spark.length >= 2
                      ? 'تغییر کل دورهٔ نمودار ${formatPct(sparkPct)} · با خرید و فروش'
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
                      'NAV از موجودی زنده به‌اضافهٔ چک دریافتی باز و منهای چک پرداختی باز '
                      'محاسبه می‌شود. «روند ۳۰ روز» ارزش دارایی‌ها (بدون چک) را با کسر خرید و فروش '
                      'همان ۳۰ روز می‌سنجد؛ نمودار، تغییر خام کل دوره را نشان می‌دهد. برای مقایسهٔ سالانه، ارزش '
                      'پایان‌سال (تومان) و در صورت نیاز دلار دستی را ثبت کنید. تخصیص در تب معاملات است.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Connection, last sync, USDT rate (live/stored) and price freshness.
class _StatusRibbon extends StatelessWidget {
  const _StatusRibbon({
    required this.status,
    required this.lastSyncedAt,
    required this.usdt,
    required this.usdIsLive,
    required this.pricesAsOf,
    required this.holdings,
    required this.openLots,
    required this.yearLabel,
  });

  final AppConnectionStatus status;
  final DateTime? lastSyncedAt;
  final double? usdt;
  final bool usdIsLive;
  final DateTime? pricesAsOf;
  final int holdings;
  final int openLots;
  final String yearLabel;

  @override
  Widget build(BuildContext context) {
    final stale = pricesAsOf == null ||
        DateTime.now().difference(pricesAsOf!) > const Duration(hours: 1);
    final conn = [
      status.label,
      if (lastSyncedAt != null) 'همگام ${agoFa(lastSyncedAt!)}',
    ].join(' · ');
    return Column(
      key: const ValueKey('vp-status'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            DashTag(conn,
                key: const ValueKey('vp-conn'),
                color: status.color,
                icon: status.isOnline ? Icons.circle : Icons.cloud_off_outlined),
            if (usdt != null)
              DashTag(
                fa('${usdIsLive ? 'نرخ زندهٔ تتر' : 'نرخ ذخیره‌شدهٔ تتر'} ${formatNumber(usdt!)}'),
                key: const ValueKey('pv-rate'),
                color: usdIsLive ? kUsd : AppTheme.muted,
              ),
            DashTag(
              pricesAsOf == null ? 'قیمت‌ها: نامعلوم' : 'قیمت‌ها: ${agoFa(pricesAsOf!)}',
              key: const ValueKey('pv-fresh'),
              color: stale ? kAmber : AppTheme.muted,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          fa('$yearLabel · $holdings دارایی · $openLots لات باز'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
    required this.trend,
    required this.lifetimePct,
  });

  final DashboardSnapshot snap;
  final PortfolioTrend trend;
  final double lifetimePct;

  @override
  Widget build(BuildContext context) {
    final up = snap.totalPnl >= 0;
    final tone = up ? AppTheme.positive : AppTheme.negative;
    final usdNav = snap.marketValueUsd;
    final usdPnl = snap.unrealizedUsd;
    final trendPct = trend.pct;
    final unpriced = snap.valuation?.unpriced ?? const [];
    return Container(
      key: const ValueKey('vp-hero'),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _Pill(text: 'NAV'),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (snap.valuation?.goldFundCash ?? 0).abs() >= 0.5
                      ? 'ارزش کل · با چک‌ها و نقد صندوق طلا'
                      : 'ارزش کل · با چک‌های باز',
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
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              fa(formatMoney(snap.marketValue)),
              key: const ValueKey('vp-nav'),
              maxLines: 1,
              style: const TextStyle(
                color: AppTheme.title,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
          if (CurrencyMode.isUsd) ...[
            const SizedBox(height: 4),
            Text(
              fa(formatMoney(snap.marketValue, forceToman: true)),
              key: const ValueKey('vp-nav-toman'),
              textAlign: TextAlign.right,
              style: mutedStyle(13, FontWeight.w700),
            ),
          ] else if (usdNav != null) ...[
            const SizedBox(height: 4),
            Text(
              '≈ ${formatUsd(usdNav)}',
              key: const ValueKey('vp-nav-usd'),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: kUsd,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 14),
          _statBox([
            _HeroStat(
              key: const ValueKey('vp-open-pnl'),
              label: 'سود باز',
              value: faSigned(formatCompactToman(snap.unrealizedPnl, showSign: true)),
              sub: faSigned(formatPct(snap.unrealizedPct)),
              tone: toneOf(snap.unrealizedPnl),
            ),
            _HeroStat(
              key: const ValueKey('vp-usd-pnl'),
              label: 'سود دلاری',
              value: usdPnl == null ? '—' : signFix(formatUsd(usdPnl, showSign: true)),
              sub: usdPnl == null ? 'نرخ تتر نامعلوم' : 'با نرخ روز خرید',
              tone: usdPnl == null ? AppTheme.muted : toneOf(usdPnl),
            ),
            _HeroStat(
              key: const ValueKey('vp-trend'),
              label: fa('روند ${trend.days} روز'),
              value: trendPct == null ? '—' : faSigned(formatPct(trendPct)),
              sub: trendPct == null
                  ? 'دادهٔ کافی نیست'
                  : fa('از ${formatCompactToman(trend.baseValue!)}'),
              tone: trendPct == null ? AppTheme.muted : toneOf(trendPct),
            ),
          ]),
          const SizedBox(height: 8),
          _statBox([
            _HeroStat(
              key: const ValueKey('vp-total-pnl'),
              label: 'سود کل',
              value: faSigned(formatCompactToman(snap.totalPnl, showSign: true)),
              tone: tone,
            ),
            _HeroStat(
              key: const ValueKey('vp-lifetime'),
              label: 'بازده عمر',
              value: faSigned(formatPct(lifetimePct)),
              tone: tone,
            ),
          ]),
          if (unpriced.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('vp-unpriced'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: kAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kAmber.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: kAmber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      fa('${unpriced.length} دارایی بدون قیمت زنده و خارج از جمع: '
                          '${unpriced.map((a) => a.name).join('، ')}'),
                      style: const TextStyle(color: kAmber, fontSize: 11.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statBox(List<Widget> stats) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.bg.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border.withValues(alpha: 0.85)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) _VRule(),
              Expanded(child: stats[i]),
            ],
          ],
        ),
      );
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
    super.key,
    required this.label,
    required this.value,
    required this.tone,
    this.sub,
  });

  final String label;
  final String value;
  final Color tone;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
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
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.muted, fontSize: 9.5),
          ),
        ],
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
  const _BalanceSheet({
    required this.snap,
    required this.lifetimePct,
    required this.trend,
    this.projects,
  });

  final DashboardSnapshot snap;
  final double lifetimePct;
  final PortfolioTrend trend;

  /// Contracting totals — shown under the sheet, never added to NAV.
  final ProjectTotals? projects;

  @override
  Widget build(BuildContext context) {
    final unrealTone =
        snap.unrealizedPnl >= 0 ? AppTheme.positive : AppTheme.negative;
    final realTone =
        snap.realizedPnl >= 0 ? AppTheme.positive : AppTheme.negative;
    final totalTone =
        snap.totalPnl >= 0 ? AppTheme.positive : AppTheme.negative;
    final showFlows = trend.pct != null && trend.netFlows.abs() >= 1;
    final fundCash = snap.valuation?.goldFundCash ?? 0;
    return Container(
      key: const ValueKey('vp-balance'),
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
            caption: [
              if (snap.chequeNav.affectsNav) 'شامل چک‌های باز',
              if (fundCash.abs() >= 0.5) 'شامل نقد صندوق طلا',
              snap.marketValueUsd == null
                  ? 'علامت زنده تومانی'
                  : 'معادل ${formatUsd(snap.marketValueUsd!)}',
            ].join(' · '),
            tone: AppTheme.title,
            showDivider: true,
          ),
          if (snap.chequeNav.affectsNav)
            _LedgerRow(
              label: 'چک‌های باز',
              value: formatMoney(snap.chequeNav.net, showSign: true),
              caption:
                  'دریافتی ${formatMoney(snap.chequeNav.pendingReceivable)}'
                  ' · پرداختی ${formatMoney(snap.chequeNav.pendingPayable)}'
                  ' · وصول‌شده و برگشتی حساب نمی‌شود',
              tone: snap.chequeNav.net >= 0
                  ? AppTheme.positive
                  : AppTheme.negative,
              showDivider: true,
            ),
          if (fundCash.abs() >= 0.5)
            _LedgerRow(
              key: const ValueKey('vp-gold-fund-cash'),
              label: 'نقد صندوق طلا',
              value: formatMoney(fundCash),
              caption: 'پول کنار گذاشته برای طلا · جزو روند ۳۰ روزه نیست',
              tone: fundCash >= 0 ? AppTheme.positive : AppTheme.negative,
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
            showDivider: showFlows || projects != null,
          ),
          if (showFlows)
            _LedgerRow(
              key: const ValueKey('vp-net-flows'),
              label: 'خرید/فروش خالص در ${trend.days} روز',
              value: formatMoney(trend.netFlows, showSign: true),
              caption: trend.netFlows > 0
                  ? 'خرید بیشتر از فروش · از «روند ${trend.days} روز» کسر شده'
                  : 'فروش بیشتر از خرید · به «روند ${trend.days} روز» افزوده شده',
              tone: AppTheme.muted,
              showDivider: projects != null,
            ),
          if (projects != null) _ProjectsBlock(totals: projects!),
        ],
      ),
    );
  }
}

class _ProjectsBlock extends StatelessWidget {
  const _ProjectsBlock({required this.totals});
  final ProjectTotals totals;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('vp-projects'),
      color: AppTheme.bg.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Text(
              'پیمانکاری (خارج از جمع ارزش)',
              textAlign: TextAlign.right,
              style: TextStyle(color: kGold, fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          _LedgerRow(
            label: 'سود تحقق‌یافتهٔ پروژه‌ها',
            value: formatMoney(totals.realized, showSign: true),
            caption: fa('${totals.finishedCount} پروژهٔ تمام‌شده'),
            tone: toneOf(totals.realized),
            showDivider: true,
          ),
          _LedgerRow(
            label: 'سود مورد انتظار',
            value: formatMoney(totals.expected, showSign: true),
            caption: fa('${totals.activeCount} پروژهٔ فعال'),
            tone: AppTheme.muted,
            showDivider: false,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Text(
              'سود پیمانکاری جدا گزارش می‌شود و به NAV یا سود کل اضافه نمی‌شود.',
              textAlign: TextAlign.right,
              style: TextStyle(color: AppTheme.muted, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    super.key,
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
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.title,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
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
    final currentUsd = tomanToUsd(currentNav, usdt);
    final yoy = YearNavCompare.fromHistory(
      currentNav: currentNav,
      currentYearKey: currentYearKey,
      history: history,
      liveUsdt: usdt,
      currentNavUsd: currentUsd,
    );
    final growth = yearNavGrowthSeries(
      history: history,
      currentNav: currentNav,
      currentYearKey: currentYearKey,
      calendar: calendar,
      liveUsdt: usdt,
      currentNavUsd: currentUsd,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (growth.length >= 2) ...[
          _ChartCard(
            title: 'رشد سالانه',
            caption: yoy.hasPrior
                ? 'نسبت به پایان ${yoy.priorYearKey}: ${formatPct(yoy.pct)}'
                : 'تومان و دلار از پایان‌سال‌های ثبت‌شده',
            child: DualCurrencyChart(
              points: growth,
              calendar: calendar,
              usdtRate: usdt,
              lineColor: const Color(0xFF5B8DEF),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
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
                    'سال و ارزش تومان را بزنید؛ دلار را دستی وارد کنید یا خالی '
                    'بگذارید تا از تتر محاسبه شود.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: AppTheme.muted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                )
              else
                for (var i = 0; i < history.length; i++) ...[
                  if (i > 0 || yoy.hasPrior)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.border,
                    ),
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
        ),
      ],
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
    final manual = entry.navUsd != null && entry.navUsd! > 0;
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
                          ? 'دلار: ثبت نشده'
                          : '${formatUsd(usd)}${manual ? ' · دستی' : ' · از تتر'}',
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
  final initialUsd = existing?.navUsdWith(usdt);
  final usdCtrl = TextEditingController(
    text: initialUsd == null
        ? ''
        : (initialUsd >= 100
            ? initialUsd.toStringAsFixed(0)
            : initialUsd.toStringAsFixed(2)),
  );

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(existing == null ? 'افزودن سال گذشته' : 'ویرایش سال'),
        content: SingleChildScrollView(
          child: Column(
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
              const SizedBox(height: 12),
              TextField(
                controller: usdCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'معادل دلار (اختیاری)',
                  hintText: usdt != null && usdt > 0
                      ? 'خالی = از تتر ${formatMoney(usdt)}'
                      : 'مثلاً 10000',
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'دلار را دستی بنویسید یا خالی بگذارید تا از نرخ تتر محاسبه شود.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ],
          ),
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
  final usdRaw = usdCtrl.text;
  yearCtrl.dispose();
  navCtrl.dispose();
  usdCtrl.dispose();
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
  final usdText = usdRaw.trim();
  final usd = usdText.isEmpty ? null : parseUsdAmount(usdText);
  if (usdText.isNotEmpty && usd == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('معادل دلار نامعتبر است.')),
      );
    }
    return;
  }

  try {
    await state.upsertYearNav(
      yearKey: year,
      navToman: nav,
      navUsd: usd,
      clearNavUsd: usdText.isEmpty,
    );
  } catch (e) {
    if (context.mounted) showUserError(context, e);
  }
}

String yearPeriodKeyHint(AppState state) {
  final fromMetrics = state.metrics?.yearKey;
  if (fromMetrics != null && fromMetrics.isNotEmpty) return fromMetrics;
  return yearPeriodKey(todayIso(), state.settings.calendar);
}

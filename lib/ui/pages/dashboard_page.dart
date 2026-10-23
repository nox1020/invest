import 'package:flutter/material.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/index_analytics.dart';
import 'package:invest/domain/services/year_nav_compare.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/home_tabs.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/pages/biz_page.dart';
import 'package:invest/ui/pages/capital_chart_page.dart';
import 'package:invest/ui/pages/checks_page.dart';
import 'package:invest/ui/pages/quote_detail_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/ui/pages/projects_page.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/domain/services/dashboard_digest.dart';
import 'package:invest/domain/services/portfolio_valuation.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/ui/pages/pwo_page.dart';
import 'package:invest/ui/pages/trades_page.dart';
import 'package:invest/ui/pages/withdrawals_page.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:invest/ui/widgets/dashboard_sections.dart';
import 'package:invest/ui/widgets/portfolio_value_card.dart';
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
    return ListenableBuilder(
      listenable: Listenable.merge(
          [PwoStore.instance, BizStore.instance, ProjectsStore.instance]),
      builder: (context, _) => _buildPage(context, state),
    );
  }

  Widget _buildPage(BuildContext context, AppState state) {
    final usdt = state.liveUsdt ?? state.settings.usdtTmnRate;
    final snap = DashboardSnapshot.compute(
      assets: state.assets,
      openTrades: state.openTrades,
      closedTrades: state.closedTrades,
      usdtTmn: usdt,
      calendar: state.settings.calendar,
      metrics: state.metrics,
      checks: state.checks,
    );
    final valuation = snap.valuation!;
    final today = todayIso();
    final trend = PortfolioTrend.window(
      series: state.metrics?.growthSeries ?? const [],
      todayValue: snap.holdingsValue,
      today: today,
      openTrades: state.openTrades,
      closedTrades: state.closedTrades,
    );
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

    final pwoStore = PwoStore.instance;
    final pwo = pwoStore.loaded ? PwoMonthSummary.of(pwoStore.ledger) : null;
    final biz = BizStore.instance;
    final bizHas = biz.loaded && biz.snap.raw.isNotEmpty;
    final projStore = ProjectsStore.instance;
    final projects = projStore.loaded && projStore.snap.hasData
        ? projStore.snap.totals
        : null;
    final alerts = dashboardAlerts(
      checks: state.checks,
      today: today,
      unpriced: valuation.unpriced,
      pwo: pwo,
      pwoMonthLabel: pwo == null ? '' : pwoMonthLabel(pwo.month),
      bizMismatchMonths: bizHas ? bizMismatchMonths(biz.snap) : 0,
    );
    final upcoming = upcomingCheques(state.checks, today: today);
    final anchors = indexAnchors(state.commodityIndex);
    final yoy = YearNavCompare.fromHistory(
      currentNav: snap.marketValue,
      currentYearKey: snap.yearKey,
      history: state.settings.yearNavHistory,
      liveUsdt: usdt,
    );
    final calendar = state.settings.calendar;

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

    void openPwo() => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const PwoPage()));
    void openBiz() => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const BizPage()));

    void openAlert(DashAlert a) {
      switch (a.kind) {
        case DashAlertKind.chequeOverdue:
        case DashAlertKind.chequeBounced:
        case DashAlertKind.chequeDueSoon:
          openChecksPage(context);
        case DashAlertKind.pwoBelowTarget:
          openPwo();
        case DashAlertKind.unpriced:
          _openTradesTab(context);
        case DashAlertKind.bizMismatch:
          openBiz();
      }
    }

    final syncAt = state.lastSyncedAt;
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
              child: Row(children: [
                const Text('داشبورد',
                    style: TextStyle(
                        color: AppTheme.title,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      fa(formatDisplayDate(today, calendar)
                          .replaceFirst(RegExp(r'^0'), '')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mutedStyle(11.5)),
                ),
                Flexible(
                  child: DashTag(
                    state.offline
                        ? 'آفلاین'
                        : syncAt == null
                            ? 'همگام'
                            : 'به‌روز ${hhmm(syncAt)}',
                    key: const ValueKey('dash-sync'),
                    color:
                        state.offline ? AppTheme.negative : AppTheme.positive,
                    icon: state.offline
                        ? Icons.cloud_off_outlined
                        : Icons.cloud_done_rounded,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            stage(
              a: 0.05,
              b: 0.45,
              child: PortfolioValueCard(
                snap: snap,
                trend: trend,
                usdIsLive: state.usdtIsLive,
                pricesAsOf: state.pricesAsOf,
                offline: state.offline,
                lastSyncedAt: syncAt,
                projects: projects,
                refreshing: state.refreshing,
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
              const SizedBox(height: 12),
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
            if (alerts.isNotEmpty) ...[
              DashSection(
                title: 'نیازمند توجه',
                subtitle: fa('${alerts.length} مورد'),
                icon: Icons.notifications_active_rounded,
              ),
              DashAlertsList(alerts: alerts, onOpen: openAlert),
            ],
            stage(
              a: 0.28,
              b: 0.65,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DashSection(
                    title: 'سود و زیان',
                    subtitle: 'عملکرد زنده پورتفو',
                    icon: Icons.insights_rounded,
                    trailing: _FxToggle(
                      usd: _usd,
                      onChanged: (v) => setState(() => _usd = v),
                    ),
                  ),
                  if (_usd && snap.usdIncomplete)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: _HintBanner(
                        text:
                            'دلار فقط با بهای خرید ثبت‌شده محاسبه می‌شود. برای لات‌های بدون دلار، «—» می‌بینید.',
                      ),
                    ),
                  _PnlLedger(
                      snap: snap,
                      usd: _usd,
                      yoy: yoy,
                      projects: projects,
                      usdt: usdt ?? 0),
                ],
              ),
            ),
            DashSection(
              title: 'برداشت و PWO',
              subtitle: pwo == null
                  ? 'سهمیه سالانه برداشت'
                  : '${pwoMonthLabel(pwo.month)}'
                      '${pwo.target > 0 ? ' · هدف ماهانه ${fa(formatCompactToman(pwo.target))}' : ''}',
              icon: Icons.account_balance_wallet_rounded,
              actionLabel: 'جدول PWO',
              onAction: openPwo,
            ),
            DashPwoCard(
              summary: pwo,
              withdrawable: state.withdrawableAmount,
              capBaseLabel: 'سهمیه سالانه',
              onOpenPwo: openPwo,
              onOpenWithdrawals: () =>
                  openHomeTab(context, HomeTabs.withdrawals),
            ),
            DashSection(
              title: 'مدیریت چک‌ها',
              subtitle: 'دریافتی، بدهی و سررسید',
              icon: Icons.receipt_long_rounded,
              actionLabel: 'همه',
              onAction: () => openChecksPage(context),
            ),
            const ChecksDashboardCard(digits: fa),
            if (upcoming.isNotEmpty) ...[
              const SizedBox(height: 8),
              DashUpcomingCheques(
                key: const ValueKey('dash-upcoming'),
                items: upcoming,
                calendar: calendar,
                onTap: () => openChecksPage(context),
              ),
            ],
            const DashSection(
              title: 'ملک و دفتر',
              subtitle: 'خلاصهٔ معاملات و دفتر امسال',
              icon: Icons.home_work_rounded,
            ),
            const BizDashboardCard(digits: fa),
            if (projects != null)
              DashSection(
                title: 'پروژه‌ها',
                subtitle: 'پیمانکاری · سود تحقق‌یافته و در جریان',
                icon: Icons.engineering_rounded,
                actionLabel: 'همه',
                onAction: () => openProjectsPage(context),
              ),
            const ProjectsDashboardCard(digits: fa),
            if (snap.holdings.isNotEmpty) ...[
              DashSection(
                title: 'ترکیب',
                subtitle: fa(
                    '${snap.holdingCount} دارایی · ${snap.openLotCount} لات باز'),
                icon: Icons.donut_large_rounded,
                actionLabel: 'معاملات',
                onAction: () => _openTradesTab(context),
              ),
              DashAssetMix(
                  valuation: valuation, onOpen: () => _openTradesTab(context)),
            ],
            const DashSection(
              title: 'میان‌بر',
              subtitle: 'کارهای پرتکرار',
              icon: Icons.bolt_rounded,
            ),
            DashQuickActions(actions: [
              DashQuickAction(Icons.add_chart_rounded, 'ثبت معامله',
                  () => showBuyTradeDialog(context),
                  key: const ValueKey('qa-trade')),
              DashQuickAction(Icons.receipt_rounded, 'ثبت چک',
                  () => openChecksPage(context),
                  key: const ValueKey('qa-check')),
              DashQuickAction(Icons.payments_rounded, 'ثبت برداشت',
                  () => showRecordWithdrawalDialog(context),
                  key: const ValueKey('qa-withdraw')),
              DashQuickAction(Icons.engineering_rounded, 'پروژه‌ها',
                  () => openProjectsPage(context),
                  key: const ValueKey('qa-project')),
              if (bizHas)
                DashQuickAction(Icons.ios_share_rounded, 'خروجی سالانه',
                    () => exportBizAnnual(context, biz),
                    key: const ValueKey('qa-export'))
              else
                DashQuickAction(Icons.table_chart_outlined, 'جدول PWO', openPwo,
                    key: const ValueKey('qa-pwo')),
            ]),
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
        DashSection(
          title: 'لنگرها',
          subtitle: 'بازار مرجع',
          icon: Icons.candlestick_chart_rounded,
          actionLabel: onOpenIndex == null ? null : 'شاخص',
          onAction: onOpenIndex,
        ),
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
            fa(caption!),
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                fa(quote.formatPrice(compact: true)),
                style: const TextStyle(
                  color: AppTheme.title,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (quote.change24h != null)
                  TrendArrow(quote.change24h!, size: 18),
                Text(
                  quote.change24h == null
                      ? '—'
                      : fa(formatPct(quote.change24h!.abs())
                          .replaceAll('+', '')),
                  style: TextStyle(
                    color: tone,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
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
    this.projects,
    this.usdt = 0,
  });

  final ProjectTotals? projects;
  final double usdt;
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
        caption: snap.closedCount == 0
            ? 'تمام معاملات بسته‌شده'
            : fa('${snap.closedCount} معامله بسته‌شده'),
        toman: snap.realizedPnl,
        usd: snap.realizedUsd,
      ),
      yearSpec,
      if (projects != null && projects!.count > 0) ...[
        _PnlSpec(
          title: 'پیمانکاری',
          caption: fa(projects!.activeCount > 0
              ? '${projects!.finishedCount} پروژهٔ تمام‌شده · پیش‌بینی در جریان ${formatCompactToman(projects!.expected)} (حساب نشده)'
              : '${projects!.finishedCount} پروژهٔ تمام‌شده · سود تحقق‌یافته'),
          toman: projects!.realized,
          usd: usdt > 0 ? projects!.realized / usdt : null,
        ),
        _PnlSpec(
          title: 'کل تحقق‌یافته',
          caption: 'معاملات بسته‌شده + پروژه‌های تمام‌شده',
          toman: snap.realizedPnl + projects!.realized,
          usd: snap.realizedUsd == null || usdt <= 0
              ? null
              : snap.realizedUsd! + projects!.realized / usdt,
        ),
      ],
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fa(spec.title),
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  fa(spec.caption),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
          if (!missing && value != null) TrendArrow(value),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    missing
                        ? '—'
                        : showUsd
                            ? formatUsd(spec.usd!.abs(), compact: true)
                            : fa(formatCompactToman(spec.toman.abs())),
                    textDirection:
                        showUsd && !missing ? TextDirection.ltr : null,
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
                    fa(formatPct(spec.pct!.abs()).replaceAll('+', '')),
                    style: TextStyle(
                      color: tone,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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
              const SizedBox(height: 18),
              const ChecksDashboardCard(),
            ],
          ),
        ),
      ],
    );
  }
}

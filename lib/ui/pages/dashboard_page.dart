import 'package:flutter/material.dart';
import 'package:invest/domain/services/connection_status.dart';
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
import 'package:invest/ui/widgets/bank_sms_ui.dart';
import 'package:invest/ui/widgets/dash_speed_dial.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:invest/ui/widgets/dashboard_sections.dart';
import 'package:invest/ui/widgets/portfolio_value_card.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/services/trade_service.dart';
import 'package:invest/ui/pages/price_alerts_page.dart';
import 'package:invest/ui/widgets/dashboard_compact.dart';
import 'package:provider/provider.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Portfolio home — one calm composition, same ledger, clearer hierarchy.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) => const _DashboardBody();
}

/// Test hook: forget the in-memory expand state between widget tests.
@visibleForTesting
void resetDashboardExpandCache() {
  _DashboardBodyState._openCache = null;
  _DashboardBodyState._touched = false;
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

  static const _kOpen = 'dash_open_v1';

  /// Open sections, kept for the whole process so a tab switch or a
  /// rebuilt page never flashes everything closed, and a tap made before
  /// the stored value arrives is never overwritten by it.
  static Set<String>? _openCache;
  Set<String> get _open => _openCache ??= <String>{};
  static bool _touched = false;

  Future<void> _loadOpen() async {
    if (_openCache != null && _touched) return;
    try {
      final p = await SharedPreferences.getInstance();
      final stored = p.getStringList(_kOpen);
      if (!mounted || _touched || stored == null) return;
      setState(() => _openCache = stored.toSet());
    } catch (_) {}
  }

  void _setUsd(bool v) => setState(() => _usd = v);

  void _toggle(String id) {
    _touched = true;
    setState(() => _open.contains(id) ? _open.remove(id) : _open.add(id));
    final list = _open.toList();
    SharedPreferences.getInstance()
        .then((p) => p.setStringList(_kOpen, list))
        .catchError((_) => false);
  }

  @override
  void initState() {
    super.initState();
    _loadOpen();
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
      listenable: Listenable.merge([
        PwoStore.instance,
        BizStore.instance,
        ProjectsStore.instance,
        BankSmsStore.instance,
      ]),
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
        case DashAlertKind.pwoOverTarget:
          openPwo();
        case DashAlertKind.unpriced:
          _openTradesTab(context);
        case DashAlertKind.bizMismatch:
          openBiz();
      }
    }

    final conn = state.connectionStatus;
    final dial = [
      SpeedDialAction(
          id: 'qa-trade',
          icon: Icons.add_chart_rounded,
          label: 'ثبت معامله',
          onTap: () => showBuyTradeDialog(context)),
      SpeedDialAction(
          id: 'qa-check',
          icon: Icons.receipt_rounded,
          label: 'ثبت چک',
          onTap: () => openChecksPage(context)),
      SpeedDialAction(
          id: 'qa-withdraw',
          icon: Icons.payments_rounded,
          label: 'ثبت برداشت',
          onTap: () => showWithdrawalChooser(context)),
      SpeedDialAction(
          id: 'qa-project',
          icon: Icons.engineering_rounded,
          label: 'پروژه‌ها',
          onTap: () => openProjectsPage(context)),
      SpeedDialAction(
          id: 'qa-export',
          icon: Icons.ios_share_rounded,
          label: 'خروجی سالانه',
          onTap: () => bizHas ? exportBizAnnual(context, biz) : openBiz()),
    ];
    return DashSpeedDial(
      key: const ValueKey('dash-dial'),
      enabled: state.canMutate,
      actions: dial,
      child: DecoratedBox(
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
            padding: shellPagePadding().copyWith(
                bottom: kShellListBottomPadding + DashSpeedDial.reserve),
            children: [
              stage(
                a: 0,
                b: 0.35,
                child: Row(children: [
                  const Flexible(
                    flex: 2,
                    child: Text('داشبورد',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.title,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Text(
                        fa(formatDisplayDate(today, calendar)
                            .replaceFirst(RegExp(r'^0'), '')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mutedStyle(11.5)),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              ..._compactChildren(
                  context,
                  state: state,
                  snap: snap,
                  trend: trend,
                  usdt: usdt,
                  today: today,
                  pwo: pwo,
                  projects: projects,
                  alerts: alerts,
                  upcoming: upcoming,
                  openAlert: openAlert,
                  openPwo: openPwo,
                  yoy: yoy,
                  anchorsCaption: anchors.caption,
                  offline:
                      !conn.isOnline && conn != AppConnectionStatus.localOnly,
                ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}


extension _CompactDash on _DashboardBodyState {
  List<Widget> _compactChildren(
    BuildContext context, {
    required AppState state,
    required DashboardSnapshot snap,
    required PortfolioTrend trend,
    required double? usdt,
    required String today,
    required PwoMonthSummary? pwo,
    required ProjectTotals? projects,
    required List<DashAlert> alerts,
    required List<UpcomingCheque> upcoming,
    required void Function(DashAlert) openAlert,
    required VoidCallback openPwo,
    required YearNavCompare yoy,
    required String? anchorsCaption,
    required bool offline,
  }) {
    PortfolioTrend win(int days) => PortfolioTrend.window(
          series: state.metrics?.growthSeries ?? const [],
          todayValue: snap.holdingsValue,
          today: today,
          days: days,
          openTrades: state.openTrades,
          closedTrades: state.closedTrades,
        );
    final jDay = Jalali.fromDateTime(DateTime.tryParse(today) ?? DateTime.now()).day;
    // «امروز» is only meaningful against a recent close: if the latest stored
    // day is older than 3 days (app not opened, no server series), show «—»
    // instead of calling a multi-day move "today".
    var dayTrend = win(1);
    final dBase = DateTime.tryParse(dayTrend.baseDate ?? '');
    final tDay = DateTime.tryParse(today.length >= 10 ? today.substring(0, 10) : today);
    if (dBase != null && tDay != null && tDay.difference(dBase).inDays > 3) {
      dayTrend = PortfolioTrend(days: 1, endValue: snap.holdingsValue);
    }
    final monthTrend = win(jDay < 1 ? 1 : jDay);

    // «امروز» chips.
    final week = upcomingCheques(state.checks, today: today, limit: 999)
        .where((u) => u.daysLeft <= 7)
        .toList();
    final smsPending = BankSmsStore.instance.pending.length;
    final prices = <String, double>{
      for (final q in [...state.commodityIndex, ...state.wallexMarkets])
        if (q.price != null) q.id: q.price!,
    };
    final hit = state.settings.priceAlerts.where((a) {
      final v = prices[a.id];
      if (!a.isArmed || v == null) return false;
      return (a.above != null && a.above! > 0 && v >= a.above!) ||
          (a.below != null && a.below! > 0 && v <= a.below!);
    }).length;
    final chips = [
      if (week.any((u) => u.daysLeft < 0))
        TodayChip(
            id: 'overdue',
            icon: Icons.warning_amber_rounded,
            label: '${week.where((u) => u.daysLeft < 0).length} چک سررسید گذشته',
            color: AppTheme.negative,
            onTap: () => openChecksPage(context)),
      if (week.any((u) => u.daysLeft >= 0))
        TodayChip(
            id: 'cheques',
            icon: Icons.receipt_long_rounded,
            label: '${week.where((u) => u.daysLeft >= 0).length} چک این هفته',
            color: kAmber,
            onTap: () => openChecksPage(context)),
      if (smsPending > 0)
        TodayChip(
            id: 'sms',
            icon: Icons.sms_rounded,
            label: '$smsPending پیامک بانک',
            color: AppTheme.negative,
            onTap: () => openBankSmsPage(context)),
      if (hit > 0)
        TodayChip(
            id: 'alerts',
            icon: Icons.notifications_active_rounded,
            label: '$hit هشدار قیمت',
            color: const Color(0xFF5AC8FA),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const PriceAlertsPage()))),
    ];

    // Rates strip: dollar, tether, 18k gold, coin, ounce (whatever is live).
    const order = ['usd', 'usdt', 'gold', 'coin', 'ounce', 'xau', 'gold_ounce'];
    final byId = {for (final q in state.commodityIndex) q.id: q};
    final rates = [
      for (final id in order)
        if (byId[id]?.price != null && byId[id]!.price! > 0) byId[id]!,
    ];

    // Holdings split by class (same kind rule as the valuation).
    AssetKind kindOf(Asset a) => TradeService.isGoldAsset(a.name, a.symbol, a.notes)
        ? AssetKind.gold
        : detectAssetKind(name: a.name, symbol: a.symbol, notes: a.notes);
    final gold = <({Asset asset, HoldingMetrics metrics})>[];
    final fx = <({Asset asset, HoldingMetrics metrics})>[];
    final other = <({Asset asset, HoldingMetrics metrics})>[];
    for (final h in snap.holdings) {
      switch (kindOf(h.asset)) {
        case AssetKind.gold:
          gold.add(h);
        case AssetKind.cash:
        case AssetKind.crypto:
          fx.add(h);
        default:
          other.add(h);
      }
    }
    double sumV(List<({Asset asset, HoldingMetrics metrics})> l) =>
        l.fold(0.0, (s, h) => s + h.metrics.marketValue);
    double? pctOf(List<({Asset asset, HoldingMetrics metrics})> l) {
      final cost = l.fold(0.0, (s, h) => s + h.metrics.costBasis);
      if (cost <= 0) return null;
      return (sumV(l) - cost) / cost * 100;
    }

    Widget rows(List<({Asset asset, HoldingMetrics metrics})> l) => Column(
          children: [
            for (final h in [...l]..sort((a, b) => b.metrics.marketValue.compareTo(a.metrics.marketValue)))
              CompactHoldingRow(
                name: h.asset.name,
                value: h.metrics.marketValue,
                pct: h.metrics.unrealizedPnlPct,
                onTap: () => _openTradesTab(context),
              ),
          ],
        );

    Widget section({
      required String id,
      required IconData icon,
      required Color color,
      required String title,
      required String line,
      String? value,
      Color valueColor = AppTheme.muted,
      required Widget child,
    }) =>
        CollapsibleSection(
          id: id,
          icon: icon,
          color: color,
          title: title,
          line: line,
          value: value,
          valueColor: valueColor,
          open: _open.contains(id),
          onToggle: () => _toggle(id),
          child: child,
        );

    final nav = snap.marketValue;
    final goldV = sumV(gold);
    final goldPct = pctOf(gold);
    final fxPct = pctOf(fx);
    final otherPct = pctOf(other);
    final pendingCheques = state.checks.where((c) => c.status == checkStatusPending && !c.isArchived).length;

    return [
      CompactSummaryCard(
        nav: nav,
        offline: offline,
        pricesAsOf: state.pricesAsOf,
        trend30: trend,
        today: dayTrend,
        month: monthTrend,
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CapitalChartPage())),
      ),
      TodayStrip(chips: chips),
      RatesStrip(quotes: rates),
      if (anchorsCaption != null && anchorsCaption.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(fa(anchorsCaption),
              key: const ValueKey('cd-anchor-caption'),
              style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
        ),
      if (pwo != null) PwoProgressCard(summary: pwo, monthLabel: pwoMonthLabel(pwo.month), onTap: openPwo),
      section(
        id: 'value',
        icon: Icons.account_balance_rounded,
        color: AppTheme.positive,
        title: 'جزئیات ارزش',
        line: fa('معادل دلاری، نرخ زنده، چک‌ها، تخصیص و نمودار'),
        child: PortfolioValueCard(
          snap: snap,
          trend: trend,
          usdIsLive: state.usdtIsLive,
          pricesAsOf: state.pricesAsOf,
          offline: offline,
          lastSyncedAt: state.lastSyncedAt,
          projects: projects,
          refreshing: state.refreshing,
          onOpenCharts: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CapitalChartPage())),
        ),
      ),
      section(
        id: 'pnl',
        icon: Icons.insights_rounded,
        color: toneOf(snap.totalPnl),
        title: 'سود و زیان',
        line: 'باز، تحقق‌یافته، امسال و مقایسه سالانه',
        value: signedToman(snap.totalPnl),
        valueColor: toneOf(snap.totalPnl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: _FxToggle(usd: _usd, onChanged: _setUsd),
          ),
          const SizedBox(height: 8),
          if (_usd && snap.usdIncomplete)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: _HintBanner(
                text: 'دلار فقط با بهای خرید ثبت‌شده محاسبه می‌شود. برای لات‌های بدون دلار، «—» می‌بینید.',
              ),
            ),
          _PnlLedger(snap: snap, usd: _usd, yoy: yoy, projects: projects, usdt: usdt ?? 0),
        ]),
      ),
      if (alerts.isNotEmpty)
        section(
          id: 'alerts',
          icon: Icons.notifications_active_rounded,
          color: kAmber,
          title: 'نیازمند توجه',
          line: fa('${alerts.length} مورد · ${alerts.first.title}'),
          child: DashAlertsList(alerts: alerts, onOpen: openAlert),
        ),
      if (gold.isNotEmpty)
        section(
          id: 'gold',
          icon: Icons.diamond_rounded,
          color: kGold,
          title: 'طلا و سکه · پوشش تورم',
          line: fa('${gold.length} دارایی · ${fa(formatCompactToman(goldV))}'
              '${snap.goldHoldingG > 0 ? ' · ${formatGrams(snap.goldHoldingG)} ۱۸ عیار' : ''}'
              '${nav > 0 ? ' · ${(goldV / nav * 100).round()}٪ سبد' : ''}'),
          value: goldPct == null ? null : signedPct(goldPct),
          valueColor: goldPct == null ? AppTheme.muted : toneOf(goldPct),
          child: rows(gold),
        ),
      if (fx.isNotEmpty)
        section(
          id: 'fx',
          icon: Icons.attach_money_rounded,
          color: const Color(0xFF5AC8FA),
          title: 'ارز',
          line: fa('${fx.length} دارایی · ${formatCompactToman(sumV(fx))}'),
          value: fxPct == null ? null : signedPct(fxPct),
          valueColor: fxPct == null ? AppTheme.muted : toneOf(fxPct),
          child: rows(fx),
        ),
      if (other.isNotEmpty)
        section(
          id: 'other',
          icon: Icons.category_rounded,
          color: AppTheme.muted,
          title: 'سایر دارایی‌ها',
          line: fa('${other.length} دارایی · ${formatCompactToman(sumV(other))}'),
          value: otherPct == null ? null : signedPct(otherPct),
          valueColor: otherPct == null ? AppTheme.muted : toneOf(otherPct),
          child: rows(other),
        ),
      section(
        id: 'cheques',
        icon: Icons.receipt_long_rounded,
        color: kAmber,
        title: 'چک‌ها',
        line: upcoming.isEmpty
            ? fa('$pendingCheques چک باز')
            : fa('$pendingCheques چک باز · نزدیک‌ترین ${upcoming.first.daysLeft < 0 ? 'سررسید گذشته' : '${upcoming.first.daysLeft} روز دیگر'}'),
        value: snap.chequeNav.affectsNav ? signedToman(snap.chequeNav.net) : null,
        valueColor: toneOf(snap.chequeNav.net),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ChecksDashboardCard(digits: fa),
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 8),
            DashUpcomingCheques(key: const ValueKey('dash-upcoming'), items: upcoming, calendar: state.settings.calendar, onTap: () => openChecksPage(context)),
          ],
        ]),
      ),
      section(
        id: 'pwo',
        icon: Icons.account_balance_wallet_rounded,
        color: AppTheme.positive,
        title: 'برداشت و PWO',
        line: pwo == null ? 'سهمیه سالانه برداشت' : '${pwoMonthLabel(pwo.month)} · جدول و سهمیه',
        child: DashPwoCard(
          summary: pwo,
          withdrawable: state.withdrawableAmount,
          capBaseLabel: 'سهمیه سالانه',
          onOpenPwo: openPwo,
          onOpenWithdrawals: () => openHomeTab(context, HomeTabs.withdrawals),
        ),
      ),
      if (projects != null)
        section(
          id: 'projects',
          icon: Icons.engineering_rounded,
          color: const Color(0xFFB38CFF),
          title: 'پروژه‌ها',
          line: fa('${projects.activeCount} فعال · ${projects.finishedCount} تمام‌شده'),
          value: signedToman(projects.sheetProfit),
          valueColor: toneOf(projects.sheetProfit),
          child: const ProjectsDashboardCard(digits: fa),
        ),
      section(
        id: 'biz',
        icon: Icons.home_work_rounded,
        color: AppTheme.muted,
        title: 'ملک و دفتر',
        line: 'خلاصهٔ معاملات و دفتر امسال',
        child: const BizDashboardCard(digits: fa),
      ),
      if (snap.holdings.isNotEmpty)
        section(
          id: 'mix',
          icon: Icons.donut_large_rounded,
          color: AppTheme.muted,
          title: 'ترکیب',
          line: fa('${snap.holdingCount} دارایی · ${snap.openLotCount} لات باز'),
          child: DashAssetMix(valuation: snap.valuation!, onOpen: () => _openTradesTab(context)),
        ),
      LastUpdatedLine(at: state.lastSyncedAt),
    ];
  }
}

void _openTradesTab(BuildContext context) {
  openHomeTab(context, HomeTabs.trades);
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

/// «ثبت برداشت» shortcut: choose personal (PWO, per person this month) or
/// system (برداشت از سرمایه، against the annual allowance).
Future<void> showWithdrawalChooser(BuildContext context) {
  Widget option(BuildContext c, String key, IconData icon, String title,
          String sub, VoidCallback go) =>
      ListTile(
        key: ValueKey(key),
        leading: CircleAvatar(
          backgroundColor: AppTheme.negative.withValues(alpha: 0.15),
          child: Icon(icon, color: AppTheme.negative),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(sub, style: mutedStyle(12)),
        onTap: () {
          Navigator.of(c).pop();
          go();
        },
      );
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppTheme.card,
    builder: (c) => Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Column(
          key: const ValueKey('withdraw-chooser'),
          mainAxisSize: MainAxisSize.min,
          children: [
            option(
                c,
                'qa-withdraw-personal',
                Icons.person_rounded,
                'ثبت برداشت شخصی',
                'PWO · برداشت یک نفر در این ماه',
                () => showPwoPersonalWithdrawal(context)),
            option(
                c,
                'qa-withdraw-system',
                Icons.account_balance_rounded,
                'ثبت برداشت سیستم',
                'برداشت از سرمایه · سهمیهٔ سالانه',
                () => showRecordWithdrawalDialog(context)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/domain/services/performance_aggregator.dart';
import 'package:invest/domain/utils/biz_dates.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/month_detail_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/perf_month_tile.dart';
import 'package:invest/ui/widgets/performance_sections.dart';
import 'package:provider/provider.dart';

Future<void> openMonthlyPerformancePage(
  BuildContext context, {
  required BizStore store,
  int? year,
  String initialMonthFilter = 'all',
  Set<PerfDomain> domainFilter = const {},
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: MonthlyPerformancePage(
          store: store,
          year: year,
          initialMonthFilter: initialMonthFilter,
          domainFilter: domainFilter,
        ),
      ),
    ),
  );
}

/// Full list of Jalali months for a year, with filters and year totals.
class MonthlyPerformancePage extends StatefulWidget {
  const MonthlyPerformancePage({
    super.key,
    required this.store,
    this.year,
    this.initialMonthFilter = 'all',
    this.domainFilter = const {},
  });

  final BizStore store;
  final int? year;
  final String initialMonthFilter;
  final Set<PerfDomain> domainFilter;

  @override
  State<MonthlyPerformancePage> createState() => _MonthlyPerformancePageState();
}

class _MonthlyPerformancePageState extends State<MonthlyPerformancePage> {
  late String _filter = widget.initialMonthFilter;
  late final Set<PerfDomain> _selectedDomains = {...widget.domainFilter};
  late int _localYear = widget.year ?? widget.store.year ?? currentJalaliYear();

  Future<void> _selectYear(int nextYear) async {
    setState(() => _localYear = nextYear);
    final store = widget.store;
    if (store.loaded || store.isRemote) {
      await store.selectYear(nextYear);
    }
  }

  Future<void> _refresh(AppState? app) async {
    final store = widget.store;
    final ps = ProjectsStore.instance;
    final futures = <Future<void>>[];
    if (store.isRemote || !store.loaded) futures.add(store.refresh());
    if (app != null) futures.add(app.refreshAll());
    if (ps.isRemote) futures.add(ps.refresh());
    await Future.wait(futures);
  }

  @override
  Widget build(BuildContext context) {
    AppState? app;
    try {
      app = Provider.of<AppState>(context);
    } on ProviderNotFoundException {
      app = null;
    }
    final store = widget.store;
    final ps = ProjectsStore.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([store, ps]),
      builder: (context, _) {
        final year = store.year ?? store.snap.year ?? _localYear;
        final stale = store.loaded &&
            store.year != null &&
            store.snap.year != null &&
            store.snap.year != year;
        final summary = PerformanceAggregator.fromStores(
          year: year,
          store: store,
          assets: app?.assets ?? const [],
          openTrades: app?.openTrades ?? const [],
          closedTrades: app?.closedTrades ?? const [],
          projects: ps.loaded ? ps.snap.items : const [],
        );
        final effectiveFilter =
            _selectedDomains.where(summary.activeDomains.contains).toSet();
        final dup = summary.mismatchCountFor(effectiveFilter);
        final filter = (_filter == 'dup' && dup == 0) ? 'all' : _filter;
        final activeMonths = summary.activeMonthsFor(effectiveFilter);
        final visible = [
          for (final m in summary.months)
            if (filter == 'all' ||
                (filter == 'active' && !m.isEmptyFor(effectiveFilter)) ||
                (filter == 'dup' && m.incomeDupTrades))
              m,
        ];
        final netTotal = summary.totalNetFor(effectiveFilter);
        final yearSoldProfit = summary.totalTradeProfitFor(effectiveFilter);
        final officeNet = summary.totalIncomeEffectiveFor(effectiveFilter) -
            summary.totalStaffFor(effectiveFilter) -
            summary.totalPwoFor(effectiveFilter) -
            summary.totalAdsFor(effectiveFilter);
        final avgNet = summary.avgNetFor(effectiveFilter);

        return Scaffold(
          backgroundColor: AppTheme.bg,
          appBar: AppBar(
            title: const Column(
              children: [
                Text('عملکرد ماهانه'),
                Text(
                  'سود قطعی همهٔ دسته‌ها + عملکرد دفتر',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          body: RefreshIndicator(
            onRefresh: () => _refresh(app),
            child: ListView(
              padding: perfListPadding(context),
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const ValueKey('perf-months-year-prev'),
                      tooltip: 'سال قبل',
                      visualDensity: VisualDensity.compact,
                      onPressed:
                          year > 1300 ? () => _selectYear(year - 1) : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'سال $year',
                        key: const ValueKey('perf-months-year'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('perf-months-year-next'),
                      tooltip: 'سال بعد',
                      visualDensity: VisualDensity.compact,
                      onPressed:
                          year < 1600 ? () => _selectYear(year + 1) : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                  ],
                ),
                if (stale)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: store.syncing
                          ? const CircularProgressIndicator()
                          : const Text(
                              'دادهٔ این سال در دسترس نیست',
                              style: TextStyle(color: AppTheme.muted),
                            ),
                    ),
                  )
                else ...[
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          Color(0xFF245A44),
                          Color(0xFF17362A),
                          Color(0xFF101F18),
                        ],
                      ),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'جمع خالص سال',
                              style: TextStyle(
                                color: AppTheme.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.positive.withValues(
                                  alpha: 0.14,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: AppTheme.positive.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: Text(
                                '${activeMonths.length} ماه فعال',
                                style: const TextStyle(
                                  color: AppTheme.positive,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            signedPerfMoney(netTotal),
                            key: const ValueKey('perf-months-total-net'),
                            style: TextStyle(
                              color: perfSignColor(netTotal),
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _MiniStat(
                                'سود معاملات',
                                signedPerfMoney(yearSoldProfit),
                                color: perfSignColor(yearSoldProfit),
                              ),
                            ),
                            if (summary.includesOffice(effectiveFilter))
                              Expanded(
                                child: _MiniStat(
                                  'عملکرد دفتر',
                                  signedPerfMoney(officeNet),
                                  color: perfSignColor(officeNet),
                                ),
                              ),
                            if (activeMonths.isNotEmpty)
                              Expanded(
                                child: _MiniStat(
                                  'میانگین ماه فعال',
                                  signedPerfMoney(avgNet),
                                  color: perfSignColor(avgNet),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (summary.skippedOverlappingPropertyTrades > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      summary.skippedOverlappingPropertyTrades == 1
                          ? '۱ معامله ملک پورتفو با معامله دفتر یکی بود و دوبار حساب نشد.'
                          : '${summary.skippedOverlappingPropertyTrades} معامله ملک پورتفو با معامله دفتر یکی بود و دوبار حساب نشد.',
                      key: const ValueKey('perf-year-overlap'),
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      PerfFilterChip(
                        key: const ValueKey('biz-months-filter-all'),
                        label: 'همه (${summary.months.length})',
                        selected: filter == 'all',
                        onTap: () => setState(() => _filter = 'all'),
                      ),
                      PerfFilterChip(
                        key: const ValueKey('biz-months-filter-active'),
                        label: 'فعال (${activeMonths.length})',
                        selected: filter == 'active',
                        onTap: () => setState(() => _filter = 'active'),
                      ),
                      if (dup > 0)
                        PerfFilterChip(
                          key: const ValueKey('biz-months-filter-mismatch'),
                          label: 'درآمد تکراری ($dup)',
                          selected: filter == 'dup',
                          tone: AppTheme.negative,
                          onTap: () => setState(() => _filter = 'dup'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        children: [
                          const Text(
                            'ماهی با این فیلتر وجود ندارد',
                            style: TextStyle(
                              color: AppTheme.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: () => setState(() => _filter = 'all'),
                            child: const Text('نمایش همه ماه‌ها'),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final m in visible) ...[
                      PerfMonthTile(
                        month: m,
                        filter: effectiveFilter,
                        onTap: () => openMonthDetailPage(
                          context,
                          year: year,
                          month: m.month,
                          store: store,
                          filter: effectiveFilter,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.muted, fontSize: 10.5),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color ?? AppTheme.title,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
      );
}

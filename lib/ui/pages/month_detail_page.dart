import 'package:flutter/material.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/domain/services/performance_aggregator.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/month_edit_dialog.dart';
import 'package:invest/ui/widgets/perf_month_tile.dart';
import 'package:invest/ui/widgets/performance_sections.dart';
import 'package:provider/provider.dart';

Future<void> openMonthDetailPage(
  BuildContext context, {
  required int year,
  required int month,
  required BizStore store,
  Set<PerfDomain> filter = const {},
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: MonthDetailPage(
          year: year,
          month: month,
          store: store,
          initialFilter: filter,
        ),
      ),
    ),
  );
}

/// Full-page breakdown of one Jalali month: office ops, profit by category,
/// and every deal (sold and bought) in that month.
class MonthDetailPage extends StatelessWidget {
  const MonthDetailPage({
    super.key,
    required this.year,
    required this.month,
    required this.store,
    this.initialFilter = const {},
  });

  final int year;
  final int month;
  final BizStore store;
  final Set<PerfDomain> initialFilter;

  @override
  Widget build(BuildContext context) {
    AppState? app;
    try {
      app = Provider.of<AppState>(context);
    } on ProviderNotFoundException {
      app = null;
    }
    final projects = ProjectsStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([store, projects]),
      builder: (context, _) {
        final summary = PerformanceAggregator.fromStores(
          year: year,
          store: store,
          assets: app?.assets ?? const [],
          openTrades: app?.openTrades ?? const [],
          closedTrades: app?.closedTrades ?? const [],
          projects: projects.loaded ? projects.snap.items : const [],
        );
        final filter =
            initialFilter.where(summary.activeDomains.contains).toSet();
        final m = summary.months[month - 1];
        return _MonthDetailBody(store: store, month: m, filter: filter);
      },
    );
  }
}

class _MonthDetailBody extends StatelessWidget {
  const _MonthDetailBody({
    required this.store,
    required this.month,
    required this.filter,
  });

  final BizStore store;
  final PerfMonthSummary month;
  final Set<PerfDomain> filter;

  Future<void> _refresh(BuildContext context) async {
    AppState? app;
    try {
      app = Provider.of<AppState>(context, listen: false);
    } on ProviderNotFoundException {
      app = null;
    }
    final futures = <Future<void>>[];
    if (store.isRemote || !store.loaded) futures.add(store.refresh());
    if (app != null) futures.add(app.refreshAll());
    if (ProjectsStore.instance.isRemote) {
      futures.add(ProjectsStore.instance.refresh());
    }
    await Future.wait(futures);
  }

  Future<void> _edit(BuildContext context) {
    return editBizMonth(
      context,
      store,
      month.bizMonth ?? placeholderBizMonth(month.year, month.month),
      allTradeProfit: month.tradeProfitFor(filter),
      allTradeGross: month.soldAmountByDomain.values.fold<double>(
        0,
        (a, b) => a + b,
      ),
      soldCount: month.soldCountFor(filter),
      boughtCount: month.boughtCountFor(filter),
      boughtAmount: month.boughtAmountFor(filter),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = month;
    final name = (m.month >= 1 && m.month <= 12)
        ? pwoMonthNames[m.month - 1]
        : '${m.month}';
    final net = m.netFor(filter);
    final tradeProfit = m.tradeProfitFor(filter);
    final officeNet = m.includesOffice(filter) ? m.officeNet : 0.0;
    final soldCount = m.soldCountFor(filter);
    final deals = m.dealsFor(filter);
    final canEdit = !store.readOnly && m.includesOffice(filter);
    final flag = m.includesOffice(filter) && m.incomeDupTrades;
    final domains = [
      for (final d in PerfDomain.values)
        if (d != PerfDomain.office &&
            (filter.isEmpty || filter.contains(d)) &&
            ((m.profitByDomain[d] ?? 0) != 0 ||
                (m.soldCountByDomain[d] ?? 0) > 0))
          d,
    ];

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Column(
          children: [
            Text('$name ${m.year}'),
            Text(
              'برج ${m.month} · عملکرد این ماه',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(context),
        child: ListView(
          padding: perfListPadding(context),
          children: [
            Container(
              key: const ValueKey('perf-month-hero'),
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
                  const Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'خالص ماه',
                        style: TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      _Tag('تحقق‌یافته'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      signedPerfMoney(net),
                      style: TextStyle(
                        color: perfSignColor(net),
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroStat(
                          'سود معاملات ($soldCount)',
                          signedPerfMoney(tradeProfit),
                          color: perfSignColor(tradeProfit),
                        ),
                      ),
                      if (m.includesOffice(filter))
                        Expanded(
                          child: _HeroStat(
                            'عملکرد دفتر',
                            signedPerfMoney(officeNet),
                            color: perfSignColor(officeNet),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (flag) ...[
              const SizedBox(height: 8),
              Container(
                key: ValueKey('perf-month-flag-${m.month}'),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: AppTheme.negative.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.negative.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: AppTheme.negative,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'درآمد دفتر همان سود معاملات است و دوبار حساب نشد.',
                        style: TextStyle(
                          color: AppTheme.negative,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (canEdit)
                      TextButton(
                        key: const ValueKey('perf-month-fix-dup'),
                        onPressed: () => _edit(context),
                        child: const Text('اصلاح'),
                      ),
                  ],
                ),
              ),
            ],
            if (m.skippedOverlappingPropertyTrades > 0) ...[
              const SizedBox(height: 8),
              Text(
                m.skippedOverlappingPropertyTrades == 1
                    ? '۱ معامله ملک پورتفو با معامله دفتر یکی بود و دوبار حساب نشد.'
                    : '${m.skippedOverlappingPropertyTrades} معامله ملک پورتفو با معامله دفتر یکی بود و دوبار حساب نشد.',
                key: ValueKey('perf-month-overlap-${m.month}'),
                style: const TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
            ],
            if (domains.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                key: const ValueKey('perf-month-domains'),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Expanded(
                            child: Text(
                              'تفکیک سود هر دسته',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          Text(
                            'فقط فروش / پایان‌یافته',
                            style: TextStyle(
                              color: AppTheme.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final d in domains)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: perfDomainColor(d),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  d.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              perfFitEnd(
                                Text(
                                  signedPerfMoney(m.profitByDomain[d] ?? 0),
                                  style: TextStyle(
                                    color: perfSignColor(
                                      m.profitByDomain[d] ?? 0,
                                    ),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: 14),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'جمع سود معاملات',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          perfFitEnd(
                            Text(
                              signedPerfMoney(tradeProfit),
                              style: TextStyle(
                                color: perfSignColor(tradeProfit),
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (m.includesOffice(filter) &&
                (m.hasOfficeActivityFor(filter) || canEdit)) ...[
              const SizedBox(height: 8),
              Card(
                key: const ValueKey('perf-month-office'),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'عملکرد دفتر',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          if (canEdit)
                            InkWell(
                              key: const ValueKey('perf-month-edit'),
                              onTap: () => _edit(context),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: Text(
                                  'ویرایش',
                                  style: TextStyle(
                                    color: AppTheme.positive,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _OfficeCell(
                              'درآمد دفتر',
                              formatMoney(m.income),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _OfficeCell(
                              'کارمندان',
                              formatMoney(m.staff),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _OfficeCell('PWO', formatMoney(m.pwo)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _OfficeCell('تبلیغات', formatMoney(m.ads)),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'خالص دفتر',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          perfFitEnd(
                            Text(
                              signedPerfMoney(officeNet),
                              style: TextStyle(
                                color: perfSignColor(officeNet),
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Card(
              key: const ValueKey('perf-month-deals'),
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'معاملات این ماه',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        Text(
                          '${deals.length} مورد',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (deals.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'معامله‌ای در این ماه ثبت نشده است',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.muted, fontSize: 13),
                        ),
                      )
                    else
                      for (var i = 0; i < deals.length; i++) ...[
                        if (i > 0) const SizedBox(height: 6),
                        _DealRow(item: deals[i]),
                      ],
                  ],
                ),
              ),
            ),
            if (m.note.isNotEmpty && m.includesOffice(filter)) ...[
              const SizedBox(height: 8),
              Text(
                m.note,
                key: ValueKey('perf-month-note-${m.month}'),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'خالص ماه = عملکرد دفتر + سود قطعی همهٔ دسته‌ها در ماه فروش/پایان. خرید و سود باز در خالص نمی‌آید.',
              style: TextStyle(
                color: AppTheme.muted,
                fontSize: 10.5,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.positive.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.positive.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppTheme.positive,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _HeroStat extends StatelessWidget {
  const _HeroStat(this.label, this.value, {this.color});
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
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: color ?? AppTheme.title,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
}

class _OfficeCell extends StatelessWidget {
  const _OfficeCell(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.muted, fontSize: 10.5),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
        ],
      );
}

class _DealRow extends StatelessWidget {
  const _DealRow({required this.item});
  final PerfDealItem item;

  @override
  Widget build(BuildContext context) {
    final c = perfDomainColor(item.domain);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bg.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: c.withValues(alpha: 0.35),
                    width: 0.7,
                  ),
                ),
                child: Text(
                  item.isSold ? item.domain.shortLabel : 'خرید',
                  style: TextStyle(
                    color: item.isSold ? c : AppTheme.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (item.isSold && item.profit != null)
                perfFitEnd(
                  Text(
                    signedPerfMoney(item.profit!),
                    style: TextStyle(
                      color: perfSignColor(item.profit!),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else
                const Flexible(
                  child: Text(
                    'در خالص نیست',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: AppTheme.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 10,
            runSpacing: 2,
            children: [
              if (item.dateLabel.isNotEmpty)
                Text(
                  item.dateLabel,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              Text(
                'بهای تمام‌شده: ${formatMoney(item.buyAmount)}',
                style: const TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
              if (item.isSold && item.sellAmount > 0)
                Text(
                  'فروش/قرارداد: ${formatMoney(item.sellAmount)}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
            ],
          ),
          if (item.subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.subtitle.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.muted, fontSize: 10.5),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/domain/services/performance_aggregator.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/theme/app_theme.dart';

Color perfDomainColor(PerfDomain d) => switch (d) {
      PerfDomain.office => AppTheme.accent,
      PerfDomain.property => const Color(0xFFC79BE0),
      PerfDomain.gold => const Color(0xFFE6B84C),
      PerfDomain.cash => const Color(0xFF9AD0A8),
      PerfDomain.crypto => const Color(0xFF6FA8DC),
      PerfDomain.stock => AppTheme.positive,
      PerfDomain.vehicle => const Color(0xFFE08F6A),
      PerfDomain.projects => const Color(0xFF56C2B5),
      PerfDomain.other => const Color(0xFFB0BEC5),
    };

IconData perfDomainIcon(PerfDomain d) => switch (d) {
      PerfDomain.office => Icons.apartment_rounded,
      PerfDomain.property => Icons.home_work_outlined,
      PerfDomain.gold => Icons.workspace_premium_outlined,
      PerfDomain.cash => Icons.attach_money_rounded,
      PerfDomain.crypto => Icons.currency_bitcoin_rounded,
      PerfDomain.stock => Icons.show_chart_rounded,
      PerfDomain.vehicle => Icons.directions_car_outlined,
      PerfDomain.projects => Icons.engineering_outlined,
      PerfDomain.other => Icons.category_outlined,
    };

Color _perfSign(double v) =>
    v < 0 ? AppTheme.negative : (v > 0 ? AppTheme.positive : AppTheme.title);

String _signedMoney(double v) {
  if (v == 0) return formatMoney(0);
  return '${v > 0 ? '+' : '-'}${formatMoney(v.abs())}';
}

String _signedCompact(double v) {
  if (v == 0) return formatCompactToman(0);
  return '${v > 0 ? '+' : '-'}${formatCompactToman(v.abs())}';
}

/// Horizontal scrollable filter bar for selecting all or specific performance domains.
class PerfDomainFilterBar extends StatelessWidget {
  const PerfDomainFilterBar({
    super.key,
    required this.activeDomains,
    required this.selected,
    required this.onClear,
    required this.onToggle,
  });

  final List<PerfDomain> activeDomains;
  final Set<PerfDomain> selected;
  final VoidCallback onClear;
  final ValueChanged<PerfDomain> onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('perf-domain-filters'),
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _PerfDomainChip(
            key: const ValueKey('perf-filter-all'),
            label: 'همه زمینه‌ها',
            selected: selected.isEmpty,
            color: AppTheme.positive,
            onTap: onClear,
          ),
          const SizedBox(width: 6),
          for (final d in activeDomains) ...[
            _PerfDomainChip(
              key: ValueKey('perf-filter-${d.id}'),
              label: d.shortLabel,
              icon: perfDomainIcon(d),
              selected: selected.contains(d),
              color: perfDomainColor(d),
              onTap: () => onToggle(d),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _PerfDomainChip extends StatelessWidget {
  const _PerfDomainChip({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : AppTheme.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: selected ? color : AppTheme.muted),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? color : AppTheme.muted,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Breakdown card showing realized net contribution & share of each active field.
class PerfDomainBreakdownCard extends StatelessWidget {
  const PerfDomainBreakdownCard({
    super.key,
    required this.summary,
    required this.selected,
    required this.onToggleDomain,
  });

  final PerfYearSummary summary;
  final Set<PerfDomain> selected;
  final ValueChanged<PerfDomain> onToggleDomain;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final d in summary.activeDomains) summary.byDomain[d]!,
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    final totalAbs = rows.fold<double>(0, (s, r) => s + r.net.abs());
    final maxAbs = rows.fold<double>(
      1,
      (m, r) => r.net.abs() > m ? r.net.abs() : m,
    );

    return Card(
      key: const ValueKey('perf-domain-breakdown'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.pie_chart_outline_rounded,
                    size: 16, color: AppTheme.accent),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'تفکیک سهم هر زمینه',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.title,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                Text(
                  '${formatNumber(rows.length, decimals: 0)} زمینه فعال',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10.5),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < rows.length; i++) ...[
              _DomainBreakdownRow(
                row: rows[i],
                totalAbs: totalAbs,
                maxAbs: maxAbs,
                selected: selected.contains(rows[i].domain),
                onTap: () => onToggleDomain(rows[i].domain),
              ),
              if (i < rows.length - 1) const SizedBox(height: 7),
            ],
          ],
        ),
      ),
    );
  }
}

class _DomainBreakdownRow extends StatelessWidget {
  const _DomainBreakdownRow({
    required this.row,
    required this.totalAbs,
    required this.maxAbs,
    required this.selected,
    required this.onTap,
  });

  final PerfDomainSummary row;
  final double totalAbs;
  final double maxAbs;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = perfDomainColor(row.domain);
    final sharePct = totalAbs > 0 ? (row.net.abs() / totalAbs * 100) : 0.0;
    final ratio = maxAbs > 0 ? (row.net.abs() / maxAbs).clamp(0.0, 1.0) : 0.0;

    final metaParts = <String>[
      if (row.domain == PerfDomain.office) 'عملکرد ماهانه دفتر',
      if (row.soldCount > 0)
        row.domain == PerfDomain.projects
            ? '${row.soldCount} تمام‌شده'
            : '${row.soldCount} فروش',
      if (row.boughtCount > 0) '${row.boughtCount} خرید',
      if (row.openCount > 0) '${row.openCount} باز',
    ];

    return InkWell(
      key: ValueKey('perf-domain-row-${row.domain.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? c.withValues(alpha: 0.1)
              : AppTheme.bg.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? c.withValues(alpha: 0.7) : AppTheme.border,
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(perfDomainIcon(row.domain), size: 15, color: c),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.domain.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.title,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (metaParts.isNotEmpty)
                        Text(
                          metaParts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _signedCompact(row.net),
                      style: TextStyle(
                        color: _perfSign(row.net),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (totalAbs > 0 && row.net != 0)
                      Text(
                        '${formatNumber(sharePct, decimals: 0)}٪ سهم اثر',
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 9.5,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (ratio > 0) ...[
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 3.5,
                  child: Stack(
                    children: [
                      Container(color: AppTheme.border.withValues(alpha: 0.45)),
                      FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: ratio,
                        child: Container(
                          color: row.net < 0 ? AppTheme.negative : c,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dedicated card for open trades, unsold properties, and running projects,
/// kept separate from realized monthly/annual net profit.
class PerfOpenExposureCard extends StatefulWidget {
  const PerfOpenExposureCard({super.key, required this.summary});

  final PerfYearSummary summary;

  @override
  State<PerfOpenExposureCard> createState() => _PerfOpenExposureCardState();
}

class _PerfOpenExposureCardState extends State<PerfOpenExposureCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    if (!s.hasAnyOpen) return const SizedBox.shrink();

    return Card(
      key: const ValueKey('perf-open-exposure'),
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.timelapse_rounded,
                      size: 16, color: AppTheme.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سرمایه باز و در جریان (${s.totalOpenCount} مورد)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.title,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          s.totalOpenUnrealizedPnl != 0
                              ? 'درگیر: ${formatCompactToman(s.totalOpenInvested)} · سود باز: ${_signedCompact(s.totalOpenUnrealizedPnl)}'
                              : 'سرمایه درگیر: ${formatCompactToman(s.totalOpenInvested)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: s.totalOpenUnrealizedPnl != 0
                                ? _perfSign(s.totalOpenUnrealizedPnl)
                                : AppTheme.muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppTheme.muted,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _OpenMetricPill(
                        label: 'سرمایه درگیر',
                        value: formatCompactToman(s.totalOpenInvested),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _OpenMetricPill(
                        label: 'سود/زیان باز (تحقق‌نیافته)',
                        value: _signedCompact(s.totalOpenUnrealizedPnl),
                        color: _perfSign(s.totalOpenUnrealizedPnl),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < s.openDomains.length; i++) ...[
                  _OpenDomainRow(row: s.openDomains[i]),
                  if (i < s.openDomains.length - 1) const SizedBox(height: 5),
                ],
                const SizedBox(height: 4),
                const Text(
                  'مبالغ باز تا زمان فروش یا پایان پروژه وارد سود قطعی عملکرد نمی‌شوند.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenMetricPill extends StatelessWidget {
  const _OpenMetricPill({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.bg.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.muted, fontSize: 10),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color ?? AppTheme.title,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenDomainRow extends StatelessWidget {
  const _OpenDomainRow({required this.row});

  final PerfDomainSummary row;

  @override
  Widget build(BuildContext context) {
    final c = perfDomainColor(row.domain);
    return Container(
      key: ValueKey('perf-open-domain-${row.domain.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bg.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border, width: 0.6),
      ),
      child: Row(
        children: [
          Icon(perfDomainIcon(row.domain), size: 14, color: c),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${row.domain.label} (${row.openCount})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.title,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatCompactToman(row.openInvested),
                style: const TextStyle(
                  color: AppTheme.title,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (row.openUnrealizedPnl != 0)
                Text(
                  _signedCompact(row.openUnrealizedPnl),
                  style: TextStyle(
                    color: _perfSign(row.openUnrealizedPnl),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet showing every individual deal in a month across all filtered domains.
Future<void> showPerfMonthDealsSheet(
  BuildContext context, {
  required PerfMonthSummary month,
  required Set<PerfDomain> filter,
}) {
  final items = month.dealsFor(filter);
  final monthName = (month.month >= 1 && month.month <= 12)
      ? pwoMonthNames[month.month - 1]
      : '${month.month}';

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, ctrl) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'معاملات برج ${month.month} · $monthName ${month.year}',
                        style: const TextStyle(
                          color: AppTheme.title,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${items.length} مورد',
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          'معامله‌ای در این ماه ثبت نشده است',
                          style: TextStyle(color: AppTheme.muted, fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        controller: ctrl,
                        padding: const EdgeInsets.all(14),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final item = items[i];
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
                                    Icon(perfDomainIcon(item.domain),
                                        size: 15, color: c),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: c.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        item.domain.shortLabel,
                                        style: TextStyle(
                                          color: c,
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
                                          color: AppTheme.title,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (item.isSold && item.profit != null)
                                      Text(
                                        _signedMoney(item.profit!),
                                        style: TextStyle(
                                          color: _perfSign(item.profit!),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      )
                                    else
                                      const Text(
                                        'خرید / در جریان',
                                        style: TextStyle(
                                          color: AppTheme.muted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
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
                                        style: const TextStyle(
                                            color: AppTheme.muted, fontSize: 11),
                                      ),
                                    Text(
                                      'بهای تمام‌شده: ${formatMoney(item.buyAmount)}',
                                      style: const TextStyle(
                                          color: AppTheme.muted, fontSize: 11),
                                    ),
                                    if (item.isSold && item.sellAmount > 0)
                                      Text(
                                        'فروش/قرارداد: ${formatMoney(item.sellAmount)}',
                                        style: const TextStyle(
                                            color: AppTheme.muted, fontSize: 11),
                                      ),
                                  ],
                                ),
                                if (item.subtitle.trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    item.subtitle.trim(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppTheme.muted,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Safe helper for tests/callers where [BizStore] is absent or offline.
int bizMismatchMonthsForSummary(PerfYearSummary s, Set<PerfDomain> filter) =>
    s.mismatchCountFor(filter);

/// Helper to create a safe, empty [BizMonth] placeholder for editing office ops
/// on a year/month where portfolio deals exist even before an office row exists.
BizMonth placeholderBizMonth(int year, int month) => BizMonth({
      'year': year,
      'month': month,
      'staff': 0,
      'pwo': 0,
      'ads': 0,
      'income': 0,
      'has_ops': false,
    });

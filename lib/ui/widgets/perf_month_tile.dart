import 'package:flutter/material.dart';
import 'package:invest/domain/services/performance_aggregator.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/pending_sync_mark.dart';
import 'package:invest/ui/widgets/performance_sections.dart';

/// Compact month card used on the Performance tab preview and the
/// «عملکرد ماهانه» list. Tap opens the month detail page.
class PerfMonthTile extends StatelessWidget {
  const PerfMonthTile({
    super.key,
    required this.month,
    required this.filter,
    required this.onTap,
    this.keyPrefix = 'biz',
  });

  final PerfMonthSummary month;
  final Set<PerfDomain> filter;
  final VoidCallback onTap;

  /// Key prefix so the preview on the Performance tab does not collide
  /// with the full list page when both are in the route stack.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final m = month;
    final keyPrefix = this.keyPrefix;
    final flag = m.includesOffice(filter) && m.incomeDupTrades;
    final empty = m.isEmptyFor(filter);
    final net = m.netFor(filter);
    final soldCount = m.soldCountFor(filter);
    final tradeProfit = m.tradeProfitFor(filter);
    final boughtCount = m.boughtCountFor(filter);
    final boughtAmount = m.boughtAmountFor(filter);
    final dealDomains = m.activeDealDomainsFor(filter);
    final pending = m.bizMonth?.raw['pending_sync'] == true;

    return PendingSyncMark(
      pending: pending,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          key: ValueKey('$keyPrefix-month-${m.month}'),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'برج ${m.month} · ${pwoMonthNames[m.month - 1]}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            empty ? '—' : formatMoney(net),
                            key: ValueKey('$keyPrefix-month-net-${m.month}'),
                            style: TextStyle(
                              color:
                                  empty ? AppTheme.muted : perfSignColor(net),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_left_rounded,
                      size: 18,
                      color: AppTheme.muted,
                    ),
                  ],
                ),
                if (!empty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      if (m.hasOfficeActivityFor(filter))
                        Text(
                          flag
                              ? 'درآمد ${formatMoney(m.income)} (تکراری، حساب نشد)'
                              : 'درآمد ${formatMoney(m.income)}',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                      if (soldCount > 0)
                        Text(
                          'سود معاملات ($soldCount مورد) ${formatMoney(tradeProfit)}',
                          key: ValueKey('$keyPrefix-month-tp-${m.month}'),
                          style: TextStyle(
                            color: perfSignColor(tradeProfit),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (m.hasOfficeActivityFor(filter)) ...[
                        Text(
                          'کارمندان ${formatMoney(m.staff)}',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'PWO ${formatMoney(m.pwo)}',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'تبلیغات ${formatMoney(m.ads)}',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (dealDomains.length > 1 ||
                      (dealDomains.length == 1 &&
                          dealDomains.single != PerfDomain.property)) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final d in dealDomains)
                          if ((m.profitByDomain[d] ?? 0) != 0 ||
                              (m.soldCountByDomain[d] ?? 0) > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    perfDomainColor(d).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: perfDomainColor(d)
                                      .withValues(alpha: 0.35),
                                  width: 0.7,
                                ),
                              ),
                              child: Text(
                                '${d.shortLabel}: ${signedCompactToman(m.profitByDomain[d] ?? 0)}',
                                style: TextStyle(
                                  color: perfSignColor(
                                    m.profitByDomain[d] ?? 0,
                                  ),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                      ],
                    ),
                  ],
                  if (boughtCount > 0) ...[
                    const SizedBox(height: 3),
                    Row(
                      key: ValueKey('$keyPrefix-month-bought-${m.month}'),
                      children: [
                        const Icon(
                          Icons.shopping_bag_outlined,
                          size: 13,
                          color: AppTheme.muted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'خرید / سرمایه‌گذاری: $boughtCount مورد · ${formatMoney(boughtAmount)} (در خالص حساب نمی‌شود)',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (m.note.isNotEmpty && m.includesOffice(filter)) ...[
                    const SizedBox(height: 5),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.notes_rounded,
                            size: 13,
                            color: AppTheme.muted,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            m.note,
                            key: ValueKey('$keyPrefix-month-note-${m.month}'),
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (flag) ...[
                    const SizedBox(height: 4),
                    Row(
                      key: ValueKey('$keyPrefix-month-flag-${m.month}'),
                      children: const [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 13,
                          color: AppTheme.negative,
                        ),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'درآمد این ماه همان سود معاملات است و دوبار حساب نشد؛ برای اصلاح، ماه را باز کنید.',
                            style: TextStyle(
                              color: AppTheme.negative,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (m.skippedOverlappingPropertyTrades > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      _overlapLabel(m.skippedOverlappingPropertyTrades),
                      key: ValueKey('$keyPrefix-month-overlap-${m.month}'),
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String signedCompactToman(double v) {
  if (v == 0) return formatCompactToman(0);
  return '${v > 0 ? '+' : '-'}${formatCompactToman(v.abs())}';
}

String _overlapLabel(int n) => n == 1
    ? '۱ معامله ملک پورتفو با معامله دفتر یکی بود و دوبار حساب نشد.'
    : '$n معامله ملک پورتفو با معامله دفتر یکی بود و دوبار حساب نشد.';

/// Opens [MonthlyPerformancePage] / month detail without pages importing each other
/// through biz_page. Callers push the page themselves.
EdgeInsets perfListPadding(BuildContext context, {bool fab = false}) =>
    EdgeInsets.fromLTRB(
      12,
      12,
      12,
      (fab ? 96 : 24) + MediaQuery.paddingOf(context).bottom,
    );

class PerfFilterChip extends StatelessWidget {
  const PerfFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tone,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = tone ?? AppTheme.positive;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.16) : AppTheme.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? c : AppTheme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c : AppTheme.muted,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

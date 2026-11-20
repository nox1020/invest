import 'package:flutter/material.dart';
import 'package:invest/domain/services/performance_aggregator.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/pending_sync_mark.dart';
import 'package:invest/ui/widgets/performance_sections.dart';

/// Compact month card used on the Performance tab preview and the
/// «عملکرد ماهانه» list. Shows only the month name and signed net;
/// tap opens the month detail page for the rest.
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
    final empty = m.isEmptyFor(filter);
    final net = m.netFor(filter);
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
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
                        empty ? '—' : signedPerfMoney(net),
                        key: ValueKey('$keyPrefix-month-net-${m.month}'),
                        style: TextStyle(
                          color: empty ? AppTheme.muted : perfSignColor(net),
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
          ),
        ),
      ),
    );
  }
}

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

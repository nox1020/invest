import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/services/dashboard_digest.dart';
import 'package:invest/domain/services/portfolio_valuation.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';

/// «نیازمند توجه»: each alert opens the page where it is resolved.
class DashAlertsList extends StatelessWidget {
  const DashAlertsList({super.key, required this.alerts, required this.onOpen});
  final List<DashAlert> alerts;
  final void Function(DashAlert alert) onOpen;

  static IconData _icon(DashAlertKind k) => switch (k) {
        DashAlertKind.chequeOverdue => Icons.event_busy_rounded,
        DashAlertKind.chequeBounced => Icons.report_rounded,
        DashAlertKind.chequeDueSoon => Icons.event_rounded,
        DashAlertKind.pwoOverTarget => Icons.flag_rounded,
        DashAlertKind.unpriced => Icons.price_change_rounded,
        DashAlertKind.bizMismatch => Icons.error_outline_rounded,
      };

  static Color _color(DashAlert a) => switch (a.severity) {
        2 => kAmber,
        1 => a.kind == DashAlertKind.pwoOverTarget ? AppTheme.negative : kAmber,
        _ => AppTheme.muted,
      };

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (var i = 0; i < alerts.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: _color(alerts[i]).withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: ValueKey('dash-alert-${alerts[i].kind.name}-$i'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => onOpen(alerts[i]),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: BorderDirectional(start: BorderSide(color: _color(alerts[i]), width: 3)),
                ),
                child: Row(children: [
                  Icon(_icon(alerts[i].kind), color: _color(alerts[i]), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(fa(alerts[i].title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppTheme.title, fontSize: 12.5, fontWeight: FontWeight.w800)),
                      Text(fa(alerts[i].sub),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(11)),
                    ]),
                  ),
                  const Icon(Icons.chevron_left_rounded, color: AppTheme.muted, size: 18),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// PWO month vs target with one bar per person, plus the withdrawable amount.
class DashPwoCard extends StatelessWidget {
  const DashPwoCard({
    super.key,
    required this.summary,
    required this.withdrawable,
    required this.capBaseLabel,
    required this.onOpenPwo,
    required this.onOpenWithdrawals,
  });

  final PwoMonthSummary? summary;
  final double withdrawable;
  final String capBaseLabel;
  final VoidCallback onOpenPwo;
  final VoidCallback onOpenWithdrawals;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final withdraw = DashTile(
      label: 'قابل برداشت',
      value: fa(formatCompactToman(withdrawable)),
      valueKey: const ValueKey('dash-withdrawable'),
      color: AppTheme.positive,
      sub: capBaseLabel,
      onTap: onOpenWithdrawals,
    );
    if (s == null) {
      return DashCard(child: Row(children: [Expanded(child: withdraw)]));
    }
    final pctTone = s.target <= 0 ? AppTheme.muted : (s.within ? AppTheme.positive : AppTheme.negative);
    return DashCard(
      onTap: onOpenPwo,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(fa(formatCompactToman(s.total)),
                  key: const ValueKey('dash-pwo-total'),
                  style: const TextStyle(color: AppTheme.title, fontSize: 21, fontWeight: FontWeight.w800)),
            ),
          ),
          if (s.target > 0) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('از ${fa(formatCompactToman(s.target))}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(12)),
              ),
            ),
            Icon(Icons.check_circle_rounded,
                key: const ValueKey('dash-pwo-check'), size: 16, color: pctTone),
            const SizedBox(width: 3),
            Text(fa('${(s.ratio * 100).round()}٪'),
                style: TextStyle(color: pctTone, fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ]),
        if (s.target > 0) ...[
          const SizedBox(height: 8),
          DashBar(s.ratio, color: s.within ? AppTheme.positive : AppTheme.negative, height: 10),
        ],
        const SizedBox(height: 10),
        for (final p in s.people)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 22, maxWidth: 72),
                child: Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.title, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DashBar(s.target > 0 ? p.amount / s.target : 0,
                    color: AppTheme.positive.withValues(alpha: 0.75), height: 6),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(fa(formatCompactToman(p.amount)), style: mutedStyle(11.5, FontWeight.w700)),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: withdraw),
          const SizedBox(width: 8),
          Expanded(
            child: DashTile(
              label: 'ماه‌های در محدودهٔ هدف',
              value: fa('${s.monthsWithin} از ${s.monthsWithData}'),
              valueKey: const ValueKey('dash-pwo-met'),
              sub: 'میانگین ${fa(formatCompactToman(s.average))}',
            ),
          ),
        ]),
      ]),
    );
  }
}

String pwoMonthLabel(PwoMonth m) =>
    fa('${pwoMonthNames[(m.month - 1).clamp(0, 11)]} ${m.year}');

/// Next open cheques (overdue first), each with days left.
class DashUpcomingCheques extends StatelessWidget {
  const DashUpcomingCheques({super.key, required this.items, required this.calendar, this.onTap});
  final List<UpcomingCheque> items;
  final String calendar;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DashCard(
      onTap: onTap,
      child: Column(children: [
        for (final u in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              _DayChip(iso: u.check.dueDate, calendar: calendar, urgent: u.daysLeft <= 7),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${u.check.isPayable ? 'پرداختی' : 'دریافتی'}'
                    '${u.check.counterparty.trim().isEmpty ? '' : ' · ${u.check.counterparty.trim()}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.title, fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    u.daysLeft < 0
                        ? fa('${-u.daysLeft} روز از سررسید گذشته')
                        : u.daysLeft == 0
                            ? 'سررسید امروز'
                            : fa('${u.daysLeft} روز دیگر'),
                    style: TextStyle(
                      color: u.daysLeft <= 7 ? kAmber : AppTheme.muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    faSigned(formatMoney(u.check.isPayable ? -u.check.amount : u.check.amount, showSign: true)),
                    style: TextStyle(
                      color: u.check.isPayable ? AppTheme.negative : AppTheme.positive,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.iso, required this.calendar, required this.urgent});
  final String iso;
  final String calendar;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    // formatDisplayDate gives "dd month yyyy" (Jalali or Gregorian).
    final parts = formatDisplayDate(iso, calendar).split(' ');
    final day = parts.isNotEmpty ? parts.first : '';
    final month = parts.length > 1 ? parts[1] : '';
    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: (urgent ? kAmber : AppTheme.border).withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: [
        Text(fa(day.replaceFirst(RegExp(r'^0'), '')),
            style: const TextStyle(color: AppTheme.title, fontSize: 14, fontWeight: FontWeight.w800, height: 1.1)),
        Text(month, maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(9.5)),
      ]),
    );
  }
}

Color kindColor(AssetKind k) => switch (k) {
      AssetKind.gold => kGold,
      AssetKind.crypto => const Color(0xFF6FA8DC),
      AssetKind.stock => AppTheme.positive,
      AssetKind.cash => const Color(0xFF9AD0A8),
      AssetKind.property => const Color(0xFFC79BE0),
      AssetKind.vehicle => const Color(0xFFE08F6A),
      AssetKind.other => AppTheme.muted,
    };

/// Stacked bar of the holdings by kind, plus the largest single position.
class DashAssetMix extends StatelessWidget {
  const DashAssetMix({super.key, required this.valuation, this.onOpen});
  final PortfolioValuation valuation;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final total = valuation.holdingsValue;
    final groups = [for (final g in valuation.groups) if (g.value > 0) g];
    final top = valuation.holdings.isEmpty ? null : valuation.holdings.first;
    return DashCard(
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (total > 0 && groups.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final g in groups)
                  Expanded(
                    flex: (g.value / total * 1000).round().clamp(1, 1000),
                    child: ColoredBox(color: kindColor(g.kind)),
                  ),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        for (final g in groups)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: kindColor(g.kind), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(g.kind == AssetKind.gold ? 'طلا · پوشش تورم' : g.kind.label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(12)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    fa('${formatNumber(total <= 0 ? 0 : g.value / total * 100, decimals: 1)}٪ · ${formatCompactToman(g.value)}'),
                    style: TextStyle(color: kindColor(g.kind), fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ]),
          ),
        if (top != null && total > 0) ...[
          const SizedBox(height: 4),
          Text(
            fa('بیشترین وزن: ${top.asset.symbol.trim().isEmpty ? top.asset.name : top.asset.symbol}'
                ' · ${formatNumber(top.metrics.marketValue / total * 100, decimals: 1)}٪'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mutedStyle(11),
          ),
        ],
        const SizedBox(height: 6),
        const Text('جزئیات تخصیص در تب معاملات',
            style: TextStyle(color: AppTheme.positive, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class DashQuickAction {
  const DashQuickAction(this.icon, this.label, this.onTap, {this.key});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Key? key;
}

class DashQuickActions extends StatelessWidget {
  const DashQuickActions({super.key, required this.actions});
  final List<DashQuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final a in actions)
        Expanded(
          child: Semantics(
            button: true,
            label: a.label,
            excludeSemantics: true,
            child: InkWell(
              key: a.key,
              onTap: a.onTap,
              borderRadius: BorderRadius.circular(15),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Icon(a.icon, color: AppTheme.positive, size: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(a.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: mutedStyle(11, FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

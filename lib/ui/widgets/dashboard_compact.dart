import 'package:flutter/material.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/services/dashboard_digest.dart';
import 'package:invest/domain/services/portfolio_valuation.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/pages/quote_detail_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:invest/ui/widgets/sparkline.dart';

/// Shared card chrome for the compact dashboard.
class CompactCard extends StatelessWidget {
  const CompactCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Signed compact toman with the sign kept left of the number.
String signedToman(double v) => faSigned(formatCompactToman(v, showSign: true));
String signedPct(double v) => faSigned(formatPct(v));

/// Total, 30-day change, today & month P/L and the 30-day sparkline.
/// Every number comes from the same [PortfolioTrend] valuation basis.
class CompactSummaryCard extends StatelessWidget {
  const CompactSummaryCard({
    super.key,
    required this.nav,
    required this.trend30,
    required this.today,
    required this.month,
    this.onTap,
  });

  final double nav;
  final PortfolioTrend trend30;
  final PortfolioTrend today;
  final PortfolioTrend month;
  final VoidCallback? onTap;

  Widget _pl(String label, PortfolioTrend t, Key key) {
    final c = t.change;
    final tone = c == null ? AppTheme.muted : toneOf(c);
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 1, style: mutedStyle(11.5)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(
              c == null ? '—' : signedToman(c),
              style: TextStyle(color: tone, fontSize: 13.5, fontWeight: FontWeight.w800),
            ),
            if (t.pct != null) ...[
              const SizedBox(width: 5),
              Text(signedPct(t.pct!), style: TextStyle(color: tone, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = trend30.pct;
    final tone = p == null ? AppTheme.muted : toneOf(p);
    final pts = [for (final x in trend30.points) x.value];
    return CompactCard(
      key: const ValueKey('cd-summary'),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('ارزش کل سبد', maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(13))),
          if (p != null) ...[
            TrendArrow(p, size: 20),
            Text('۳۰ روز ${signedPct(p)}',
                key: const ValueKey('cd-30d'),
                style: TextStyle(color: tone, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ]),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(fa(formatCompactToman(nav)),
              key: const ValueKey('cd-total'),
              style: const TextStyle(color: AppTheme.title, fontSize: 26, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _pl('امروز', today, const ValueKey('cd-today'))),
          const SizedBox(width: 8),
          Expanded(child: _pl('این ماه', month, const ValueKey('cd-month'))),
        ]),
        if (pts.length >= 2) ...[
          const SizedBox(height: 10),
          Sparkline(values: pts, color: tone == AppTheme.muted ? AppTheme.positive : tone, height: 46),
        ],
      ]),
    );
  }
}

class TodayChip {
  const TodayChip({required this.id, required this.icon, required this.label, required this.color, required this.onTap});
  final String id;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// «امروز» strip — hidden entirely when there is nothing to act on.
class TodayStrip extends StatelessWidget {
  const TodayStrip({super.key, required this.chips});
  final List<TodayChip> chips;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('cd-today-strip'),
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          const Text('امروز', style: TextStyle(color: AppTheme.text, fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          for (final c in chips)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Material(
                color: c.color.withValues(alpha: 0.13),
                shape: StadiumBorder(side: BorderSide(color: c.color.withValues(alpha: 0.4))),
                child: InkWell(
                  key: ValueKey('cd-chip-${c.id}'),
                  customBorder: const StadiumBorder(),
                  onTap: c.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(c.icon, size: 15, color: c.color),
                      const SizedBox(width: 5),
                      Text(fa(c.label), style: TextStyle(color: c.color, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Horizontal live-rates strip; tap opens the quote detail.
class RatesStrip extends StatelessWidget {
  const RatesStrip({super.key, required this.quotes});
  final List<CommodityQuote> quotes;

  @override
  Widget build(BuildContext context) {
    if (quotes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        key: const ValueKey('cd-rates'),
        height: 84,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: quotes.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final q = quotes[i];
            final ch = q.change24h;
            final tone = ch == null ? AppTheme.muted : toneOf(ch);
            return Material(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => openQuoteDetail(context, q),
                child: Container(
                  width: 116,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(q.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(12)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(fa(q.formatPrice(compact: true)),
                          style: const TextStyle(color: AppTheme.title, fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                    Row(children: [
                      if (ch != null && ch != 0) TrendArrow(ch, size: 18),
                      Flexible(
                        child: Text(ch == null ? '—' : fa(formatPct(ch.abs()).replaceAll('+', '')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: tone, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// This month's PWO withdrawals against the target: at or under = green,
/// above = red. The withdrawn amount itself stays red (withdrawal rule).
class PwoProgressCard extends StatelessWidget {
  const PwoProgressCard({super.key, required this.summary, required this.monthLabel, required this.onTap});
  final PwoMonthSummary summary;
  final String monthLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final over = s.target > 0 && s.total > s.target;
    final tone = over ? AppTheme.negative : AppTheme.positive;
    final left = s.target - s.total;
    return CompactCard(
      key: const ValueKey('cd-pwo'),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.flag_rounded, size: 18, color: tone),
          const SizedBox(width: 6),
          Expanded(
            child: Text('PWO · برداشت $monthLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.w800)),
          ),
          if (s.target > 0)
            Icon(over ? Icons.cancel_rounded : Icons.check_circle_rounded,
                key: ValueKey(over ? 'cd-pwo-over' : 'cd-pwo-ok'), size: 18, color: tone),
        ]),
        if (s.target > 0) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: s.ratio.clamp(0.0, 1.0),
              minHeight: 10,
              color: tone,
              backgroundColor: AppTheme.border,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text('${fa(formatCompactToman(s.total))} برداشت',
            key: const ValueKey('cd-pwo-total'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.negative, fontSize: 12.5, fontWeight: FontWeight.w800)),
        if (s.target > 0)
          Text(
            'هدف ${fa(formatCompactToman(s.target))} · '
            '${over ? '${fa(formatCompactToman(-left))} بیش از هدف' : '${fa(formatCompactToman(left))} مانده'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: over ? AppTheme.negative : AppTheme.muted, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
      ]),
    );
  }
}

/// One-line section that expands to show its detail.
class CollapsibleSection extends StatelessWidget {
  const CollapsibleSection({
    super.key,
    required this.id,
    required this.icon,
    required this.color,
    required this.title,
    required this.line,
    required this.open,
    required this.onToggle,
    required this.child,
    this.value,
    this.valueColor = AppTheme.muted,
  });

  final String id;
  final IconData icon;
  final Color color;
  final String title;
  final String line;
  final String? value;
  final Color valueColor;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CompactCard(
      key: ValueKey('cd-sec-$id'),
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: ValueKey('cd-sec-$id-head'),
          borderRadius: BorderRadius.circular(16),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.w800)),
                  Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(11.5)),
                ]),
              ),
              if (value != null)
                Flexible(
                  flex: 0,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(value!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.w800)),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppTheme.muted),
            ]),
          ),
        ),
        if (open)
          Padding(
            key: ValueKey('cd-sec-$id-body'),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: child,
          ),
      ]),
    );
  }
}

/// A holdings row inside an expanded section.
class CompactHoldingRow extends StatelessWidget {
  const CompactHoldingRow({super.key, required this.name, required this.value, required this.pct, this.onTap});
  final String name;
  final double value;
  final double pct;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(children: [
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Flexible(
            child: Text(fa(formatCompactToman(value)), maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(12)),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56),
            child: Text(signedPct(pct),
                textAlign: TextAlign.end,
                style: TextStyle(color: toneOf(pct), fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

/// Last refresh + pull hint at the bottom of the compact list.
class LastUpdatedLine extends StatelessWidget {
  const LastUpdatedLine({super.key, required this.at});
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('cd-updated'),
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.south_rounded, size: 14, color: AppTheme.muted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '${at == null ? 'هنوز بروزرسانی نشده' : 'آخرین بروزرسانی ${agoFa(at!)}'} · برای بروزرسانی بکشید',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mutedStyle(11),
          ),
        ),
      ]),
    );
  }
}

/// Compact ↔ full switch for the dashboard header.
class DashModeToggle extends StatelessWidget {
  const DashModeToggle({super.key, required this.compact, required this.onChanged});
  final bool compact;
  final ValueChanged<bool> onChanged;

  Widget _seg(String label, bool on, VoidCallback tap, Key key) => InkWell(
        key: key,
        onTap: tap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: on ? AppTheme.accent : null, borderRadius: BorderRadius.circular(16)),
          child: Text(label,
              style: TextStyle(color: on ? AppTheme.text : AppTheme.muted, fontSize: 12, fontWeight: on ? FontWeight.w700 : FontWeight.w600)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _seg('خلاصه', compact, () => onChanged(true), const ValueKey('dash-mode-compact')),
        _seg('کامل', !compact, () => onChanged(false), const ValueKey('dash-mode-full')),
      ]),
    );
  }
}

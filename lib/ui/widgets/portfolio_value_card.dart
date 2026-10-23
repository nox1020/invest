import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/portfolio_valuation.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:invest/ui/widgets/sparkline.dart';

/// «ارزش پورتفو» hero card: one valuation, a like-for-like 30-day trend,
/// price freshness, rate source and an expandable breakdown.
class PortfolioValueCard extends StatefulWidget {
  const PortfolioValueCard({
    super.key,
    required this.snap,
    required this.trend,
    required this.usdIsLive,
    required this.pricesAsOf,
    required this.offline,
    required this.lastSyncedAt,
    this.refreshing = false,
    this.onOpenCharts,
    this.initiallyExpanded = false,
    this.now,
  });

  final DashboardSnapshot snap;
  final PortfolioTrend trend;
  final bool usdIsLive;
  final DateTime? pricesAsOf;
  final bool offline;
  final DateTime? lastSyncedAt;
  final bool refreshing;
  final VoidCallback? onOpenCharts;
  final bool initiallyExpanded;
  final DateTime? now;

  @override
  State<PortfolioValueCard> createState() => _PortfolioValueCardState();
}

class _PortfolioValueCardState extends State<PortfolioValueCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final snap = widget.snap;
    final val = snap.valuation;
    final nav = snap.marketValue;
    final cheques = snap.chequeNav;
    final usd = snap.marketValueUsd;
    final trendPct = widget.trend.pct;
    final goldG = snap.goldHoldingG;
    final goldValue = val?.goldValue ?? 0;
    final goldShare = nav > 0 ? goldValue / nav * 100 : 0.0;
    final unpriced = val?.unpriced ?? const [];
    final stale = widget.pricesAsOf == null ||
        (widget.now ?? DateTime.now()).difference(widget.pricesAsOf!) > const Duration(hours: 1);

    final semantic = StringBuffer('ارزش پورتفو ${formatMoney(nav)}. ')
      ..write('سود باز ${formatMoney(snap.unrealizedPnl, showSign: true)}. ');
    if (trendPct != null) semantic.write('روند ${widget.trend.days} روز ${formatPct(trendPct)}. ');
    if (widget.offline) semantic.write('آفلاین. ');

    final tone = trendPct == null ? AppTheme.positive : toneOf(trendPct);

    return Semantics(
      container: true,
      label: semantic.toString(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('pv-card'),
          onTap: widget.onOpenCharts,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF245A44), Color(0xFF17362A), Color(0xFF101F18)],
                stops: [0, 0.5, 1],
              ),
              border: Border.all(color: AppTheme.border.withValues(alpha: 0.7)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  height: 2,
                  child: widget.refreshing
                      ? const LinearProgressIndicator(
                          key: ValueKey('pv-loading'),
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                          color: AppTheme.positive,
                        )
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _header(),
                    const SizedBox(height: 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        fa(formatMoney(nav)),
                        key: const ValueKey('pv-nav'),
                        maxLines: 1,
                        style: const TextStyle(
                          color: AppTheme.title,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (usd != null)
                          Text('≈ ${formatUsd(usd)}',
                              key: const ValueKey('pv-usd'),
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(color: kUsd, fontSize: 15, fontWeight: FontWeight.w700)),
                        if (usd != null && snap.usdtTmn != null)
                          DashTag(
                            fa('${widget.usdIsLive ? 'نرخ زنده' : 'نرخ ذخیره‌شده'} ${formatNumber(snap.usdtTmn!)}'),
                            key: const ValueKey('pv-rate'),
                            color: widget.usdIsLive ? kUsd : AppTheme.muted,
                          ),
                        if (widget.pricesAsOf != null)
                          Text(
                            'قیمت‌ها: ${agoFa(widget.pricesAsOf!, now: widget.now)}',
                            key: const ValueKey('pv-fresh'),
                            style: TextStyle(
                              color: stale ? kAmber : AppTheme.muted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    if (cheques.affectsNav) ...[
                      const SizedBox(height: 8),
                      Text(
                        'دارایی‌ها ${fa(formatCompactToman(snap.holdingsValue))}'
                        ' · چک دریافتی ${faSigned(formatCompactToman(cheques.pendingReceivable, showSign: true))}'
                        ' · پرداختی ${faSigned(formatCompactToman(-cheques.pendingPayable, showSign: true))}',
                        key: const ValueKey('pv-cheque-line'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mutedStyle(11, FontWeight.w700),
                      ),
                    ],
                    if (goldG > 0) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: DashTag(
                          fa('پوشش تورم · طلا ${formatGrams(goldG)} ۱۸ عیار'
                              '${nav > 0 ? ' · ${goldShare.round()}٪ سبد' : ''}'),
                          key: const ValueKey('pv-gold-chip'),
                          color: kGold,
                          icon: Icons.diamond_outlined,
                        ),
                      ),
                    ],
                    if (unpriced.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        fa('${unpriced.length} دارایی بدون قیمت زنده — با قیمت خرید حساب شد'),
                        key: const ValueKey('pv-unpriced'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kAmber, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _stats(),
                    if (widget.trend.points.length >= 2) ...[
                      const SizedBox(height: 12),
                      Sparkline(
                        values: [for (final p in widget.trend.points) p.value],
                        color: tone,
                        height: 40,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(
                        child: Text(
                          fa('${widget.trend.days} روز گذشته · بدون چک'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mutedStyle(10),
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('pv-toggle'),
                        onPressed: () => setState(() => _expanded = !_expanded),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.positive,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(_expanded ? 'بستن جزئیات' : 'جزئیات ارزش',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
                        ]),
                      ),
                    ]),
                    if (_expanded) _breakdown(val, nav, goldG, goldValue, goldShare),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final offline = widget.offline;
    final sync = widget.lastSyncedAt;
    final row = Row(children: [
      Flexible(
        flex: 2,
        child: Text('ارزش پورتفو',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(13, FontWeight.w700)),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 3,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: offline
              ? const SizedBox.shrink()
              : const DashTag('زنده', key: ValueKey('pv-live'), color: AppTheme.positive, icon: Icons.circle),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        flex: 3,
        child: Text('میز سرمایه', maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(11)),
      ),
      const Icon(Icons.chevron_left_rounded, size: 16, color: AppTheme.muted),
    ]);
    if (!offline) return row;
    // Offline: the last-sync tag gets its own line so it is never cut.
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row,
      const SizedBox(height: 6),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: DashTag(
          sync == null ? 'آفلاین' : 'آفلاین · آخرین همگام‌سازی ${hhmm(sync)}',
          key: const ValueKey('pv-offline'),
          color: kAmber,
          icon: Icons.cloud_off_rounded,
        ),
      ),
    ]);
  }

  Widget _stats() {
    final snap = widget.snap;
    final usdPnl = snap.unrealizedUsd;
    final t = widget.trend;
    Widget stat(String label, String value, Color tone, {num? dir, String? sub, Key? key, bool ltr = false}) =>
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(11)),
            const SizedBox(height: 4),
            Row(children: [
              if (dir != null) TrendArrow(dir),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value,
                      key: key,
                      maxLines: 1,
                      textDirection: ltr ? TextDirection.ltr : null,
                      style: TextStyle(color: tone, fontSize: 14, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
            if (sub != null)
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tone, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      stat('سود باز', fa(formatCompactToman(snap.unrealizedPnl.abs())), toneOf(snap.unrealizedPnl),
          dir: snap.unrealizedPnl, sub: fa(formatPct(snap.unrealizedPct.abs()).replaceAll('+', '')),
          key: const ValueKey('pv-pnl')),
      stat('سود دلاری', usdPnl == null ? '—' : formatUsd(usdPnl.abs(), compact: true),
          usdPnl == null ? AppTheme.muted : toneOf(usdPnl),
          dir: usdPnl, key: const ValueKey('pv-usd-pnl'), ltr: usdPnl != null),
      if (t.pct != null)
        stat(fa('روند ${t.days} روز'), fa(formatPct(t.pct!.abs()).replaceAll('+', '')), toneOf(t.pct!),
            dir: t.pct, sub: 'از ${fa(formatCompactToman(t.baseValue!))}', key: const ValueKey('pv-trend'))
      else
        stat('بهای تمام‌شده', fa(formatCompactToman(snap.costBasis)), AppTheme.muted),
    ]);
  }

  Widget _row(String k, String v, {Color? c, bool bold = false, Key? key}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(12))),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Text(v,
                  key: key,
                  style: TextStyle(
                      color: c ?? AppTheme.title,
                      fontSize: 12.5,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w700)),
            ),
          ),
        ]),
      );

  Widget _breakdown(PortfolioValuation? val, double nav, double goldG, double goldValue, double goldShare) {
    final snap = widget.snap;
    final ch = snap.chequeNav;
    final others = [
      for (final g in val?.groups ?? const <ValuationGroup>[])
        if (g.kind != AssetKind.gold) g,
    ];
    final count = snap.holdingCount;
    return Column(key: const ValueKey('pv-breakdown'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(color: AppTheme.border, height: 16),
      if (goldG > 0)
        Container(
          key: const ValueKey('pv-gold-section'),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [kGold.withValues(alpha: 0.16), Colors.transparent]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kGold.withValues(alpha: 0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.diamond_outlined, color: kGold, size: 16),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('موجودی طلا · پوشش تورم',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: kGold, fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 6),
              Text(fa(formatGrams(goldG)),
                  style: const TextStyle(color: AppTheme.title, fontSize: 13, fontWeight: FontWeight.w800)),
            ]),
            _row('ارزش (معادل ۱۸ عیار)', fa(formatMoney(goldValue))),
            if (nav > 0) _row('سهم از کل پورتفو', fa('${formatNumber(goldShare, decimals: 1)}٪'), c: kGold),
            if (goldG > 0 && goldValue > 0)
              _row('قیمت هر گرم ۱۸ عیار', fa(formatMoney(goldValue / goldG)), c: AppTheme.muted),
            Text('جزو جمع ارزش پورتفو حساب شده است', style: mutedStyle(10.5)),
          ]),
        ),
      for (final g in others)
        _row(fa('${g.kind.label} (${g.count})'), fa(formatMoney(g.value))),
      _row(fa('جمع دارایی‌ها ($count قلم)'), fa(formatMoney(snap.holdingsValue)), bold: true),
      if (ch.pendingReceivableCount > 0)
        _row(fa('چک دریافتی باز (${ch.pendingReceivableCount} فقره)'),
            faSigned(formatMoney(ch.pendingReceivable, showSign: true)), c: AppTheme.positive,
            key: const ValueKey('pv-recv')),
      if (ch.pendingPayableCount > 0)
        _row(fa('چک پرداختی باز (${ch.pendingPayableCount} فقره)'),
            faSigned(formatMoney(-ch.pendingPayable, showSign: true)), c: AppTheme.negative,
            key: const ValueKey('pv-pay')),
      const Divider(color: AppTheme.border, height: 14),
      _row('جمع ارزش پورتفو', fa(formatMoney(nav)), bold: true),
      _row('بهای تمام‌شده', fa(formatMoney(snap.costBasis)), c: AppTheme.muted),
      if (widget.trend.netFlows != 0 && widget.trend.pct != null)
        _row(fa('خرید/فروش خالص در ${widget.trend.days} روز (از روند کم شد)'),
            faSigned(formatCompactToman(widget.trend.netFlows, showSign: true)), c: AppTheme.muted),
    ]);
  }
}

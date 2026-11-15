import 'package:flutter/material.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/portfolio_valuation.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';

/// Compact «ارزش پورتفو» hero on the dashboard: header, total value, one
/// line with the 30-day trend and the open profit, and at most one warning
/// chip. Every detail (rate, freshness, cheques, gold, breakdown, charts)
/// lives on the «ارزش پورتفو» page that a tap opens ([onOpenCharts]).
class PortfolioValueCard extends StatelessWidget {
  const PortfolioValueCard({
    super.key,
    required this.snap,
    required this.trend,
    required this.usdIsLive,
    required this.pricesAsOf,
    required this.offline,
    this.refreshing = false,
    this.onOpenCharts,
    this.now,
  });

  final DashboardSnapshot snap;

  /// The shared 30-day trend (see `portfolioTrend30`).
  final PortfolioTrend trend;
  final bool usdIsLive;
  final DateTime? pricesAsOf;
  final bool offline;
  final bool refreshing;
  final VoidCallback? onOpenCharts;
  final DateTime? now;

  /// Prices older than this get the «قیمت‌ها قدیمی» chip.
  static const staleAfter = Duration(hours: 1);

  @override
  Widget build(BuildContext context) {
    final nav = snap.marketValue;
    final trendPct = trend.pct;
    final pnl = snap.unrealizedPnl;
    final unpriced = snap.valuation?.unpriced ?? const [];
    final stale = pricesAsOf == null ||
        (now ?? DateTime.now()).difference(pricesAsOf!) > staleAfter;
    final live = !offline && usdIsLive;

    final semantic = StringBuffer('ارزش پورتفو ${formatMoney(nav)}. ');
    if (trendPct != null) semantic.write('روند ${trend.days} روز ${formatPct(trendPct)}. ');
    semantic.write('سود باز ${formatMoney(pnl, showSign: true)}. ');
    if (unpriced.isNotEmpty) semantic.write('${unpriced.length} دارایی بدون قیمت زنده. ');
    if (!live) semantic.write('قیمت ذخیره‌شده. ');

    return Semantics(
      container: true,
      button: onOpenCharts != null,
      label: semantic.toString(),
      hint: 'جزئیات ارزش',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('pv-card'),
          onTap: onOpenCharts,
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
                  child: refreshing
                      ? const LinearProgressIndicator(
                          key: ValueKey('pv-loading'),
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                          color: AppTheme.positive,
                        )
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _header(live),
                    const SizedBox(height: 8),
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
                    const SizedBox(height: 6),
                    _summaryLine(trendPct, pnl),
                    if (unpriced.isNotEmpty || stale) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: unpriced.isNotEmpty
                            ? DashTag(
                                fa('${unpriced.length} دارایی بدون قیمت زنده'),
                                key: const ValueKey('pv-unpriced'),
                                color: kAmber,
                                icon: Icons.warning_amber_rounded,
                              )
                            : const DashTag(
                                'قیمت‌ها قدیمی',
                                key: ValueKey('pv-stale'),
                                color: kAmber,
                                icon: Icons.schedule_rounded,
                              ),
                      ),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(bool live) => Row(children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('ارزش پورتفو', maxLines: 1, style: mutedStyle(13, FontWeight.w700)),
              const SizedBox(width: 8),
              live
                  ? const DashTag('زنده', key: ValueKey('pv-live'), color: AppTheme.positive, icon: Icons.circle)
                  : const DashTag('ذخیره‌شده', key: ValueKey('pv-stored'), color: AppTheme.muted),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        const Text('جزئیات',
            key: ValueKey('pv-details'),
            style: TextStyle(color: AppTheme.positive, fontSize: 12, fontWeight: FontWeight.w700)),
        const Icon(Icons.chevron_left_rounded, size: 18, color: AppTheme.positive),
      ]);

  /// «▲ ۳٫۲٪ روند ۳۰ روز · سود باز +۸۷٫۵ م» — one line, shrinks on 320 px.
  Widget _summaryLine(double? trendPct, double pnl) {
    const label = TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w600);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (trendPct != null) ...[
          TrendArrow(trendPct, size: 18),
          Text(fa(formatPct(trendPct.abs()).replaceAll('+', '')),
              key: const ValueKey('pv-trend'),
              style: TextStyle(color: toneOf(trendPct), fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(width: 4),
          Text(fa('روند ${trend.days} روز'), style: label),
          const Text('  ·  ', style: label),
        ],
        const Text('سود باز ', style: label),
        Text(faSigned(formatCompactToman(pnl, showSign: true)),
            key: const ValueKey('pv-pnl'),
            style: TextStyle(color: toneOf(pnl), fontSize: 13.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

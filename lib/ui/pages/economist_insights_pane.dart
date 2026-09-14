import 'package:flutter/material.dart';
import 'package:invest/domain/services/economist_insights.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

class EconomistInsightsPane extends StatelessWidget {
  const EconomistInsightsPane({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final holdings = HoldingMetrics.activeHoldings(
      assets: state.assets,
      openTrades: state.openTrades,
    );
    var cost = 0.0;
    var pnl = 0.0;
    for (final h in holdings) {
      cost += h.metrics.costBasis;
      pnl += h.metrics.unrealizedPnl;
    }
    final briefing = buildEconomistInsights(
      holdings: holdings,
      quotes: state.commodityIndex,
      inflation: state.iranInflation,
      unrealizedPnlPct: cost.abs() < 1e-9 ? null : pnl / cost * 100,
    );

    return RefreshIndicator(
      onRefresh: () => state.refreshCommodityIndex(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: shellPagePadding(),
        children: [
          _MixStrip(mix: briefing.mix),
          const SizedBox(height: 12),
          const Text(
            'از نگاه اقتصاددان',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'توصیهٔ تخصیص نسبت به پورتفو، تورم رسمی و نبض شاخص — نه سیگنال خرید و فروش.',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppTheme.muted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < briefing.insights.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _InsightCard(insight: briefing.insights[i], featured: i == 0),
          ],
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Text(
              'این بینش‌ها قاعده‌محورند: ترکیب سبد را با طلا، دلار آزاد و CPI مرکز آمار می‌سنجند. تصمیم نهایی با شماست و جایگزین مشاوره سرمایه‌گذاری شخصی نیست.',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppTheme.muted,
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MixStrip extends StatelessWidget {
  const _MixStrip({required this.mix});

  final PortfolioSleeveWeights mix;

  @override
  Widget build(BuildContext context) {
    if (mix.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Text(
          'هنوز موقعیت بازی نیست — بینش‌ها روی هستهٔ پیشنهادی خانوار ایران بنا می‌شوند.',
          textAlign: TextAlign.right,
          style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45),
        ),
      );
    }

    final slices = <({String label, double pct, Color color})>[
      (label: 'طلا', pct: mix.goldPct, color: const Color(0xFFE8C547)),
      (label: 'نقد', pct: mix.cashPct, color: AppTheme.positive),
      (label: 'ریسک', pct: mix.cryptoPct, color: const Color(0xFFF7931A)),
      (label: 'سهام', pct: mix.stockPct, color: const Color(0xFF4C8DFF)),
      (label: 'واقعی', pct: mix.realPct, color: const Color(0xFF5B8DEF)),
      (label: 'سایر', pct: mix.otherPct, color: const Color(0xFF4ECDC4)),
    ].where((e) => e.pct >= 0.5).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ترکیب پورتفو',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  for (final s in slices)
                    Expanded(
                      flex: (s.pct * 10).round().clamp(1, 1000),
                      child: Container(color: s.color),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              for (final s in slices)
                _MixChip(
                  label:
                      '${s.label} ${s.pct >= 10 ? s.pct.round() : s.pct.toStringAsFixed(1)}٪',
                  color: s.color,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MixChip extends StatelessWidget {
  const _MixChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, this.featured = false});

  final EconomistInsight insight;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final tone = switch (insight.tone) {
      EconomistInsightTone.caution => AppTheme.negative,
      EconomistInsightTone.watch => const Color(0xFFE8C547),
      EconomistInsightTone.constructive => AppTheme.positive,
      EconomistInsightTone.note => const Color(0xFF7EB6FF),
    };
    final icon = switch (insight.tone) {
      EconomistInsightTone.caution => Icons.report_outlined,
      EconomistInsightTone.watch => Icons.visibility_outlined,
      EconomistInsightTone.constructive => Icons.verified_outlined,
      EconomistInsightTone.note => Icons.menu_book_outlined,
    };

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: featured ? tone.withValues(alpha: 0.45) : AppTheme.border,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: tone),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, color: tone, size: 18),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                insight.title,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  color: AppTheme.title,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tone.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    insight.category,
                                    style: TextStyle(
                                      color: tone,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      insight.body,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 12.5,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        insight.action,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: tone,
                          fontSize: 12,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dual_currency_chart.dart';
import 'package:provider/provider.dart';

class CapitalChartPage extends StatelessWidget {
  const CapitalChartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final metrics = state.metrics;
    final usdt = state.liveUsdt ?? state.settings.usdtTmnRate;
    final calendar = state.settings.calendar;
    final growth = state.capitalGrowthSeries;
    final year = state.yearRealizedChartSeries;
    final usdValue =
        metrics == null ? null : tomanToUsd(metrics.totalValue, usdt);
    final usdYear =
        metrics == null ? null : tomanToUsd(metrics.yearRealizedPnl, usdt);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('نمودار سرمایه'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (metrics != null)
            _Headline(
              toman: formatMoney(metrics.totalValue),
              usd: usdValue == null ? null : formatUsd(usdValue),
            ),
          const SizedBox(height: 16),
          _ChartCard(
            title: 'ارزش کل سرمایه',
            child: DualCurrencyChart(
              points: growth,
              calendar: calendar,
              usdtRate: usdt,
            ),
          ),
          const SizedBox(height: 16),
          _ChartCard(
            title: 'سود سالانه تحقق‌یافته',
            caption: [
              if (metrics != null && metrics.yearKey.isNotEmpty) metrics.yearKey,
              if (usdYear != null) formatUsd(usdYear, showSign: true),
            ].join(' · '),
            child: year.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Text(
                      'در این سال معامله بسته‌شده‌ای نیست',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  )
                : DualCurrencyChart(
                    points: year,
                    calendar: calendar,
                    usdtRate: usdt,
                    lineColor: const Color(0xFF5B8DEF),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.toman, this.usd});

  final String toman;
  final String? usd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1A3A2C), Color(0xFF16241D)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ارزش فعلی',
            textAlign: TextAlign.right,
            style: TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            toman,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.title,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (usd != null) ...[
            const SizedBox(height: 4),
            Text(
              usd!,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFFE8C547),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.child,
    this.caption,
  });

  final String title;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          if (caption != null && caption!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

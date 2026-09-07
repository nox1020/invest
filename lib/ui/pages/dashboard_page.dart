import 'package:flutter/material.dart';
import 'package:invest/domain/services/dashboard_pnl.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/pages/capital_chart_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/metric_card.dart';
import 'package:provider/provider.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final m = state.metrics;
    if (m == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                state.offline ? Icons.cloud_off_outlined : Icons.inbox_outlined,
                size: 40,
                color: AppTheme.muted,
              ),
              const SizedBox(height: 12),
              Text(
                state.offline
                    ? 'هنوز داده‌ای برای نمایش آفلاین ذخیره نشده است'
                    : 'داده‌ای نیست',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.muted),
              ),
              if (state.offline) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => state.tryGoOnline(),
                  child: const Text('تلاش برای اتصال'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final usdt = state.liveUsdt ?? state.settings.usdtTmnRate;
    final usdValue = tomanToUsd(m.totalValue, usdt);

    final currencyPnl = DashboardCurrencyPnl.compute(
      assets: state.assets,
      openTrades: state.openTrades,
      closedTrades: state.closedTrades,
      usdtTmn: usdt,
      yearKey: m.yearKey,
      calendar: state.settings.calendar,
    );
    final totalPnlPct = DashboardCurrencyPnl.totalPnlPct(
      totalPnl: m.totalPnl,
      assets: state.assets,
      openTrades: state.openTrades,
    );
    final totalUsdPct = DashboardCurrencyPnl.totalUsdPnlPct(
      totalUsdPnl: currencyPnl.totalUsd,
      assets: state.assets,
      openTrades: state.openTrades,
      closedTrades: state.closedTrades,
    );

    String tone(num v) => v > 0 ? 'positive' : (v < 0 ? 'negative' : '');

    void openCharts() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const CapitalChartPage()),
      );
    }

    Widget metricRow(List<Widget> cards, {double gap = 12}) {
      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              cards[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }

    final totalUsd = currencyPnl.totalUsd;
    final realizedUsd = currencyPnl.realizedUsd;
    final yearUsd = currencyPnl.yearRealizedUsd;
    final unrealizedUsd = currencyPnl.unrealizedUsd;

    return RefreshIndicator(
      onRefresh: () => state.refreshAll(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: shellPagePadding(),
        children: [
          metricRow([
            MetricCard(
              title: 'ارزش کل سرمایه',
              value: formatMoney(m.totalValue),
              caption: usdValue == null ? null : formatUsd(usdValue),
              hero: true,
              onTap: openCharts,
            ),
            MetricCard(
              title: 'سود سالانه تحقق‌یافته',
              value: formatMoney(m.yearRealizedPnl, showSign: true),
              caption: [
                if (m.yearKey.isNotEmpty) m.yearKey,
                if (yearUsd != null) formatUsd(yearUsd, showSign: true),
              ].join(' · '),
              tone: tone(m.yearRealizedPnl),
              hero: true,
              onTap: openCharts,
            ),
          ]),
          const SizedBox(height: 18),
          const Text(
            'سود و زیان',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          metricRow([
            MetricCard(
              title: 'سود / زیان تومانی',
              value: formatMoney(m.totalPnl, showSign: true),
              caption: formatPct(totalPnlPct),
              tone: tone(m.totalPnl),
            ),
            MetricCard(
              title: 'سود / زیان دلاری',
              value: totalUsd == null
                  ? '—'
                  : formatUsd(totalUsd, showSign: true),
              caption: totalUsd == null
                  ? 'بهای دلاری خرید ناقص است'
                  : (totalUsdPct == null ? null : formatPct(totalUsdPct)),
              tone: totalUsd == null ? null : tone(totalUsd),
            ),
          ], gap: 8),
          const SizedBox(height: 8),
          metricRow([
            MetricCard(
              title: 'تحقق‌یافته (تومان)',
              value: formatMoney(m.realizedPnl, showSign: true),
              caption: realizedUsd == null
                  ? null
                  : formatUsd(realizedUsd, showSign: true),
              tone: tone(m.realizedPnl),
            ),
            MetricCard(
              title: 'تحقق‌نیافته (تومان)',
              value: formatMoney(m.unrealizedPnl, showSign: true),
              caption: unrealizedUsd == null
                  ? null
                  : formatUsd(unrealizedUsd, showSign: true),
              tone: tone(m.unrealizedPnl),
            ),
          ], gap: 8),
          const SizedBox(height: 8),
          metricRow([
            MetricCard(
              title: 'معاملات باز',
              value: '${m.openCount}',
            ),
            MetricCard(
              title: 'معاملات بسته',
              value: '${m.closedCount}',
            ),
          ], gap: 8),
        ],
      ),
    );
  }
}

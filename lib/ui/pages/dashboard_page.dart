import 'package:flutter/material.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
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
    final g = m.goldFund;
    final narrow = MediaQuery.sizeOf(context).width < 520;
    String tone(num v) => v > 0 ? 'positive' : (v < 0 ? 'negative' : '');

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
              hero: true,
            ),
            MetricCard(
              title: 'سود سالانه تحقق‌یافته',
              value: formatMoney(m.yearRealizedPnl, showSign: true),
              caption: m.yearKey,
              tone: tone(m.yearRealizedPnl),
              hero: true,
            ),
          ]),
          const SizedBox(height: 18),
          const Text(
            'صندوق طلا',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          metricRow(
            [
              MetricCard(
                title: 'طلای واردشده',
                value: formatGrams(g.goldInG),
              ),
              MetricCard(
                title: 'طلای خارج‌شده',
                value: formatGrams(g.goldOutG),
              ),
              MetricCard(
                title: 'موجودی طلا',
                value: formatGrams(g.goldHoldingG),
                caption: g.goldHoldingG > 0 ? 'بدهی به صندوق' : null,
                tone: g.goldHoldingG > 0 ? 'negative' : null,
              ),
            ],
            gap: 8,
          ),
          const SizedBox(height: 18),
          const Text(
            'خلاصه',
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
              title: 'سود / زیان کل',
              value: formatMoney(m.totalPnl, showSign: true),
              caption: formatPct(m.totalPnlPct),
              tone: tone(m.totalPnl),
            ),
            MetricCard(
              title: 'تحقق‌یافته',
              value: formatMoney(m.realizedPnl, showSign: true),
              tone: tone(m.realizedPnl),
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
          if (state.liveUsdt != null || state.settings.usdtTmnRate != null) ...[
            const SizedBox(height: 18),
            MetricCard(
              title: 'نرخ تتر',
              value:
                  '${formatNumber(state.liveUsdt ?? state.settings.usdtTmnRate ?? 0)} تومان',
              caption: state.liveUsdt != null ? 'زنده' : 'ذخیره‌شده',
            ),
          ],
          if (state.liveGold != null ||
              state.settings.goldTmnPerGram != null) ...[
            const SizedBox(height: 8),
            MetricCard(
              title: 'قیمت طلا (گرم)',
              value:
                  '${formatNumber(state.liveGold ?? state.settings.goldTmnPerGram ?? 0)} تومان',
              caption: state.liveGold != null ? 'زنده' : 'ذخیره‌شده',
            ),
          ],
        ],
      ),
    );
  }
}

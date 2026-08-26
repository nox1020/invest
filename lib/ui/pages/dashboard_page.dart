import 'package:flutter/material.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/metric_card.dart';
import 'package:provider/provider.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final m = state.metrics;
    if (state.loading && m == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (m == null) {
      return const Center(child: Text('داده‌ای نیست'));
    }
    final g = m.goldFund;
    String tone(num v) => v > 0 ? 'positive' : (v < 0 ? 'negative' : '');

    return RefreshIndicator(
      onRefresh: () async {
        await state.refreshQuotes();
        await state.refresh();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  title: 'ارزش کل سرمایه',
                  value: formatMoney(m.totalValue),
                  hero: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  title: 'سود سالانه تحقق‌یافته',
                  value: formatMoney(m.yearRealizedPnl, showSign: true),
                  caption: m.yearKey,
                  tone: tone(m.yearRealizedPnl),
                  hero: true,
                ),
              ),
            ],
          ),
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
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  title: 'طلای واردشده',
                  value: formatGrams(g.goldInG),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricCard(
                  title: 'طلای خارج‌شده',
                  value: formatGrams(g.goldOutG),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricCard(
                  title: 'موجودی طلا',
                  value: formatGrams(g.goldHoldingG),
                  caption: g.goldHoldingG > 0 ? 'بدهی به صندوق' : null,
                  tone: g.goldHoldingG > 0 ? 'negative' : null,
                ),
              ),
            ],
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
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  title: 'سود / زیان کل',
                  value: formatMoney(m.totalPnl, showSign: true),
                  caption: formatPct(m.totalPnlPct),
                  tone: tone(m.totalPnl),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricCard(
                  title: 'تحقق‌یافته',
                  value: formatMoney(m.realizedPnl, showSign: true),
                  tone: tone(m.realizedPnl),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  title: 'معاملات باز',
                  value: '${m.openCount}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricCard(
                  title: 'معاملات بسته',
                  value: '${m.closedCount}',
                ),
              ),
            ],
          ),
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

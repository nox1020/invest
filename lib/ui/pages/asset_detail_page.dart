import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/chart_series.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/asset_editor_sheet.dart';
import 'package:invest/ui/widgets/dual_currency_chart.dart';
import 'package:provider/provider.dart';

Future<void> openAssetDetail(
  BuildContext context, {
  required Asset asset,
  required HoldingMetrics metrics,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AssetDetailPage(asset: asset, metrics: metrics),
    ),
  );
}

class AssetDetailPage extends StatelessWidget {
  const AssetDetailPage({
    super.key,
    required this.asset,
    required this.metrics,
  });

  final Asset asset;
  final HoldingMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final usdt = state.liveUsdt ?? state.settings.usdtTmnRate;
    final calendar = state.settings.calendar;
    final lots = state.openTrades
        .where((t) => t.assetId == asset.id && t.quantity > 1e-9)
        .toList()
      ..sort((a, b) => a.buyDate.compareTo(b.buyDate));

    final buyToman = metrics.avgBuyPrice;
    final buyUsd = metrics.avgBuyPriceUsd ?? tomanToUsd(buyToman, usdt);
    final curToman = metrics.currentPrice;
    final curUsd = tomanToUsd(curToman, usdt);
    final series = _unitPriceSeries(
      asset: asset,
      metrics: metrics,
      lots: lots,
    );

    final pnlTone =
        metrics.unrealizedPnl >= 0 ? AppTheme.positive : AppTheme.negative;

    return Scaffold(
      appBar: AppBar(
        title: Text(asset.name),
        centerTitle: true,
        actions: [
          if (state.canMutate)
            IconButton(
              tooltip: 'ویرایش',
              onPressed: () => showAssetEditor(context, edit: asset),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _HeroTotals(
            metrics: metrics,
            usdt: usdt,
            pnlTone: pnlTone,
          ),
          const SizedBox(height: 14),
          const _SectionTitle('بهای خرید و قیمت فعلی'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PriceCard(
                  title: 'بهای خرید',
                  toman: buyToman,
                  usd: buyUsd,
                  accent: AppTheme.muted,
                  usdHint: metrics.avgBuyPriceUsd != null
                      ? 'ثبت‌شده'
                      : (buyUsd != null ? 'بر اساس نرخ تتر' : null),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PriceCard(
                  title: 'قیمت فعلی',
                  toman: curToman,
                  usd: curUsd,
                  accent: AppTheme.positive,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CompareBars(
            buyToman: buyToman,
            currentToman: curToman,
            buyUsd: buyUsd,
            currentUsd: curUsd,
          ),
          const SizedBox(height: 18),
          const _SectionTitle('نمودار قیمت واحد (تومان / دلار)'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: DualCurrencyChart(
              points: series,
              calendar: calendar,
              usdtRate: usdt,
              lineColor: pnlTone,
              height: 260,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            lots.isEmpty
                ? 'نمودار از میانگین خرید تا قیمت فعلی ساخته شده است.'
                : 'نقاط خرید لات‌های باز و قیمت فعلی روی یک مقیاس دو‌ارزی.',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppTheme.muted.withValues(alpha: 0.9),
              fontSize: 11,
              height: 1.4,
            ),
          ),
          if (lots.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _SectionTitle('لات‌های باز'),
            const SizedBox(height: 8),
            for (final t in lots) ...[
              _LotTile(trade: t, usdt: usdt, calendar: calendar),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  static List<SeriesPoint> _unitPriceSeries({
    required Asset asset,
    required HoldingMetrics metrics,
    required List<Trade> lots,
  }) {
    final today = todayIso();
    final points = <SeriesPoint>[];

    for (final t in lots) {
      if (t.buyPrice <= 0) continue;
      final raw = t.buyDate.trim();
      final day = raw.length >= 10 ? raw.substring(0, 10) : today;
      points.add(SeriesPoint(date: day, value: t.buyPrice));
    }

    if (points.isEmpty && metrics.avgBuyPrice > 0) {
      final created = asset.createdAt.trim();
      final buyDay = created.length >= 10 ? created.substring(0, 10) : today;
      points.add(SeriesPoint(date: buyDay, value: metrics.avgBuyPrice));
    }

    if (metrics.currentPrice > 0) {
      if (points.isNotEmpty && points.last.date == today) {
        points[points.length - 1] =
            SeriesPoint(date: today, value: metrics.currentPrice);
      } else {
        points.add(SeriesPoint(date: today, value: metrics.currentPrice));
      }
    }

    return ensureChartSeries(
      points,
      todayValue: metrics.currentPrice > 0
          ? metrics.currentPrice
          : metrics.avgBuyPrice,
      today: today,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(
        color: AppTheme.title,
        fontWeight: FontWeight.w800,
        fontSize: 14,
      ),
    );
  }
}

class _HeroTotals extends StatelessWidget {
  const _HeroTotals({
    required this.metrics,
    required this.usdt,
    required this.pnlTone,
  });

  final HoldingMetrics metrics;
  final double? usdt;
  final Color pnlTone;

  @override
  Widget build(BuildContext context) {
    final valueUsd = tomanToUsd(metrics.marketValue, usdt);
    final pnlUsd = tomanToUsd(metrics.unrealizedPnl, usdt);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'ارزش فعلی موقعیت',
            style: TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            valueUsd != null
                ? formatUsd(valueUsd)
                : formatMoney(metrics.marketValue),
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: AppTheme.title,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (valueUsd != null)
            Text(
              formatMoney(metrics.marketValue),
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                formatPct(metrics.unrealizedPnlPct),
                style: TextStyle(
                  color: pnlTone,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                pnlUsd != null
                    ? '${formatUsd(pnlUsd, showSign: true)}  ·  ${formatMoney(metrics.unrealizedPnl, showSign: true)}'
                    : formatMoney(metrics.unrealizedPnl, showSign: true),
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: pnlTone,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.title,
    required this.toman,
    required this.usd,
    required this.accent,
    this.usdHint,
  });

  final String title;
  final double toman;
  final double? usd;
  final Color accent;
  final String? usdHint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatMoney(toman),
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            usd == null ? '— دلار' : formatUsd(usd!),
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: Color(0xFFE8C547),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          if (usdHint != null) ...[
            const SizedBox(height: 4),
            Text(
              usdHint!,
              style: const TextStyle(color: AppTheme.muted, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompareBars extends StatelessWidget {
  const _CompareBars({
    required this.buyToman,
    required this.currentToman,
    required this.buyUsd,
    required this.currentUsd,
  });

  final double buyToman;
  final double currentToman;
  final double? buyUsd;
  final double? currentUsd;

  @override
  Widget build(BuildContext context) {
    final maxT = [buyToman, currentToman].fold<double>(0, (a, b) => a > b ? a : b);
    final maxU = [buyUsd ?? 0, currentUsd ?? 0]
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          _BarRow(
            label: 'تومان',
            buy: buyToman,
            current: currentToman,
            max: maxT <= 0 ? 1 : maxT,
            format: (v) => formatCompactToman(v),
            buyColor: AppTheme.muted,
            currentColor: AppTheme.positive,
          ),
          if (buyUsd != null || currentUsd != null) ...[
            const SizedBox(height: 12),
            _BarRow(
              label: 'دلار',
              buy: buyUsd ?? 0,
              current: currentUsd ?? 0,
              max: maxU <= 0 ? 1 : maxU,
              format: (v) => formatUsd(v, compact: true),
              buyColor: const Color(0xFFB89B2E),
              currentColor: const Color(0xFFE8C547),
            ),
          ],
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.buy,
    required this.current,
    required this.max,
    required this.format,
    required this.buyColor,
    required this.currentColor,
  });

  final String label;
  final double buy;
  final double current;
  final double max;
  final String Function(double) format;
  final Color buyColor;
  final Color currentColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: TextAlign.right,
          style: const TextStyle(color: AppTheme.muted, fontSize: 11),
        ),
        const SizedBox(height: 6),
        _one('خرید', buy, buyColor),
        const SizedBox(height: 6),
        _one('فعلی', current, currentColor),
      ],
    );
  }

  Widget _one(String title, double value, Color color) {
    final w = (value / max).clamp(0.04, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            format(value),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: w,
              minHeight: 10,
              backgroundColor: AppTheme.border.withValues(alpha: 0.5),
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            title,
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _LotTile extends StatelessWidget {
  const _LotTile({
    required this.trade,
    required this.usdt,
    required this.calendar,
  });

  final Trade trade;
  final double? usdt;
  final String calendar;

  @override
  Widget build(BuildContext context) {
    final usd = trade.buyPriceUsd ?? tomanToUsd(trade.buyPrice, usdt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatDisplayDate(trade.buyDate, calendar),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
                Text(
                  'مقدار ${formatNumber(trade.quantity, decimals: 4)}',
                  style: const TextStyle(color: AppTheme.text, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(trade.buyPrice),
                style: const TextStyle(
                  color: AppTheme.title,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Text(
                usd == null ? '—' : formatUsd(usd),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Color(0xFFE8C547),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/profit_alert.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/trades_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/asset_editor_sheet.dart';
import 'package:invest/ui/widgets/dual_currency_chart.dart';
import 'package:invest/ui/widgets/profit_alert_sheet.dart';
import 'package:provider/provider.dart';

Future<void> openAssetDetail(
  BuildContext context, {
  required Asset asset,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AssetDetailPage(assetId: asset.id!),
    ),
  );
}

class AssetDetailPage extends StatelessWidget {
  const AssetDetailPage({
    super.key,
    required this.assetId,
  });

  final int assetId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    Asset? matched;
    for (final a in state.assets) {
      if (a.id == assetId) {
        matched = a;
        break;
      }
    }
    if (matched == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('دارایی')),
        body: RefreshIndicator(
          onRefresh: () => state.refreshAll(includeQuotes: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 160),
              Center(child: Text('دارایی یافت نشد')),
            ],
          ),
        ),
      );
    }
    final asset = matched;

    final metrics = HoldingMetrics.forAsset(asset, state.openTrades);
    final usdt = state.liveUsdt ?? state.settings.usdtTmnRate;
    final calendar = state.settings.calendar;
    final lots = state.openTrades
        .where((t) => t.assetId == asset.id && t.quantity > 1e-9)
        .toList()
      ..sort((a, b) => a.buyDate.compareTo(b.buyDate));

    final buyToman = metrics.avgBuyPrice;
    // Registered USD only — match asset cards (no live USDT conversion).
    final buyUsd = metrics.avgBuyPriceUsd;
    final curToman = metrics.currentPrice;
    final curUsd = metrics.currentPriceUsd(usdt);
    final series = _unitPriceSeries(
      asset: asset,
      metrics: metrics,
      lots: lots,
      usdt: usdt,
    );

    final tomanTone =
        metrics.unrealizedPnl >= 0 ? AppTheme.positive : AppTheme.negative;
    final usdPnl = metrics.unrealizedPnlUsd(usdt);
    final usdTone = usdPnl == null
        ? tomanTone
        : (usdPnl >= 0 ? AppTheme.positive : AppTheme.negative);

    return Scaffold(
      appBar: AppBar(
        title: Text(asset.name),
        centerTitle: true,
        actions: [
          ProfitAlertBell(
            id: ProfitAlert.forAsset(asset.id!),
            name: asset.name,
            symbol: asset.symbol,
            currentPnl: metrics.unrealizedPnl,
            currentPnlPct: metrics.unrealizedPnlPct,
            color: Colors.white,
          ),
          if (state.canMutate)
            IconButton(
              tooltip: 'ویرایش',
              onPressed: () => showAssetEditor(context, edit: asset),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      floatingActionButton: state.canMutate
          ? FloatingActionButton.extended(
              onPressed: () => showBuyTradeDialog(context, assetId: asset.id),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('خرید'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: RefreshIndicator(
        onRefresh: () => state.refreshAll(includeQuotes: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          children: [
          _HeroTotals(
            metrics: metrics,
            usdt: usdt,
            tomanTone: tomanTone,
            usdTone: usdTone,
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
                  usdHint: buyUsd != null ? 'دلار ثبت‌شده' : 'دلار خرید ثبت نشده',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PriceCard(
                  title: 'قیمت فعلی',
                  toman: curToman,
                  usd: curUsd,
                  accent: AppTheme.positive,
                  usdHint: curUsd != null ? 'دلار زنده (تومان ÷ تتر)' : null,
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
              lineColor: tomanTone,
              height: 260,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            lots.isEmpty
                ? 'نمودار از میانگین خرید تا قیمت فعلی ساخته شده است.'
                : 'نقاط خرید: دلار ثبت‌شده (در صورت وجود)؛ نقطه فعلی از نرخ زنده.',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppTheme.muted.withValues(alpha: 0.9),
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          AssetTradesSection(assetId: asset.id!),
        ],
        ),
      ),
    );
  }

  static List<SeriesPoint> _unitPriceSeries({
    required Asset asset,
    required HoldingMetrics metrics,
    required List<Trade> lots,
    double? usdt,
  }) {
    final today = todayIso();
    final points = <SeriesPoint>[];

    for (final t in lots) {
      if (t.buyPrice <= 0) continue;
      final raw = t.buyDate.trim();
      final day = raw.length >= 10 ? raw.substring(0, 10) : today;
      final u = t.buyPriceUsd;
      points.add(
        SeriesPoint(
          date: day,
          value: t.buyPrice,
          usdValue: (u != null && u > 0) ? u : null,
        ),
      );
    }

    if (points.isEmpty && metrics.avgBuyPrice > 0) {
      final created = asset.createdAt.trim();
      final buyDay = created.length >= 10 ? created.substring(0, 10) : today;
      final u = metrics.avgBuyPriceUsd;
      points.add(
        SeriesPoint(
          date: buyDay,
          value: metrics.avgBuyPrice,
          usdValue: (u != null && u > 0) ? u : null,
        ),
      );
    }

    // Always append current price; do not overwrite a same-day buy point.
    if (metrics.currentPrice > 0) {
      points.add(
        SeriesPoint(
          date: today,
          value: metrics.currentPrice,
          usdValue: tomanToUsd(metrics.currentPrice, usdt),
        ),
      );
    }

    if (points.isEmpty) {
      return [
        SeriesPoint(
          date: today,
          value: metrics.currentPrice > 0
              ? metrics.currentPrice
              : metrics.avgBuyPrice,
          usdValue: tomanToUsd(
            metrics.currentPrice > 0
                ? metrics.currentPrice
                : metrics.avgBuyPrice,
            usdt,
          ),
        ),
      ];
    }
    return points;
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
    required this.tomanTone,
    required this.usdTone,
  });

  final HoldingMetrics metrics;
  final double? usdt;
  final Color tomanTone;
  final Color usdTone;

  @override
  Widget build(BuildContext context) {
    final valueUsd = metrics.marketValueUsd(usdt);
    final pnlUsd = metrics.unrealizedPnlUsd(usdt);
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
          const SizedBox(height: 12),
          _PnlLine(
            label: 'سود/ضرر ریالی',
            amount: formatMoney(metrics.unrealizedPnl, showSign: true),
            pct: metrics.unrealizedPnlPct,
            tone: tomanTone,
          ),
          if (pnlUsd != null) ...[
            const SizedBox(height: 8),
            _PnlLine(
              label: 'سود/ضرر دلاری',
              amount: formatUsd(pnlUsd, showSign: true),
              pct: metrics.unrealizedPnlUsdPct(usdt),
              tone: usdTone,
            ),
          ],
        ],
      ),
    );
  }
}

class _PnlLine extends StatelessWidget {
  const _PnlLine({
    required this.label,
    required this.amount,
    required this.pct,
    required this.tone,
  });

  final String label;
  final String amount;
  final double pct;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          formatPct(pct),
          style: TextStyle(
            color: tone,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            amount,
            textAlign: TextAlign.left,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppTheme.muted, fontSize: 11),
        ),
      ],
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
            formatTomanPrice(toman),
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
    final usdBuy = buyUsd;
    final usdCur = currentUsd;
    final maxU = [usdBuy ?? 0, usdCur ?? 0]
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
          if (usdBuy != null && usdCur != null) ...[
            const SizedBox(height: 12),
            _BarRow(
              label: 'دلار',
              buy: usdBuy,
              current: usdCur,
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

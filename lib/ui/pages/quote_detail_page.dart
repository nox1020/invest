import 'package:flutter/material.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/services/market_history_service.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/price_alert_sheet.dart';
import 'package:invest/ui/widgets/value_line_chart.dart';
import 'package:provider/provider.dart';

Future<void> openQuoteDetail(BuildContext context, CommodityQuote quote) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => QuoteDetailPage(quote: quote),
    ),
  );
}

class QuoteDetailPage extends StatefulWidget {
  const QuoteDetailPage({super.key, required this.quote});

  final CommodityQuote quote;

  @override
  State<QuoteDetailPage> createState() => _QuoteDetailPageState();
}

class _QuoteDetailPageState extends State<QuoteDetailPage> {
  final _history = MarketHistoryService();
  List<SeriesPoint> _points = const [];
  bool _loading = true;
  String? _error;
  int _days = 60;

  CommodityQuote _resolveQuote(AppState state) {
    for (final q in state.commodityIndex) {
      if (q.id == widget.quote.id) return q;
    }
    for (final q in state.wallexMarkets) {
      if (q.id == widget.quote.id) return q;
    }
    return widget.quote;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final symbol = _resolveQuote(context.read<AppState>()).resolvedMarketSymbol;
    setState(() {
      _loading = true;
      _error = null;
    });
    if (symbol == null) {
      setState(() {
        _points = const [];
        _loading = false;
        _error = 'نمودار تاریخی برای این مورد از والکس در دسترس نیست.';
      });
      return;
    }
    try {
      final pts = await _history.fetchDailyCloses(
        marketSymbol: symbol,
        days: _days,
      );
      if (!mounted) return;
      setState(() {
        _points = pts;
        _loading = false;
        if (pts.isEmpty) {
          _error = 'داده نموداری خالی بود.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'دریافت نمودار ناموفق بود.';
        _points = const [];
      });
    }
  }

  String _formatPrice(double v, CommodityQuote q) {
    switch (q.unit) {
      case 'usd':
        return '\$${formatNumber(v, decimals: v >= 1000 ? 0 : 2)}';
      case 'toman_per_gram':
        return '${formatNumber(v, decimals: 0)} ت/گرم';
      case 'toman':
      default:
        final decimals = v >= 1000 ? 0 : (v >= 1 ? 2 : 4);
        return '${formatNumber(v, decimals: decimals)} تومان';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final q = _resolveQuote(state);
    final calendar = state.settings.calendar;
    final change = q.change24h;
    final changeColor = change == null
        ? AppTheme.muted
        : (change > 0
            ? AppTheme.positive
            : (change < 0 ? AppTheme.negative : AppTheme.muted));

    return Scaffold(
      appBar: AppBar(
        title: Text(q.name),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'اعلان قیمت',
            onPressed: !state.canMutate
                ? null
                : () => showPriceAlertEditor(
                      context,
                      id: q.id,
                      name: q.name,
                      symbol: q.symbol,
                      unit: q.unit,
                      currentPrice: q.price,
                    ),
            icon: Icon(
              state.settings.alertFor(q.id).isArmed
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_outlined,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    if (change != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: changeColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          formatPct(change),
                          style: TextStyle(
                            color: changeColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      q.symbol,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(q.icon, color: AppTheme.positive),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  q.price == null ? '—' : _formatPrice(q.price!, q),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'قیمت لحظه‌ای',
                  style: TextStyle(
                    color: AppTheme.muted.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              _StatChip(
                label: 'بالاترین ۲۴س',
                value: q.high24h == null ? '—' : _formatPrice(q.high24h!, q),
              ),
              _StatChip(
                label: 'پایین‌ترین ۲۴س',
                value: q.low24h == null ? '—' : _formatPrice(q.low24h!, q),
              ),
              _StatChip(
                label: 'خرید',
                value: q.bidPrice == null ? '—' : _formatPrice(q.bidPrice!, q),
              ),
              _StatChip(
                label: 'فروش',
                value: q.askPrice == null ? '—' : _formatPrice(q.askPrice!, q),
              ),
              if ((q.quoteVolume24h ?? 0) > 0)
                _StatChip(
                  label: 'حجم ۲۴س',
                  value: formatNumber(q.quoteVolume24h!, decimals: 0),
                ),
              if (q.resolvedMarketSymbol != null)
                _StatChip(
                  label: 'بازار',
                  value: q.resolvedMarketSymbol!,
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (final d in const [30, 60, 90])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text('$d روز'),
                    selected: _days == d,
                    onSelected: (_) {
                      if (_days == d) return;
                      setState(() => _days = d);
                      _load();
                    },
                  ),
                ),
              const Spacer(),
              const Text(
                'نمودار قیمت',
                style: TextStyle(
                  color: AppTheme.title,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: _loading
                ? const SizedBox(
                    height: 240,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _points.isEmpty
                    ? SizedBox(
                        height: 200,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _error ?? 'نمودار در دسترس نیست',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.muted),
                            ),
                            if (q.resolvedMarketSymbol != null) ...[
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _load,
                                child: const Text('تلاش مجدد'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ValueLineChart(
                        points: _points,
                        calendar: calendar,
                        formatValue: (v) => _formatPrice(v, q),
                        valueTitle: 'قیمت پایانی روز',
                        lineColor: changeColor == AppTheme.muted
                            ? AppTheme.positive
                            : changeColor,
                      ),
          ),
          if (_error != null && _points.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: AppTheme.text,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

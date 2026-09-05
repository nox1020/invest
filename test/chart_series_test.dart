import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/chart_series.dart';
import 'package:invest/ui/widgets/dual_currency_chart.dart';

void main() {
  test('parses dashboard growth_series json', () {
    final points = SeriesPoint.fromJsonList([
      {'date': '2026-01-01', 'value': 100},
      {'date': '2026-01-02T00:00:00', 'value': 150.5},
      {'date': '', 'value': 1},
    ]);
    expect(points, hasLength(2));
    expect(points.first.date, '2026-01-01');
    expect(points.last.value, 150.5);
  });

  test('downsample keeps first and last', () {
    final points = [
      for (var i = 0; i < 10; i++)
        SeriesPoint(
          date: '2026-01-${(i + 1).toString().padLeft(2, '0')}',
          value: i.toDouble(),
        ),
    ];
    final out = downsampleSeries(points, maxPoints: 3);
    expect(out.first.date, points.first.date);
    expect(out.last.date, points.last.date);
    expect(out.length, lessThanOrEqualTo(4));
  });

  test('ensureChartSeries always ends with today value', () {
    final out = ensureChartSeries(
      const [SeriesPoint(date: '2026-01-01', value: 10)],
      todayValue: 99,
      today: '2026-09-05',
    );
    expect(out.last.date, '2026-09-05');
    expect(out.last.value, 99);
  });

  test('year realized series is cumulative and grouped by day', () {
    Trade closed(String sell, double pnl) => Trade(
          assetId: 1,
          status: AppConfig.tradeClosed,
          quantity: 1,
          buyPrice: 1,
          sellDate: sell,
          realizedPnl: pnl,
        );
    final series = yearRealizedSeries(
      closedTrades: [
        closed('2026-02-01', 10),
        closed('2026-02-01', 5),
        closed('2026-03-01', -2),
        closed('2025-12-01', 999),
      ],
      yearKey: '2026',
      calendar: 'gregorian',
    );
    expect(series, hasLength(2));
    expect(series.first.value, 15);
    expect(series.last.value, 13);
  });

  testWidgets('merged toman/usd chart paints legend and values', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DualCurrencyChart(
            points: [
              SeriesPoint(date: '2026-01-01', value: 180000000000),
              SeriesPoint(date: '2026-06-01', value: 200000000000),
            ],
            calendar: 'gregorian',
            usdtRate: 250000,
          ),
        ),
      ),
    );
    expect(find.text('تومان'), findsOneWidget);
    expect(find.text('دلار'), findsOneWidget);
    expect(find.textContaining('یک نمودار با دو مقیاس'), findsOneWidget);
  });
}

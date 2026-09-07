import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/services/market_history_service.dart';

void main() {
  test('closeOnOrBefore picks exact day', () {
    const series = [
      SeriesPoint(date: '2024-01-01', value: 50000),
      SeriesPoint(date: '2024-01-02', value: 51000),
      SeriesPoint(date: '2024-01-04', value: 52000),
    ];
    expect(
      MarketHistoryService.closeOnOrBefore(series, '2024-01-02'),
      51000,
    );
  });

  test('closeOnOrBefore falls back to previous trading day', () {
    const series = [
      SeriesPoint(date: '2024-01-01', value: 50000),
      SeriesPoint(date: '2024-01-02', value: 51000),
      SeriesPoint(date: '2024-01-04', value: 52000),
    ];
    expect(
      MarketHistoryService.closeOnOrBefore(series, '2024-01-03'),
      51000,
    );
  });

  test('closeOnOrBefore returns null when all points are after', () {
    const series = [
      SeriesPoint(date: '2024-01-10', value: 50000),
    ];
    expect(
      MarketHistoryService.closeOnOrBefore(series, '2024-01-01'),
      isNull,
    );
  });
}

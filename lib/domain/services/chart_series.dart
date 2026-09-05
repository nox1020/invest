import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/utils/dates.dart';

List<SeriesPoint> downsampleSeries(
  List<SeriesPoint> points, {
  int maxPoints = 120,
}) {
  if (points.length <= maxPoints) return List<SeriesPoint>.from(points);
  final step = (points.length / maxPoints).ceil();
  final out = <SeriesPoint>[];
  for (var i = 0; i < points.length; i += step) {
    out.add(points[i]);
  }
  if (out.isEmpty || out.last.date != points.last.date) {
    out.add(points.last);
  }
  return out;
}

List<SeriesPoint> ensureChartSeries(
  List<SeriesPoint> points, {
  required double todayValue,
  String? today,
}) {
  final day = today ?? todayIso();
  if (points.isEmpty) {
    return [SeriesPoint(date: day, value: todayValue)];
  }
  final out = List<SeriesPoint>.from(points);
  if (out.last.date == day) {
    out[out.length - 1] = SeriesPoint(date: day, value: todayValue);
  } else {
    out.add(SeriesPoint(date: day, value: todayValue));
  }
  return out;
}

/// Cumulative realized PnL for the selected calendar year.
List<SeriesPoint> yearRealizedSeries({
  required List<Trade> closedTrades,
  required String yearKey,
  required String calendar,
}) {
  final rows = closedTrades.where((t) {
    final sell = t.sellDate;
    if (sell == null || sell.isEmpty || t.realizedPnl == null) return false;
    return yearPeriodKey(sell, calendar) == yearKey;
  }).toList()
    ..sort((a, b) => (a.sellDate ?? '').compareTo(b.sellDate ?? ''));

  if (rows.isEmpty) return const [];

  final out = <SeriesPoint>[];
  var sum = 0.0;
  String? lastDay;
  for (final trade in rows) {
    final day = (trade.sellDate ?? '').length >= 10
        ? trade.sellDate!.substring(0, 10)
        : trade.sellDate!;
    sum += trade.realizedPnl!;
    if (lastDay == day && out.isNotEmpty) {
      out[out.length - 1] = SeriesPoint(date: day, value: sum);
    } else {
      out.add(SeriesPoint(date: day, value: sum));
      lastDay = day;
    }
  }
  return out;
}

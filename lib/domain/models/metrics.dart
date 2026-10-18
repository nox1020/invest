import 'package:invest/domain/utils/json_values.dart';

class GoldFundMetrics {
  const GoldFundMetrics({
    required this.goldInG,
    required this.goldOutG,
    required this.goldHoldingG,
  });

  final double goldInG;
  final double goldOutG;
  final double goldHoldingG;

  double get goldDebtG => goldHoldingG;
}

class SeriesPoint {
  const SeriesPoint({
    required this.date,
    required this.value,
    this.usdValue,
  });

  final String date;

  /// Unit / series value in Toman.
  final double value;

  /// Optional USD for this point (registered buy or live mark).
  /// When null, UI may convert [value] with the live USDT rate.
  final double? usdValue;

  static List<SeriesPoint> fromJsonList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <SeriesPoint>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final date = jsonText(map['date']).trim();
      if (date.isEmpty) continue;
      final usd = jsonDouble(map['usd']) ?? jsonDouble(map['usdValue']);
      out.add(
        SeriesPoint(
          date: date.length >= 10 ? date.substring(0, 10) : date,
          value: jsonDouble(map['value']) ?? 0,
          usdValue: (usd != null && usd > 0) ? usd : null,
        ),
      );
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'value': value,
        if (usdValue != null) 'usd': usdValue,
      };
}

class DashboardMetrics {
  const DashboardMetrics({
    required this.totalValue,
    required this.totalPnl,
    required this.totalPnlPct,
    required this.realizedPnl,
    required this.unrealizedPnl,
    required this.openCount,
    required this.closedCount,
    required this.yearRealizedPnl,
    required this.yearKey,
    required this.goldFund,
    this.growthSeries = const [],
  });

  final double totalValue;
  final double totalPnl;
  final double totalPnlPct;
  final double realizedPnl;
  final double unrealizedPnl;
  final int openCount;
  final int closedCount;
  final double yearRealizedPnl;
  final String yearKey;
  final GoldFundMetrics goldFund;
  final List<SeriesPoint> growthSeries;
}

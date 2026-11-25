import 'dart:convert';

import 'package:invest/data/local_platform.dart';
import 'package:invest/domain/models/metrics.dart';

/// One day of the on-device 18k gold price log.
class GoldPricePoint {
  const GoldPricePoint({required this.date, required this.mid, this.bid, this.ask});

  /// ISO `yyyy-MM-dd` (device-local day).
  final String date;
  final double mid;
  final double? bid;
  final double? ask;

  Map<String, dynamic> toJson() => {
        'd': date,
        'p': mid,
        if (bid != null) 'b': bid,
        if (ask != null) 'a': ask,
      };

  static GoldPricePoint? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final d = '${raw['d'] ?? ''}';
    final p = raw['p'];
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)) return null;
    if (p is! num || !p.isFinite || p <= 0) return null;
    double? opt(Object? v) => v is num && v.isFinite && v > 0 ? v.toDouble() : null;
    return GoldPricePoint(date: d, mid: p.toDouble(), bid: opt(raw['b']), ask: opt(raw['a']));
  }
}

/// Daily 18k gold price kept on the phone (the app has no gold history
/// source). One point per day — the last price seen that day — capped at
/// [maxDays]. Feeds the «روند قیمت گرم ۱۸» chart.
class GoldPriceLog {
  GoldPriceLog._();

  static const prefsKey = 'vplus_gold_price_log_v1';
  static const maxDays = 800;

  /// Points that parse, oldest first, one per day.
  static List<GoldPricePoint> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      final byDay = <String, GoldPricePoint>{};
      for (final e in list) {
        final p = GoldPricePoint.tryParse(e);
        if (p != null) byDay[p.date] = p;
      }
      final out = byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
      return out;
    } catch (_) {
      return [];
    }
  }

  static String encode(List<GoldPricePoint> points) => jsonEncode(points.map((e) => e.toJson()).toList());

  /// [points] with [p] replacing the same day, trimmed to [maxDays].
  static List<GoldPricePoint> upsert(List<GoldPricePoint> points, GoldPricePoint p, {int max = maxDays}) {
    final next = [
      for (final x in points)
        if (x.date != p.date) x,
      p
    ]..sort((a, b) => a.date.compareTo(b.date));
    if (next.length > max) next.removeRange(0, next.length - max);
    return next;
  }

  /// Points inside the last [days] days before (and including) [today].
  static List<GoldPricePoint> window(List<GoldPricePoint> points, String today, int days) {
    final t = DateTime.tryParse(today);
    if (t == null) return points;
    final from = t.subtract(Duration(days: days));
    final key =
        '${from.year.toString().padLeft(4, '0')}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    return [
      for (final p in points)
        if (p.date.compareTo(key) >= 0 && p.date.compareTo(today) <= 0) p
    ];
  }

  static List<SeriesPoint> series(List<GoldPricePoint> points) =>
      [for (final p in points) SeriesPoint(date: p.date, value: p.mid)];

  static Future<List<GoldPricePoint>> load() async {
    final prefs = await LocalPrefs.open();
    if (prefs == null) return [];
    return decode(prefs.getString(prefsKey));
  }

  /// Records today's price. Ignores non-positive prices.
  static Future<List<GoldPricePoint>?> record({
    required String today,
    required double mid,
    double? bid,
    double? ask,
  }) async {
    if (!mid.isFinite || mid <= 0) return null;
    final prefs = await LocalPrefs.open();
    if (prefs == null) return null;
    final next = upsert(
      decode(prefs.getString(prefsKey)),
      GoldPricePoint(date: today, mid: mid, bid: bid, ask: ask),
    );
    await LocalPrefs.setString(prefs, prefsKey, encode(next));
    return next;
  }
}

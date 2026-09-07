import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/utils/dates.dart';

/// OHLC history from Wallex public UDF endpoint.
class MarketHistoryService {
  MarketHistoryService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _historyUrl = 'https://api.wallex.ir/v1/udf/history';

  Future<List<SeriesPoint>> fetchDailyCloses({
    required String marketSymbol,
    int days = 60,
  }) async {
    final symbol = marketSymbol.trim().toUpperCase();
    if (symbol.isEmpty) return const [];

    final to = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final from = to - days * 24 * 60 * 60;
    final uri = Uri.parse(_historyUrl).replace(queryParameters: {
      'symbol': symbol,
      'resolution': '1D',
      'from': '$from',
      'to': '$to',
    });

    final res = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('HTTP ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map) return const [];
    final map = Map<String, dynamic>.from(body);
    if ('${map['s']}' != 'ok') return const [];

    final times = (map['t'] as List?) ?? const [];
    final closes = (map['c'] as List?) ?? const [];
    final n = times.length < closes.length ? times.length : closes.length;
    final out = <SeriesPoint>[];
    for (var i = 0; i < n; i++) {
      final ts = (times[i] as num?)?.toInt();
      final close = _num(closes[i]);
      if (ts == null || close == null) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true)
          .toLocal();
      out.add(SeriesPoint(date: toIsoDate(dt), value: close));
    }
    return out;
  }

  /// Daily close on [isoDate] or the nearest earlier trading day.
  Future<double?> fetchCloseOnOrBefore({
    required String marketSymbol,
    required String isoDate,
  }) async {
    final day = tryNormalizeToIso(isoDate) ??
        (isoDate.trim().length >= 10 ? isoDate.trim().substring(0, 10) : '');
    if (day.isEmpty) return null;

    final target = parseIsoDate(day);
    final span = DateTime.now().difference(target).inDays;
    final days = (span + 21).clamp(7, 4000);
    final series = await fetchDailyCloses(
      marketSymbol: marketSymbol,
      days: days,
    );
    return closeOnOrBefore(series, day);
  }

  /// USDT/TMN rate for a buy date (Wallex `USDTTMN`), with optional live fallback.
  Future<double?> fetchUsdtTmnOnDate(
    String isoDate, {
    double? fallback,
  }) async {
    try {
      final v = await fetchCloseOnOrBefore(
        marketSymbol: 'USDTTMN',
        isoDate: isoDate,
      );
      if (v != null && v > 0) return v;
    } catch (_) {}
    if (fallback != null && fallback > 0) return fallback;
    return null;
  }

  /// Pick the latest point on or before [isoDay] (`YYYY-MM-DD`).
  static double? closeOnOrBefore(List<SeriesPoint> series, String isoDay) {
    final day = isoDay.length >= 10 ? isoDay.substring(0, 10) : isoDay;
    SeriesPoint? best;
    for (final p in series) {
      final d = p.date.length >= 10 ? p.date.substring(0, 10) : p.date;
      if (d.compareTo(day) > 0) continue;
      if (best == null ||
          d.compareTo(
                best.date.length >= 10 ? best.date.substring(0, 10) : best.date,
              ) >
              0) {
        best = p;
      }
    }
    return best?.value;
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }
}

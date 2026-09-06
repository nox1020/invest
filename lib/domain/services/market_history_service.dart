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

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }
}

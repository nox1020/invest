import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/services/gold_price_log.dart';

/// Back-fills the daily 18k gold log from TGJU's public daily table (the
/// same free, key-less provider the app already uses as a live fallback),
/// so «ستون قیمت طلا» has a 30-day range from the first day.
class GoldHistorySeed {
  GoldHistorySeed({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Source tag stored on back-filled points.
  static const source = 'tgju';

  /// Rows asked for (newest first): 30 days need ~26 market days.
  static const rows = 40;

  /// Fetches the latest [rows] days; empty on any problem.
  Future<List<GoldPricePoint>> fetch({double? sanityPrice}) async {
    final uri = Uri.parse(AppConfig.tgjuGold18HistoryUrl)
        .replace(queryParameters: {'start': '0', 'length': '$rows', 'order_dir': 'desc'});
    final res = await _client.get(uri, headers: const {'Accept': 'application/json'}).timeout(
      const Duration(seconds: 15),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    return parse(utf8.decode(res.bodyBytes), sanityPrice: sanityPrice);
  }

  /// Parses TGJU `summary-table-data/geram18`: rows of
  /// `[open, low, high, close, change, change%, 'YYYY/MM/DD', jalali]` in
  /// Rial. Returns Toman closes, oldest first, one per day. When
  /// [sanityPrice] (current Toman/gram) is given, a table whose latest
  /// close is more than 40% away from it is dropped (unit or feed change).
  static List<GoldPricePoint> parse(String body, {double? sanityPrice}) {
    Object? json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return const [];
    }
    final data = json is Map ? json['data'] : null;
    if (data is! List) return const [];
    final byDay = <String, GoldPricePoint>{};
    for (final row in data) {
      if (row is! List || row.length < 7) continue;
      final close = _rial(row[3]);
      final date = _date(row[6]);
      if (close == null || date == null) continue;
      final toman = close / 10;
      if (toman < 100000) continue; // not an 18k gram price
      byDay[date] = GoldPricePoint(date: date, mid: toman.roundToDouble(), source: source);
    }
    final out = byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final s = sanityPrice;
    if (out.isNotEmpty && s != null && s.isFinite && s > 0) {
      final r = out.last.mid / s;
      if (r < 0.6 || r > 1.4) return const [];
    }
    return out;
  }

  static double? _rial(Object? v) {
    final t = '$v'.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'[,\s٬]'), '');
    final d = double.tryParse(t);
    return d != null && d.isFinite && d > 0 ? d : null;
  }

  static String? _date(Object? v) {
    final m = RegExp(r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$').firstMatch('$v'.trim());
    if (m == null) return null;
    final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
    if (y < 2000 || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    return '${m.group(1)}-${mo.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }
}

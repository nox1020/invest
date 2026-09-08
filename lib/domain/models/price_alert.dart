import 'dart:convert';

/// Per-instrument high/low price notification threshold.
class PriceAlert {
  PriceAlert({
    required this.id,
    this.name = '',
    this.symbol = '',
    this.unit = 'toman',
    this.enabled = true,
    this.above,
    this.below,
  });

  /// Commodity / Wallex quote id (`usdt`, `gold`, `wallex_btctmn`, …).
  String id;
  String name;
  String symbol;
  String unit;
  bool enabled;

  /// Notify when live price is at or above this value (same unit as quote).
  double? above;

  /// Notify when live price is at or below this value.
  double? below;

  bool get hasThreshold =>
      (above != null && above! > 0) || (below != null && below! > 0);

  bool get isArmed => enabled && hasThreshold;

  String get displayName {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    final s = symbol.trim();
    if (s.isNotEmpty) return s;
    return catalogNameFor(id) ?? id;
  }

  PriceAlert copy() => PriceAlert(
        id: id,
        name: name,
        symbol: symbol,
        unit: unit,
        enabled: enabled,
        above: above,
        below: below,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'symbol': symbol,
        'unit': unit,
        'enabled': enabled,
        'above': above,
        'below': below,
      };

  factory PriceAlert.fromJson(Map<String, dynamic> m) {
    return PriceAlert(
      id: '${m['id'] ?? ''}'.trim(),
      name: '${m['name'] ?? ''}',
      symbol: '${m['symbol'] ?? ''}',
      unit: '${m['unit'] ?? 'toman'}'.trim().isEmpty
          ? 'toman'
          : '${m['unit']}'.trim(),
      enabled: _on(m['enabled']),
      above: _d(m['above']),
      below: _d(m['below']),
    );
  }

  static bool _on(dynamic v) {
    if (v == null) return true;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final t = '$v'.trim().toLowerCase();
    return t == '1' || t == 'true' || t == 'yes' || t == 'on';
  }

  static double? _d(dynamic v) {
    if (v == null || v == '') return null;
    if (v is num) {
      final d = v.toDouble();
      return d > 0 ? d : null;
    }
    return double.tryParse('$v'.trim().replaceAll(',', ''));
  }
}

class PriceAlertInstrument {
  const PriceAlertInstrument({
    required this.id,
    required this.name,
    required this.symbol,
    this.unit = 'toman',
  });

  final String id;
  final String name;
  final String symbol;
  final String unit;
}

/// Built-in quotes that always appear in Settings → Notifications.
const priceAlertCatalog = <PriceAlertInstrument>[
  PriceAlertInstrument(id: 'usdt', name: 'تتر', symbol: 'USDT'),
  PriceAlertInstrument(id: 'usd', name: 'دلار آمریکا', symbol: 'USD'),
  PriceAlertInstrument(id: 'eur', name: 'یورو', symbol: 'EUR'),
  PriceAlertInstrument(id: 'gbp', name: 'پوند انگلیس', symbol: 'GBP'),
  PriceAlertInstrument(id: 'aed', name: 'درهم امارات', symbol: 'AED'),
  PriceAlertInstrument(id: 'try', name: 'لیر ترکیه', symbol: 'TRY'),
  PriceAlertInstrument(
    id: 'gold',
    name: 'طلای ۱۸ عیار',
    symbol: 'GOLD',
    unit: 'toman_per_gram',
  ),
  PriceAlertInstrument(id: 'coin', name: 'سکه تمام', symbol: 'COIN'),
  PriceAlertInstrument(id: 'btc', name: 'بیت‌کوین', symbol: 'BTC'),
  PriceAlertInstrument(id: 'eth', name: 'اتریوم', symbol: 'ETH'),
];

String? catalogNameFor(String id) {
  for (final item in priceAlertCatalog) {
    if (item.id == id) return item.name;
  }
  return null;
}

PriceAlertInstrument? catalogInstrument(String id) {
  for (final item in priceAlertCatalog) {
    if (item.id == id) return item;
  }
  return null;
}

/// JSON list or encoded string (SQLite settings table / backups).
class PriceAlertList {
  static List<PriceAlert> parse(dynamic v) {
    if (v == null) return [];
    dynamic raw = v;
    if (raw is String) {
      final t = raw.trim();
      if (t.isEmpty) return [];
      try {
        raw = jsonDecode(t);
      } catch (_) {
        return [];
      }
    }
    if (raw is! List) return [];
    final out = <PriceAlert>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final alert = PriceAlert.fromJson(Map<String, dynamic>.from(item));
      if (alert.id.isEmpty) continue;
      out.add(alert);
    }
    return out;
  }

  static String encode(List<PriceAlert> alerts) =>
      jsonEncode(alerts.map((e) => e.toJson()).toList());
}

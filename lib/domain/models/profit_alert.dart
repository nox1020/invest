import 'dart:convert';

/// Per-holding / per-lot unrealized PnL notification thresholds.
class ProfitAlert {
  ProfitAlert({
    required this.id,
    this.name = '',
    this.symbol = '',
    this.enabled = true,
    this.profitToman,
    this.lossToman,
    this.profitPct,
    this.lossPct,
  });

  /// `asset:12` or `trade:45`.
  String id;
  String name;
  String symbol;
  bool enabled;

  /// Notify when unrealized PnL is at or above this (toman).
  double? profitToman;

  /// Notify when unrealized PnL is at or below `-lossToman`.
  double? lossToman;

  /// Notify when unrealized PnL % is at or above this.
  double? profitPct;

  /// Notify when unrealized PnL % is at or below `-lossPct`.
  double? lossPct;

  bool get hasThreshold =>
      _pos(profitToman) ||
      _pos(lossToman) ||
      _pos(profitPct) ||
      _pos(lossPct);

  bool get isArmed => enabled && hasThreshold;

  String get displayName {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    final s = symbol.trim();
    if (s.isNotEmpty) return s;
    return id;
  }

  static String forAsset(int assetId) => 'asset:$assetId';
  static String forTrade(int tradeId) => 'trade:$tradeId';

  ProfitAlert copy() => ProfitAlert(
        id: id,
        name: name,
        symbol: symbol,
        enabled: enabled,
        profitToman: profitToman,
        lossToman: lossToman,
        profitPct: profitPct,
        lossPct: lossPct,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'symbol': symbol,
        'enabled': enabled,
        'profit_toman': profitToman,
        'loss_toman': lossToman,
        'profit_pct': profitPct,
        'loss_pct': lossPct,
      };

  factory ProfitAlert.fromJson(Map<String, dynamic> m) {
    return ProfitAlert(
      id: '${m['id'] ?? ''}'.trim(),
      name: '${m['name'] ?? ''}',
      symbol: '${m['symbol'] ?? ''}',
      enabled: _on(m['enabled']),
      profitToman: _d(m['profit_toman'] ?? m['profitToman']),
      lossToman: _d(m['loss_toman'] ?? m['lossToman']),
      profitPct: _d(m['profit_pct'] ?? m['profitPct']),
      lossPct: _d(m['loss_pct'] ?? m['lossPct']),
    );
  }

  static bool _pos(double? v) => v != null && v > 0;

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

class ProfitAlertList {
  static List<ProfitAlert> parse(dynamic v) {
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
    final out = <ProfitAlert>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final alert = ProfitAlert.fromJson(Map<String, dynamic>.from(item));
      if (alert.id.isEmpty) continue;
      out.add(alert);
    }
    return out;
  }

  static String encode(List<ProfitAlert> alerts) =>
      jsonEncode(alerts.map((e) => e.toJson()).toList());
}

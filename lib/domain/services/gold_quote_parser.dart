import 'package:invest/config/app_config.dart';

/// Parsed Iranian 18k gold quote in Toman per gram.
class GoldQuoteParse {
  const GoldQuoteParse({
    required this.priceToman,
    this.change24hPct,
    required this.source,
  });

  final double priceToman;
  final double? change24hPct;
  final String source;
}

/// Parse free / public gold JSON payloads into Toman/gram (18k).
class GoldQuoteParser {
  GoldQuoteParser._();

  static const wallGoldSymbol = 'GLD_18C_750TMN';

  /// WallGold public markets list (`/api/v1/markets`).
  static GoldQuoteParse? fromWallGold(dynamic body) {
    final markets = _marketsList(body);
    if (markets == null) return null;
    for (final item in markets) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final symbol = '${m['symbol'] ?? ''}'.toUpperCase();
      if (symbol != wallGoldSymbol) continue;
      final cap = m['marketCap'];
      final capMap = cap is Map ? Map<String, dynamic>.from(cap) : m;
      final price = _positive(_num(capMap['lastPrice']) ??
          _num(capMap['lastBuyPrice']) ??
          _num(capMap['lastSellPrice']));
      if (price == null) return null;
      // WallGold reports relative day change (0.02 → 2%).
      final rawChange = _num(capMap['24hChangePrice']);
      final change = rawChange == null
          ? null
          : (rawChange.abs() <= 1 ? rawChange * 100 : rawChange);
      return GoldQuoteParse(
        priceToman: price,
        change24hPct: change,
        source: 'wallgold',
      );
    }
    return null;
  }

  /// TGJU public ajax feed (`call1.tgju.org/ajax.json`).
  static GoldQuoteParse? fromTgju(dynamic body) {
    if (body is! Map) return null;
    final current = body['current'];
    if (current is! Map) return null;
    final geram = current['geram18'];
    if (geram is! Map) return null;
    final irr = _positive(_num(geram['p']));
    if (irr == null) return null;
    return GoldQuoteParse(
      priceToman: irr / 10.0,
      change24hPct: _num(geram['dp']),
      source: 'tgju',
    );
  }

  /// Legacy Persian Toolbox metal/market payloads (often 24k spot in IRR).
  ///
  /// When [assume24kSpot] is true (default), convert to 18k. Prefer WallGold /
  /// TGJU for Iranian bazaar 18k — this path is only a last-resort fallback.
  static GoldQuoteParse? fromPersianToolbox(
    dynamic body, {
    bool assume24kSpot = true,
  }) {
    if (body is! Map) return null;
    final root = Map<String, dynamic>.from(body);
    final payload = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    final gold = payload['gold'];
    if (gold is! Map) return null;
    final g = Map<String, dynamic>.from(gold);
    var price = _positive(_num(g['pricePerGram']));
    if (price == null) return null;
    final units = payload['units'];
    final unit = units is Map
        ? '${units['goldPricePerGram'] ?? 'IRR'}'.toUpperCase()
        : 'IRR';
    if (unit.contains('IRR') || unit.contains('RIAL') || unit.contains('RLS')) {
      price = price / 10.0;
    }
    if (assume24kSpot) {
      price = price * 0.75;
    }
    return GoldQuoteParse(
      priceToman: price,
      change24hPct: _num(g['change24h']),
      source: 'persiantoolbox',
    );
  }

  static GoldQuoteParse? fromAny(dynamic body) {
    return fromWallGold(body) ?? fromTgju(body) ?? fromPersianToolbox(body);
  }

  /// Persian Toolbox metal host is dead; its `/market` gold field is 24k spot
  /// on a non-bazaar FX and should not drive Iranian 18k holdings.
  static bool isStaleGoldUrl(String? url) {
    final u = (url ?? '').trim().toLowerCase();
    if (u.isEmpty) return true;
    if (u.contains('api.persiantoolbox.com')) return true;
    if (u.contains('persiantoolbox.ir') && u.contains('/market')) return true;
    return false;
  }

  static String resolveConfiguredUrl(String? configured) {
    final t = (configured ?? '').trim();
    if (isStaleGoldUrl(t)) return AppConfig.defaultGoldApiUrl;
    return t;
  }

  /// Vinor/toolbox often store ~13–18M Toman/g (24k spot × wrong FX × 0.75).
  /// Live Iranian 18k bazaar is far higher; reject those stale marks when a
  /// free-market quote is available (or when the candidate is obviously low).
  static bool isUnderstated18kToman(double? priceToman) {
    if (priceToman == null || !priceToman.isFinite || priceToman <= 0) {
      return true;
    }
    // Floor keeps a wide margin under today's ~26M bazaar 18k.
    return priceToman < 20000000;
  }

  /// Prefer [freeMarket] whenever the remote/server mark looks understated.
  static double? preferFreeMarketGold({
    required double? freeMarket,
    required double? remoteOrCached,
  }) {
    if (freeMarket != null &&
        freeMarket > 0 &&
        !isUnderstated18kToman(freeMarket)) {
      return freeMarket;
    }
    if (remoteOrCached != null &&
        remoteOrCached > 0 &&
        !isUnderstated18kToman(remoteOrCached)) {
      return remoteOrCached;
    }
    return freeMarket ?? remoteOrCached;
  }

  static List? _marketsList(dynamic body) {
    if (body is List) return body;
    if (body is! Map) return null;
    final result = body['result'];
    if (result is List) return result;
    if (body['data'] is List) return body['data'] as List;
    return null;
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final t = '$v'.trim().replaceAll(',', '').replaceAll('٬', '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  static double? _positive(double? v) =>
      (v != null && v > 0 && v.isFinite) ? v : null;
}

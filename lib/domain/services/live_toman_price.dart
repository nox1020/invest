import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/commodity_quote.dart';

/// Live **Toman** unit mark from the commodity/Wallex index.
///
/// Gold and cash (USDT) use the dedicated quotes/rates. Crypto uses the
/// matching TMN market when present; a USD-only quote is converted with
/// the live USDT/TMN rate. Returns null when there is no match — callers
/// must keep the stored price and must not invent a mark.
double? liveTomanPriceFor({
  required String name,
  String symbol = '',
  String notes = '',
  required Iterable<CommodityQuote> quotes,
  double? usdtTmn,
  double? goldTmn,
  bool includeGold = true,
  bool includeUsdt = true,
  bool includeCrypto = true,
}) {
  final kind = detectAssetKind(name: name, symbol: symbol, notes: notes);

  if (includeGold && kind == AssetKind.gold) {
    final quoted = _priceById(quotes, 'gold');
    if (quoted != null) return quoted;
    if (goldTmn != null && goldTmn > 0) return goldTmn;
    return null;
  }

  if (includeUsdt && kind == AssetKind.cash) {
    final quoted = _priceById(quotes, 'usdt');
    if (quoted != null) return quoted;
    if (usdtTmn != null && usdtTmn > 0) return usdtTmn;
    return null;
  }

  if (!includeCrypto) return null;
  if (kind == AssetKind.property ||
      kind == AssetKind.vehicle ||
      kind == AssetKind.stock) {
    return null;
  }
  if (kind == AssetKind.gold || kind == AssetKind.cash) return null;

  final ticker = cryptoTicker(name: name, symbol: symbol);
  if (ticker == null) return null;

  double? toman;
  double? usd;
  for (final q in quotes) {
    final p = q.price;
    if (p == null || p <= 0) continue;
    if (!_quoteMatchesTicker(q, ticker)) continue;
    if (q.unit.toLowerCase() == 'usd') {
      usd = p;
    } else {
      toman = p;
    }
  }
  if (toman != null) return toman;
  if (usd != null && usdtTmn != null && usdtTmn > 0) return usd * usdtTmn;
  return null;
}

/// Normalized crypto base ticker (`BTC`, `SOL`) from symbol or Persian name.
String? cryptoTicker({required String name, String symbol = ''}) {
  var s = symbol.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (s.endsWith('TMN') && s.length > 3) {
    s = s.substring(0, s.length - 3);
  } else if (s.endsWith('IRT') && s.length > 3) {
    s = s.substring(0, s.length - 3);
  } else if (s.endsWith('USDT') && s.length > 4) {
    s = s.substring(0, s.length - 4);
  }
  if (s.isNotEmpty && s != 'TMN' && s != 'IRT' && s != 'USDT' && s != 'USD') {
    return s;
  }

  final n = name.trim().toLowerCase();
  if (n.contains('bitcoin') || n.contains('بیت')) return 'BTC';
  if (n.contains('ethereum') || n.contains('اتریوم') || n.contains('اتـریوم')) {
    return 'ETH';
  }
  return null;
}

bool _quoteMatchesTicker(CommodityQuote q, String ticker) {
  final t = ticker.toUpperCase();
  final qs = q.symbol.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final id = q.id.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9_]'), '');
  final mkt = (q.resolvedMarketSymbol ?? '')
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), '');

  if (qs == t || qs == '${t}TMN') return true;
  if (id == t || id == 'WALLEX_${t}TMN' || id.endsWith('_${t}TMN')) {
    return true;
  }
  if (mkt == t || mkt == '${t}TMN') return true;
  return false;
}

double? _priceById(Iterable<CommodityQuote> quotes, String id) {
  for (final q in quotes) {
    if (q.id == id && q.price != null && q.price! > 0) return q.price;
  }
  return null;
}

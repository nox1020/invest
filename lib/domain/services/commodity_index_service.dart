import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/commodity_quote.dart';

class MarketIndexBundle {
  const MarketIndexBundle({
    required this.essentials,
    required this.wallexMarkets,
  });

  final List<CommodityQuote> essentials;
  final List<CommodityQuote> wallexMarkets;

  bool get hasAnyPrice =>
      essentials.any((q) => q.price != null) ||
      wallexMarkets.any((q) => q.price != null);
}

/// Essential commodities + full Wallex TMN market book.
class CommodityIndexService {
  CommodityIndexService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _coinGoldGrams = 8.133;

  Future<MarketIndexBundle> fetchAll({
    String? wallexUrl,
    String? marketUrl,
  }) async {
    final wallexUrlResolved = wallexUrl?.isNotEmpty == true
        ? wallexUrl!
        : AppConfig.defaultWallexUrl;

    final marketFuture = _fetchPersianMarket(marketUrl);
    final wallexFuture = _fetchWallexPayload(wallexUrlResolved);

    final market = await marketFuture;
    final wallex = await wallexFuture;

    final essentials = _buildEssentials(market, wallex);
    final wallexMarkets = _parseWallexTmnMarkets(wallex);

    return MarketIndexBundle(
      essentials: essentials,
      wallexMarkets: wallexMarkets,
    );
  }

  /// Backward-compatible essentials-only fetch.
  Future<List<CommodityQuote>> fetch({
    String? wallexUrl,
    String? marketUrl,
  }) async {
    final bundle = await fetchAll(wallexUrl: wallexUrl, marketUrl: marketUrl);
    return bundle.essentials;
  }

  List<CommodityQuote> _buildEssentials(
    Map<String, dynamic>? market,
    Map<String, dynamic>? wallex,
  ) {
    final usdt = _usdtFromWallex(wallex);

    final usdIrr = _num(market?['currencies']?['IRR']?['rate']);
    final usdToman = usdIrr != null && usdIrr > 0 ? usdIrr / 10.0 : null;

    double? fxToman(String code) {
      if (usdToman == null) return null;
      final rate = _num(market?['currencies']?[code]?['rate']);
      if (rate == null || rate <= 0) return null;
      if (code == 'USD') return usdToman;
      if (rate >= 1) return usdToman / rate;
      return usdToman / rate;
    }

    double? fxChange(String code) =>
        _num(market?['currencies']?[code]?['change24h']);

    final goldIrr = _num(market?['gold']?['pricePerGram']);
    final goldToman =
        goldIrr != null && goldIrr > 0 ? goldIrr / 10.0 : null;
    final goldChange = _num(market?['gold']?['change24h']);

    final btcUsd = _num(market?['crypto']?['BTC']?['priceUSD']);
    final ethUsd = _num(market?['crypto']?['ETH']?['priceUSD']);

    // Prefer live Wallex TMN prices for BTC/ETH when available.
    final wallexBtc = _findWallexQuote(wallex, 'BTCTMN');
    final wallexEth = _findWallexQuote(wallex, 'ETHTMN');

    return [
      CommodityQuote(
        id: 'usdt',
        name: 'تتر',
        symbol: 'USDT',
        unit: 'toman',
        price: usdt,
        change24h: _findWallexQuote(wallex, 'USDTTMN')?.change24h,
        icon: Icons.currency_bitcoin_rounded,
      ),
      CommodityQuote(
        id: 'usd',
        name: 'دلار آمریکا',
        symbol: 'USD',
        unit: 'toman',
        price: fxToman('USD'),
        change24h: fxChange('USD'),
        icon: Icons.attach_money_rounded,
      ),
      CommodityQuote(
        id: 'eur',
        name: 'یورو',
        symbol: 'EUR',
        unit: 'toman',
        price: fxToman('EUR'),
        change24h: fxChange('EUR'),
        icon: Icons.euro_rounded,
      ),
      CommodityQuote(
        id: 'gbp',
        name: 'پوند انگلیس',
        symbol: 'GBP',
        unit: 'toman',
        price: fxToman('GBP'),
        change24h: fxChange('GBP'),
        icon: Icons.currency_pound_rounded,
      ),
      CommodityQuote(
        id: 'aed',
        name: 'درهم امارات',
        symbol: 'AED',
        unit: 'toman',
        price: fxToman('AED'),
        change24h: fxChange('AED'),
        icon: Icons.flag_rounded,
      ),
      CommodityQuote(
        id: 'try',
        name: 'لیر ترکیه',
        symbol: 'TRY',
        unit: 'toman',
        price: fxToman('TRY'),
        change24h: fxChange('TRY'),
        icon: Icons.currency_lira_rounded,
      ),
      CommodityQuote(
        id: 'gold',
        name: 'طلای ۱۸ عیار',
        symbol: 'GOLD',
        unit: 'toman_per_gram',
        price: goldToman,
        change24h: goldChange,
        icon: Icons.diamond_outlined,
      ),
      CommodityQuote(
        id: 'coin',
        name: 'سکه تمام (تقریبی)',
        symbol: 'COIN',
        unit: 'toman',
        price: goldToman != null ? goldToman * _coinGoldGrams : null,
        change24h: goldChange,
        icon: Icons.monetization_on_outlined,
      ),
      CommodityQuote(
        id: 'btc',
        name: 'بیت‌کوین',
        symbol: 'BTC',
        unit: wallexBtc?.price != null ? 'toman' : 'usd',
        price: wallexBtc?.price ?? btcUsd,
        change24h: wallexBtc?.change24h ??
            _num(market?['crypto']?['BTC']?['change24h']),
        icon: Icons.currency_bitcoin,
      ),
      CommodityQuote(
        id: 'eth',
        name: 'اتریوم',
        symbol: 'ETH',
        unit: wallexEth?.price != null ? 'toman' : 'usd',
        price: wallexEth?.price ?? ethUsd,
        change24h: wallexEth?.change24h ??
            _num(market?['crypto']?['ETH']?['change24h']),
        icon: Icons.token_outlined,
      ),
    ];
  }

  List<CommodityQuote> _parseWallexTmnMarkets(Map<String, dynamic>? wallex) {
    if (wallex == null) return const [];
    final result = wallex['result'];
    if (result is! Map) return const [];
    final symbols = result['symbols'];
    if (symbols is! Map) return const [];

    final items = <CommodityQuote>[];
    for (final entry in symbols.entries) {
      final raw = entry.value;
      if (raw is! Map) continue;
      final quoteAsset = '${raw['quoteAsset'] ?? ''}'.toUpperCase();
      if (quoteAsset != 'TMN') continue;

      final stats = raw['stats'];
      if (stats is! Map) continue;

      final price = _num(stats['lastPrice']) ??
          _num(stats['bidPrice']) ??
          _num(stats['askPrice']);
      if (price == null || price <= 0) continue;

      final base = '${raw['baseAsset'] ?? entry.key}'.toUpperCase();
      final faName = '${raw['faBaseAsset'] ?? raw['faName'] ?? base}'.trim();
      final volume = _num(stats['24h_quoteVolume']) ??
          _num(stats['24h_tmnVolume']) ??
          0;

      items.add(
        CommodityQuote(
          id: 'wallex_${entry.key}',
          name: faName.isEmpty ? base : faName,
          symbol: base,
          unit: 'toman',
          price: price,
          change24h: _num(stats['24h_ch']),
          icon: Icons.currency_exchange_rounded,
          quoteVolume24h: volume,
          marketSymbol: '${entry.key}',
        ),
      );
    }

    items.sort((a, b) {
      final av = a.quoteVolume24h ?? 0;
      final bv = b.quoteVolume24h ?? 0;
      final byVol = bv.compareTo(av);
      if (byVol != 0) return byVol;
      return a.symbol.compareTo(b.symbol);
    });
    return items;
  }

  CommodityQuote? _findWallexQuote(
    Map<String, dynamic>? wallex,
    String marketSymbol,
  ) {
    if (wallex == null) return null;
    final result = wallex['result'];
    if (result is! Map) return null;
    final symbols = result['symbols'];
    if (symbols is! Map) return null;
    final raw = symbols[marketSymbol];
    if (raw is! Map) return null;
    final stats = raw['stats'];
    if (stats is! Map) return null;
    final price = _num(stats['lastPrice']) ?? _num(stats['bidPrice']);
    if (price == null) return null;
    return CommodityQuote(
      id: marketSymbol.toLowerCase(),
      name: '${raw['faBaseAsset'] ?? marketSymbol}',
      symbol: '${raw['baseAsset'] ?? marketSymbol}',
      unit: 'toman',
      price: price,
      change24h: _num(stats['24h_ch']),
    );
  }

  double? _usdtFromWallex(Map<String, dynamic>? wallex) {
    for (final key in ['USDTTMN', 'USDTTOM', 'USDTIRT']) {
      final q = _findWallexQuote(wallex, key);
      if (q?.price != null) return q!.price;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _fetchPersianMarket(String? marketUrl) async {
    final url = Uri.parse(
      marketUrl?.isNotEmpty == true
          ? marketUrl!
          : AppConfig.defaultMarketUrl,
    );
    try {
      final res = await _client.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map) return null;
      final data = body['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return Map<String, dynamic>.from(body);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchWallexPayload(String wallexUrl) async {
    try {
      final res = await _client
          .get(Uri.parse(wallexUrl))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is Map) return Map<String, dynamic>.from(body);
    } catch (_) {}
    return null;
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final n = double.tryParse('$v');
    if (n == null) return null;
    return n;
  }
}

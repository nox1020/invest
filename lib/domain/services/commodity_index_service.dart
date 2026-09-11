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

  Future<MarketIndexBundle> fetchAll({
    String? wallexUrl,
    String? marketUrl,
  }) async {
    final wallexUrlResolved = wallexUrl?.isNotEmpty == true
        ? wallexUrl!
        : AppConfig.defaultWallexUrl;

    // Sequential fetches keep shared http.Client / MockClient deterministic.
    final market = await _fetchPersianMarket(marketUrl);
    final wallex = await _fetchWallexPayload(wallexUrlResolved);

    final essentials = alignDerivedQuotes(_buildEssentials(market, wallex));
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
    final units = _asMap(market?['units']);
    final iranUnit = '${units?['iranCurrency'] ?? 'IRR'}'.toUpperCase();
    final goldUnit =
        '${units?['goldPricePerGram'] ?? iranUnit}'.toUpperCase();

    final usdIrr = _num(market?['currencies']?['IRR']?['rate']);
    final usdFromIrr = usdIrr != null && usdIrr > 0
        ? _toToman(usdIrr, iranUnit)
        : null;
    // Free-market dollar ≈ USDT/TMN; Persian Toolbox IRR is official/forex.
    final usdToman =
        (usdt != null && usdt > 0) ? usdt : usdFromIrr;

    double? fxToman(String code) {
      if (usdToman == null) return null;
      if (code == 'USD') return usdToman;
      final rate = _num(market?['currencies']?[code]?['rate']);
      if (rate == null || rate <= 0) return null;
      return usdToman / rate;
    }

    double? fxChange(String code) =>
        _num(market?['currencies']?[code]?['change24h']);

    final goldRaw = _num(market?['gold']?['pricePerGram']);
    final goldSpot =
        goldRaw != null && goldRaw > 0 ? _toToman(goldRaw, goldUnit) : null;
    // Spot/CoinGecko gold is 24k; the index shows طلای ۱۸ عیار.
    final goldToman =
        goldSpot != null ? goldSpot * k18GoldPurity : null;
    final goldChange = _num(market?['gold']?['change24h']);

    final btcUsd = _num(market?['crypto']?['BTC']?['priceUSD']);
    final ethUsd = _num(market?['crypto']?['ETH']?['priceUSD']);

    // Prefer live Wallex TMN prices for BTC/ETH when available.
    final wallexUsdt = _findWallexQuote(wallex, 'USDTTMN');
    final wallexBtc = _findWallexQuote(wallex, 'BTCTMN');
    final wallexEth = _findWallexQuote(wallex, 'ETHTMN');

    return [
      CommodityQuote(
        id: 'usdt',
        name: 'تتر',
        symbol: 'USDT',
        unit: 'toman',
        price: usdt,
        change24h: wallexUsdt?.change24h,
        icon: Icons.paid_rounded,
        marketSymbol: 'USDTTMN',
        high24h: wallexUsdt?.high24h,
        low24h: wallexUsdt?.low24h,
        bidPrice: wallexUsdt?.bidPrice,
        askPrice: wallexUsdt?.askPrice,
        quoteVolume24h: wallexUsdt?.quoteVolume24h,
      ),
      CommodityQuote(
        id: 'usd',
        name: 'دلار آمریکا',
        symbol: 'USD',
        unit: 'toman',
        price: fxToman('USD'),
        change24h: usdt != null ? wallexUsdt?.change24h : fxChange('USD'),
        icon: Icons.attach_money_rounded,
        marketSymbol: usdt != null ? 'USDTTMN' : null,
        high24h: usdt != null ? wallexUsdt?.high24h : null,
        low24h: usdt != null ? wallexUsdt?.low24h : null,
        bidPrice: usdt != null ? wallexUsdt?.bidPrice : null,
        askPrice: usdt != null ? wallexUsdt?.askPrice : null,
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
        goldKarat: 18,
      ),
      CommodityQuote(
        id: 'coin',
        name: 'سکه تمام (تقریبی)',
        symbol: 'COIN',
        unit: 'toman',
        price: goldToman != null ? goldToman * kFullCoin18kGrams : null,
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
        marketSymbol: wallexBtc != null ? 'BTCTMN' : null,
        high24h: wallexBtc?.high24h,
        low24h: wallexBtc?.low24h,
        bidPrice: wallexBtc?.bidPrice,
        askPrice: wallexBtc?.askPrice,
        quoteVolume24h: wallexBtc?.quoteVolume24h,
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
        marketSymbol: wallexEth != null ? 'ETHTMN' : null,
        high24h: wallexEth?.high24h,
        low24h: wallexEth?.low24h,
        bidPrice: wallexEth?.bidPrice,
        askPrice: wallexEth?.askPrice,
        quoteVolume24h: wallexEth?.quoteVolume24h,
      ),
    ];
  }

  List<CommodityQuote> _parseWallexTmnMarkets(Map<String, dynamic>? wallex) {
    final symbols = _symbolsMap(wallex);
    if (symbols == null) return const [];

    final items = <CommodityQuote>[];
    for (final entry in symbols.entries) {
      final raw = _asMap(entry.value);
      if (raw == null) continue;
      final quoteAsset = '${raw['quoteAsset'] ?? ''}'.toUpperCase();
      if (quoteAsset != 'TMN') continue;

      final stats = _asMap(raw['stats']);
      if (stats == null) continue;

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
          high24h: _num(stats['24h_highPrice']) ?? _num(stats['24h_high']),
          low24h: _num(stats['24h_lowPrice']) ?? _num(stats['24h_low']),
          bidPrice: _num(stats['bidPrice']),
          askPrice: _num(stats['askPrice']),
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
    final symbols = _symbolsMap(wallex);
    if (symbols == null) return null;
    final raw = _asMap(symbols[marketSymbol]);
    if (raw == null) return null;
    final stats = _asMap(raw['stats']);
    if (stats == null) return null;
    final price = _num(stats['lastPrice']) ?? _num(stats['bidPrice']);
    if (price == null || price <= 0) return null;
    return CommodityQuote(
      id: marketSymbol.toLowerCase(),
      name: '${raw['faBaseAsset'] ?? marketSymbol}',
      symbol: '${raw['baseAsset'] ?? marketSymbol}',
      unit: 'toman',
      price: price,
      change24h: _num(stats['24h_ch']),
      marketSymbol: marketSymbol,
      high24h: _num(stats['24h_highPrice']) ?? _num(stats['24h_high']),
      low24h: _num(stats['24h_lowPrice']) ?? _num(stats['24h_low']),
      bidPrice: _num(stats['bidPrice']),
      askPrice: _num(stats['askPrice']),
      quoteVolume24h: _num(stats['24h_quoteVolume']) ??
          _num(stats['24h_tmnVolume']),
    );
  }

  double? _usdtFromWallex(Map<String, dynamic>? wallex) {
    for (final key in ['USDTTMN', 'USDTTOM', 'USDTIRT']) {
      final q = _findWallexQuote(wallex, key);
      if (q?.price != null) return q!.price;
    }
    return null;
  }

  Map<String, dynamic>? _symbolsMap(Map<String, dynamic>? wallex) {
    if (wallex == null) return null;
    final result = _asMap(wallex['result']);
    if (result == null) return null;
    return _asMap(result['symbols']);
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
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
      final root = _asMap(body);
      if (root == null) return null;
      final data = _asMap(root['data']);
      return data ?? root;
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
      return _asMap(jsonDecode(res.body));
    } catch (_) {
      return null;
    }
  }

  static double? _num(dynamic v) => CommodityQuote.numOf(v);

  static double _toToman(double amount, String unit) {
    if (unit.contains('IRR') || unit.contains('RIAL')) return amount / 10.0;
    return amount;
  }

  /// Keep سکه derived from ۱۸ عیار gold and mark gold as 18k.
  static List<CommodityQuote> alignDerivedQuotes(List<CommodityQuote> quotes) {
    CommodityQuote? gold;
    for (final q in quotes) {
      if (q.id == 'gold') gold = q;
    }
    if (gold == null) return quotes;
    var g = gold;
    if (g.goldKarat != 18 && g.price != null && g.price! > 0) {
      g = g.copyWith(price: g.price! * k18GoldPurity, goldKarat: 18);
    } else if (g.goldKarat != 18) {
      g = g.copyWith(goldKarat: 18);
    }
    final coinPrice =
        g.price != null && g.price! > 0 ? g.price! * kFullCoin18kGrams : null;
    return [
      for (final q in quotes)
        if (q.id == 'gold')
          g
        else if (q.id == 'coin')
          q.copyWith(
            price: coinPrice,
            change24h: g.change24h,
            clearPrice: coinPrice == null,
            clearChange: g.change24h == null,
          )
        else
          q,
    ];
  }
}

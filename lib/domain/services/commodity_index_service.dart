import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/services/quote_clients.dart';

/// Fetches 10 essential commodity / FX quotes for the index tab.
class CommodityIndexService {
  CommodityIndexService({http.Client? client, QuoteClients? quotes})
      : _client = client ?? http.Client(),
        _quotes = quotes ?? QuoteClients(client: client);

  final http.Client _client;
  final QuoteClients _quotes;

  static const _coinGoldGrams = 8.133;

  Future<List<CommodityQuote>> fetch({
    String? wallexUrl,
    String? marketUrl,
  }) async {
    final market = await _fetchMarket(marketUrl);
    final usdt = await _quotes.fetchUsdtToman(wallexUrl: wallexUrl);

    final usdIrr = _num(market?['currencies']?['IRR']?['rate']);
    final usdToman = usdIrr != null && usdIrr > 0 ? usdIrr / 10.0 : null;

    double? fxToman(String code) {
      if (usdToman == null) return null;
      final rate = _num(market?['currencies']?[code]?['rate']);
      if (rate == null || rate <= 0) return null;
      if (code == 'USD') return usdToman;
      // Rates are foreign units per 1 USD (e.g. AED 3.67, TRY 48.28).
      if (rate >= 1) return usdToman / rate;
      // EUR/GBP style: USD per 1 unit of currency.
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

    return [
      CommodityQuote(
        id: 'usdt',
        name: 'تتر',
        symbol: 'USDT',
        unit: 'toman',
        price: usdt,
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
        unit: 'usd',
        price: btcUsd,
        change24h: _num(market?['crypto']?['BTC']?['change24h']),
        icon: Icons.currency_bitcoin,
      ),
      CommodityQuote(
        id: 'eth',
        name: 'اتریوم',
        symbol: 'ETH',
        unit: 'usd',
        price: ethUsd,
        change24h: _num(market?['crypto']?['ETH']?['change24h']),
        icon: Icons.token_outlined,
      ),
    ];
  }

  Future<Map<String, dynamic>?> _fetchMarket(String? marketUrl) async {
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

  static double? _num(dynamic v) {
    if (v == null) return null;
    final n = double.tryParse('$v');
    if (n == null || n <= 0) return null;
    return n;
  }
}

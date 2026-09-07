import 'package:flutter/material.dart';

class CommodityQuote {
  const CommodityQuote({
    required this.id,
    required this.name,
    required this.symbol,
    required this.unit,
    this.price,
    this.change24h,
    this.icon = Icons.show_chart_rounded,
    this.quoteVolume24h,
    this.marketSymbol,
    this.high24h,
    this.low24h,
    this.bidPrice,
    this.askPrice,
  });

  final String id;
  final String name;
  final String symbol;
  final String unit;
  final double? price;
  final double? change24h;
  final IconData icon;
  final double? quoteVolume24h;
  final String? marketSymbol;
  final double? high24h;
  final double? low24h;
  final double? bidPrice;
  final double? askPrice;

  bool get isUp => (change24h ?? 0) > 0;
  bool get isDown => (change24h ?? 0) < 0;

  /// Wallex market key for OHLC history when available.
  String? get resolvedMarketSymbol {
    final direct = marketSymbol?.trim();
    if (direct != null && direct.isNotEmpty) return direct.toUpperCase();
    return switch (id) {
      'usdt' => 'USDTTMN',
      'btc' => 'BTCTMN',
      'eth' => 'ETHTMN',
      _ => null,
    };
  }

  static IconData iconForId(String id) => switch (id) {
        'usdt' => Icons.currency_bitcoin_rounded,
        'usd' => Icons.attach_money_rounded,
        'eur' => Icons.euro_rounded,
        'gbp' => Icons.currency_pound_rounded,
        'aed' => Icons.flag_rounded,
        'try' => Icons.currency_lira_rounded,
        'gold' => Icons.diamond_outlined,
        'coin' => Icons.monetization_on_outlined,
        'btc' => Icons.currency_bitcoin_rounded,
        'eth' => Icons.token_outlined,
        _ => id.startsWith('wallex_')
            ? Icons.currency_exchange_rounded
            : Icons.show_chart_rounded,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'symbol': symbol,
        'unit': unit,
        'price': price,
        'change24h': change24h,
        'quote_volume_24h': quoteVolume24h,
        'market_symbol': marketSymbol,
        'high24h': high24h,
        'low24h': low24h,
        'bid_price': bidPrice,
        'ask_price': askPrice,
      };

  factory CommodityQuote.fromJson(Map<String, dynamic> m) {
    var id = (m['id'] as String?) ?? '';
    var unit = (m['unit'] as String?) ?? 'toman';
    var symbol = (m['symbol'] as String?) ?? '';
    // Normalize legacy/server gold payload to local essentials shape.
    if (id == 'gold') {
      unit = 'toman_per_gram';
      if (symbol.isEmpty || symbol == 'XAU') symbol = 'GOLD';
    }
    return CommodityQuote(
      id: id,
      name: (m['name'] as String?) ?? '',
      symbol: symbol,
      unit: unit,
      price: (m['price'] as num?)?.toDouble(),
      change24h: (m['change24h'] as num?)?.toDouble() ??
          (m['change_24h'] as num?)?.toDouble(),
      quoteVolume24h: (m['quote_volume_24h'] as num?)?.toDouble(),
      marketSymbol: m['market_symbol'] as String?,
      high24h: (m['high24h'] as num?)?.toDouble(),
      low24h: (m['low24h'] as num?)?.toDouble(),
      bidPrice: (m['bid_price'] as num?)?.toDouble() ??
          (m['bidPrice'] as num?)?.toDouble(),
      askPrice: (m['ask_price'] as num?)?.toDouble() ??
          (m['askPrice'] as num?)?.toDouble(),
      icon: iconForId(id),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:invest/domain/utils/money.dart';

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
    this.goldKarat,
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

  /// 18 for Iranian 18k display gold; 24 for raw spot; null when unknown.
  final int? goldKarat;

  bool get isUp => (change24h ?? 0) > 0;
  bool get isDown => (change24h ?? 0) < 0;

  /// Wallex market key for OHLC history when available.
  String? get resolvedMarketSymbol {
    final direct = marketSymbol?.trim();
    if (direct != null && direct.isNotEmpty) return direct.toUpperCase();
    return switch (id) {
      'usdt' || 'usd' => 'USDTTMN',
      'btc' => 'BTCTMN',
      'eth' => 'ETHTMN',
      _ => null,
    };
  }

  String formatPrice({bool compact = false}) {
    final p = price;
    if (p == null) return '—';
    switch (unit) {
      case 'usd':
        return formatUsd(p, compact: compact);
      case 'toman_per_gram':
        if (compact) return '${formatCompactToman(p)}/گ';
        return '${formatNumber(p, decimals: 0)} ت/گرم';
      case 'toman':
      default:
        if (compact) return formatCompactToman(p);
        return formatTomanPrice(p);
    }
  }

  static IconData iconForId(String id) => switch (id) {
        'usdt' => Icons.paid_rounded,
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

  CommodityQuote copyWith({
    String? id,
    String? name,
    String? symbol,
    String? unit,
    double? price,
    double? change24h,
    IconData? icon,
    double? quoteVolume24h,
    String? marketSymbol,
    double? high24h,
    double? low24h,
    double? bidPrice,
    double? askPrice,
    int? goldKarat,
    bool clearPrice = false,
    bool clearChange = false,
  }) {
    return CommodityQuote(
      id: id ?? this.id,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      unit: unit ?? this.unit,
      price: clearPrice ? null : (price ?? this.price),
      change24h: clearChange ? null : (change24h ?? this.change24h),
      icon: icon ?? this.icon,
      quoteVolume24h: quoteVolume24h ?? this.quoteVolume24h,
      marketSymbol: marketSymbol ?? this.marketSymbol,
      high24h: high24h ?? this.high24h,
      low24h: low24h ?? this.low24h,
      bidPrice: bidPrice ?? this.bidPrice,
      askPrice: askPrice ?? this.askPrice,
      goldKarat: goldKarat ?? this.goldKarat,
    );
  }

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
        if (id == 'gold') 'karat': goldKarat ?? 18,
      };

  factory CommodityQuote.fromJson(Map<String, dynamic> m) {
    var id = '${m['id'] ?? ''}';
    var unit = '${m['unit'] ?? 'toman'}';
    if (unit.trim().isEmpty) unit = 'toman';
    var symbol = '${m['symbol'] ?? ''}';
    var price = numOf(m['price']);
    var karat = (m['karat'] as num?)?.toInt();
    // Normalize legacy/server gold payload to local 18k Toman/gram.
    if (id == 'gold') {
      unit = 'toman_per_gram';
      if (symbol.isEmpty || symbol.toUpperCase() == 'XAU') {
        symbol = 'GOLD';
        karat ??= 24;
      }
      if (price != null && price > 0 && karat != 18) {
        price = price * k18GoldPurity;
        karat = 18;
      }
      karat ??= 18;
    }
    return CommodityQuote(
      id: id,
      name: '${m['name'] ?? ''}',
      symbol: symbol,
      unit: unit,
      price: price,
      change24h: numOf(m['change24h']) ?? numOf(m['change_24h']),
      quoteVolume24h: numOf(m['quote_volume_24h']) ?? numOf(m['quoteVolume24h']),
      marketSymbol: m['market_symbol'] as String? ?? m['marketSymbol'] as String?,
      high24h: numOf(m['high24h']),
      low24h: numOf(m['low24h']),
      bidPrice: numOf(m['bid_price']) ?? numOf(m['bidPrice']),
      askPrice: numOf(m['ask_price']) ?? numOf(m['askPrice']),
      goldKarat: karat,
      icon: iconForId(id),
    );
  }

  static double? numOf(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final t = '$v'.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }
}

/// 18-karat gold is 75% pure; CoinGecko/spot quotes are 24k.
const k18GoldPurity = 0.75;

/// Full Bahar Azadi coin: 8.133g at 900 purity → grams of 18k equivalent.
const kFullCoinMassGrams = 8.133;
const kFullCoinPurity = 0.900;
const kFullCoin18kGrams = kFullCoinMassGrams * kFullCoinPurity / k18GoldPurity;

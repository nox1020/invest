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
}

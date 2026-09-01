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
  });

  final String id;
  final String name;
  final String symbol;
  final String unit;
  final double? price;
  final double? change24h;
  final IconData icon;

  bool get isUp => (change24h ?? 0) > 0;
  bool get isDown => (change24h ?? 0) < 0;
}

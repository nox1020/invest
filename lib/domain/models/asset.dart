import 'package:invest/domain/utils/json_values.dart';

class Asset {
  Asset({
    this.id,
    required this.name,
    this.symbol = '',
    this.quantity = 0,
    this.avgBuyPrice = 0,
    this.currentPrice = 0,
    this.notes = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  int? id;
  String name;
  String symbol;
  double quantity;
  double avgBuyPrice;
  double currentPrice;
  String notes;
  String createdAt;
  String updatedAt;

  double get totalValue => quantity * currentPrice;
  double get costBasis => quantity * avgBuyPrice;
  double get unrealizedPnl => totalValue - costBasis;
  double get unrealizedPnlPct =>
      costBasis.abs() < 1e-12 ? 0 : unrealizedPnl / costBasis * 100;

  factory Asset.fromMap(Map<String, Object?> m) => Asset(
        id: jsonInt(m['id']),
        name: jsonText(m['name']),
        symbol: jsonText(m['symbol']),
        quantity: jsonDouble(m['quantity']) ?? 0,
        avgBuyPrice: jsonDouble(m['avg_buy_price']) ?? 0,
        currentPrice: jsonDouble(m['current_price']) ?? 0,
        notes: jsonText(m['notes']),
        createdAt: jsonText(m['created_at']),
        updatedAt: jsonText(m['updated_at']),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'symbol': symbol,
        'quantity': quantity,
        'avg_buy_price': avgBuyPrice,
        'current_price': currentPrice,
        'notes': notes,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

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

  factory Asset.fromMap(Map<String, Object?> m) => Asset(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        symbol: (m['symbol'] as String?) ?? '',
        quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
        avgBuyPrice: (m['avg_buy_price'] as num?)?.toDouble() ?? 0,
        currentPrice: (m['current_price'] as num?)?.toDouble() ?? 0,
        notes: (m['notes'] as String?) ?? '',
        createdAt: (m['created_at'] as String?) ?? '',
        updatedAt: (m['updated_at'] as String?) ?? '',
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

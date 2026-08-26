import 'package:invest/config/app_config.dart';

class Trade {
  Trade({
    this.id,
    required this.assetId,
    required this.status,
    required this.quantity,
    required this.buyPrice,
    this.buyFee = 0,
    this.buyDate = '',
    this.buyNote = '',
    this.sellPrice,
    this.sellFee = 0,
    this.sellDate,
    this.sellNote = '',
    this.realizedPnl,
    this.returnPct,
    this.holdingDays,
    this.createdAt = '',
    this.updatedAt = '',
    this.assetName = '',
    this.assetSymbol = '',
    this.currentPrice = 0,
  });

  int? id;
  int assetId;
  String status;
  double quantity;
  double buyPrice;
  double buyFee;
  String buyDate;
  String buyNote;
  double? sellPrice;
  double sellFee;
  String? sellDate;
  String sellNote;
  double? realizedPnl;
  double? returnPct;
  int? holdingDays;
  String createdAt;
  String updatedAt;
  String assetName;
  String assetSymbol;
  double currentPrice;

  bool get isOpen => status == AppConfig.tradeOpen;
  bool get isClosed => status == AppConfig.tradeClosed;

  double get buyCost => quantity * buyPrice + buyFee;

  factory Trade.fromMap(Map<String, Object?> m) => Trade(
        id: m['id'] as int?,
        assetId: m['asset_id'] as int,
        status: (m['status'] as String?) ?? AppConfig.tradeOpen,
        quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
        buyPrice: (m['buy_price'] as num?)?.toDouble() ?? 0,
        buyFee: (m['buy_fee'] as num?)?.toDouble() ?? 0,
        buyDate: (m['buy_date'] as String?) ?? '',
        buyNote: (m['buy_note'] as String?) ?? '',
        sellPrice: (m['sell_price'] as num?)?.toDouble(),
        sellFee: (m['sell_fee'] as num?)?.toDouble() ?? 0,
        sellDate: m['sell_date'] as String?,
        sellNote: (m['sell_note'] as String?) ?? '',
        realizedPnl: (m['realized_pnl'] as num?)?.toDouble(),
        returnPct: (m['return_pct'] as num?)?.toDouble(),
        holdingDays: m['holding_days'] as int?,
        createdAt: (m['created_at'] as String?) ?? '',
        updatedAt: (m['updated_at'] as String?) ?? '',
        assetName: (m['asset_name'] as String?) ?? '',
        assetSymbol: (m['asset_symbol'] as String?) ?? '',
        currentPrice: (m['current_price'] as num?)?.toDouble() ?? 0,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'asset_id': assetId,
        'status': status,
        'quantity': quantity,
        'buy_price': buyPrice,
        'buy_fee': buyFee,
        'buy_date': buyDate,
        'buy_note': buyNote,
        'sell_price': sellPrice,
        'sell_fee': sellFee,
        'sell_date': sellDate,
        'sell_note': sellNote,
        'realized_pnl': realizedPnl,
        'return_pct': returnPct,
        'holding_days': holdingDays,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

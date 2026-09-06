import 'package:invest/config/app_config.dart';
import 'package:invest/domain/utils/buy_usd.dart';
import 'package:invest/domain/utils/dates.dart';

class Trade {
  Trade({
    this.id,
    required this.assetId,
    required this.status,
    required this.quantity,
    required this.buyPrice,
    this.buyPriceUsd,
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

  /// Optional unit buy price in USD (persisted + mirrored in [buyNote]).
  double? buyPriceUsd;
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

  double? get buyCostUsd {
    final u = buyPriceUsd;
    if (u == null || u <= 0) return null;
    return quantity * u;
  }

  double get markPrice =>
      isOpen ? currentPrice : (sellPrice ?? currentPrice);

  double get currentValue => quantity * markPrice;

  double get unrealizedPnl =>
      quantity * (currentPrice - buyPrice) - buyFee;

  double get unrealizedPnlPct {
    if (buyCost.abs() < 1e-12) return 0;
    return unrealizedPnl / buyCost * 100;
  }

  /// Days since buy for an open lot (0 if closed or undated).
  int get openDays => isOpen ? openHoldingDays(buyDate) : (holdingDays ?? 0);

  /// Free-text note without the `[buy_usd:…]` marker.
  String get buyNoteDisplay => parseBuyNoteUsd(buyNote).note;

  factory Trade.fromMap(Map<String, Object?> m) {
    final rawNote = (m['buy_note'] as String?) ?? '';
    final parsed = parseBuyNoteUsd(rawNote);
    final usd = readBuyPriceUsd(
      columnValue: m['buy_price_usd'] ?? m['buyPriceUsd'],
      buyNote: rawNote,
    );
    int? asInt(Object? v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    return Trade(
      id: asInt(m['id']),
      assetId: asInt(m['asset_id']) ?? 0,
      status: (m['status'] as String?) ?? AppConfig.tradeOpen,
      quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
      buyPrice: (m['buy_price'] as num?)?.toDouble() ?? 0,
      buyPriceUsd: usd,
      buyFee: (m['buy_fee'] as num?)?.toDouble() ?? 0,
      buyDate: (m['buy_date'] as String?) ?? '',
      buyNote: encodeBuyNoteUsd(usd: usd ?? parsed.usd, note: parsed.note),
      sellPrice: (m['sell_price'] as num?)?.toDouble(),
      sellFee: (m['sell_fee'] as num?)?.toDouble() ?? 0,
      sellDate: m['sell_date'] as String?,
      sellNote: (m['sell_note'] as String?) ?? '',
      realizedPnl: (m['realized_pnl'] as num?)?.toDouble(),
      returnPct: (m['return_pct'] as num?)?.toDouble(),
      holdingDays: asInt(m['holding_days']),
      createdAt: (m['created_at'] as String?) ?? '',
      updatedAt: (m['updated_at'] as String?) ?? '',
      assetName: (m['asset_name'] as String?) ?? '',
      assetSymbol: (m['asset_symbol'] as String?) ?? '',
      currentPrice: (m['current_price'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    final packedNote = encodeBuyNoteUsd(
      usd: buyPriceUsd,
      note: parseBuyNoteUsd(buyNote).note,
    );
    return {
      if (id != null) 'id': id,
      'asset_id': assetId,
      'status': status,
      'quantity': quantity,
      'buy_price': buyPrice,
      'buy_price_usd': buyPriceUsd,
      'buy_fee': buyFee,
      'buy_date': buyDate,
      'buy_note': packedNote,
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
}

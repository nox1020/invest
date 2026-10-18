import 'package:invest/config/app_config.dart';
import 'package:invest/domain/utils/buy_usd.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/json_values.dart';

class Trade {
  Trade({
    this.id,
    required this.assetId,
    required this.status,
    required this.quantity,
    required this.buyPrice,
    this.buyPriceUsd,
    this.buyUsdTmn,
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

  /// Toman per 1 USD on the buy date (`[buy_fx:…]` in [buyNote]).
  double? buyUsdTmn;
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

  /// Registered USD cost including buy fee converted at buy FX when known.
  double? get buyCostUsd {
    final u = buyPriceUsd;
    if (u == null || u <= 0) return null;
    var cost = quantity * u;
    if (buyFee.abs() > 1e-12) {
      final fx = resolvedBuyUsdTmn;
      if (fx == null || fx <= 0) return null;
      cost += buyFee / fx;
    }
    return cost;
  }

  /// Toman-per-USD rate locked at sell time (`[sell_fx:…]` in [sellNote]).
  double? get sellUsdTmn => readSellUsdTmn(sellNote);

  /// Free-text sell note without the `[sell_fx:…]` marker.
  String get sellNoteDisplay => parseSellNoteFx(sellNote).note;

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

  /// Free-text note without `[buy_usd:…]` / `[buy_fx:…]` markers.
  String get buyNoteDisplay => parseBuyNoteUsd(buyNote).note;

  /// Stored dollar Toman rate, else implied from Toman ÷ registered USD.
  double? get resolvedBuyUsdTmn => resolveBuyUsdTmn(
        storedFx: buyUsdTmn,
        buyToman: buyPrice,
        buyUsd: buyPriceUsd,
      );

  factory Trade.fromMap(Map<String, Object?> m) {
    final rawNote = jsonText(m['buy_note']);
    final parsed = parseBuyNoteUsd(rawNote);
    final usd = readBuyPriceUsd(
      columnValue: m['buy_price_usd'] ?? m['buyPriceUsd'],
      buyNote: rawNote,
    );
    int? asInt(Object? v) => jsonInt(v);

    return Trade(
      id: asInt(m['id']),
      assetId: asInt(m['asset_id']) ?? 0,
      status: jsonText(m['status'], fallback: AppConfig.tradeOpen),
      quantity: jsonDouble(m['quantity']) ?? 0,
      buyPrice: jsonDouble(m['buy_price']) ?? 0,
      buyPriceUsd: usd,
      buyUsdTmn: parsed.fx,
      buyFee: jsonDouble(m['buy_fee']) ?? 0,
      buyDate: jsonText(m['buy_date']),
      buyNote: encodeBuyNoteUsd(
        usd: usd ?? parsed.usd,
        fx: parsed.fx,
        note: parsed.note,
      ),
      sellPrice: jsonDouble(m['sell_price']),
      sellFee: jsonDouble(m['sell_fee']) ?? 0,
      sellDate: jsonText(m['sell_date']).trim().isEmpty
          ? null
          : jsonText(m['sell_date']),
      sellNote: jsonText(m['sell_note']),
      realizedPnl: jsonDouble(m['realized_pnl']),
      returnPct: jsonDouble(m['return_pct']),
      holdingDays: asInt(m['holding_days']),
      createdAt: jsonText(m['created_at']),
      updatedAt: jsonText(m['updated_at']),
      assetName: jsonText(m['asset_name']),
      assetSymbol: jsonText(m['asset_symbol']),
      currentPrice: jsonDouble(m['current_price']) ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    final packedNote = encodeBuyNoteUsd(
      usd: buyPriceUsd,
      fx: buyUsdTmn,
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

import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';

/// Shared mutation surface so local SQLite and Vinor REST stay in sync.
///
/// UI must call this instead of `dynamic` — missing named args then fail
/// at compile time instead of a giant APK [NoSuchMethodError].
abstract class InvestMutations {
  Future<Asset> createAsset({
    required String name,
    String symbol = '',
    double quantity = 0,
    double avgBuyPrice = 0,
    double currentPrice = 0,
    String notes = '',
    String? buyDate,
  });

  Future<void> updateAsset(Asset asset);

  Future<Trade> registerBuy({
    int? assetId,
    String? name,
    String symbol = '',
    required double quantity,
    required double buyPrice,
    double? buyPriceUsd,
    double? buyUsdTmn,
    double buyFee = 0,
    String? buyDate,
    String buyNote = '',
    double? currentPrice,
  });

  Future<Trade> updateOpenTrade({
    required int tradeId,
    required double quantity,
    required double buyPrice,
    double? buyPriceUsd,
    double? buyUsdTmn,
    double buyFee = 0,
    String? buyDate,
    String? buyNote,
  });

  Future<Trade> closeTrade({
    required int tradeId,
    required double sellPrice,
    double sellFee = 0,
    String? sellDate,
    String sellNote = '',
    double? quantity,
  });

  Future<void> deleteClosedTrade(int tradeId);
}

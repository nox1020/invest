import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';

/// Which local rows are not already on the server, and the book to show.
///
/// Server rows are never removed. A second pass with those rows present
/// creates nothing, so a re-login does not duplicate the book.
class PortfolioUploadPlan {
  const PortfolioUploadPlan({
    required this.assetsToCreate,
    required this.tradesToCreate,
    required this.assetIdsByKey,
    required this.displayAssets,
    required this.displayOpen,
    required this.displayClosed,
  });

  final List<Asset> assetsToCreate;
  final List<Trade> tradesToCreate;

  /// Server asset id for a [portfolioAssetKey], including assets we already have.
  final Map<String, int> assetIdsByKey;
  final List<Asset> displayAssets;
  final List<Trade> displayOpen;
  final List<Trade> displayClosed;

  bool get isComplete => assetsToCreate.isEmpty && tradesToCreate.isEmpty;
}

String portfolioAssetKey(String name, String symbol) =>
    '${name.trim().toLowerCase()}|${symbol.trim().toLowerCase()}';

String portfolioTradeKey(Trade trade) {
  String n(double? value) => value == null ? '' : value.toStringAsFixed(4);
  return [
    portfolioAssetKey(trade.assetName, trade.assetSymbol),
    trade.status,
    n(trade.quantity),
    n(trade.buyPrice),
    trade.buyDate,
    trade.sellDate ?? '',
    n(trade.sellPrice),
  ].join('|');
}

PortfolioUploadPlan planPortfolioUpload({
  required List<Asset> localAssets,
  required List<Trade> localTrades,
  required List<Asset> serverAssets,
  required List<Trade> serverTrades,
}) {
  final assetIdsByKey = <String, int>{};
  final serverAssetKeys = <String>{};
  for (final asset in serverAssets) {
    final key = portfolioAssetKey(asset.name, asset.symbol);
    serverAssetKeys.add(key);
    final id = asset.id;
    if (id != null) assetIdsByKey[key] = id;
  }
  final serverTradeKeys = {
    for (final trade in serverTrades) portfolioTradeKey(trade),
  };

  final seenAssetKeys = <String>{};
  final assetsToCreate = <Asset>[];
  for (final asset in localAssets) {
    if (asset.name.trim().isEmpty) continue;
    final key = portfolioAssetKey(asset.name, asset.symbol);
    if (serverAssetKeys.contains(key) || !seenAssetKeys.add(key)) continue;
    assetsToCreate.add(asset);
  }
  final seenTradeKeys = <String>{};
  final tradesToCreate = <Trade>[];
  for (final trade in localTrades) {
    if (!_tradeCanUpload(trade)) continue;
    final key = portfolioTradeKey(trade);
    if (serverTradeKeys.contains(key) || !seenTradeKeys.add(key)) continue;
    tradesToCreate.add(trade);
  }

  final displayAssets = <String, Asset>{};
  for (final asset in serverAssets) {
    displayAssets[portfolioAssetKey(asset.name, asset.symbol)] = asset;
  }
  for (final asset in localAssets) {
    final key = portfolioAssetKey(asset.name, asset.symbol);
    final existing = displayAssets[key];
    // A failed trade upload leaves the server asset at quantity 0.
    // Keep the local holding until the server copy is at least as large.
    if (existing == null || asset.quantity > existing.quantity + 1e-6) {
      displayAssets[key] = asset;
    }
  }

  final displayTrades = <String, Trade>{};
  for (final trade in serverTrades) {
    displayTrades[portfolioTradeKey(trade)] = trade;
  }
  for (final trade in localTrades) {
    displayTrades.putIfAbsent(portfolioTradeKey(trade), () => trade);
  }

  return PortfolioUploadPlan(
    assetsToCreate: assetsToCreate,
    tradesToCreate: tradesToCreate,
    assetIdsByKey: assetIdsByKey,
    displayAssets: displayAssets.values.toList(),
    displayOpen: [
      for (final trade in displayTrades.values)
        if (trade.isOpen) trade,
    ],
    displayClosed: [
      for (final trade in displayTrades.values)
        if (!trade.isOpen) trade,
    ],
  );
}

bool _tradeCanUpload(Trade trade) {
  if (trade.quantity <= 0 || trade.buyPrice <= 0) return false;
  if (trade.isClosed && (trade.sellPrice ?? 0) <= 0) return false;
  return true;
}

/// True when this asset has a local lot, so its quantity must come from trades
/// and not be posted twice on the asset row.
bool assetHasLocalTrades(Asset asset, List<Trade> trades) {
  final key = portfolioAssetKey(asset.name, asset.symbol);
  for (final trade in trades) {
    if (portfolioAssetKey(trade.assetName, trade.assetSymbol) == key) {
      return true;
    }
    if (asset.id != null && trade.assetId == asset.id) return true;
  }
  return false;
}

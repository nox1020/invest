import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/portfolio_upload.dart';

Asset _asset({
  int? id,
  required String name,
  String symbol = '',
  double quantity = 0,
}) {
  return Asset(
    id: id,
    name: name,
    symbol: symbol,
    quantity: quantity,
    avgBuyPrice: 10,
    currentPrice: 12,
  );
}

Trade _trade({
  int? id,
  int assetId = 1,
  String status = 'open',
  double quantity = 2,
  double buyPrice = 10,
  String buyDate = '2024-01-01',
  double? sellPrice,
  String? sellDate,
  String name = 'طلا',
  String symbol = 'GOLD',
}) {
  return Trade(
    id: id,
    assetId: assetId,
    status: status,
    quantity: quantity,
    buyPrice: buyPrice,
    buyDate: buyDate,
    sellPrice: sellPrice,
    sellDate: sellDate,
    assetName: name,
    assetSymbol: symbol,
  );
}

void main() {
  test('creates local-only rows once, then nothing on the next pass', () {
    final localAsset = _asset(name: 'طلا', symbol: 'GOLD', quantity: 2);
    final localTrade = _trade();
    final first = planPortfolioUpload(
      localAssets: [localAsset],
      localTrades: [localTrade],
      serverAssets: const [],
      serverTrades: const [],
    );
    expect(first.assetsToCreate, hasLength(1));
    expect(first.tradesToCreate, hasLength(1));
    expect(first.displayAssets.single.quantity, 2);
    expect(first.displayOpen, hasLength(1));

    final second = planPortfolioUpload(
      localAssets: [localAsset],
      localTrades: [localTrade],
      serverAssets: [
        _asset(id: 9, name: 'طلا', symbol: 'GOLD', quantity: 2),
      ],
      serverTrades: [
        _trade(id: 3, assetId: 9),
      ],
    );
    expect(second.isComplete, isTrue);
    expect(second.assetsToCreate, isEmpty);
    expect(second.tradesToCreate, isEmpty);
  });

  test('keeps every server row and shows the larger local quantity', () {
    final plan = planPortfolioUpload(
      localAssets: [
        _asset(id: 2, name: 'طلا', symbol: 'GOLD', quantity: 4),
      ],
      localTrades: const [],
      serverAssets: [
        _asset(id: 1, name: 'طلا', symbol: 'GOLD', quantity: 0),
        _asset(id: 3, name: 'سکه', symbol: 'COIN', quantity: 1),
      ],
      serverTrades: [
        _trade(id: 8, name: 'سکه', symbol: 'COIN', assetId: 3),
      ],
    );

    expect(plan.assetsToCreate, isEmpty);
    expect(plan.tradesToCreate, isEmpty);
    expect(plan.displayAssets.map((a) => a.id), containsAll([2, 3]));
    expect(
      plan.displayAssets.firstWhere((a) => a.name == 'طلا').quantity,
      4,
    );
    expect(plan.displayOpen.single.id, 8);
  });

  test('identical local rows are uploaded once', () {
    final plan = planPortfolioUpload(
      localAssets: [
        _asset(name: 'طلا', symbol: 'GOLD', quantity: 1),
        _asset(name: 'طلا', symbol: 'GOLD', quantity: 1),
      ],
      localTrades: [
        _trade(),
        _trade(),
      ],
      serverAssets: const [],
      serverTrades: const [],
    );
    expect(plan.assetsToCreate, hasLength(1));
    expect(plan.tradesToCreate, hasLength(1));
  });
}

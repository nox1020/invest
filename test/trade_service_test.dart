import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/app_database.dart';
import 'package:invest/domain/services/trade_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late TradeService service;

  setUp(() async {
    // Unique DB path per test so data does not leak across cases.
    final path =
        '${inMemoryDatabasePath}_${DateTime.now().microsecondsSinceEpoch}';
    db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, version) async {
          await AppDatabase.migrateFresh(db);
        },
      ),
    );
    service = TradeService(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('isGoldAsset heuristics', () {
    expect(TradeService.isGoldAsset('طلا', 'GOLD'), isTrue);
    expect(TradeService.isGoldAsset('سکه طلا', 'COIN'), isFalse);
    expect(TradeService.isGoldAsset('بیت‌کوین', 'BTC'), isFalse);
  });

  test('gold fund metrics from buy and partial sell', () async {
    final asset = await service.createAsset(
      name: 'طلا',
      symbol: 'GOLD',
      quantity: 0,
      avgBuyPrice: 0,
      currentPrice: 30000000,
    );
    await service.registerBuy(
      assetId: asset.id,
      quantity: 10,
      buyPrice: 30000000,
    );
    final open = await service.trades.listOpen();
    expect(open.length, 1);
    await service.closeTrade(
      tradeId: open.first.id!,
      sellPrice: 31000000,
      quantity: 4,
    );

    final m = await service.goldFundMetrics();
    expect(m.goldInG, 10);
    expect(m.goldOutG, 4);
    expect(m.goldHoldingG, 6);
    expect(m.goldInG - m.goldOutG, m.goldHoldingG);

    final refreshed = await service.assets.get(asset.id!);
    expect(refreshed!.quantity, 6);
  });

  test('gold fund ignores non-gold', () async {
    await service.createAsset(
      name: 'بیت‌کوین',
      symbol: 'BTC',
      quantity: 2,
      avgBuyPrice: 100,
      currentPrice: 110,
    );
    await service.createAsset(
      name: 'سکه طلا',
      symbol: 'COIN',
      quantity: 1,
      avgBuyPrice: 50000000,
      currentPrice: 50000000,
    );
    final m = await service.goldFundMetrics();
    expect(m.goldInG, 0);
    expect(m.goldOutG, 0);
    expect(m.goldHoldingG, 0);
  });

  test('deleteClosedTrade removes history without changing inventory', () async {
    final asset = await service.createAsset(
      name: 'طلا',
      symbol: 'GOLD',
      quantity: 0,
      avgBuyPrice: 0,
      currentPrice: 30000000,
    );
    await service.registerBuy(
      assetId: asset.id,
      quantity: 10,
      buyPrice: 30000000,
    );
    final open = await service.trades.listOpen();
    await service.closeTrade(
      tradeId: open.first.id!,
      sellPrice: 31000000,
      quantity: 4,
    );
    final closed = await service.trades.listClosed();
    expect(closed.length, 1);

    await service.deleteClosedTrade(closed.first.id!);
    expect(await service.trades.listClosed(), isEmpty);

    final remainingOpen = await service.trades.listOpen();
    expect(remainingOpen.single.quantity, 6);
    final refreshed = await service.assets.get(asset.id!);
    expect(refreshed!.quantity, 6);

    await expectLater(
      service.deleteClosedTrade(remainingOpen.single.id!),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('updateOpenTrade changes lot and resyncs inventory', () async {
    final asset = await service.createAsset(
      name: 'BTC',
      symbol: 'BTC',
      quantity: 0,
    );
    await service.registerBuy(
      assetId: asset.id,
      quantity: 2,
      buyPrice: 100,
      buyFee: 10,
    );
    final open = await service.trades.listOpen();
    final updated = await service.updateOpenTrade(
      tradeId: open.first.id!,
      quantity: 5,
      buyPrice: 80,
      buyFee: 4,
    );
    expect(updated.quantity, 5);
    expect(updated.buyPrice, 80);
    expect(updated.buyFee, 4);

    final refreshed = await service.assets.get(asset.id!);
    expect(refreshed!.quantity, 5);
    expect(refreshed.avgBuyPrice, 80);
  });

  test('updateOpenTrade rejects closed lots', () async {
    final asset = await service.createAsset(name: 'ETH', symbol: 'ETH', quantity: 0);
    await service.registerBuy(assetId: asset.id, quantity: 1, buyPrice: 50);
    final lot = (await service.trades.listOpen()).single;
    await service.closeTrade(tradeId: lot.id!, sellPrice: 60);
    final closed = (await service.trades.listClosed()).single;
    await expectLater(
      service.updateOpenTrade(
        tradeId: closed.id!,
        quantity: 1,
        buyPrice: 50,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}

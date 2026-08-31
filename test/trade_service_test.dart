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
}

import 'package:invest/config/app_config.dart';
import 'package:invest/data/repositories.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:sqflite/sqflite.dart';

const _eps = 1e-9;

class TradeService {
  TradeService(this._db)
      : assets = AssetRepository(_db),
        trades = TradeRepository(_db);

  final Database _db;
  final AssetRepository assets;
  final TradeRepository trades;

  static bool isGoldAsset(String name, [String symbol = '']) {
    final sym = symbol.trim().toUpperCase();
    final nm = name.trim();
    if ({'GOLD', 'XAU', 'GERAM', 'GRAM'}.contains(sym)) return true;
    if (sym.startsWith('AYAR')) return false;
    if (nm.contains('سکه') || nm.contains('عیار')) return false;
    return nm.contains('طلا');
  }

  static bool isUsdtAsset(String name, [String symbol = '']) {
    final sym = symbol.trim().toUpperCase();
    final nm = name.trim().toLowerCase();
    if ({'USDT', 'USD', 'DOLLAR', 'USDT.TMN', 'USDTTMN'}.contains(sym)) {
      return true;
    }
    if (name.contains('تتر')) return true;
    if ({'دلار', 'dollar', 'usd', 'usdt'}.contains(nm)) return true;
    return name.contains('دلار') && !name.contains('سکه');
  }

  Future<GoldFundMetrics> goldFundMetrics() async {
    var openG = 0.0;
    var closedG = 0.0;
    final all = [...await trades.listOpen(), ...await trades.listClosed()];
    for (final t in all) {
      if (!isGoldAsset(t.assetName, t.assetSymbol)) continue;
      final qty = t.quantity;
      if (qty <= _eps) continue;
      if (t.isClosed) {
        closedG += qty;
      } else {
        openG += qty;
      }
    }
    double clean(double v) => v.abs() < _eps ? 0.0 : double.parse(v.toStringAsFixed(8));
    return GoldFundMetrics(
      goldInG: clean(openG + closedG),
      goldOutG: clean(closedG),
      goldHoldingG: clean(openG),
    );
  }

  Future<Asset> createAsset({
    required String name,
    String symbol = '',
    double quantity = 0,
    double avgBuyPrice = 0,
    double currentPrice = 0,
    String notes = '',
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('نام دارایی الزامی است.');
    if (quantity < 0) throw ArgumentError('مقدار نمی‌تواند منفی باشد.');
    if (quantity > _eps && avgBuyPrice <= 0) {
      throw ArgumentError('برای موجودی اولیه، قیمت خرید الزامی است.');
    }
    final existing =
        await assets.findByNameSymbol(name.trim(), symbol.trim());
    if (existing != null) {
      throw ArgumentError('دارایی با این نام و نماد از قبل وجود دارد.');
    }
    final price = currentPrice > 0 ? currentPrice : avgBuyPrice;
    var asset = Asset(
      name: name.trim(),
      symbol: symbol.trim(),
      quantity: 0,
      avgBuyPrice: 0,
      currentPrice: price,
      notes: notes,
    );
    asset = await assets.create(asset);
    if (quantity > _eps) {
      await trades.create(Trade(
        assetId: asset.id!,
        status: AppConfig.tradeOpen,
        quantity: quantity,
        buyPrice: avgBuyPrice,
        buyDate: todayIso(),
        buyNote: 'موجودی اولیه',
      ));
      asset = await _syncInventory(asset.id!);
    }
    return asset;
  }

  Future<Trade> registerBuy({
    int? assetId,
    String? name,
    String symbol = '',
    required double quantity,
    required double buyPrice,
    double buyFee = 0,
    String? buyDate,
    String buyNote = '',
    double? currentPrice,
  }) async {
    if (quantity <= 0) throw ArgumentError('مقدار باید بزرگ‌تر از صفر باشد.');
    if (buyPrice <= 0) throw ArgumentError('قیمت خرید باید بزرگ‌تر از صفر باشد.');
    if (buyFee < 0) throw ArgumentError('کارمزد نمی‌تواند منفی باشد.');

    final asset = await _resolveAsset(
      assetId: assetId,
      name: name,
      symbol: symbol,
      buyPrice: buyPrice,
      currentPrice: currentPrice,
    );
    if (currentPrice != null && currentPrice > 0) {
      asset.currentPrice = currentPrice;
    } else if (asset.currentPrice <= 0) {
      asset.currentPrice = buyPrice;
    }
    await assets.update(asset);

    final trade = await trades.create(Trade(
      assetId: asset.id!,
      status: AppConfig.tradeOpen,
      quantity: quantity,
      buyPrice: buyPrice,
      buyFee: buyFee,
      buyDate: buyDate ?? todayIso(),
      buyNote: buyNote,
    ));
    await _syncInventory(asset.id!);
    return trade;
  }

  Future<Trade> closeTrade({
    required int tradeId,
    required double sellPrice,
    double sellFee = 0,
    String? sellDate,
    String sellNote = '',
    double? quantity,
  }) async {
    final trade = await trades.get(tradeId);
    if (trade == null) throw ArgumentError('معامله یافت نشد.');
    if (!trade.isOpen) throw ArgumentError('این معامله قبلاً بسته شده است.');
    if (sellPrice <= 0) throw ArgumentError('قیمت فروش باید بزرگ‌تر از صفر باشد.');
    if (sellFee < 0) throw ArgumentError('کارمزد نمی‌تواند منفی باشد.');

    final closeQty = quantity ?? trade.quantity;
    if (closeQty <= 0) throw ArgumentError('مقدار فروش باید بزرگ‌تر از صفر باشد.');
    if (closeQty > trade.quantity + _eps) {
      throw ArgumentError('مقدار فروش از مقدار معامله باز بیشتر است.');
    }

    final asset = await assets.get(trade.assetId);
    if (asset == null) throw ArgumentError('دارایی مرتبط یافت نشد.');

    final sellD = sellDate ?? todayIso();
    if (sellD.substring(0, 10).compareTo(trade.buyDate.substring(0, 10)) < 0) {
      throw ArgumentError('تاریخ فروش نمی‌تواند قبل از تاریخ خرید باشد.');
    }

    if (closeQty >= trade.quantity - _eps) {
      return _closeFull(trade, asset, sellPrice, sellFee, sellD, sellNote);
    }
    return _closePartial(
      trade,
      asset,
      closeQty,
      sellPrice,
      sellFee,
      sellD,
      sellNote,
    );
  }

  Future<Trade> _closeFull(
    Trade trade,
    Asset asset,
    double sellPrice,
    double sellFee,
    String sellDate,
    String sellNote,
  ) async {
    final pnl = realizedPnl(
      qty: trade.quantity,
      buyPrice: trade.buyPrice,
      sellPrice: sellPrice,
      buyFee: trade.buyFee,
      sellFee: sellFee,
    );
    final pct = returnPct(
      qty: trade.quantity,
      buyPrice: trade.buyPrice,
      sellPrice: sellPrice,
      buyFee: trade.buyFee,
      sellFee: sellFee,
    );
    trade
      ..status = AppConfig.tradeClosed
      ..sellPrice = sellPrice
      ..sellFee = sellFee
      ..sellDate = sellDate
      ..sellNote = sellNote
      ..realizedPnl = pnl
      ..returnPct = pct
      ..holdingDays = holdingDays(trade.buyDate, sellDate);
    await trades.update(trade);
    final synced = await _syncInventory(asset.id!);
    synced.currentPrice = sellPrice;
    await assets.update(synced);
    return (await trades.get(trade.id!))!;
  }

  Future<Trade> _closePartial(
    Trade trade,
    Asset asset,
    double closeQty,
    double sellPrice,
    double sellFee,
    String sellDate,
    String sellNote,
  ) async {
    final ratio = closeQty / trade.quantity;
    final buyFeeClosed = trade.buyFee * ratio;
    final buyFeeRemain = trade.buyFee - buyFeeClosed;
    final pnl = realizedPnl(
      qty: closeQty,
      buyPrice: trade.buyPrice,
      sellPrice: sellPrice,
      buyFee: buyFeeClosed,
      sellFee: sellFee,
    );
    final pct = returnPct(
      qty: closeQty,
      buyPrice: trade.buyPrice,
      sellPrice: sellPrice,
      buyFee: buyFeeClosed,
      sellFee: sellFee,
    );
    final closed = await trades.create(Trade(
      assetId: trade.assetId,
      status: AppConfig.tradeClosed,
      quantity: closeQty,
      buyPrice: trade.buyPrice,
      buyFee: buyFeeClosed,
      buyDate: trade.buyDate,
      buyNote: trade.buyNote,
      sellPrice: sellPrice,
      sellFee: sellFee,
      sellDate: sellDate,
      sellNote: sellNote,
      realizedPnl: pnl,
      returnPct: pct,
      holdingDays: holdingDays(trade.buyDate, sellDate),
    ));
    trade
      ..quantity = trade.quantity - closeQty
      ..buyFee = buyFeeRemain;
    await trades.update(trade);
    final synced = await _syncInventory(asset.id!);
    synced.currentPrice = sellPrice;
    await assets.update(synced);
    return closed;
  }

  Future<Asset> _syncInventory(int assetId) async {
    final asset = await assets.get(assetId);
    if (asset == null) throw ArgumentError('دارایی یافت نشد.');
    final openLots =
        await trades.listByAsset(assetId, AppConfig.tradeOpen);
    final totalQty = openLots.fold<double>(0, (s, t) => s + t.quantity);
    if (totalQty <= _eps) {
      asset.quantity = 0;
      asset.avgBuyPrice = 0;
    } else {
      final cost =
          openLots.fold<double>(0, (s, t) => s + t.quantity * t.buyPrice);
      asset.quantity = totalQty;
      asset.avgBuyPrice = cost / totalQty;
    }
    await assets.update(asset);
    return asset;
  }

  Future<Asset> _resolveAsset({
    int? assetId,
    String? name,
    String symbol = '',
    required double buyPrice,
    double? currentPrice,
  }) async {
    if (assetId != null) {
      final a = await assets.get(assetId);
      if (a == null) throw ArgumentError('دارایی یافت نشد.');
      return a;
    }
    if (name == null || name.trim().isEmpty) {
      throw ArgumentError('دارایی یا نام الزامی است.');
    }
    return createAsset(
      name: name,
      symbol: symbol,
      avgBuyPrice: buyPrice,
      currentPrice: currentPrice ?? buyPrice,
    );
  }

  Future<int> applyLivePrices({
    double? usdtTmn,
    double? goldTmn,
    bool updateUsdt = true,
    bool updateGold = true,
  }) async {
    var count = 0;
    for (final asset in await assets.listAll()) {
      double? newPrice;
      if (updateGold && isGoldAsset(asset.name, asset.symbol)) {
        if (goldTmn != null && goldTmn > 0) newPrice = goldTmn;
      } else if (updateUsdt && isUsdtAsset(asset.name, asset.symbol)) {
        if (usdtTmn != null && usdtTmn > 0) newPrice = usdtTmn;
      }
      if (newPrice == null) continue;
      if ((asset.currentPrice - newPrice).abs() < 0.5) continue;
      asset.currentPrice = newPrice;
      await assets.update(asset);
      count++;
    }
    return count;
  }
}

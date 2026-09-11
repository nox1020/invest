import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/services/commodity_index_service.dart';

void main() {
  test('CommodityQuote json round-trip keeps full quote fields', () {
    const q = CommodityQuote(
      id: 'btc',
      name: 'بیت‌کوین',
      symbol: 'BTC',
      unit: 'toman',
      price: 12,
      change24h: 1.5,
      quoteVolume24h: 9,
      marketSymbol: 'BTCTMN',
      high24h: 13,
      low24h: 11,
      bidPrice: 11.9,
      askPrice: 12.1,
    );
    final again = CommodityQuote.fromJson(q.toJson());
    expect(again.id, 'btc');
    expect(again.price, 12);
    expect(again.marketSymbol, 'BTCTMN');
    expect(again.high24h, 13);
    expect(again.bidPrice, 11.9);
    expect(again.askPrice, 12.1);
    expect(again.resolvedMarketSymbol, 'BTCTMN');
  });

  test('fromJson normalizes gold unit, symbol, and 24k spot to 18k', () {
    final gold = CommodityQuote.fromJson({
      'id': 'gold',
      'name': 'طلا',
      'symbol': 'XAU',
      'unit': 'toman',
      'price': 1000,
    });
    expect(gold.unit, 'toman_per_gram');
    expect(gold.symbol, 'GOLD');
    expect(gold.price, closeTo(750, 1e-9));
    expect(gold.goldKarat, 18);
    expect(gold.toJson()['karat'], 18);
  });

  test('fromJson gold with karat 18 is not converted again', () {
    final gold = CommodityQuote.fromJson({
      'id': 'gold',
      'name': 'طلای ۱۸ عیار',
      'symbol': 'GOLD',
      'unit': 'toman_per_gram',
      'price': 15000000,
      'karat': 18,
    });
    expect(gold.price, 15000000);
    expect(gold.goldKarat, 18);
  });

  test('fromJson accepts string numbers', () {
    final q = CommodityQuote.fromJson({
      'id': 'usdt',
      'name': 'تتر',
      'symbol': 'USDT',
      'unit': 'toman',
      'price': '236339.5',
      'change24h': '0.54',
      'bid_price': '236330',
    });
    expect(q.price, closeTo(236339.5, 1e-9));
    expect(q.change24h, closeTo(0.54, 1e-9));
    expect(q.bidPrice, closeTo(236330, 1e-9));
    expect(q.icon, isNotNull);
  });

  test('USD quote uses USDT Wallex history', () {
    const usd = CommodityQuote(
      id: 'usd',
      name: 'دلار آمریکا',
      symbol: 'USD',
      unit: 'toman',
      price: 1,
    );
    expect(usd.resolvedMarketSymbol, 'USDTTMN');
    expect(usd.formatPrice(compact: true), contains('ت'));
  });

  test('alignDerivedQuotes recomputes coin from 18k gold', () {
    final aligned = CommodityIndexService.alignDerivedQuotes([
      const CommodityQuote(
        id: 'gold',
        name: 'طلا',
        symbol: 'GOLD',
        unit: 'toman_per_gram',
        price: 10000000,
        goldKarat: 18,
        change24h: 1.2,
      ),
      const CommodityQuote(
        id: 'coin',
        name: 'سکه',
        symbol: 'COIN',
        unit: 'toman',
        price: 1,
      ),
    ]);
    final coin = aligned.firstWhere((q) => q.id == 'coin');
    expect(coin.price, closeTo(10000000 * kFullCoin18kGrams, 1));
    expect(coin.change24h, closeTo(1.2, 1e-9));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/commodity_quote.dart';

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

  test('fromJson normalizes gold unit and symbol', () {
    final gold = CommodityQuote.fromJson({
      'id': 'gold',
      'name': 'طلا',
      'symbol': 'XAU',
      'unit': 'toman',
      'price': 1000,
    });
    expect(gold.unit, 'toman_per_gram');
    expect(gold.symbol, 'GOLD');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/services/live_toman_price.dart';

void main() {
  const btcToman = CommodityQuote(
    id: 'btc',
    name: 'بیت‌کوین',
    symbol: 'BTC',
    unit: 'toman',
    price: 8e9,
    marketSymbol: 'BTCTMN',
  );
  const btcUsd = CommodityQuote(
    id: 'btc',
    name: 'Bitcoin',
    symbol: 'BTC',
    unit: 'usd',
    price: 80000,
  );
  const wallexSol = CommodityQuote(
    id: 'wallex_SOLTMN',
    name: 'سولانا',
    symbol: 'SOL',
    unit: 'toman',
    price: 15000000,
    marketSymbol: 'SOLTMN',
  );
  const usdt = CommodityQuote(
    id: 'usdt',
    name: 'تتر',
    symbol: 'USDT',
    unit: 'toman',
    price: 100000,
  );
  const gold = CommodityQuote(
    id: 'gold',
    name: 'طلا',
    symbol: 'GOLD',
    unit: 'toman_per_gram',
    price: 50000000,
  );

  test('crypto ticker from symbol variants and Persian names', () {
    expect(cryptoTicker(name: 'x', symbol: 'BTC'), 'BTC');
    expect(cryptoTicker(name: 'x', symbol: 'btctmn'), 'BTC');
    expect(cryptoTicker(name: 'x', symbol: 'SOL.TMN'), 'SOL');
    expect(cryptoTicker(name: 'بیت‌کوین', symbol: ''), 'BTC');
    expect(cryptoTicker(name: 'Ethereum', symbol: ''), 'ETH');
  });

  test('BTC current Toman comes from Wallex TMN, not USDT conversion', () {
    final p = liveTomanPriceFor(
      name: 'Bitcoin',
      symbol: 'BTC',
      quotes: [usdt, btcToman, wallexSol],
      usdtTmn: 100000,
    );
    expect(p, 8e9);
  });

  test('USD-only BTC quote converts through live USDT', () {
    final p = liveTomanPriceFor(
      name: 'Bitcoin',
      symbol: 'BTC',
      quotes: [btcUsd],
      usdtTmn: 100000,
    );
    expect(p, 80000 * 100000);
  });

  test('Wallex altcoin matches holdings by symbol', () {
    final p = liveTomanPriceFor(
      name: 'Solana',
      symbol: 'SOL',
      quotes: [wallexSol],
    );
    expect(p, 15000000);
  });

  test('kind marker lets unknown symbols match Wallex', () {
    const xyz = CommodityQuote(
      id: 'wallex_XYZTMN',
      name: 'XYZ',
      symbol: 'XYZ',
      unit: 'toman',
      price: 42,
      marketSymbol: 'XYZTMN',
    );
    expect(
      liveTomanPriceFor(
        name: 'MyToken',
        symbol: 'XYZ',
        notes: '[kind:crypto]',
        quotes: [xyz],
      ),
      42,
    );
    expect(
      liveTomanPriceFor(name: 'MyToken', symbol: 'XYZ', quotes: [btcToman]),
      isNull,
    );
  });

  test('gold and USDT use dedicated quotes; property is ignored', () {
    final quotes = [usdt, gold, btcToman];
    expect(
      liveTomanPriceFor(name: 'طلا', symbol: 'GOLD', quotes: quotes),
      50000000,
    );
    expect(
      liveTomanPriceFor(name: 'تتر', symbol: 'USDT', quotes: quotes),
      100000,
    );
    expect(
      liveTomanPriceFor(name: 'دلار', symbol: '', quotes: quotes),
      100000,
    );
    expect(
      liveTomanPriceFor(name: 'آپارتمان', symbol: 'REAL', quotes: quotes),
      isNull,
    );
    expect(
      liveTomanPriceFor(
        name: 'سهام فولاد',
        symbol: 'فولاد',
        notes: '[kind:stock]',
        quotes: quotes,
      ),
      isNull,
    );
  });

  test('wallex TMN quote wins over earlier USD essential', () {
    final p = liveTomanPriceFor(
      name: 'BTC',
      symbol: 'BTC',
      quotes: [btcUsd, btcToman],
      usdtTmn: 1,
    );
    expect(p, 8e9);
  });
}

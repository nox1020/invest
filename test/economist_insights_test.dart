import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/iran_inflation.dart';
import 'package:invest/domain/services/economist_insights.dart';
import 'package:invest/domain/services/holding_metrics.dart';

Asset _asset({
  required int id,
  required String name,
  String symbol = '',
  required double qty,
  required double price,
  String notes = '',
}) {
  return Asset(
    id: id,
    name: name,
    symbol: symbol,
    quantity: qty,
    avgBuyPrice: price,
    currentPrice: price,
    notes: notes,
  );
}

List<({Asset asset, HoldingMetrics metrics})> _holdings(List<Asset> assets) {
  return HoldingMetrics.activeHoldings(assets: assets, openTrades: const []);
}

IranInflationSnapshot _cpi({double yoy = 35, double monthly = 2.4}) {
  return IranInflationSnapshot(
    period: '1404-06',
    year: 1404,
    month: 6,
    cpiIndex: 280,
    pointToPointPct: yoy,
    monthlyPct: monthly,
    annualPct: 32,
    history: const [],
    sourceLabel: 'test',
    fetchedAt: DateTime(2026, 1, 1),
  );
}

CommodityQuote _q({
  required String id,
  double? price,
  double? change24h,
  double? high24h,
  double? low24h,
}) {
  return CommodityQuote(
    id: id,
    name: id,
    symbol: id.toUpperCase(),
    unit: 'toman',
    price: price,
    change24h: change24h,
    high24h: high24h,
    low24h: low24h,
  );
}

void main() {
  test('empty book asks for a household FX + gold core', () {
    final brief = buildEconomistInsights(
      holdings: const [],
      quotes: [
        _q(id: 'usdt', price: 100000, change24h: 1),
        _q(id: 'gold', price: 5000000, change24h: 0.5),
      ],
      inflation: _cpi(),
    );
    expect(brief.mix.isEmpty, isTrue);
    expect(brief.insights.map((e) => e.id),
        containsAll(['macro_brief', 'empty_book']));
    expect(brief.headline, isNotEmpty);
  });

  test('cash-heavy book is underhedged when CPI is high', () {
    final brief = buildEconomistInsights(
      holdings: _holdings([
        _asset(id: 1, name: 'تتر', symbol: 'USDT', qty: 70, price: 1),
        _asset(id: 2, name: 'طلا', symbol: 'GOLD', qty: 5, price: 1),
      ]),
      quotes: [
        _q(id: 'usdt', price: 100000, change24h: 0.4),
        _q(id: 'gold', price: 5000000, change24h: -0.2),
      ],
      inflation: _cpi(yoy: 38),
    );
    expect(brief.mix.cashPct, closeTo(93.3, 0.2));
    expect(brief.insights.map((e) => e.id), contains('cash_heavy'));
    expect(brief.insights.map((e) => e.id), contains('underhedged_inflation'));
  });

  test('crypto overweight without gold core is flagged', () {
    final brief = buildEconomistInsights(
      holdings: _holdings([
        _asset(id: 1, name: 'Bitcoin', symbol: 'BTC', qty: 8, price: 10),
        _asset(id: 2, name: 'طلا', symbol: 'GOLD', qty: 1, price: 10),
      ]),
      quotes: [
        _q(id: 'btc', price: 4e9, change24h: -3),
        _q(id: 'gold', price: 5e6, change24h: 1),
      ],
      inflation: _cpi(),
    );
    expect(brief.mix.cryptoPct, closeTo(88.9, 0.2));
    final ids = brief.insights.map((e) => e.id).toList();
    expect(ids, contains('crypto_overweight'));
    expect(ids, contains('btc_without_core'));
  });

  test('balanced gold+cash core is constructive', () {
    final brief = buildEconomistInsights(
      holdings: _holdings([
        _asset(id: 1, name: 'طلا', symbol: 'GOLD', qty: 30, price: 1),
        _asset(id: 2, name: 'تتر', symbol: 'USDT', qty: 40, price: 1),
        _asset(id: 3, name: 'Bitcoin', symbol: 'BTC', qty: 20, price: 1),
      ]),
      quotes: [
        _q(id: 'gold', price: 5e6, change24h: 0.4),
        _q(id: 'usdt', price: 1e5, change24h: 0.2),
        _q(id: 'btc', price: 4e9, change24h: 1),
      ],
      inflation: _cpi(yoy: 28, monthly: 1.2),
    );
    expect(brief.mix.goldPct, closeTo(33.3, 0.2));
    expect(brief.mix.cashPct, closeTo(44.4, 0.2));
    expect(brief.insights.map((e) => e.id), contains('balanced_core'));
    expect(brief.insights.first.id, 'macro_brief');
  });

  test('gold heat near the 24h high warns not to chase', () {
    final brief = buildEconomistInsights(
      holdings: _holdings([
        _asset(id: 1, name: 'طلا', symbol: 'GOLD', qty: 40, price: 1),
        _asset(id: 2, name: 'تتر', symbol: 'USDT', qty: 60, price: 1),
      ]),
      quotes: [
        _q(
          id: 'gold',
          price: 98,
          change24h: 4.2,
          high24h: 100,
          low24h: 80,
        ),
        _q(id: 'usdt', price: 1e5, change24h: 0.1),
      ],
    );
    expect(brief.mix.goldPct, 40);
    expect(brief.insights.map((e) => e.id), contains('gold_heat'));
  });

  test('coin holdings count as the gold inflation sleeve', () {
    final mix = portfolioSleeveWeights(
      _holdings([
        _asset(id: 1, name: 'سکه تمام', symbol: 'COIN', qty: 1, price: 80),
        _asset(id: 2, name: 'تتر', symbol: 'USDT', qty: 20, price: 1),
      ]),
    );
    expect(mix.goldPct, 80);
    expect(mix.cashPct, 20);
  });

  test('single-name concentration is a caution', () {
    final brief = buildEconomistInsights(
      holdings: _holdings([
        _asset(id: 1, name: 'آپارتمان ونک', symbol: 'REAL', qty: 1, price: 100),
      ]),
      quotes: const [],
    );
    expect(brief.insights.map((e) => e.id), contains('single_name'));
    expect(brief.insights.map((e) => e.id), contains('real_illiquid'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/price_alert.dart';
import 'package:invest/domain/services/price_alert_engine.dart';

void main() {
  test('fires once when crossing above/below then waits for recovery', () {
    final alerts = [
      PriceAlert(id: 'usdt', name: 'تتر', above: 120000, below: 100000),
    ];
    final latches = <String, PriceAlertLatch>{};

    var hits = PriceAlertEngine.evaluate(
      alerts: alerts,
      prices: {'usdt': 121000},
      latches: latches,
    );
    expect(hits, hasLength(1));
    expect(hits.single.side, PriceAlertSide.above);

    hits = PriceAlertEngine.evaluate(
      alerts: alerts,
      prices: {'usdt': 130000},
      latches: latches,
    );
    expect(hits, isEmpty);

    hits = PriceAlertEngine.evaluate(
      alerts: alerts,
      prices: {'usdt': 119000},
      latches: latches,
    );
    expect(hits, isEmpty);

    hits = PriceAlertEngine.evaluate(
      alerts: alerts,
      prices: {'usdt': 99000},
      latches: latches,
    );
    expect(hits, hasLength(1));
    expect(hits.single.side, PriceAlertSide.below);
  });

  test('disabled or threshold-less alerts never fire', () {
    final latches = <String, PriceAlertLatch>{};
    final hits = PriceAlertEngine.evaluate(
      alerts: [
        PriceAlert(id: 'btc', enabled: false, above: 1),
        PriceAlert(id: 'eth', enabled: true),
      ],
      prices: {'btc': 2, 'eth': 3},
      latches: latches,
    );
    expect(hits, isEmpty);
  });

  test('pricesFrom maps quote ids and live usdt/gold fallback', () {
    final prices = PriceAlertEngine.pricesFrom(
      quotes: const [
        CommodityQuote(
          id: 'eur',
          name: 'یورو',
          symbol: 'EUR',
          unit: 'toman',
          price: 80,
        ),
      ],
      usdt: 100,
      gold: 50,
    );
    expect(prices['eur'], 80);
    expect(prices['usdt'], 100);
    expect(prices['gold'], 50);
  });
}

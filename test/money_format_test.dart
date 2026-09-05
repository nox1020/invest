import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/utils/money.dart';

void main() {
  test('compact toman uses میلیارد / میلیون', () {
    expect(formatCompactToman(182000000000), '182 میلیارد ت');
    expect(formatCompactToman(73400000000, showSign: true), '+73.4 میلیارد ت');
    expect(formatCompactToman(-1450000), '−1.5 میلیون ت');
    expect(formatCompactToman(850), '850 ت');
  });

  test('usd formatting matches portfolio cards', () {
    expect(formatUsd(807379), '\$807,379');
    expect(formatUsd(800000, compact: true), '\$800K');
    expect(formatUsd(-149975, showSign: true), '−\$149,975');
    expect(formatUsd(80018), '\$80,018');
  });

  test('tomanToUsd converts with USDT rate', () {
    expect(tomanToUsd(180000000000, 225000), closeTo(800000, 1));
    expect(tomanToUsd(100, null), isNull);
    expect(tomanToUsd(100, 0), isNull);
  });

  test('unrealized pnl percent uses cost basis', () {
    final asset = Asset(
      name: 'Bitcoin',
      symbol: 'BTC',
      quantity: 10,
      avgBuyPrice: 100,
      currentPrice: 84.7,
    );
    expect(asset.unrealizedPnlPct, closeTo(-15.3, 0.05));
  });
}

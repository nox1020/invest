import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/utils/gold_purity.dart';

void main() {
  test('parses karat and millesimal purity', () {
    expect(parseGoldPurityFraction('18'), closeTo(k18GoldPurity, 1e-9));
    expect(parseGoldPurityFraction('۱۸'), closeTo(k18GoldPurity, 1e-9));
    expect(parseGoldPurityFraction('عیار 24'), closeTo(1.0, 1e-9));
    expect(parseGoldPurityFraction('750'), closeTo(0.75, 1e-9));
    expect(parseGoldPurityFraction('900'), closeTo(0.90, 1e-9));
    expect(parseGoldPurityFraction(''), isNull);
    expect(parseGoldPurityFraction('nope'), isNull);
  });

  test('scales 18k index quote to the holding karat', () {
    const p18 = 40000000.0;
    expect(scaleGoldPriceFrom18k(p18, null), p18);
    expect(scaleGoldPriceFrom18k(p18, '18'), p18);
    expect(scaleGoldPriceFrom18k(p18, '750'), p18);
    expect(
        scaleGoldPriceFrom18k(p18, '24'), closeTo(p18 / k18GoldPurity, 1e-6));
    expect(scaleGoldPriceFrom18k(p18, '21'),
        closeTo(p18 * (21 / 24) / k18GoldPurity, 1e-6));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/services/gold_calc.dart';

const _lots = [
  // id, grams, buyPrice, buyFee, date
  GoldLot(id: 1, grams: 8, buyPrice: 9850000, buyFee: 0, buyDate: '2025-06-02'),
  GoldLot(id: 2, grams: 12.5, buyPrice: 12400000, buyFee: 500000, buyDate: '2025-11-26'),
  GoldLot(id: 3, grams: 22, buyPrice: 12361400, buyFee: 0, buyDate: '2026-05-10'),
];

void main() {
  group('units', () {
    test('mithqal and مظنه conversions', () {
      expect(gramsToMithqal(4.6083), closeTo(1, 1e-12));
      expect(mithqalToGrams(2), closeTo(9.2166, 1e-12));
      expect(gramsToMithqal(mithqalToGrams(3.7)), closeTo(3.7, 1e-12));
      expect(gram18FromMazaneh(43318000), closeTo(10000000, 1e-6));
      expect(mazanehFromGram18(14280000), closeTo(61858104, 1e-3));
      expect(gram18FromMazaneh(mazanehFromGram18(14350000)), closeTo(14350000, 1e-6));
      expect(gram18FromMazaneh(0), 0);
      expect(gram18FromMazaneh(-5), 0);
      expect(mazanehFromGram18(0), 0);
    });

    test('karat fractions and conversions', () {
      expect(karatFraction(18), 0.75);
      expect(karatFraction(24), 1);
      expect(karatFraction(21), 0.875);
      expect(karatFraction(0), isNull);
      expect(karatFraction(25), isNull);
      expect(karatFraction(double.nan), isNull);
      // 1 g of 24k is 1.333 g of 18k, and back.
      expect(convertGoldGrams(1, 1, 0.75), closeTo(4 / 3, 1e-12));
      expect(convertGoldGrams(4 / 3, 0.75, 1), closeTo(1, 1e-12));
      expect(convertGoldGrams(10, 0.75, 0.75), 10);
      // 18k price → 24k price is ×4/3; 21k is ×7/6.
      expect(convertGoldPrice(12000000, 0.75, 1), closeTo(16000000, 1e-6));
      expect(convertGoldPrice(12000000, 0.75, 0.875), closeTo(14000000, 1e-6));
      // Value is invariant: grams × price in either karat.
      const g18 = 7.5, p18 = 14350000.0;
      final g24 = convertGoldGrams(g18, 0.75, 1), p24 = convertGoldPrice(p18, 0.75, 1);
      expect(g24 * p24, closeTo(g18 * p18, 1e-3));
      expect(convertGoldGrams(0, 0.75, 1), 0);
      expect(convertGoldGrams(5, 0, 1), 0);
      expect(convertGoldPrice(-1, 0.75, 1), 0);
    });

    test('rounding to Toman and milligram', () {
      expect(roundToman(1234.5), 1235);
      expect(roundToman(-1234.4), -1234);
      expect(roundToman(double.nan), 0);
      expect(roundToman(double.infinity), 0);
      expect(roundGrams(1.23456), 1.235);
      expect(roundGrams(double.nan), 0);
      expect(floorGrams(1.2349), 1.234);
      expect(floorGrams(0.1 + 0.2), 0.3); // float noise does not lose a mg
      expect(ceilGrams(1.2341), 1.235);
      expect(ceilGrams(1.234), 1.234);
      expect(ceilGrams(0.7 * 3), 2.1);
    });

    test('invoice multiplier', () {
      expect(buyMultiplier(GoldProduct.online, GoldFees.onlineDefault), closeTo(1.005, 1e-12));
      // (1.15)(1.07) + 0.10 × (0.15 + 1.15 × 0.07)
      expect(buyMultiplier(GoldProduct.jewelry, GoldFees.jewelryDefault), closeTo(1.25355, 1e-12));
      expect(buyMultiplier(GoldProduct.online, const GoldFees()), 1);
      expect(buyMultiplier(GoldProduct.online, const GoldFees(feePct: -3)), 1); // negative = 0
    });

    test('fees json round trip and bad values fall back', () {
      const f = GoldFees(feePct: 0.4, makingPct: 18, profitPct: 5, vatPct: 9);
      final back = GoldFees.fromJson(f.toJson(), GoldFees.jewelryDefault);
      expect(back.toJson(), f.toJson());
      final bad = GoldFees.fromJson({'fee': 'x', 'making': -1, 'profit': 150, 'vat': 10}, GoldFees.jewelryDefault);
      expect(bad.feePct, 0.5);
      expect(bad.makingPct, 15);
      expect(bad.profitPct, 7);
      expect(bad.vatPct, 10);
      expect(GoldFees.fromJson(null, GoldFees.onlineDefault).feePct, 0.5);
      expect(GoldProductX.parse('jewelry'), GoldProduct.jewelry);
      expect(GoldProductX.parse('?'), GoldProduct.online);
      expect(GoldLotOrderX.parse('highestCost'), GoldLotOrder.highestCost);
      expect(GoldLotOrderX.parse(null), GoldLotOrder.fifo);
    });
  });

  group('buy', () {
    test('online by amount never spends more than the amount', () {
      final q = GoldCalc.buy(
        product: GoldProduct.online,
        mode: GoldInputMode.amount,
        input: 100000000,
        pricePerGram: 14350000,
        fees: GoldFees.onlineDefault,
        midPerGram: 14280000,
        exitPerGram: 14210000,
        cashBefore: 185400000,
        holdingBefore: 42.5,
        costBefore: 42.5 * 11900000,
      );
      expect(q.grams, 6.933); // floor(100e6 / 14,421,750) to the mg
      expect(q.goldValue, 99488550);
      expect(q.commission, 497443);
      expect(q.total, 99985993);
      expect(q.total, lessThanOrEqualTo(100000000));
      expect(q.leftover, 14007);
      expect(q.recordFee, 497443);
      expect(q.effectivePerGram, closeTo(99985993 / 6.933, 1e-6));
      expect(q.premiumPct, closeTo((99985993 / 6.933 / 14280000 - 1) * 100, 1e-9));
      expect(q.cashAfter, 185400000 - 99985993);
      expect(q.shortfall, 0);
      expect(q.holdingAfter, closeTo(49.433, 1e-9));
      expect(q.avgBefore, closeTo(11900000, 1e-6));
      expect(q.avgAfter, closeTo((42.5 * 11900000 + 99985993) / 49.433, 1e-6));
      // Break-even sell price covers the 0.5% sell fee too.
      expect(q.breakEvenSellPrice, closeTo(99985993 / (6.933 * 0.995), 1e-6));
      expect(q.breakEvenOverExitPct, greaterThan(0));
      expect(q.exitValue, roundToman(6.933 * 14210000 * 0.995));
      expect(q.exitResult, lessThan(0));
    });

    test('by amount: whole-Toman rounding never pushes over budget', () {
      for (final amount in <double>[1000000, 3333333, 9999999, 123456789, 777777777]) {
        for (final price in <double>[9876543, 14350000, 15012345]) {
          final q = GoldCalc.buy(
            product: GoldProduct.jewelry,
            mode: GoldInputMode.amount,
            input: amount,
            pricePerGram: price,
            fees: GoldFees.jewelryDefault,
          );
          expect(q.total, lessThanOrEqualTo(amount), reason: '$amount @ $price');
          expect(q.leftover, amount.roundToDouble() - q.total);
          // One more milligram would not fit.
          final more = GoldCalc.buy(
            product: GoldProduct.jewelry,
            mode: GoldInputMode.weight,
            input: q.grams + 0.001,
            pricePerGram: price,
            fees: GoldFees.jewelryDefault,
          );
          expect(more.total, greaterThan(amount), reason: '$amount @ $price');
        }
      }
    });

    test('jewelry by weight: invoice parts and hidden cost', () {
      final q = GoldCalc.buy(
        product: GoldProduct.jewelry,
        mode: GoldInputMode.weight,
        input: 12,
        pricePerGram: 14350000,
        fees: GoldFees.jewelryDefault,
        midPerGram: 14280000,
        exitPerGram: 14210000,
        exitFeePct: 0.5,
        cashBefore: 185400000,
      );
      expect(q.goldValue, 172200000);
      expect(q.making, 25830000);
      expect(q.profit, 13862100);
      expect(q.vat, 3969210);
      expect(q.commission, 0);
      expect(q.total, 215861310);
      expect(q.fees, 43661310);
      expect(q.nonRecoverable, 43661310);
      expect(q.nonRecoverablePct, closeTo(43661310 / 172200000 * 100, 1e-9));
      expect(q.effectivePerGram, closeTo(215861310 / 12, 1e-6));
      expect(q.shortfall, 30461310);
      expect(q.cashAfter, -30461310);
      expect(q.exitResult, roundToman(12 * 14210000 * 0.995) - 215861310);
      expect(q.breakEvenSellPrice, closeTo(215861310 / (12 * 0.995), 1e-6));
      expect(q.leftover, 0);
    });

    test('zero, empty and nonsense input', () {
      for (final input in <double>[0, -5, double.nan, double.infinity]) {
        final q = GoldCalc.buy(
          product: GoldProduct.online,
          mode: GoldInputMode.amount,
          input: input,
          pricePerGram: 14000000,
          fees: GoldFees.onlineDefault,
          cashBefore: 1000,
        );
        expect(q.isEmpty, isTrue);
        expect(q.grams, 0);
        expect(q.total, 0);
        expect(q.shortfall, 0);
        expect(q.premiumPct, isNull);
        expect(q.breakEvenSellPrice, 0);
        expect(q.exitValue, isNull);
      }
      final noPrice = GoldCalc.buy(
        product: GoldProduct.online,
        mode: GoldInputMode.weight,
        input: 5,
        pricePerGram: 0,
        fees: GoldFees.onlineDefault,
      );
      expect(noPrice.isEmpty, isTrue);
      expect(noPrice.pricePerGram, 0);
      // Too little money for a milligram.
      final tiny = GoldCalc.buy(
        product: GoldProduct.online,
        mode: GoldInputMode.amount,
        input: 5000,
        pricePerGram: 14000000,
        fees: GoldFees.onlineDefault,
      );
      expect(tiny.grams, 0);
      expect(tiny.isEmpty, isTrue);
      expect(tiny.leftover, 5000);
      expect(tiny.avgAfter, 0);
    });

    test('very large amounts stay exact to the Toman', () {
      final q = GoldCalc.buy(
        product: GoldProduct.online,
        mode: GoldInputMode.amount,
        input: 1e15, // a thousand trillion Toman
        pricePerGram: 14350000,
        fees: GoldFees.onlineDefault,
      );
      expect(q.total, lessThanOrEqualTo(1e15));
      expect(q.total, q.goldValue + q.commission);
      expect(q.grams, greaterThan(69000000));
      expect(q.total % 1, 0);
      final w = GoldCalc.buy(
        product: GoldProduct.jewelry,
        mode: GoldInputMode.weight,
        input: 1e6,
        pricePerGram: 14350000,
        fees: GoldFees.jewelryDefault,
      );
      expect(w.total, w.goldValue + w.making + w.profit + w.vat);
      expect(w.total / w.goldValue, closeTo(1.25355, 1e-6));
    });

    test('weight is rounded to the milligram', () {
      final q = GoldCalc.buy(
        product: GoldProduct.online,
        mode: GoldInputMode.weight,
        input: 1.23456,
        pricePerGram: 10000000,
        fees: const GoldFees(),
      );
      expect(q.grams, 1.235);
      expect(q.total, 12350000);
      expect(q.leftover, 0);
    });

    test('unknown cash means no shortfall', () {
      final q = GoldCalc.buy(
        product: GoldProduct.online,
        mode: GoldInputMode.weight,
        input: 10,
        pricePerGram: 10000000,
        fees: const GoldFees(),
      );
      expect(q.cashAfter, isNull);
      expect(q.shortfall, 0);
    });
  });

  group('sell', () {
    test('FIFO by weight closes the oldest lot then part of the next', () {
      final q = GoldCalc.sell(
        mode: GoldInputMode.weight,
        input: 10,
        pricePerGram: 14210000,
        feePct: 0.5,
        lots: _lots,
        cashBefore: 185400000,
      );
      expect(q.grams, 10);
      expect(q.gross, 142100000);
      expect(q.fee, 710500);
      expect(q.net, 141389500);
      expect(q.takes.map((t) => t.lot.id), [1, 2]);
      expect(q.takes.map((t) => t.grams), [8, 2]);
      expect(q.takes[0].closesWholeLot, isTrue);
      expect(q.takes[1].closesWholeLot, isFalse);
      // Fee split by weight; pieces add up exactly.
      expect(q.takes[0].sellFeePart, 568400);
      expect(q.takes[1].sellFeePart, 142100);
      expect(q.takes.fold<double>(0, (s, t) => s + t.sellFeePart), q.fee);
      // Partial lot carries its share of the buy fee (2/12.5 of 500,000).
      expect(q.takes[1].buyFeePart, closeTo(80000, 1e-6));
      expect(q.takes[0].realized, closeTo(8 * (14210000 - 9850000) - 568400, 1e-6));
      expect(q.takes[1].realized, closeTo(2 * (14210000 - 12400000) - 80000 - 142100, 1e-6));
      expect(q.realized, closeTo(q.takes[0].realized + q.takes[1].realized, 1e-6));
      expect(q.cashAfter, 185400000 + 141389500);
      expect(q.holdingBefore, 42.5);
      expect(q.holdingAfter, 32.5);
      final costBefore = _lots.fold<double>(0, (s, l) => s + l.cost);
      expect(q.costBefore, costBefore);
      expect(q.avgAfter, closeTo((costBefore - q.costOut) / 32.5, 1e-6));
      expect(q.canRecord, isTrue);
      expect(q.exceedsHolding, isFalse);
    });

    test('highest cost first', () {
      final q = GoldCalc.sell(
        mode: GoldInputMode.weight,
        input: 13,
        pricePerGram: 14000000,
        feePct: 0,
        lots: _lots,
        order: GoldLotOrder.highestCost,
      );
      // Unit costs: lot2 12,440,000 > lot3 12,361,400 > lot1 9,850,000.
      expect(q.takes.map((t) => t.lot.id), [2, 3]);
      expect(q.takes.map((t) => t.grams), [12.5, 0.5]);
      expect(GoldCalc.sortLots(_lots, GoldLotOrder.highestCost).map((l) => l.id), [2, 3, 1]);
    });

    test('FIFO order: by date, undated last, ties by id', () {
      const lots = [
        GoldLot(id: 9, grams: 1, buyPrice: 1, buyFee: 0, buyDate: ''),
        GoldLot(id: 5, grams: 1, buyPrice: 1, buyFee: 0, buyDate: '2026-01-02'),
        GoldLot(id: 4, grams: 1, buyPrice: 1, buyFee: 0, buyDate: '2026-01-02'),
        GoldLot(id: 7, grams: 1, buyPrice: 1, buyFee: 0, buyDate: '2025-12-31'),
      ];
      expect(GoldCalc.sortLots(lots, GoldLotOrder.fifo).map((l) => l.id), [7, 4, 5, 9]);
    });

    test('manual picks set the weight and are capped by the lot', () {
      final q = GoldCalc.sell(
        mode: GoldInputMode.weight,
        input: 999, // ignored in manual mode
        pricePerGram: 14000000,
        feePct: 0.5,
        lots: _lots,
        order: GoldLotOrder.manual,
        manualGrams: {3: 5, 1: 100, 2: 0, 77: 3},
      );
      expect(q.grams, 13); // 5 from lot 3 + all 8 of lot 1
      expect(q.takes.map((t) => t.lot.id).toSet(), {1, 3});
      expect(q.takes.firstWhere((t) => t.lot.id == 1).grams, 8);
      expect(q.picksMismatch, isFalse);
      expect(q.canRecord, isTrue);
      final none = GoldCalc.sell(
        mode: GoldInputMode.weight,
        input: 5,
        pricePerGram: 14000000,
        feePct: 0.5,
        lots: _lots,
        order: GoldLotOrder.manual,
      );
      expect(none.isEmpty, isTrue);
      expect(none.canRecord, isFalse);
    });

    test('by amount asks for enough grams to net the amount', () {
      final q = GoldCalc.sell(
        mode: GoldInputMode.amount,
        input: 50000000,
        pricePerGram: 14210000,
        feePct: 0.5,
        lots: _lots,
      );
      expect(q.net, greaterThanOrEqualTo(50000000 - 1));
      // One milligram less would not be enough.
      final less = (q.grams - 0.001) * 14210000 * 0.995;
      expect(less, lessThan(50000000));
      expect(q.grams, ceilGrams(50000000 / (14210000 * 0.995)));
    });

    test('more than the holding is flagged and not recordable', () {
      final q = GoldCalc.sell(
        mode: GoldInputMode.weight,
        input: 50,
        pricePerGram: 14000000,
        feePct: 0.5,
        lots: _lots,
      );
      expect(q.exceedsHolding, isTrue);
      expect(q.available, 42.5);
      expect(q.coveredGrams, 42.5);
      expect(q.canRecord, isFalse);
      expect(q.holdingAfter, 0);
      expect(q.avgAfter, 0);
    });

    test('selling everything closes every lot whole', () {
      final q = GoldCalc.sell(
        mode: GoldInputMode.weight,
        input: 42.5,
        pricePerGram: 14000000,
        feePct: 1,
        lots: _lots,
      );
      expect(q.takes.length, 3);
      expect(q.takes.every((t) => t.closesWholeLot), isTrue);
      expect(q.holdingAfter, 0);
      expect(q.takes.fold<double>(0, (s, t) => s + t.sellFeePart), q.fee);
      expect(q.takes.fold<double>(0, (s, t) => s + t.buyFeePart), 500000);
    });

    test('zero input, zero price, no lots, 100% fee', () {
      for (final input in <double>[0, -1, double.nan]) {
        final q =
            GoldCalc.sell(mode: GoldInputMode.weight, input: input, pricePerGram: 14000000, feePct: 0.5, lots: _lots);
        expect(q.isEmpty, isTrue);
        expect(q.takes, isEmpty);
        expect(q.canRecord, isFalse);
      }
      final noPrice = GoldCalc.sell(mode: GoldInputMode.weight, input: 5, pricePerGram: 0, feePct: 0.5, lots: _lots);
      expect(noPrice.isEmpty, isTrue);
      final noLots =
          GoldCalc.sell(mode: GoldInputMode.weight, input: 5, pricePerGram: 14000000, feePct: 0.5, lots: const []);
      expect(noLots.exceedsHolding, isTrue);
      expect(noLots.canRecord, isFalse);
      final allFee =
          GoldCalc.sell(mode: GoldInputMode.amount, input: 5000000, pricePerGram: 14000000, feePct: 100, lots: _lots);
      expect(allFee.isEmpty, isTrue);
      final emptyLot = GoldCalc.sell(
        mode: GoldInputMode.weight,
        input: 1,
        pricePerGram: 14000000,
        feePct: 0,
        lots: const [GoldLot(id: 1, grams: 0, buyPrice: 1, buyFee: 0, buyDate: '')],
      );
      expect(emptyLot.available, 0);
      expect(emptyLot.canRecord, isFalse);
    });

    test('fee split over many tiny lots still adds up', () {
      final lots = [
        for (var i = 0; i < 7; i++)
          GoldLot(id: i + 1, grams: 0.333, buyPrice: 13000000, buyFee: 1000, buyDate: '2026-01-0${i + 1}'),
      ];
      final q = GoldCalc.sell(mode: GoldInputMode.weight, input: 2.2, pricePerGram: 14123457, feePct: 0.7, lots: lots);
      expect(q.takes.length, 7);
      expect(q.takes.fold<double>(0, (s, t) => s + t.grams), closeTo(2.2, 1e-9));
      expect(q.takes.fold<double>(0, (s, t) => s + t.sellFeePart), q.fee);
      expect(q.takes.last.grams, closeTo(0.202, 1e-9));
    });

    test('very large holdings', () {
      const lots = [GoldLot(id: 1, grams: 1e6, buyPrice: 10000000, buyFee: 1e9, buyDate: '2020-01-01')];
      final q =
          GoldCalc.sell(mode: GoldInputMode.weight, input: 999999.999, pricePerGram: 14000000, feePct: 0.5, lots: lots);
      expect(q.gross, roundToman(999999.999 * 14000000));
      expect(q.net, q.gross - q.fee);
      expect(q.takes.single.closesWholeLot, isFalse);
      expect(q.realized.isFinite, isTrue);
    });
  });
}

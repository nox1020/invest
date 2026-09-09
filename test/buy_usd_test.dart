import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/utils/buy_usd.dart';

void main() {
  group('buy_usd note packing', () {
    test('encode and parse round-trip', () {
      final packed = encodeBuyNoteUsd(usd: 12.5, note: 'یادداشت');
      expect(packed, contains('[buy_usd:12.5]'));
      final parsed = parseBuyNoteUsd(packed);
      expect(parsed.usd, 12.5);
      expect(parsed.note, 'یادداشت');
    });

    test('readBuyPriceUsd prefers column over note', () {
      final usd = readBuyPriceUsd(
        columnValue: 9.1,
        buyNote: encodeBuyNoteUsd(usd: 1.0, note: 'x'),
      );
      expect(usd, 9.1);
    });

    test('Trade toMap/fromMap keeps buyPriceUsd', () {
      final t = Trade(
        assetId: 1,
        status: 'open',
        quantity: 2,
        buyPrice: 1000,
        buyPriceUsd: 0.02,
        buyNote: 'تست',
      );
      final again = Trade.fromMap(t.toMap());
      expect(again.buyPriceUsd, closeTo(0.02, 1e-12));
      expect(again.buyNoteDisplay, 'تست');
      expect(again.buyNote, contains('[buy_usd:'));
    });

    test('packs and parses buy_fx dollar Toman rate', () {
      final packed = encodeBuyNoteUsd(usd: 70000, fx: 100000, note: 'لات ۱');
      expect(packed, contains('[buy_usd:70000]'));
      expect(packed, contains('[buy_fx:100000]'));
      final parsed = parseBuyNoteUsd(packed);
      expect(parsed.usd, 70000);
      expect(parsed.fx, 100000);
      expect(parsed.note, 'لات ۱');
    });

    test('parses buy_fx before buy_usd', () {
      final parsed = parseBuyNoteUsd('[buy_fx:95000] [buy_usd:12.5] note');
      expect(parsed.fx, 95000);
      expect(parsed.usd, 12.5);
      expect(parsed.note, 'note');
    });

    test('impliedBuyUsdTmn is Toman per 1 USD', () {
      expect(
        impliedBuyUsdTmn(buyToman: 7e9, buyUsd: 70000),
        closeTo(100000, 1e-6),
      );
      expect(impliedBuyUsdTmn(buyToman: 1, buyUsd: null), isNull);
    });

    test('resolveBuyUsdTmn prefers stored rate', () {
      expect(
        resolveBuyUsdTmn(storedFx: 90000, buyToman: 7e9, buyUsd: 70000),
        90000,
      );
      expect(
        resolveBuyUsdTmn(storedFx: null, buyToman: 7e9, buyUsd: 70000),
        closeTo(100000, 1e-6),
      );
    });

    test('Trade toMap/fromMap keeps buyUsdTmn', () {
      final t = Trade(
        assetId: 1,
        status: 'open',
        quantity: 1,
        buyPrice: 7e9,
        buyPriceUsd: 70000,
        buyUsdTmn: 100000,
        buyNote: 'btc',
      );
      final again = Trade.fromMap(t.toMap());
      expect(again.buyUsdTmn, closeTo(100000, 1e-9));
      expect(again.resolvedBuyUsdTmn, closeTo(100000, 1e-9));
      expect(again.buyNoteDisplay, 'btc');
      expect(again.buyNote, contains('[buy_fx:100000]'));
    });

    test('resolvedBuyUsdTmn falls back to implied rate', () {
      final t = Trade(
        assetId: 1,
        status: 'open',
        quantity: 1,
        buyPrice: 8e9,
        buyPriceUsd: 80000,
      );
      expect(t.resolvedBuyUsdTmn, closeTo(100000, 1e-6));
    });
  });
}

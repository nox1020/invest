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
  });
}

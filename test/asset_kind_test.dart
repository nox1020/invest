import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/asset_kind.dart';

void main() {
  test('detects property and vehicle from Persian names', () {
    expect(
      detectAssetKind(name: 'آپارتمان ونک', symbol: ''),
      AssetKind.property,
    );
    expect(
      detectAssetKind(name: 'ملک تجاری', symbol: 'X'),
      AssetKind.property,
    );
    expect(
      detectAssetKind(name: 'پژو ۲۰۷', symbol: ''),
      AssetKind.vehicle,
    );
    expect(
      detectAssetKind(name: 'خودرو شخصی', symbol: 'CAR'),
      AssetKind.vehicle,
    );
  });

  test('detects gold cash crypto and kind marker', () {
    expect(detectAssetKind(name: 'طلا', symbol: 'GOLD'), AssetKind.gold);
    expect(detectAssetKind(name: 'تتر', symbol: 'USDT'), AssetKind.cash);
    expect(detectAssetKind(name: 'Bitcoin', symbol: 'BTC'), AssetKind.crypto);
    expect(
      detectAssetKind(name: 'آیتم خاص', symbol: '', notes: '[kind:property]'),
      AssetKind.property,
    );
  });

  test('notesWithKind round-trips', () {
    final tagged = notesWithKind('پلاک ۱۲', AssetKind.vehicle);
    expect(tagged, contains('[kind:vehicle]'));
    expect(stripKindMarker(tagged), 'پلاک ۱۲');
    expect(
      detectAssetKind(name: 'x', notes: tagged),
      AssetKind.vehicle,
    );
  });

  test('unit assets default to quantity 1', () {
    expect(AssetKind.property.defaultQuantity, 1);
    expect(AssetKind.vehicle.defaultQuantity, 1);
    expect(AssetKind.property.isUnitAsset, isTrue);
    expect(AssetKind.crypto.isUnitAsset, isFalse);
  });
}

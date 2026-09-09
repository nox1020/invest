import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/asset_meta.dart';

void main() {
  test('encode/parse round-trips property meta', () {
    const meta = AssetMeta(
      address: 'ونک',
      areaM2: 120,
      usage: 'residential',
      deedNotes: 'سند ۱۲۳',
      purchaseDate: '1402/05/01',
    );
    final notes = encodeAssetNotes(
      kind: AssetKind.property,
      meta: meta,
      freeNotes: 'یادداشت آزاد',
    );
    expect(notes, contains('[kind:property]'));
    expect(notes, contains('[meta:'));

    final parts = parseAssetNotes(notes);
    expect(parts.kind, AssetKind.property);
    expect(parts.freeNotes, 'یادداشت آزاد');
    expect(parts.meta.address, 'ونک');
    expect(parts.meta.areaM2, 120);
    expect(parts.meta.usage, 'residential');
    expect(parts.meta.deedNotes, 'سند ۱۲۳');
    expect(parts.meta.purchaseDate, '1402/05/01');
  });

  test('encode/parse round-trips vehicle meta', () {
    const meta = AssetMeta(
      brandModel: 'پژو ۲۰۷',
      year: 1399,
      plate: '۱۲ب۳۴۵',
      mileageKm: 45000,
      color: 'سفید',
      purchaseDate: '1401/01/01',
    );
    final notes = encodeAssetNotes(kind: AssetKind.vehicle, meta: meta);
    final parts = parseAssetNotes(notes);
    expect(parts.kind, AssetKind.vehicle);
    expect(parts.meta.brandModel, 'پژو ۲۰۷');
    expect(parts.meta.year, 1399);
    expect(parts.meta.plate, '۱۲ب۳۴۵');
    expect(parts.meta.mileageKm, 45000);
    expect(parts.meta.color, 'سفید');
  });

  test('encode/parse gold purity', () {
    final notes = encodeAssetNotes(
      kind: AssetKind.gold,
      meta: const AssetMeta(purity: '18'),
    );
    final parts = parseAssetNotes(notes);
    expect(parts.kind, AssetKind.gold);
    expect(parts.meta.purity, '18');
  });

  test('legacy kind-only notes still parse', () {
    final parts = parseAssetNotes('[kind:cash] موجودی کیف');
    expect(parts.kind, AssetKind.cash);
    expect(parts.meta.isEmpty, isTrue);
    expect(parts.freeNotes, 'موجودی کیف');
  });

  test('stripKindMarker removes meta block', () {
    final notes = encodeAssetNotes(
      kind: AssetKind.property,
      meta: const AssetMeta(address: 'تهران', areaM2: 80),
      freeNotes: 'طبقه ۳',
    );
    expect(stripKindMarker(notes), 'طبقه ۳');
  });

  test('empty meta omits meta marker', () {
    final notes = encodeAssetNotes(
      kind: AssetKind.crypto,
      freeNotes: 'cold wallet',
    );
    expect(notes, '[kind:crypto] cold wallet');
    expect(notes.contains('[meta:'), isFalse);
  });

  test('stock kind round-trips in notes', () {
    final notes = encodeAssetNotes(
      kind: AssetKind.stock,
      meta: const AssetMeta(buyPriceUsd: 0.12),
      freeNotes: 'بورس تهران',
    );
    final parts = parseAssetNotes(notes);
    expect(parts.kind, AssetKind.stock);
    expect(parts.freeNotes, 'بورس تهران');
    expect(parts.meta.buyPriceUsd, closeTo(0.12, 1e-9));
  });

  test('crypto buyUsdTmn round-trips in notes', () {
    final notes = encodeAssetNotes(
      kind: AssetKind.crypto,
      meta: const AssetMeta(buyPriceUsd: 70000, buyUsdTmn: 100000),
    );
    final parts = parseAssetNotes(notes);
    expect(parts.kind, AssetKind.crypto);
    expect(parts.meta.buyPriceUsd, closeTo(70000, 1e-9));
    expect(parts.meta.buyUsdTmn, closeTo(100000, 1e-9));
  });

  test('card summary for property and vehicle', () {
    expect(
      assetMetaCardSummary(
        AssetKind.property,
        const AssetMeta(
          address: 'ونک',
          areaM2: 120,
          usage: 'residential',
        ),
      ),
      '120 م² · مسکونی · ونک',
    );
    expect(
      assetMetaCardSummary(
        AssetKind.vehicle,
        const AssetMeta(plate: '۱۲ب', year: 1400, mileageKm: 10),
      ),
      '۱۲ب · 1400 · 10 km',
    );
    expect(
      assetMetaCardSummary(
        AssetKind.gold,
        const AssetMeta(purity: '24'),
      ),
      'عیار 24',
    );
  });

  test('corrupt meta does not throw', () {
    final parts = parseAssetNotes('[kind:other] [meta:{broken] hello');
    expect(parts.kind, AssetKind.other);
    expect(parts.meta.isEmpty, isTrue);
  });
}

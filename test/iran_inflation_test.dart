import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/iran_inflation.dart';

void main() {
  test('IranInflationSnapshot round-trip json', () {
    final snap = IranInflationSnapshot(
      period: '1405-03',
      year: 1405,
      month: 3,
      cpiIndex: 656.3,
      pointToPointPct: 88.5,
      monthlyPct: 5.9,
      annualPct: 62.0,
      history: const [
        IranInflationPoint(
          period: '1405-02',
          year: 1405,
          month: 2,
          cpiIndex: 619.5,
          pointToPointPct: 83.8,
          monthlyPct: 8.8,
          annualPct: 57.7,
        ),
      ],
      sourceLabel: 'SCI',
      fetchedAt: DateTime.utc(2026, 9, 6),
    );

    final again = IranInflationSnapshot.fromJson(snap.toJson());
    expect(again.period, '1405-03');
    expect(again.periodLabel, 'خرداد 1405');
    expect(again.pointToPointPct, closeTo(88.5, 1e-9));
    expect(again.history, hasLength(1));
    expect(again.history.first.shortLabel, contains('ارد'));
  });
}

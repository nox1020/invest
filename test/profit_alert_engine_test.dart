import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/profit_alert.dart';
import 'package:invest/domain/services/price_alert_engine.dart';
import 'package:invest/domain/services/profit_alert_engine.dart';

void main() {
  test('fires once when unrealized profit crosses toman or percent', () {
    final alerts = [
      ProfitAlert(
        id: 'asset:1',
        name: 'بیت‌کوین',
        profitToman: 1000000,
        profitPct: 10,
      ),
    ];
    final latches = <String, PriceAlertLatch>{};
    final pos = {
      'asset:1': const ProfitPosition(
        id: 'asset:1',
        name: 'بیت‌کوین',
        pnl: 1500000,
        pnlPct: 12,
      ),
    };

    var hits = ProfitAlertEngine.evaluate(
      alerts: alerts,
      positions: pos,
      latches: latches,
    );
    expect(hits, hasLength(1));
    expect(hits.single.side, PriceAlertSide.above);

    hits = ProfitAlertEngine.evaluate(
      alerts: alerts,
      positions: pos,
      latches: latches,
    );
    expect(hits, isEmpty);

    hits = ProfitAlertEngine.evaluate(
      alerts: alerts,
      positions: {
        'asset:1': const ProfitPosition(
          id: 'asset:1',
          name: 'بیت‌کوین',
          pnl: 100,
          pnlPct: 1,
        ),
      },
      latches: latches,
    );
    expect(hits, isEmpty);

    hits = ProfitAlertEngine.evaluate(
      alerts: [
        ProfitAlert(id: 'asset:1', name: 'بیت‌کوین', lossToman: 500000),
      ],
      positions: {
        'asset:1': const ProfitPosition(
          id: 'asset:1',
          name: 'بیت‌کوین',
          pnl: -800000,
          pnlPct: -20,
        ),
      },
      latches: latches,
    );
    expect(hits, hasLength(1));
    expect(hits.single.side, PriceAlertSide.below);
  });

  test('profit alert json round-trip', () {
    final a = ProfitAlert(
      id: 'trade:9',
      name: 'طلا',
      profitPct: 5,
      lossPct: 3,
    );
    final again = ProfitAlert.fromJson(a.toJson());
    expect(again.id, 'trade:9');
    expect(again.profitPct, 5);
    expect(again.lossPct, 3);
    expect(again.isArmed, isTrue);
  });
}

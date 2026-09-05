import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/utils/dates.dart';

void main() {
  test('openHoldingDays counts calendar days and never goes negative', () {
    expect(openHoldingDays('2026-01-01', asOf: '2026-01-11'), 10);
    expect(openHoldingDays('2026-01-11', asOf: '2026-01-11'), 0);
    expect(openHoldingDays('2026-01-12', asOf: '2026-01-11'), 0);
    expect(openHoldingDays('', asOf: '2026-01-11'), 0);
  });

  test('open trade exposes unrealized pnl and current value', () {
    final trade = Trade(
      assetId: 1,
      status: AppConfig.tradeOpen,
      quantity: 2,
      buyPrice: 100,
      buyFee: 10,
      buyDate: '2026-01-01',
      currentPrice: 130,
    );
    expect(trade.buyCost, 210);
    expect(trade.currentValue, 260);
    expect(trade.unrealizedPnl, 50);
    expect(trade.unrealizedPnlPct, closeTo(50 / 210 * 100, 1e-9));
    expect(trade.openDays, openHoldingDays('2026-01-01'));
  });
}

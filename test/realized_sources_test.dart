import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/state/app_state.dart';

void main() {
  tearDown(() {
    BizStore.instance.debugReset();
    ProjectsStore.instance.debugReset();
  });

  AppState state() => AppState()
    ..settings = AppSettings(calendar: AppConfig.calendarJalali, annualWithdrawalPct: 100)
    ..closedTrades = [
      Trade(assetId: 1, status: AppConfig.tradeClosed, quantity: 1, buyPrice: 100, sellPrice: 300, realizedPnl: 200, buyDate: '2026-01-01', sellDate: '2026-02-01'),
    ];

  test('sold property deals and finished projects count as realized, once', () {
    BizStore.instance.debugSet(BizSnapshot({
      'trades': [
        {'id': 1, 'buy_date': '1404/01/01', 'sell_date': '1405/01/01', 'buy_amount': 1000, 'sell_amount': 1500, 'profit': 500},
        {'id': 2, 'buy_date': '1405/03/01', 'sell_date': null, 'buy_amount': 800, 'sell_amount': 0, 'profit': null},
        {'id': 3, 'buy_date': '1404/05/01', 'sell_date': '1405/02/01', 'buy_amount': 900, 'sell_amount': 850, 'profit': -50},
      ],
    }));
    ProjectsStore.instance.debugSet(ProjectsSnapshot({
      'items': [
        {'id': 1, 'title': 'a', 'status': 'finished', 'contract_amount': 80, 'cost': 30, 'profit': 50, 'archived': false},
        {'id': 2, 'title': 'b', 'status': 'active', 'contract_amount': 999, 'cost': 1, 'profit': 998, 'archived': false},
      ],
    }));
    final s = state();
    final b = s.realizedBreakdown;
    expect(b.trades, 200);
    expect(b.property, 450); // unsold deal excluded, loss included
    expect(b.projects, 50); // running project not counted
    expect(b.total, 700);
    expect(s.withdrawalAllowance.realizedPnl, 700);
    // Asking twice must not accumulate.
    expect(s.realizedBreakdown.total, 700);
  });

  test('stores not loaded: only closed lots', () {
    final s = state();
    expect(s.realizedBreakdown.hasOther, isFalse);
    expect(s.withdrawalAllowance.realizedPnl, 200);
  });
}

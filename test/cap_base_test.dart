import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/remote_invest_service.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/withdrawal_allowance.dart';

void main() {
  final open = [Trade(assetId: 1, status: 'open', quantity: 1, buyPrice: 400)];
  final closed = [Trade(assetId: 1, status: 'closed', quantity: 1, buyPrice: 600)];

  WithdrawalAllowance calc(String base, {double? nav}) => WithdrawalAllowance.compute(
        realizedPnl: 1e9,
        openTrades: open,
        closedTrades: closed,
        withdrawals: const [],
        annualPct: 10,
        calendar: AppConfig.calendarJalali,
        asOfIso: '2026-10-22',
        capBase: base,
        navValue: nav,
      );

  test('default base is unchanged inflows; others selectable', () {
    expect(AppSettings().withdrawalCapBase, AppConfig.capBaseInflows);
    final def = WithdrawalAllowance.compute(
        realizedPnl: 1e9, openTrades: open, closedTrades: closed,
        withdrawals: const [], annualPct: 10,
        calendar: AppConfig.calendarJalali, asOfIso: '2026-10-22');
    expect(def.annualCap, 100);
    expect(def.capBaseAmount, def.inflows);
    expect(calc('open_cost').annualCap, 40);
    expect(calc('nav', nav: 2000).annualCap, 200);
    final fb = calc('nav');
    expect(fb.capBaseFallback, isTrue);
    expect(fb.annualCap, 100);
    expect(calc('garbage').capBase, AppConfig.capBaseInflows);
  });

  test('setting round-trips through json, storage and the API bundle', () {
    final s = AppSettings(withdrawalCapBase: 'open_cost');
    expect(AppSettings.fromJson(s.toJson()).withdrawalCapBase, 'open_cost');
    expect(AppSettings.fromStorageMap(s.toStorageMap()).withdrawalCapBase, 'open_cost');
    expect(AppSettings.fromStorageMap(const {}).withdrawalCapBase, 'inflows');
    final echoed = RemoteSettingsBundle.fromApiMap({'withdrawal_cap_base': 'nav'});
    expect(echoed.settings.withdrawalCapBase, 'nav');
    expect(settingsMismatches(sent: s, echoed: echoed), ['مبنای سقف برداشت']);
    // older server that drops the key: no false mismatch, sent value kept
    final old = RemoteSettingsBundle.fromApiMap({'theme': 'dark'});
    expect(settingsMismatches(sent: s, echoed: old), isNot(contains('مبنای سقف برداشت')));
    expect(old.mergePreserving(sent: s).settings.withdrawalCapBase, 'open_cost');
  });
}

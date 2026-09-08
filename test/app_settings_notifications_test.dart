import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/price_alert.dart';
import 'package:invest/domain/models/profit_alert.dart';
import 'package:invest/config/app_config.dart';

void main() {
  test('notification prefs round-trip json and storage', () {
    final s = AppSettings(
      notificationsEnabled: false,
      notifyTrades: true,
      notifyWithdrawals: false,
      notifyPriceMoves: true,
      notifyBackground: false,
      priceAlerts: [
        PriceAlert(id: 'usdt', name: 'تتر', above: 120000, below: 90000),
      ],
    );
    final again = AppSettings.fromJson(s.toJson());
    expect(again.notificationsEnabled, isFalse);
    expect(again.notifyTrades, isTrue);
    expect(again.notifyWithdrawals, isFalse);
    expect(again.notifyPriceMoves, isTrue);
    expect(again.notifyBackground, isFalse);
    expect(again.tradesAlertsOn, isFalse);
    expect(again.priceAlertsOn, isFalse);
    expect(again.priceAlerts, hasLength(1));
    expect(again.priceAlerts.single.above, 120000);
    expect(again.priceAlerts.single.below, 90000);

    final withProfit = AppSettings(
      profitAlerts: [
        ProfitAlert(id: 'asset:1', name: 'BTC', profitPct: 8),
      ],
    );
    expect(
      AppSettings.fromJson(withProfit.toJson()).profitAlerts.single.profitPct,
      8,
    );
    expect(
      AppSettings.fromStorageMap(withProfit.toStorageMap())
          .profitAlerts
          .single
          .id,
      'asset:1',
    );

    final stored = AppSettings.fromStorageMap(s.toStorageMap());
    expect(stored.notificationsEnabled, isFalse);
    expect(stored.notifyWithdrawals, isFalse);
    expect(stored.notifyBackground, isFalse);
    expect(stored.priceAlerts.single.id, 'usdt');
    expect(stored.toStorageMap()[AppConfig.settingPriceAlerts], isNotEmpty);
  });

  test('defaults enable notification prefs', () {
    final s = AppSettings.fromJson(const {});
    expect(s.notificationsEnabled, isTrue);
    expect(s.notifyTrades, isTrue);
    expect(s.tradesAlertsOn, isTrue);
    expect(s.notifyBackground, isTrue);
    expect(s.priceAlerts, isEmpty);
  });

  test('copyWith keeps price alerts independently', () {
    final s = AppSettings(
      priceAlerts: [PriceAlert(id: 'gold', above: 1)],
    );
    final copy = s.copyWith();
    copy.priceAlerts.first.above = 9;
    expect(s.priceAlerts.first.above, 1);
    expect(copy.armedPriceAlertCount, 1);
  });
}

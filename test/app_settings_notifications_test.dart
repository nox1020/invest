import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/app_settings.dart';

void main() {
  test('notification prefs round-trip json and storage', () {
    final s = AppSettings(
      notificationsEnabled: false,
      notifyTrades: true,
      notifyWithdrawals: false,
      notifyPriceMoves: true,
    );
    final again = AppSettings.fromJson(s.toJson());
    expect(again.notificationsEnabled, isFalse);
    expect(again.notifyTrades, isTrue);
    expect(again.notifyWithdrawals, isFalse);
    expect(again.notifyPriceMoves, isTrue);
    expect(again.tradesAlertsOn, isFalse);
    expect(again.priceAlertsOn, isFalse);

    final stored = AppSettings.fromStorageMap(s.toStorageMap());
    expect(stored.notificationsEnabled, isFalse);
    expect(stored.notifyWithdrawals, isFalse);
  });

  test('defaults enable notification prefs', () {
    final s = AppSettings.fromJson(const {});
    expect(s.notificationsEnabled, isTrue);
    expect(s.notifyTrades, isTrue);
    expect(s.tradesAlertsOn, isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/remote_invest_service.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/price_alert.dart';
import 'package:invest/domain/models/profit_alert.dart';
import 'package:invest/domain/models/withdrawal.dart';

void main() {
  test('parses alerts, lock, and client withdrawals from raw', () {
    final bundle = RemoteSettingsBundle.fromApiMap({
      'calendar': 'jalali',
      'theme': 'dark',
      'raw': {
        'notify_background': false,
        'price_alerts': [
          {'id': 'usdt', 'name': 'تتر', 'above': 120000},
        ],
        'profit_alerts': [
          {'id': 'asset:1', 'name': 'BTC', 'profit_pct': 8},
        ],
        'app_lock_hash': 'abc123',
        'app_lock_biometric': true,
        'client_withdrawals': [
          {
            'id': 7,
            'amount': 1500000,
            'note': 'test',
            'status': 'completed',
            'created_at': '2026-01-01T00:00:00',
          },
        ],
      },
    });

    expect(bundle.settings.notifyBackground, isFalse);
    expect(bundle.settings.priceAlerts, hasLength(1));
    expect(bundle.settings.priceAlerts.single.id, 'usdt');
    expect(bundle.settings.profitAlerts.single.profitPct, 8);
    expect(bundle.appLockHash, 'abc123');
    expect(bundle.appLockBiometric, isTrue);
    expect(bundle.hasClientWithdrawals, isTrue);
    expect(bundle.clientWithdrawals, hasLength(1));
    expect(bundle.clientWithdrawals.single.amount, 1500000);
    expect(
      bundle.presentKeys.contains(AppConfig.settingClientWithdrawals),
      isTrue,
    );
  });

  test('mergePreserving keeps sent extras when response omits them', () {
    final sent = AppSettings(
      notifyBackground: false,
      autoRefreshSeconds: 30,
      annualWithdrawalPct: 15,
      priceAlerts: [PriceAlert(id: 'gold', above: 1)],
      profitAlerts: [ProfitAlert(id: 'asset:2', profitPct: 5)],
      usdtTmnRate: 90000,
      goldTmnPerGram: 7000000,
    );
    final response = RemoteSettingsBundle.fromApiMap({
      'calendar': 'jalali',
      'theme': 'light',
      'live_prices_enabled': true,
    });

    final merged = response.mergePreserving(
      sent: sent,
      clientWithdrawals: [
        Withdrawal(id: 1, amount: 10, note: 'n', createdAt: 't'),
      ],
      appLockHash: 'hash',
      appLockBiometric: false,
    );

    expect(merged.settings.theme, 'light');
    expect(merged.settings.notifyBackground, isFalse);
    expect(merged.settings.autoRefreshSeconds, 30);
    expect(merged.settings.annualWithdrawalPct, 15);
    expect(merged.settings.priceAlerts.single.id, 'gold');
    expect(merged.settings.profitAlerts.single.id, 'asset:2');
    expect(merged.settings.usdtTmnRate, 90000);
    expect(merged.appLockHash, 'hash');
    expect(merged.appLockBiometric, isFalse);
    expect(merged.hasClientWithdrawals, isTrue);
    expect(merged.clientWithdrawals.single.id, 1);
  });

  test('empty app_lock_hash clears lock', () {
    final bundle = RemoteSettingsBundle.fromApiMap({
      'app_lock_hash': '',
      'raw': {'app_lock_biometric': '0'},
    });
    expect(bundle.appLockHash, '');
    expect(bundle.appLockBiometric, isFalse);
  });
}

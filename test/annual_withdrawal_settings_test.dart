import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';

void main() {
  test('annual withdrawal defaults to ten percent of inflows', () {
    expect(AppSettings().annualWithdrawalPct, 10);
    expect(AppSettings.fromJson(const {}).annualWithdrawalPct, 10);
    expect(AppSettings.fromStorageMap(const {}).annualWithdrawalPct, 10);
    expect(
      AppConfig.defaultSettings[AppConfig.settingAnnualWithdrawalPct],
      '10',
    );
  });

  test('annual withdrawal clamps and snaps to allowed options', () {
    expect(AppSettings.clampAnnualWithdrawalPct(1), 5);
    expect(AppSettings.clampAnnualWithdrawalPct(6), 5);
    expect(AppSettings.clampAnnualWithdrawalPct(7), 8);
    expect(AppSettings.clampAnnualWithdrawalPct(10), 10);
    expect(AppSettings.clampAnnualWithdrawalPct(11), 10);
    expect(AppSettings.clampAnnualWithdrawalPct(18), 20);
    expect(AppSettings.clampAnnualWithdrawalPct(99), 30);
    expect(AppSettings.parseAnnualWithdrawalPct('15'), 15);
    expect(AppSettings.parseAnnualWithdrawalPct(null), 10);
    expect(AppSettings.parseAnnualWithdrawalPct('nope'), 10);
  });

  test('annual withdrawal round-trips json and storage', () {
    final s = AppSettings(annualWithdrawalPct: 20);
    expect(AppSettings.fromJson(s.toJson()).annualWithdrawalPct, 20);
    expect(
      AppSettings.fromStorageMap(s.toStorageMap()).annualWithdrawalPct,
      20,
    );
    expect(
      s.toStorageMap()[AppConfig.settingAnnualWithdrawalPct],
      '20',
    );
    expect(s.toJson()['annual_withdrawal_pct'], 20);
  });

  test('annual withdrawal labels use persian copy', () {
    expect(AppSettings.annualWithdrawalShortLabel(10), '۱۰٪');
    expect(AppSettings.annualWithdrawalLabel(10), '۱۰٪ از ورودی');
    expect(AppSettings.annualWithdrawalLabel(15), '۱۵٪ از ورودی');
  });
}

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

  test('annual withdrawal clamps to one through one hundred', () {
    expect(AppSettings.clampAnnualWithdrawalPct(0), 1);
    expect(AppSettings.clampAnnualWithdrawalPct(1), 1);
    expect(AppSettings.clampAnnualWithdrawalPct(6), 6);
    expect(AppSettings.clampAnnualWithdrawalPct(10), 10);
    expect(AppSettings.clampAnnualWithdrawalPct(37), 37);
    expect(AppSettings.clampAnnualWithdrawalPct(99), 99);
    expect(AppSettings.clampAnnualWithdrawalPct(100), 100);
    expect(AppSettings.clampAnnualWithdrawalPct(150), 100);
    expect(AppSettings.parseAnnualWithdrawalPct('15'), 15);
    expect(AppSettings.parseAnnualWithdrawalPct('100'), 100);
    expect(AppSettings.parseAnnualWithdrawalPct(null), 10);
    expect(AppSettings.parseAnnualWithdrawalPct('nope'), 10);
    expect(AppConfig.maxAnnualWithdrawalPct, 100);
  });

  test('annual withdrawal round-trips json and storage', () {
    final s = AppSettings(annualWithdrawalPct: 73);
    expect(AppSettings.fromJson(s.toJson()).annualWithdrawalPct, 73);
    expect(
      AppSettings.fromStorageMap(s.toStorageMap()).annualWithdrawalPct,
      73,
    );
    expect(
      s.toStorageMap()[AppConfig.settingAnnualWithdrawalPct],
      '73',
    );
    expect(s.toJson()['annual_withdrawal_pct'], 73);
  });

  test('annual withdrawal labels use persian digits for any percent', () {
    expect(AppSettings.annualWithdrawalShortLabel(10), '۱۰٪');
    expect(AppSettings.annualWithdrawalLabel(10), '۱۰٪ از ورودی');
    expect(AppSettings.annualWithdrawalLabel(15), '۱۵٪ از ورودی');
    expect(AppSettings.annualWithdrawalShortLabel(100), '۱۰۰٪');
    expect(AppSettings.annualWithdrawalLabel(37), '۳۷٪ از ورودی');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';

void main() {
  test('auto refresh defaults to five seconds', () {
    expect(AppSettings().autoRefreshSeconds, 5);
    expect(AppSettings().autoRefreshInterval, const Duration(seconds: 5));
    expect(AppSettings.fromJson(const {}).autoRefreshSeconds, 5);
    expect(AppSettings.fromStorageMap(const {}).autoRefreshSeconds, 5);
    expect(
      AppConfig.defaultSettings[AppConfig.settingAutoRefreshSeconds],
      '5',
    );
  });

  test('auto refresh clamps and snaps to allowed options', () {
    expect(AppSettings.clampAutoRefreshSeconds(1), 5);
    expect(AppSettings.clampAutoRefreshSeconds(7), 5);
    expect(AppSettings.clampAutoRefreshSeconds(8), 10);
    expect(AppSettings.clampAutoRefreshSeconds(15), 15);
    expect(AppSettings.clampAutoRefreshSeconds(45), 30);
    expect(AppSettings.clampAutoRefreshSeconds(90), 60);
    expect(AppSettings.clampAutoRefreshSeconds(99999), 300);
    expect(AppSettings.parseAutoRefreshSeconds('10'), 10);
    expect(AppSettings.parseAutoRefreshSeconds(null), 5);
    expect(AppSettings.parseAutoRefreshSeconds('nope'), 5);
  });

  test('auto refresh round-trips json and storage', () {
    final s = AppSettings(autoRefreshSeconds: 15);
    expect(AppSettings.fromJson(s.toJson()).autoRefreshSeconds, 15);
    expect(
      AppSettings.fromStorageMap(s.toStorageMap()).autoRefreshSeconds,
      15,
    );
    expect(
      s.toStorageMap()[AppConfig.settingAutoRefreshSeconds],
      '15',
    );
    expect(s.toJson()['price_refresh_seconds'], 15);
  });

  test('auto refresh labels use persian copy', () {
    expect(AppSettings.autoRefreshLabel(5), '۵ ثانیه');
    expect(AppSettings.autoRefreshLabel(10), '۱۰ ثانیه');
    expect(AppSettings.autoRefreshLabel(60), '۱ دقیقه');
    expect(AppSettings.autoRefreshLabel(300), '۵ دقیقه');
  });
}

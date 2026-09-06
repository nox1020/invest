import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/utils/dates.dart';

void main() {
  test('formatDisplayDate uses settings calendar', () {
    // 2024-03-20 ≈ 1403/01/01 Jalali
    expect(
      formatDisplayDate('2024-03-20', AppConfig.calendarJalali),
      '01 فروردین 1403',
    );
    expect(
      formatDisplayDate('2024-03-20', AppConfig.calendarGregorian),
      '2024-03-20',
    );
  });

  test('tryNormalizeToIso accepts jalali slash dates', () {
    expect(tryNormalizeToIso('1403/01/01'), '2024-03-20');
    expect(tryNormalizeToIso('2024-03-20'), '2024-03-20');
  });

  test('yearPeriodKey follows calendar', () {
    expect(yearPeriodKey('2024-03-20', AppConfig.calendarJalali), '1403');
    expect(yearPeriodKey('2024-03-20', AppConfig.calendarGregorian), '2024');
  });
}

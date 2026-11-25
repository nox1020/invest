import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/ui/gold/gold_format.dart';

void main() {
  // 2026-11-25 12:00 in Tehran (UTC+3:30).
  final noon = DateTime.utc(2026, 11, 25, 8, 30);

  test('Tehran today ignores the device zone', () {
    expect(tehranTodayIso(now: noon), '2026-11-25');
    // 23:59 Tehran is still the 25th; 00:00 Tehran is the 26th.
    expect(tehranTodayIso(now: DateTime.utc(2026, 11, 25, 20, 29)), '2026-11-25');
    expect(tehranTodayIso(now: DateTime.utc(2026, 11, 25, 20, 30)), '2026-11-26');
    // A device clock in another zone reports the same instant.
    expect(tehranTodayIso(now: DateTime.utc(2026, 11, 25, 20, 30).toLocal()), '2026-11-26');
  });

  test('whole Tehran days, 0 on the buy day', () {
    expect(lotOpenDays('2026-11-25', now: noon), 0);
    expect(lotOpenDays('2026-11-24', now: noon), 1);
    expect(lotOpenDays('2026-10-14', now: noon), 42);
    expect(lotOpenDays('2025-11-25', now: noon), 365);
    expect(lotOpenDays('2024-02-29', now: DateTime.utc(2024, 3, 1, 8)), 1); // leap day
  });

  test('midnight in Tehran turns the count, UTC midnight does not', () {
    // Bought on the 24th. 23:59 Tehran on the 24th is 20:29 UTC: still 0.
    expect(lotOpenDays('2026-11-24', now: DateTime.utc(2026, 11, 24, 20, 29)), 0);
    // 00:00 Tehran on the 25th is 20:30 UTC on the 24th: already 1 day.
    expect(lotOpenDays('2026-11-24', now: DateTime.utc(2026, 11, 24, 20, 30)), 1);
    // 02:00 Tehran on the 25th (22:30 UTC on the 24th) is 1, not 0.
    expect(lotOpenDays('2026-11-24', now: DateTime.utc(2026, 11, 24, 22, 30)), 1);
  });

  test('old dates across Iran\'s former daylight saving do not lose a day', () {
    // Summer 2021 had DST (+4:30); counted on calendar dates, not hours.
    expect(lotOpenDays('2021-06-01', now: DateTime.utc(2021, 12, 1, 8)), 183);
    expect(lotOpenDays('2021-01-01', now: DateTime.utc(2021, 7, 1, 8)), 181);
  });

  test('Jalali and Persian-digit buy dates', () {
    // 1405/09/04 = 2026-11-25.
    expect(lotOpenDays('1405/09/04', now: noon), 0);
    expect(lotOpenDays('۱۴۰۵/۰۸/۱۴', now: noon), 20); // 2026-11-05
    expect(lotOpenDays('1404-09-04', now: noon), 365);
    expect(lotOpenDays('1404/12/29', now: DateTime.utc(2026, 3, 21, 8)), 1); // Esfand 29 → Nowruz
  });

  test('timestamps, future and unreadable dates', () {
    expect(lotOpenDays('2026-11-20T23:10:00', now: noon), 5);
    expect(lotOpenDays('2026-12-01', now: noon), 0);
    expect(lotOpenDays('', now: noon), isNull);
    expect(lotOpenDays(null, now: noon), isNull);
    expect(lotOpenDays('نامعلوم', now: noon), isNull);
  });

  test('labels', () {
    expect(gDays(0), 'امروز');
    expect(gDays(1), '۱ روز');
    expect(gDays(42), '۴۲ روز');
    expect(gDays(1200), '۱٬۲۰۰ روز');
  });
}

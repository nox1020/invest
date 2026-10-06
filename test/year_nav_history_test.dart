import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/year_nav_entry.dart';
import 'package:invest/domain/services/year_nav_compare.dart';
import 'package:invest/data/remote_invest_service.dart';

void main() {
  group('YearNavList', () {
    test('parses manual USD and derives rate', () {
      final rows = YearNavList.parse([
        {'year': '1404', 'nav_toman': 1000000000, 'nav_usd': 10000},
      ]);
      expect(rows.single.navUsd, 10000);
      expect(rows.single.navUsdWith(null), 10000);
      expect(rows.single.usdtRate, closeTo(100000, 0.01));
    });

    test('normalizeYearKey pads and accepts persian digits', () {
      expect(YearNavList.normalizeYearKey('۱۴۰۴'), '1404');
      expect(YearNavList.normalizeYearKey('404'), '0404');
      expect(YearNavList.normalizeYearKey(''), '');
    });

    test('encode round-trips manual USD', () {
      final encoded = YearNavList.encode([
        const YearNavEntry(
          yearKey: '1404',
          navToman: 1e9,
          navUsd: 12000,
          usdtRate: 83333.333,
        ),
      ]);
      final parsed = YearNavList.parse(encoded);
      expect(parsed.single.navUsd, 12000);
      expect(parsed.single.navToman, 1e9);
    });
  });

  group('parse amounts', () {
    test('toman and usd parsers', () {
      expect(parseTomanAmount('۱ میلیارد'), 1e9);
      expect(parseTomanAmount('1٬000٬000٬000'), 1e9);
      expect(parseUsdAmount('10000'), 10000);
      expect(parseUsdAmount(r'$12.5k'), 12500);
      expect(parseUsdAmount(''), null);
    });
  });

  group('YearNavCompare + growth series', () {
    test('YoY uses manual USD when present', () {
      final yoy = YearNavCompare.fromHistory(
        currentNav: 1.2e9,
        currentYearKey: '1405',
        history: const [
          YearNavEntry(yearKey: '1404', navToman: 1e9, navUsd: 8000),
        ],
        liveUsdt: 100000,
        currentNavUsd: 12000,
      );
      expect(yoy.deltaToman, closeTo(2e8, 0.1));
      expect(yoy.deltaUsd, closeTo(4000, 0.01));
    });

    test('growth series builds ascending toman/usd points', () {
      final series = yearNavGrowthSeries(
        history: const [
          YearNavEntry(yearKey: '1403', navToman: 8e8, navUsd: 10000),
          YearNavEntry(yearKey: '1404', navToman: 1e9, navUsd: 11000),
        ],
        currentNav: 1.2e9,
        currentYearKey: '1405',
        calendar: AppConfig.calendarJalali,
        liveUsdt: 100000,
        currentNavUsd: 12000,
      );
      expect(series.length, 3);
      expect(series.first.value, 8e8);
      expect(series.first.usdValue, 10000);
      expect(series.last.value, 1.2e9);
      expect(series.last.usdValue, 12000);
    });
  });

  group('remote mergePreserving year nav', () {
    test('keeps sent history when server returns empty present key', () {
      final sent = AppSettings(
        yearNavHistory: const [
          YearNavEntry(yearKey: '1404', navToman: 1e9, navUsd: 10000),
        ],
      );
      final server = RemoteSettingsBundle(
        settings: AppSettings(yearNavHistory: const []),
        presentKeys: {AppConfig.settingYearNavHistory},
      );
      final merged = server.mergePreserving(sent: sent);
      expect(merged.settings.yearNavHistory.single.navUsd, 10000);
    });
  });
}

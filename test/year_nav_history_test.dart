import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/year_nav_entry.dart';
import 'package:invest/domain/services/year_nav_compare.dart';

void main() {
  group('YearNavList', () {
    test('parses, upserts, and finds prior year', () {
      final rows = YearNavList.parse([
        {'year': '1403', 'nav_toman': 800000000, 'usdt_tmn': 80000},
        {'year': '1404', 'nav_toman': 1000000000, 'usdt_tmn': 100000},
      ]);
      expect(rows.length, 2);
      expect(rows.first.yearKey, '1404');
      expect(rows.first.navUsd, closeTo(10000, 0.01));

      final next = YearNavList.upsert(
        rows,
        const YearNavEntry(yearKey: '1404', navToman: 1.1e9, usdtRate: 110000),
      );
      expect(next.length, 2);
      expect(YearNavList.find(next, '1404')!.navToman, 1.1e9);
      expect(YearNavList.priorYearKey('1405'), '1404');
    });

    test('encode round-trips through settings string', () {
      final encoded = YearNavList.encode([
        const YearNavEntry(
          yearKey: '1404',
          navToman: 1e9,
          usdtRate: 100000,
        ),
      ]);
      final parsed = YearNavList.parse(encoded);
      expect(parsed.single.yearKey, '1404');
      expect(parsed.single.navToman, 1e9);
    });
  });

  group('parseTomanAmount', () {
    test('accepts plain, persian, and میلیارد', () {
      expect(parseTomanAmount('1000000000'), 1e9);
      expect(parseTomanAmount('۱ میلیارد'), 1e9);
      expect(parseTomanAmount('2.5 میلیون'), 2.5e6);
      expect(parseTomanAmount(''), null);
      expect(parseTomanAmount('abc'), null);
    });
  });

  group('YearNavCompare', () {
    test('computes YoY delta against prior year-end', () {
      final yoy = YearNavCompare.fromHistory(
        currentNav: 1.2e9,
        currentYearKey: '1405',
        history: const [
          YearNavEntry(yearKey: '1404', navToman: 1e9, usdtRate: 100000),
        ],
        liveUsdt: 100000,
      );
      expect(yoy.hasPrior, isTrue);
      expect(yoy.priorYearKey, '1404');
      expect(yoy.deltaToman, closeTo(2e8, 0.1));
      expect(yoy.pct, closeTo(20, 0.01));
      expect(yoy.deltaUsd, closeTo(2000, 0.01));
    });

    test('missing prior year keeps realized-only mode', () {
      final yoy = YearNavCompare.fromHistory(
        currentNav: 1.2e9,
        currentYearKey: '1405',
        history: const [],
      );
      expect(yoy.hasPrior, isFalse);
    });
  });
}

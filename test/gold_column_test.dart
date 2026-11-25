import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/domain/services/gold_column.dart';
import 'package:invest/domain/services/gold_history_seed.dart';
import 'package:invest/domain/services/gold_price_log.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/widgets/gold_price_column.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _iso(DateTime d) => toIsoDate(d);

/// One point per day, the last one on 2026-11-24 (the day before «today»).
List<GoldPricePoint> _log(List<double> mids) {
  final t = DateTime.utc(2026, 11, 25);
  return [
    for (var i = 0; i < mids.length; i++) GoldPricePoint(date: _iso(t.subtract(Duration(days: mids.length - i))), mid: mids[i]),
  ];
}

GoldColumnModel _m(List<double> mids, {double? current, double? ch}) =>
    GoldColumnModel.compute(log: _log(mids), today: '2026-11-25', current: current, change24hPct: ch);

void main() {
  group('position, clamping and range', () {
    test('position is (price − low) / (high − low), bottom 0 and top 1', () {
      final m = _m([100, 200, 150], current: 175);
      expect(m.low, 100);
      expect(m.high, 200);
      expect(m.position, closeTo(0.75, 1e-9));
      expect(m.fractionOf(100), 0);
      expect(m.fractionOf(200), 1);
      expect(m.referencePosition, closeTo(0.5, 1e-9)); // yesterday 150
    });

    test('the live price widens the range so the marker never leaves the column', () {
      final up = _m([100, 200, 150], current: 260);
      expect(up.high, 260);
      expect(up.position, 1);
      final down = _m([100, 200, 150], current: 40);
      expect(down.low, 40);
      expect(down.position, 0);
    });

    test('values outside the range clamp to the ends; NaN is no position', () {
      final m = _m([100, 200], current: 150);
      expect(m.fractionOf(1000), 1);
      expect(m.fractionOf(-5), 0);
      expect(m.fractionOf(double.nan), isNull);
      expect(m.fractionOf(null), isNull);
    });

    test('flat range: everything sits in the middle', () {
      final m = _m([150, 150], current: 150);
      expect(m.hasRange, isTrue);
      expect(m.flatRange, isTrue);
      expect(m.position, 0.5);
      expect(m.referencePosition, 0.5);
    });

    test('only the last 30 days count; future and bad days are ignored', () {
      final log = [
        const GoldPricePoint(date: '2026-10-01', mid: 10), // 55 days back
        const GoldPricePoint(date: '2026-10-27', mid: 90), // 29 days back: in
        const GoldPricePoint(date: '2026-10-26', mid: 5), // 30 days back: out
        const GoldPricePoint(date: '2026-11-24', mid: 120),
        const GoldPricePoint(date: '2026-12-01', mid: 999), // future
        const GoldPricePoint(date: 'bad', mid: 1),
      ];
      final m = GoldColumnModel.compute(log: log, today: '2026-11-25', current: 100);
      expect(m.low, 90);
      expect(m.high, 120);
      expect(m.daysWithData, 3);
    });
  });

  group('sparse data and missing price', () {
    test('no price at all: empty', () {
      final m = GoldColumnModel.compute(log: const [], today: '2026-11-25');
      expect(m.hasPrice, isFalse);
      expect(m.hasRange, isFalse);
      expect(m.position, isNull);
      expect(m.direction, isNull);
    });

    test('price only (first day): no range yet, change from the 24h move', () {
      final m = GoldColumnModel.compute(log: const [], today: '2026-11-25', current: 101, change24hPct: 1);
      expect(m.hasPrice, isTrue);
      expect(m.hasRange, isFalse);
      expect(m.daysWithData, 1);
      expect(m.position, isNull);
      expect(m.reference, closeTo(100, 1e-9));
      expect(m.referenceDaysAgo, 1);
      expect(m.direction, GoldColumnDirection.up);
      expect(m.average, isNull);
    });

    test('offline: the latest logged day stands in for the price', () {
      final m = _m([100, 120, 110]); // no current
      expect(m.price, 110);
      expect(m.reference, 120);
      expect(m.daysWithData, 3);
    });

    test('a logged day beats the 24h change for the reference', () {
      final m = _m([100, 120], current: 130, ch: 50);
      expect(m.reference, 120);
    });

    test('a gap (market holiday) uses the latest earlier day', () {
      final log = [
        const GoldPricePoint(date: '2026-11-20', mid: 100),
        const GoldPricePoint(date: '2026-11-22', mid: 104),
      ];
      final m = GoldColumnModel.compute(log: log, today: '2026-11-25', current: 102);
      expect(m.reference, 104);
      expect(m.referenceDaysAgo, 3);
      expect(m.direction, GoldColumnDirection.down);
    });

    test('bad current price and bad 24h change are ignored', () {
      final m = GoldColumnModel.compute(
          log: const [], today: '2026-11-25', current: double.nan, change24hPct: double.infinity);
      expect(m.hasPrice, isFalse);
      final n = GoldColumnModel.compute(log: const [], today: '2026-11-25', current: 100, change24hPct: -100);
      expect(n.reference, isNull);
    });
  });

  group('direction vs yesterday', () {
    test('up, down, flat', () {
      expect(_m([100, 100], current: 101).direction, GoldColumnDirection.up);
      expect(_m([100, 100], current: 99).direction, GoldColumnDirection.down);
      expect(_m([100, 100], current: 100).direction, GoldColumnDirection.flat);
      // Under 0.01% is flat.
      expect(_m([25000000, 25000000], current: 25002000).direction, GoldColumnDirection.flat);
      expect(_m([25000000, 25000000], current: 25003000).direction, GoldColumnDirection.up);
    });

    test('change in Toman and percent', () {
      final m = _m([14110000], current: 14280000);
      expect(m.change, 170000);
      expect(m.changePct, closeTo(1.2048, 1e-3));
    });

    test('«yesterday» turns at Tehran midnight, whatever the device zone', () {
      final log = [
        const GoldPricePoint(date: '2026-11-24', mid: 100),
        const GoldPricePoint(date: '2026-11-25', mid: 110),
      ];
      GoldColumnModel at(DateTime utc) =>
          GoldColumnModel.compute(log: log, today: tehranTodayIso(now: utc), current: 120);
      // 23:59 Tehran on the 25th = 20:29 UTC: today is the 25th, yesterday the 24th.
      final before = at(DateTime.utc(2026, 11, 25, 20, 29));
      expect(before.reference, 100);
      // 00:00 Tehran on the 26th = 20:30 UTC: the 25th is now yesterday.
      final after = at(DateTime.utc(2026, 11, 25, 20, 30));
      expect(after.reference, 110);
      expect(after.referenceDaysAgo, 1);
    });
  });

  group('30-day average', () {
    test('mean of one price per day, today = the current price', () {
      final m = _m([100, 200, 300], current: 400);
      expect(m.average, 250);
      expect(m.belowAverage, isFalse);
      expect(m.belowAverageGap, isNull);
    });

    test('below the average: gap in Toman and percent', () {
      final m = _m([110, 120, 130], current: 100); // mean 115
      expect(m.average, 115);
      expect(m.belowAverage, isTrue);
      expect(m.belowAverageGap, 15);
      expect(m.belowAveragePct, closeTo(13.0435, 1e-3));
      expect(m.averagePosition, closeTo(0.5, 1e-9));
    });

    test('equal to the average is not below', () {
      final m = _m([90, 110], current: 100);
      expect(m.average, 100);
      expect(m.belowAverage, isFalse);
    });

    test('today\'s logged point is replaced by the current price, not counted twice', () {
      final log = [
        const GoldPricePoint(date: '2026-11-23', mid: 100),
        const GoldPricePoint(date: '2026-11-24', mid: 100),
        const GoldPricePoint(date: '2026-11-25', mid: 500),
      ];
      final m = GoldColumnModel.compute(log: log, today: '2026-11-25', current: 100);
      expect(m.average, 100);
    });

    test('fewer than 3 days: no average', () {
      expect(_m([100], current: 90).average, isNull);
      expect(_m([100], current: 90).belowAverage, isFalse);
      expect(_m([100, 100], current: 90).average, isNotNull);
    });
  });

  group('semantics', () {
    test('Persian label with price, move, range and the average', () {
      final s = goldColumnSemantics(_m([110, 120, 130], current: 100));
      expect(s, contains('قیمت الان ۱۰۰ تومان'));
      expect(s, contains('پایین‌تر از دیروز'));
      expect(s, contains('کف ۳۰ روز ۱۰۰'));
      expect(s, contains('زیر میانگین'));
      expect(goldColumnSemantics(GoldColumnModel.compute(log: const [], today: '2026-11-25')), contains('هنوز'));
    });
  });

  group('TGJU back-fill', () {
    const body = '{"draw":null,"recordsTotal":3,"data":['
        '["240,888,000","240,881,000","260,178,000","253,947,000","<span>13063000</span>","<span>5.42%</span>","2026/11/24","1405/09/03"],'
        '["234,780,000","234,780,000","241,135,000","240,884,000","x","y","2026/11/23","1405/09/02"],'
        '["bad","row"],'
        '["1","1","1","0","x","y","2026/11/22","1405/09/01"],'
        '["229,456,000","229,456,000","235,018,000","234,584,000","x","y","2026/13/40","1405/09/01"]]}';

    test('parses Rial closes into Toman, oldest first, skipping bad rows', () {
      final p = GoldHistorySeed.parse(body);
      expect(p.map((e) => e.date), ['2026-11-23', '2026-11-24']);
      expect(p.map((e) => e.mid), [24088400, 25394700]);
      expect(p.every((e) => e.source == 'tgju'), isTrue);
      expect(GoldHistorySeed.parse('not json'), isEmpty);
      expect(GoldHistorySeed.parse('{"data":"x"}'), isEmpty);
    });

    test('a table far from the live price is dropped', () {
      expect(GoldHistorySeed.parse(body, sanityPrice: 25569000), hasLength(2));
      expect(GoldHistorySeed.parse(body, sanityPrice: 2556900), isEmpty); // 10× off
    });

    test('fill adds missing days only; the phone\'s own days win', () {
      final mine = [const GoldPricePoint(date: '2026-11-24', mid: 25500000)];
      final out = GoldPriceLog.fill(mine, GoldHistorySeed.parse(body));
      expect(out.map((e) => '${e.date}:${e.mid.toInt()}:${e.source}'),
          ['2026-11-23:24088400:tgju', '2026-11-24:25500000:null']);
      // Source survives a save/load round trip.
      expect(GoldPriceLog.decode(GoldPriceLog.encode(out)).first.source, 'tgju');
    });

    test('AppState seeds once, then waits 12 hours; off when live gold is off', () async {
      SharedPreferences.setMockInitialValues({});
      var calls = 0;
      final s = AppState()
        ..liveGold = 25569000
        ..goldHistorySeed = GoldHistorySeed(
          client: MockClient((r) async {
            calls++;
            expect(r.url.host, 'api.tgju.org');
            expect(r.url.queryParameters['length'], '40');
            return http.Response(body, 200);
          }),
        );
      final now = DateTime.utc(2026, 11, 25, 9);
      await s.seedGoldPriceLog(now: now);
      expect(calls, 1);
      expect(s.goldPriceLog.map((e) => e.date), ['2026-11-23', '2026-11-24']);
      await s.seedGoldPriceLog(now: now.add(const Duration(hours: 3)));
      expect(calls, 1);
      await s.seedGoldPriceLog(now: now.add(const Duration(hours: 13)));
      expect(calls, 2);
      s.settings.goldApiEnabled = false;
      await s.seedGoldPriceLog(now: now.add(const Duration(hours: 40)));
      expect(calls, 2);
    });

    test('a full month on the phone is never back-filled', () async {
      SharedPreferences.setMockInitialValues({});
      var calls = 0;
      final s = AppState()
        ..goldPriceLog = [
          for (var i = 0; i < 25; i++)
            GoldPricePoint(date: _iso(DateTime.utc(2026, 11, 25).subtract(Duration(days: i))), mid: 25000000),
        ]
        ..goldHistorySeed = GoldHistorySeed(client: MockClient((r) async {
          calls++;
          return http.Response(body, 200);
        }));
      await s.seedGoldPriceLog(now: DateTime.utc(2026, 11, 25, 9));
      expect(calls, 0);
    });

    test('a failing feed leaves the log alone', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState()
        ..goldHistorySeed = GoldHistorySeed(client: MockClient((r) async => http.Response('oops', 500)));
      await s.seedGoldPriceLog(now: DateTime.utc(2026, 11, 25, 9));
      expect(s.goldPriceLog, isEmpty);
    });
  });
}

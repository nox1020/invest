import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/gold_cash_entry.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/gold_calc.dart';
import 'package:invest/domain/services/gold_calc_prefs.dart';
import 'package:invest/domain/services/gold_fund_book.dart';
import 'package:invest/domain/services/gold_price_log.dart';
import 'package:invest/domain/utils/gold_fund_tag.dart';
import 'package:shared_preferences/shared_preferences.dart';

Asset _gold(int id, String name, double price, {String notes = ''}) =>
    Asset(id: id, name: name, symbol: 'GOLD', quantity: 0, avgBuyPrice: 0, currentPrice: price, notes: notes);

Trade _open(int id, int asset, double q, double p,
        {double fee = 0, String date = '2026-01-01', String note = '', String created = ''}) =>
    Trade(
      id: id,
      assetId: asset,
      status: AppConfig.tradeOpen,
      quantity: q,
      buyPrice: p,
      buyFee: fee,
      buyDate: date,
      buyNote: note,
      createdAt: created,
    );

Trade _closed(int id, int asset, double q, double p, double sp,
        {double fee = 0,
        double sellFee = 0,
        String date = '2026-01-01',
        String sellDate = '2026-02-01',
        String note = '',
        String sellNote = ''}) =>
    Trade(
      id: id,
      assetId: asset,
      status: AppConfig.tradeClosed,
      quantity: q,
      buyPrice: p,
      buyFee: fee,
      buyDate: date,
      buyNote: note,
      sellPrice: sp,
      sellFee: sellFee,
      sellDate: sellDate,
      sellNote: sellNote,
      realizedPnl: q * (sp - p) - fee - sellFee,
    );

GoldCashEntry _e(String id, String kind, double amount, String date, {String created = '', String op = ''}) =>
    GoldCashEntry(id: id, kind: kind, amount: amount, date: date, createdAt: created, opId: op);

void main() {
  group('[gf] tag', () {
    test('add, read, strip, carry', () {
      expect(withGoldFundTag('', 'AB12'), '[gf:ab12]');
      expect(withGoldFundTag('سکه بازار', 'x1'), '[gf:x1] سکه بازار');
      expect(withGoldFundTag('[gf:old] یادداشت', 'n1'), '[gf:n1] یادداشت');
      expect(goldFundTagId('[gf:x1] hi'), 'x1');
      expect(goldFundTagId('[gf] hi'), '');
      expect(goldFundTagId('hi'), isNull);
      expect(goldFundTagId(null), isNull);
      expect(hasGoldFundTag('text [GF:Q9] more'), isTrue);
      expect(stripGoldFundTag('[gf:x1] یادداشت'), 'یادداشت');
      expect(stripGoldFundTag('[gf:x1]'), '');
      expect(carryGoldFundTag('[gf:x1] old', 'new note'), '[gf:x1] new note');
      expect(carryGoldFundTag('[gf:x1] old', ''), '[gf:x1]');
      expect(carryGoldFundTag('[gf] old', 'n'), '[gf] n');
      expect(carryGoldFundTag('plain', 'n'), 'n');
      expect(carryGoldFundTag('[gf:x1]', '[gf:x1] kept'), '[gf:x1] kept');
      final a = newGoldFundOpId(), b = newGoldFundOpId();
      expect(a, isNot(b));
      expect(RegExp(r'^[a-z0-9]+$').hasMatch(a), isTrue);
      expect(goldFundTagId(withGoldFundTag('', a)), a);
    });

    test('trade notes hide the tag but keep it for edits/backups', () {
      final t = _closed(1, 1, 1, 10, 12, note: '[gf:ab] buy', sellNote: '[gf:cd] sold');
      expect(t.buyNoteDisplay, 'buy');
      expect(t.sellNoteDisplay, 'sold');
      expect(t.buyNoteFree, '[gf:ab] buy');
      expect(t.buyFromGoldFund, isTrue);
      expect(t.soldToGoldFund, isTrue);
      final open = _open(2, 1, 1, 10, note: '[gf:ab]');
      expect(open.soldToGoldFund, isFalse);
      expect(open.buyNoteDisplay, '');
    });
  });

  group('cash ledger', () {
    test('parse repairs signs, drops junk and duplicates, sorts', () {
      final rows = GoldCashLedger.parse([
        {'id': 'b', 'kind': 'withdraw', 'amount': 500, 'date': '2026-03-02'},
        {
          'id': 'a',
          'kind': 'deposit',
          'amount': -1000,
          'date': '2026-03-01T10:00:00',
          'note': ' x ',
          'op': 'q1',
          'mirrored': 1
        },
        {'id': 'a', 'kind': 'deposit', 'amount': 9, 'date': '2026-03-01'},
        {'id': 'c', 'kind': 'bogus', 'amount': 5, 'date': '2026-03-01'},
        {'id': '', 'kind': 'deposit', 'amount': 5, 'date': '2026-03-01'},
        {'id': 'd', 'kind': 'deposit', 'amount': 0, 'date': '2026-03-01'},
        {'id': 'e', 'kind': 'deposit', 'amount': 'NaN', 'date': '2026-03-01'},
        {'id': 'f', 'kind': 'deposit', 'amount': 5, 'date': '1405/01/01'},
        {'id': 'g', 'kind': 'adjust', 'amount': -250, 'date': '2026-03-03'},
        'junk',
      ]);
      expect(rows.map((e) => e.id), ['a', 'b', 'g']);
      expect(rows[0].amount, 1000);
      expect(rows[0].date, '2026-03-01');
      expect(rows[0].note, 'x');
      expect(rows[0].opId, 'q1');
      expect(rows[0].withdrawalMirrored, isTrue);
      expect(rows[1].amount, -500);
      expect(rows[2].amount, -250);
      expect(GoldCashLedger.total(rows), 250);
    });

    test('json string round trip, add/remove, same', () {
      final rows = [
        _e('a', GoldCashKind.opening, 100, '2026-01-01'),
        _e('b', GoldCashKind.withdraw, -40, '2026-01-05')
      ];
      final back = GoldCashLedger.parse(GoldCashLedger.encode(rows));
      expect(GoldCashLedger.same(rows, back), isTrue);
      expect(GoldCashLedger.parse('not json'), isEmpty);
      expect(GoldCashLedger.parse(''), isEmpty);
      expect(GoldCashLedger.parse(null), isEmpty);
      final added = GoldCashLedger.add(rows, _e('c', GoldCashKind.deposit, 7, '2025-12-31'));
      expect(added.first.id, 'c');
      final replaced = GoldCashLedger.add(added, _e('c', GoldCashKind.deposit, 8, '2025-12-31'));
      expect(replaced.length, 3);
      expect(replaced.first.amount, 8);
      // A delete leaves a hidden tombstone (so it syncs) and stops counting.
      final removed = GoldCashLedger.remove(replaced, 'c');
      expect(removed.map((e) => e.id), ['c', 'a', 'b']);
      expect(removed.first.deleted, isTrue);
      expect(GoldCashLedger.live(removed).map((e) => e.id), ['a', 'b']);
      expect(GoldCashLedger.total(removed), 60);
      expect(GoldCashLedger.same(removed, replaced), isFalse);
      expect(GoldCashLedger.same(GoldCashLedger.remove(removed, 'c'), removed), isTrue);
      expect(GoldCashLedger.parse(GoldCashLedger.encode(removed)).first.deleted, isTrue);
      expect(GoldCashLedger.same(rows, replaced), isFalse);
      expect(GoldCashKind.label(GoldCashKind.adjust), 'تنظیم مانده');
    });
  });

  group('quote', () {
    test('uses market bid/ask when sane, estimates otherwise', () {
      final real = GoldQuote.resolve(mid: 14280000, bid: 14210000, ask: 14350000, change24hPct: 1.2);
      expect(real.estimated, isFalse);
      expect(real.ask, 14350000);
      expect(real.bid, 14210000);
      expect(real.change24hPct, 1.2);
      // Swapped sides are put back in order.
      final swapped = GoldQuote.resolve(mid: 14280000, bid: 14350000, ask: 14210000);
      expect(swapped.bid, 14210000);
      expect(swapped.estimated, isFalse);
      for (final bad in [
        (null, 14350000.0),
        (14210000.0, null),
        (0.0, 14350000.0),
        (13000000.0, 14350000.0), // spread > 5%
        (14300000.0, 14350000.0), // bid above mid
        (14100000.0, 14200000.0), // ask below mid
        (double.nan, 14350000.0),
      ]) {
        final q = GoldQuote.resolve(mid: 14280000, bid: bad.$1, ask: bad.$2);
        expect(q.estimated, isTrue, reason: '$bad');
        expect(q.ask, 14351400);
        expect(q.bid, 14208600);
      }
      expect(GoldQuote.resolve(mid: null).hasPrice, isFalse);
      expect(GoldQuote.resolve(mid: 0, bid: 1, ask: 2).ask, 0);
      expect(real.mazaneh, closeTo(14280000 * 4.3318, 1e-3));
    });
  });

  group('book', () {
    final assets = [
      _gold(1, 'طلای آب‌شده', 14000000),
      _gold(2, 'طلای ۲۴', 18000000, notes: '[meta:{"purity":"24"}]'),
      Asset(id: 3, name: 'سکه امامی', symbol: 'COIN', quantity: 1, avgBuyPrice: 1, currentPrice: 90000000),
      Asset(id: 4, name: 'Bitcoin', symbol: 'BTC', quantity: 1, avgBuyPrice: 1, currentPrice: 5e9),
    ];
    final open = [
      _open(10, 1, 8, 9850000, date: '2025-06-02'),
      _open(11, 1, 2, 12400000, fee: 80000, date: '2025-11-26', note: '[gf:op1]', created: '2025-11-26T10:00'),
      _open(12, 2, 3, 16000000, fee: 0, date: '2026-01-10'),
      _open(13, 3, 1, 80000000),
      _open(14, 4, 1, 4e9),
    ];
    final closed = [
      // The other half of op1 (partial close copied the buy note), sold
      // through the fund in op2 together with lot 16.
      _closed(15, 1, 10.5, 12400000, 14000000,
          fee: 420000,
          sellFee: 300000,
          date: '2025-11-26',
          note: '[gf:op1]',
          sellNote: '[gf:op2]',
          sellDate: '2026-02-01'),
      _closed(16, 1, 1, 10000000, 14000000, sellFee: 28571, sellNote: '[gf:op2]', sellDate: '2026-02-01'),
      // Sold outside the fund: realized counts, cash does not.
      _closed(17, 1, 1, 10000000, 13000000, sellDate: '2026-01-20'),
      // Coins are not part of the fund.
      _closed(18, 3, 1, 70000000, 85000000, note: '[gf:zz]', sellNote: '[gf:zz]'),
    ];
    final ledger = [
      _e('o', GoldCashKind.opening, 50000000, '2025-11-01', created: 'a'),
      _e('gap', GoldCashKind.deposit, 1000000, '2025-11-26', created: 'z', op: 'op1'),
      _e('w', GoldCashKind.withdraw, -20000000, '2026-03-01', created: 'b'),
    ];
    final book = GoldFundBook.compute(
      assets: assets,
      openTrades: open,
      closedTrades: closed,
      ledger: ledger,
      quote: GoldQuote.resolve(mid: 14000000),
    );

    test('holdings: gold only, karat-aware', () {
      expect(book.holdings.map((h) => h.asset.id).toSet(), {1, 2});
      final h1 = book.holdingFor(1)!, h2 = book.holdingFor(2)!;
      expect(h1.grams, 10);
      expect(h1.cost, 8 * 9850000 + 2 * 12400000 + 80000);
      expect(h1.value, 10 * 14000000);
      expect(h2.purity, 1);
      expect(h2.karatLabel, '24');
      expect(h2.grams18, closeTo(4, 1e-9));
      expect(book.holdingG18, closeTo(14, 1e-9));
      expect(book.mainHolding!.asset.id, 1);
      expect(h1.calcLots.map((l) => l.id), [10, 11]);
      expect(book.value, 10 * 14000000 + 3 * 18000000);
      expect(book.cost, 8 * 9850000 + 2 * 12400000 + 80000 + 3 * 16000000);
      expect(book.unrealized, book.value - book.cost);
      expect(book.avgCost18, closeTo(book.cost / 14, 1e-6));
    });

    test('in/out flow and realized (gold only)', () {
      expect(book.inG18, closeTo(10 + 4 + 10.5 + 1 + 1, 1e-9));
      expect(book.outG18, closeTo(12.5, 1e-9));
      expect(book.sellCount, 3);
      final r = closed.take(3).fold<double>(0, (s, t) => s + t.realizedPnl!);
      expect(book.realized, closeTo(r, 1e-6));
      expect(book.totalPnl, closeTo(book.unrealized + r, 1e-6));
    });

    test('cash: manual rows + tagged trades grouped by operation, running balance', () {
      final rows = book.cashRows;
      expect(rows.map((r) => r.kind), [
        GoldCashRowKind.manual, // opening 2025-11-01
        GoldCashRowKind.manual, // gap deposit sorts before its buy
        GoldCashRowKind.buy, // op1: lot 11 + closed 15
        GoldCashRowKind.sell, // op2: closed 15 + 16
        GoldCashRowKind.manual, // withdraw
      ]);
      final buy = rows[2];
      expect(buy.opId, 'op1');
      expect(buy.grams, closeTo(12.5, 1e-9));
      expect(buy.amount, closeTo(-(2 * 12400000 + 80000 + 10.5 * 12400000 + 420000), 1e-6));
      expect(buy.tradeIds.toSet(), {11, 15});
      final sell = rows[3];
      expect(sell.amount, closeTo(10.5 * 14000000 - 300000 + 14000000 - 28571, 1e-6));
      expect(sell.grams, closeTo(11.5, 1e-9));
      var bal = 0.0;
      for (final r in rows) {
        bal += r.amount;
        expect(r.balance, closeTo(bal, 1e-6));
      }
      expect(book.cash, closeTo(bal, 1e-6));
      expect(book.total, closeTo(book.value + book.cash, 1e-6));
      expect(rows.every((r) => r.isAuto == (r.kind != GoldCashRowKind.manual)), isTrue);
    });

    test('derived ratios', () {
      final share = book.goldShare!;
      expect(share, closeTo(book.value / (book.value + book.cash), 1e-9));
      expect(book.breakEvenSell18(0.5), closeTo(book.avgCost18 / 0.995, 1e-6));
      expect(book.buyingPowerG18(0.5), closeTo(book.cash / (book.quote.ask * 1.005), 1e-9));
      expect(book.cashEffectOf(closed[1]), closeTo(14000000 - 28571, 1e-6));
      expect(book.cashEffectOf(closed[2]), 0);
      expect(book.cashEffectOf(open[1]), closeTo(-(2 * 12400000 + 80000), 1e-6));
      expect(book.hasAnything, isTrue);
    });

    test('empty book', () {
      final e = GoldFundBook.compute(assets: const [], openTrades: const [], closedTrades: const [], ledger: const []);
      expect(e.hasAnything, isFalse);
      expect(e.cash, 0);
      expect(e.total, 0);
      expect(e.goldShare, isNull);
      expect(e.avgCost18, 0);
      expect(e.breakEvenSell18(0.5), 0);
      expect(e.buyingPowerG18(0.5), 0);
      expect(e.mainHolding, isNull);
      // Cash only.
      final c = GoldFundBook.compute(
        assets: const [],
        openTrades: const [],
        closedTrades: const [],
        ledger: [_e('a', GoldCashKind.deposit, 5000000, '2026-01-01')],
        quote: GoldQuote.resolve(mid: 10000000),
      );
      expect(c.cash, 5000000);
      expect(c.goldShare, 0);
      expect(c.hasAnything, isTrue);
    });

    test('bare [gf] tags still count, one row per trade', () {
      final b = GoldFundBook.compute(
        assets: [_gold(1, 'طلا', 10)],
        openTrades: [_open(1, 1, 1, 10, note: '[gf]'), _open(2, 1, 1, 10, note: '[gf]')],
        closedTrades: const [],
        ledger: const [],
      );
      expect(b.cashRows.length, 2);
      expect(b.cash, -20);
    });
  });

  group('device stores', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('price log: one point per day, window, cap, bad values', () async {
      expect(await GoldPriceLog.record(today: '2026-01-01', mid: 0), isNull);
      expect(await GoldPriceLog.record(today: '2026-01-01', mid: double.nan), isNull);
      await GoldPriceLog.record(today: '2026-01-01', mid: 100);
      await GoldPriceLog.record(today: '2026-01-01', mid: 110, bid: 105, ask: 115);
      await GoldPriceLog.record(today: '2026-02-15', mid: 120);
      final all = await GoldPriceLog.load();
      expect(all.map((p) => p.date), ['2026-01-01', '2026-02-15']);
      expect(all.first.mid, 110);
      expect(all.first.bid, 105);
      expect(GoldPriceLog.window(all, '2026-02-20', 30).map((p) => p.date), ['2026-02-15']);
      expect(GoldPriceLog.window(all, '2026-02-20', 90).length, 2);
      expect(GoldPriceLog.series(all).last.value, 120);
      expect(GoldPriceLog.decode('garbage'), isEmpty);
      expect(GoldPriceLog.decode('[{"d":"x","p":1},{"d":"2026-01-01","p":-1},{"d":"2026-01-02","p":5}]').length, 1);
      var many = <GoldPricePoint>[];
      for (var i = 0; i < GoldPriceLog.maxDays + 20; i++) {
        final d = DateTime(2020, 1, 1).add(Duration(days: i));
        final iso = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        many = GoldPriceLog.upsert(many, GoldPricePoint(date: iso, mid: i + 1.0));
      }
      expect(many.length, GoldPriceLog.maxDays);
      expect(many.last.mid, GoldPriceLog.maxDays + 20.0);
    });

    test('calculator prefs: first run is online, last used product sticks', () async {
      final first = await GoldCalcPrefs.load();
      expect(first.product, GoldProduct.online);
      expect(first.buyMode, GoldInputMode.amount);
      expect(first.sellMode, GoldInputMode.weight);
      expect(first.lotOrder, GoldLotOrder.fifo);
      expect(first.feesFor(GoldProduct.jewelry).makingPct, 15);
      await first
          .copyWith(
            product: GoldProduct.jewelry,
            jewelryFees: const GoldFees(feePct: 1, makingPct: 20, profitPct: 5, vatPct: 9),
            lotOrder: GoldLotOrder.highestCost,
          )
          .save();
      final again = await GoldCalcPrefs.load();
      expect(again.product, GoldProduct.jewelry);
      expect(again.jewelryFees.makingPct, 20);
      expect(again.onlineFees.feePct, 0.5);
      expect(again.lotOrder, GoldLotOrder.highestCost);
      expect(GoldCalcPrefs.decode('{bad').product, GoldProduct.online);
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/remote_invest_service.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/gold_cash_entry.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/gold_calc.dart';
import 'package:invest/domain/services/portfolio_valuation.dart';
import 'package:invest/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Server {
  bool down = true;
  final posts = <String>[];
  Future<http.Response> handle(http.Request r) async {
    if (down) throw http.ClientException('offline');
    if (r.method != 'GET') posts.add('${r.method} ${r.url.path}');
    return http.Response(jsonEncode({'success': true, 'items': []}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

const _phone = '09120000000';

Future<AppState> _offlineState(_Server s) async {
  final session = await SessionStore.load();
  final api = InvestApiClient(session, client: MockClient(s.handle))..restoreSessionCookie();
  final state = AppState()
    ..loading = false
    ..authenticated = true
    ..useRemote = true
    ..offline = true
    ..readOnlyOffline = true
    ..userPhone = _phone
    ..remote = RemoteInvestService(api)
    ..liveGold = 14000000
    ..assets = [
      Asset(id: 5, name: 'طلای آب‌شده', symbol: 'GOLD', currentPrice: 14000000, quantity: 10, avgBuyPrice: 10000000),
    ]
    ..openTrades = [
      Trade(
          id: 50,
          assetId: 5,
          status: AppConfig.tradeOpen,
          quantity: 4,
          buyPrice: 9000000,
          buyDate: '2025-01-01',
          assetName: 'طلای آب‌شده'),
      Trade(
          id: 51,
          assetId: 5,
          status: AppConfig.tradeOpen,
          quantity: 6,
          buyPrice: 11000000,
          buyFee: 60000,
          buyDate: '2025-06-01',
          assetName: 'طلای آب‌شده'),
    ]
    ..settings = AppSettings(calendar: AppConfig.calendarGregorian);
  await state.coreOutbox.bind(_phone);
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({
        AppConfig.prefBaseUrl: 'https://vinor.test',
        AppConfig.prefSessionCookie: 'vinor_session=t',
      }));

  test('NAV adds fund cash like cheques; holdings and trend do not', () {
    final assets = [Asset(id: 1, name: 'طلا', currentPrice: 100, quantity: 1, avgBuyPrice: 50)];
    final open = [Trade(id: 1, assetId: 1, status: AppConfig.tradeOpen, quantity: 2, buyPrice: 50)];
    final v = PortfolioValuation.of(assets: assets, openTrades: open, goldFundCash: 300);
    expect(v.holdingsValue, 200);
    expect(v.goldFundCash, 300);
    expect(v.nav, 500);
    expect(PortfolioValuation.of(assets: assets, openTrades: open, goldFundCash: double.nan).nav, 200);
    final snap = DashboardSnapshot.compute(
      assets: assets,
      openTrades: open,
      closedTrades: const [],
      usdtTmn: null,
      calendar: AppConfig.calendarGregorian,
      goldFundCash: -50,
    );
    expect(snap.marketValue, 150);
    expect(snap.holdingsValue, 200);
  });

  test('cash entries: deposit, withdraw limits, adjust stores the difference, delete', () async {
    final s = await _offlineState(_Server());
    await s.addGoldCashEntry(kind: GoldCashKind.deposit, amount: 50000000, date: '2026-01-01', note: ' اول ');
    expect(s.goldFundCash, 50000000);
    expect(s.settings.goldFundLedger.single.note, 'اول');
    await expectLater(
      s.addGoldCashEntry(kind: GoldCashKind.withdraw, amount: 60000000),
      throwsArgumentError,
    );
    await expectLater(s.addGoldCashEntry(kind: GoldCashKind.deposit, amount: 0), throwsArgumentError);
    await expectLater(s.addGoldCashEntry(kind: GoldCashKind.deposit, amount: double.nan), throwsArgumentError);
    await expectLater(s.addGoldCashEntry(kind: 'bogus', amount: 5), throwsArgumentError);
    await s.addGoldCashEntry(kind: GoldCashKind.withdraw, amount: 20000000, date: '2026-01-02');
    expect(s.goldFundCash, 30000000);
    final adj = await s.addGoldCashEntry(kind: GoldCashKind.adjust, amount: 31500000, date: '2026-01-03');
    expect(adj.amount, 1500000);
    expect(s.goldFundCash, 31500000);
    await expectLater(s.addGoldCashEntry(kind: GoldCashKind.adjust, amount: 31500000), throwsArgumentError);
    await s.deleteGoldCashEntry(adj.id);
    expect(s.goldFundCash, 30000000);
    await s.deleteGoldCashEntry('missing');
    expect(s.settings.goldFundLedger.length, 2);
    // Settings wait in the outbox while offline.
    expect(s.coreOutbox.ops.any((o) => o.kind == 'settings.push'), isTrue);
  });

  test('offline buy: gap deposit first, then a tagged buy in the queue', () async {
    final s = await _offlineState(_Server());
    await s.addGoldCashEntry(kind: GoldCashKind.deposit, amount: 10000000, date: '2026-01-01');
    final q = GoldCalc.buy(
      product: GoldProduct.online,
      mode: GoldInputMode.weight,
      input: 1,
      pricePerGram: s.goldQuote.ask,
      fees: GoldFees.onlineDefault,
      cashBefore: s.goldFundCash,
    );
    expect(q.shortfall, greaterThan(0));
    final res = await s.recordGoldBuy(
      assetId: 5,
      grams: q.grams,
      pricePerGram: q.pricePerGram,
      fee: q.recordFee,
      date: '2026-01-05',
      note: 'آنلاین',
      gapDeposit: q.shortfall,
    );
    expect(res.complete, isTrue);
    expect(res.queued, 1);
    final buy = s.openTrades.firstWhere((t) => t.id != 50 && t.id != 51);
    expect(buy.buyFromGoldFund, isTrue);
    expect(buy.buyNoteDisplay, 'آنلاین');
    final gap = s.settings.goldFundLedger.firstWhere((e) => e.opId == res.opId);
    expect(gap.amount, q.shortfall);
    // Deposit + gap − buy = 0: the fund spent exactly what it had.
    expect(s.goldFundCash.abs(), lessThan(1));
    final rows = s.goldFund.cashRows;
    expect(rows.last.kind.name, 'buy');
    expect(s.pendingSyncCount, greaterThanOrEqualTo(2));
  });

  test('offline multi-lot sell: every lot queued, status reported', () async {
    final s = await _offlineState(_Server());
    final h = s.goldFund.holdingFor(5)!;
    final q = GoldCalc.sell(
      mode: GoldInputMode.weight,
      input: 7,
      pricePerGram: s.goldQuote.bid,
      feePct: 0.5,
      lots: h.calcLots,
      cashBefore: s.goldFundCash,
      holdingBefore: h.grams,
      costBefore: h.cost,
    );
    expect(q.takes.length, 2);
    final progress = <int>[];
    final res = await s.recordGoldSell(quote: q, date: '2026-02-01', onProgress: (d, t) => progress.add(d));
    expect(res.total, 2);
    expect(res.done, 2);
    expect(res.queued, 2);
    expect(res.sent, 0);
    expect(res.complete, isTrue);
    expect(progress, [1, 2]);
    final sold = s.closedTrades.where((t) => t.soldToGoldFund).toList();
    expect(sold.length, 2);
    expect(sold.map((t) => t.quantity).fold<double>(0, (a, b) => a + b), closeTo(7, 1e-9));
    expect(s.goldFundCash, closeTo(q.net, 1));
    expect(s.goldFund.holdingFor(5)!.grams, closeTo(3, 1e-9));
  });

  test('sell refuses an unrecordable quote; result helpers', () async {
    final s = await _offlineState(_Server());
    await expectLater(s.recordGoldSell(quote: GoldSellQuote.empty), throwsArgumentError);
    await expectLater(
      s.recordGoldBuy(assetId: 5, grams: 0, pricePerGram: 1, fee: 0),
      throwsArgumentError,
    );
    await expectLater(
      s.recordGoldBuy(grams: 1, pricePerGram: 1, fee: 0),
      throwsArgumentError,
    );
    const r = GoldRecordResult(opId: 'x', total: 3, done: 1, queued: 1, error: 'boom');
    expect(r.complete, isFalse);
    expect(r.partial, isTrue);
    expect(r.sent, 0);
  });

  test('quote falls back to settings price and estimates sides', () {
    final s = AppState()..settings = AppSettings(goldTmnPerGram: 10000000);
    expect(s.goldQuote.mid, 10000000);
    expect(s.goldQuote.estimated, isTrue);
    s
      ..liveGold = 14280000
      ..liveGoldBid = 14210000
      ..liveGoldAsk = 14350000;
    expect(s.goldQuote.estimated, isFalse);
    expect(s.goldQuote.ask, 14350000);
  });
}

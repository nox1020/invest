import 'dart:convert';

import 'package:flutter/services.dart';
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
import 'package:invest/domain/services/gold_calc.dart';
import 'package:invest/domain/utils/gold_fund_tag.dart';
import 'package:invest/domain/utils/gold_number_input.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/gold/gold_input.dart';
import 'package:shared_preferences/shared_preferences.dart';

GoldCashEntry _e(String id, double amount, String date, {bool deleted = false}) => GoldCashEntry(
      id: id,
      kind: amount >= 0 ? GoldCashKind.deposit : GoldCashKind.withdraw,
      amount: amount,
      date: date,
      createdAt: '${date}T08:00:00',
      deleted: deleted,
    );

/// Vinor stand-in: GET /settings answers [settings]; everything else is an
/// empty success; writes are recorded.
class _Server {
  _Server(this.settings);
  Map<String, dynamic> settings;
  final puts = <Map<String, dynamic>>[];
  bool refuseWrites = false;
  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    if (refuseWrites && r.method == 'POST') {
      return http.Response(jsonEncode({'success': false, 'error': 'نامعتبر'}), 400,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }
    if (r.method == 'PUT' && path.endsWith('/settings')) {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      puts.add(body);
      return _json({'success': true, 'settings': settings});
    }
    if (path.endsWith('/settings')) return _json({'success': true, 'settings': settings});
    return _json({'success': true, 'items': []});
  }

  static http.Response _json(Object o) =>
      http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json; charset=utf-8'});
}

Future<AppState> _online(_Server s, {String phone = '09120000001'}) async {
  final session = await SessionStore.load();
  final api = InvestApiClient(session, client: MockClient(s.handle))..restoreSessionCookie();
  final state = AppState()
    ..loading = false
    ..authenticated = true
    ..useRemote = true
    ..offline = false
    ..readOnlyOffline = false
    ..userPhone = phone
    ..remote = RemoteInvestService(api)
    ..settings = AppSettings(calendar: AppConfig.calendarGregorian);
  await state.coreOutbox.bind(phone);
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({
        AppConfig.prefBaseUrl: 'https://vinor.test',
        AppConfig.prefSessionCookie: 'vinor_session=t',
      }));

  group('number input', () {
    test('weights and percents: Persian/Arabic digits, «٫», a lone «,» is a decimal mark', () {
      expect(parseGoldDecimal('۲٫۵'), 2.5);
      expect(parseGoldDecimal('٢٫٥'), 2.5);
      expect(parseGoldDecimal('2.5'), 2.5);
      expect(parseGoldDecimal('2,5'), 2.5); // never 25 g
      expect(parseGoldDecimal('0,75'), 0.75);
      expect(parseGoldDecimal('1,234.5'), 1234.5);
      expect(parseGoldDecimal('1,234,567'), 1234567);
      expect(parseGoldDecimal('۱٬۲۳۴'), 1234);
      expect(parseGoldDecimal(' 12 '), 12);
      expect(parseGoldDecimal(''), isNull);
      expect(parseGoldDecimal('abc'), isNull);
      expect(parseGoldDecimal(null), isNull);
    });

    test('Toman: every grouping style, «.» groups of three are thousands', () {
      expect(parseGoldToman('100,000,000'), 100000000);
      expect(parseGoldToman('۱۰۰٬۰۰۰٬۰۰۰'), 100000000);
      expect(parseGoldToman('100.000.000'), 100000000);
      expect(parseGoldToman('۱۴۳۵۰۰۰۰'), 14350000);
      expect(parseGoldToman('1500.5'), 1500.5);
      expect(parseGoldToman(''), isNull);
      expect(groupTomanDigits('۱۰۰۰۰۰۰۰۰'), '100,000,000');
      expect(groupTomanDigits('0012'), '12');
      expect(groupTomanDigits('999'), '999');
      expect(goldTomanText(43318000), '43,318,000');
    });

    test('live grouping keeps the caret after the same digit', () {
      const f = GoldTomanFormatter();
      var v = f.formatEditUpdate(TextEditingValue.empty,
          const TextEditingValue(text: '1000000', selection: TextSelection.collapsed(offset: 7)));
      expect(v.text, '1,000,000');
      expect(v.selection.end, 9);
      // Typing a digit in the middle («1,0|00» + 5).
      v = f.formatEditUpdate(const TextEditingValue(text: '1,000'),
          const TextEditingValue(text: '1,0500', selection: TextSelection.collapsed(offset: 4)));
      expect(v.text, '10,500');
      expect(v.selection.end, 4);
    });
  });

  group('ledger merge', () {
    test('union by id, a delete on either side wins, sorted', () {
      final phone = [_e('a', 100, '2026-01-01'), _e('b', -20, '2026-01-03')];
      final server = [_e('a', 100, '2026-01-01', deleted: true), _e('c', 5, '2026-01-02')];
      final m = GoldCashLedger.merge(phone, server);
      expect(m.map((e) => e.id), ['a', 'c', 'b']);
      expect(m.first.deleted, isTrue);
      expect(GoldCashLedger.total(m), -15);
      expect(GoldCashLedger.same(GoldCashLedger.merge(m, m), m), isTrue);
      expect(GoldCashLedger.same(GoldCashLedger.merge(server, phone), m), isTrue);
    });
  });

  group('sync', () {
    test('a row added while the push waited is merged into the server copy and sent back', () async {
      final server = _Server({
        AppConfig.settingGoldFundLedger: [_e('srv', 50000000, '2026-01-01').toJson()],
      });
      final s = await _online(server);
      // Offline add (memory/local) that the server never got.
      s.settings.goldFundLedger = [_e('phone', 7000000, '2026-01-05')];
      await s.refresh();
      expect(s.settings.goldFundLedger.map((e) => e.id), ['srv', 'phone']);
      expect(s.goldFundCash, 57000000);
      expect(server.puts, isNotEmpty);
      final sent = server.puts.last[AppConfig.settingGoldFundLedger] as List;
      expect(sent.map((e) => (e as Map)['id']), ['srv', 'phone']);
    });

    test('a delete made here survives a server copy that still has the row', () async {
      final server = _Server({
        AppConfig.settingGoldFundLedger: [_e('a', 50000000, '2026-01-01').toJson()],
      });
      final s = await _online(server);
      s.settings.goldFundLedger = [_e('a', 50000000, '2026-01-01', deleted: true)];
      await s.refresh();
      expect(s.goldFundCash, 0);
      expect(s.goldFund.cashRows, isEmpty);
    });

    test('logout keeps the book under its account and never hands it to the next one', () async {
      final server = _Server({}); // server without the key (not deployed)
      final s = await _online(server, phone: '09120000001');
      await s.addGoldCashEntry(kind: GoldCashKind.deposit, amount: 30000000, date: '2026-01-01');
      expect(s.goldFundCash, 30000000);
      await s.logout();
      expect(s.settings.goldFundLedger, isEmpty);

      // Another account logs in on the same phone.
      final other = await _online(server, phone: '09129999999');
      other.settings = s.settings;
      await other.refresh();
      expect(other.goldFundCash, 0);

      // The first account comes back: its local copy is restored.
      final back = await _online(server, phone: '09120000001');
      await back.refresh();
      expect(back.goldFundCash, 30000000);
    });
  });

  group('recording', () {
    Future<AppState> offline() async {
      final s = await _online(_Server({}));
      s
        ..offline = true
        ..readOnlyOffline = true
        ..liveGold = 14000000
        ..assets = [Asset(id: 5, name: 'طلای آب‌شده', symbol: 'GOLD', currentPrice: 14000000, quantity: 4)]
        ..openTrades = [
          Trade(
              id: 50,
              assetId: 5,
              status: AppConfig.tradeOpen,
              quantity: 4,
              buyPrice: 9000000,
              buyDate: '2026-03-01',
              assetName: 'طلای آب‌شده'),
        ];
      return s;
    }

    test('a sale dated before a lot was bought is refused before any lot closes', () async {
      final s = await offline();
      final q = GoldCalc.sell(
        mode: GoldInputMode.weight,
        input: 1,
        pricePerGram: 14000000,
        feePct: 0.5,
        lots: s.goldFund.holdingFor(5)!.calcLots,
      );
      expect(goldSellDateConflict(q, '2026-02-01'), '2026-03-01');
      expect(goldSellDateConflict(q, '2026-03-01'), isNull);
      await expectLater(s.recordGoldSell(quote: q, date: '2026-02-01'), throwsArgumentError);
      expect(s.closedTrades, isEmpty);
      expect(s.coreOutbox.ops.where((o) => o.kind == 'trade.close'), isEmpty);
    });

    test('a refused buy takes its gap deposit back', () async {
      final server = _Server({})..refuseWrites = true;
      final s = await _online(server);
      s
        ..liveGold = 14000000
        ..assets = [Asset(id: 5, name: 'طلای آب‌شده', symbol: 'GOLD', currentPrice: 14000000)];
      final res = await s.recordGoldBuy(
        assetId: 5,
        grams: 1,
        pricePerGram: 14000000,
        fee: 0,
        date: '2026-04-01',
        gapDeposit: 14000000,
      );
      expect(res.error, isNotNull);
      expect(res.done, 0);
      expect(s.goldFundCash, 0);
      expect(s.goldFund.cashRows, isEmpty);
      // The rollback is a tombstone, so the server copy loses it too.
      expect(s.settings.goldFundLedger.single.deleted, isTrue);
    });
  });

  group('hidden marker', () {
    test('free-text getters keep the marker for re-writes, display getters drop it', () {
      final t = Trade(
        assetId: 1,
        status: AppConfig.tradeClosed,
        quantity: 1,
        buyPrice: 1,
        buyNote: withGoldFundTag('یادداشت', 'op1'),
        sellPrice: 2,
        sellNote: '[gf:op2] فروش',
      );
      expect(t.buyNoteFree, contains('[gf:op1]'));
      expect(t.buyNoteDisplay, 'یادداشت');
      expect(t.sellNoteDisplay, 'فروش');
      expect(t.soldToGoldFund, isTrue);
    });
  });
}

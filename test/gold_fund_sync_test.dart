import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/remote_invest_service.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/gold_cash_entry.dart';
import 'package:invest/domain/services/backup_payload.dart';
import 'package:invest/domain/services/backup_service.dart';
import 'package:invest/domain/services/gold_quote_parser.dart';

const _ledger = [
  GoldCashEntry(
      id: 'gc_1', kind: GoldCashKind.opening, amount: 100000000, date: '2026-01-01', createdAt: '2026-01-01T08:00:00'),
  GoldCashEntry(
      id: 'gc_2',
      kind: GoldCashKind.withdraw,
      amount: -40000000,
      date: '2026-02-01',
      note: 'خرج خانه',
      withdrawalMirrored: true),
  GoldCashEntry(id: 'gc_3', kind: GoldCashKind.deposit, amount: 5000000, date: '2026-02-03', opId: 'op9'),
];

void main() {
  test('settings: json, storage map and copyWith keep the ledger', () {
    final s = AppSettings(goldFundLedger: _ledger);
    final j = s.toJson();
    expect(j[AppConfig.settingGoldFundLedger], isA<List>());
    final back = AppSettings.fromJson(j);
    expect(GoldCashLedger.same(back.goldFundLedger, _ledger), isTrue);
    expect(back.goldFundLedger[1].withdrawalMirrored, isTrue);
    expect(back.goldFundLedger[2].opId, 'op9');
    final stored = AppSettings.fromStorageMap(s.toStorageMap());
    expect(GoldCashLedger.same(stored.goldFundLedger, _ledger), isTrue);
    expect(s.copyWith(usdtTmnRate: 1).goldFundLedger.length, 3);
    expect(s.copyWith(goldFundLedger: const []).goldFundLedger, isEmpty);
    expect(AppSettings.fromJson(const {}).goldFundLedger, isEmpty);
  });

  test('server bundle: reads top-level or raw key', () {
    final top = RemoteSettingsBundle.fromApiMap({
      AppConfig.settingGoldFundLedger: [for (final e in _ledger) e.toJson()],
    });
    expect(top.settings.goldFundLedger.length, 3);
    expect(top.presentKeys, contains(AppConfig.settingGoldFundLedger));
    final raw = RemoteSettingsBundle.fromApiMap({
      'raw': {AppConfig.settingGoldFundLedger: GoldCashLedger.encode(_ledger)},
    });
    expect(raw.settings.goldFundLedger.map((e) => e.id), ['gc_1', 'gc_2', 'gc_3']);
  });

  test('PUT echo: older server without the key keeps what was sent', () {
    final sent = AppSettings(goldFundLedger: _ledger);
    final old = RemoteSettingsBundle.fromApiMap({'usdt_tmn_rate': 100000});
    expect(settingsMismatches(sent: sent, echoed: old), isEmpty);
    expect(old.mergePreserving(sent: sent).settings.goldFundLedger.length, 3);

    // New server echoes it back.
    final echo = RemoteSettingsBundle.fromApiMap({
      AppConfig.settingGoldFundLedger: [for (final e in _ledger) e.toJson()],
    });
    expect(settingsMismatches(sent: sent, echoed: echo), isEmpty);
    expect(echo.mergePreserving(sent: sent).settings.goldFundLedger.length, 3);

    // Server that has the key but dropped rows is a mismatch.
    final lossy = RemoteSettingsBundle.fromApiMap({
      AppConfig.settingGoldFundLedger: [_ledger.first.toJson()],
    });
    expect(settingsMismatches(sent: sent, echoed: lossy), contains('نقد صندوق طلا'));
  });

  test('backup: ledger and hidden [gf] notes survive', () {
    final p = BackupService.buildFromMemory(
      settings: AppSettings(goldFundLedger: _ledger),
      assets: const [],
      openTrades: const [],
      closedTrades: const [],
      withdrawals: const [],
    );
    final back = BackupPayload.fromJson(p.toJson());
    expect(GoldCashLedger.same(back.settings.goldFundLedger, _ledger), isTrue);

    // Typed settings empty (older writer) → filled from the raw table.
    final j = p.toJson();
    (j['settings'] as Map).remove(AppConfig.settingGoldFundLedger);
    j['settings_raw'] = {AppConfig.settingGoldFundLedger: GoldCashLedger.encode(_ledger)};
    expect(BackupPayload.fromJson(j).settings.goldFundLedger.length, 3);
  });

  test('WallGold sides: bid/ask from last buy/sell prints', () {
    Map<String, dynamic> body(Map<String, dynamic> cap) => {
          'result': [
            {'symbol': 'GLD_18C_750TMN', 'marketCap': cap},
          ],
        };
    final q = GoldQuoteParser.fromWallGold(body({
      'lastPrice': '14280000',
      'lastBuyPrice': '14350000',
      'lastSellPrice': '14210000',
    }))!;
    expect(q.priceToman, 14280000);
    expect(q.bidToman, 14210000);
    expect(q.askToman, 14350000);
    final one = GoldQuoteParser.fromWallGold(body({'lastPrice': '14280000', 'lastBuyPrice': '14350000'}))!;
    expect(one.bidToman, isNull);
    expect(one.askToman, isNull);
    final none = GoldQuoteParser.fromWallGold(body({'lastPrice': '14280000'}))!;
    expect(none.bidToman, isNull);
    final tgju = GoldQuoteParser.fromTgju({
      'current': {
        'geram18': {'p': '142,800,000'},
      },
    })!;
    expect(tgju.bidToman, isNull);
    expect(tgju.askToman, isNull);
  });
}

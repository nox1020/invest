import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/services/backup_payload.dart';
import 'package:invest/domain/services/backup_service.dart';
import 'package:invest/domain/services/pwo_ledger.dart';

void main() {
  test('PWO backup keeps base amounts and single withdrawals separately', () {
    final l = PwoLedger(people: [PwoPerson(id: 'p0', name: 'M')]);
    l.months[pwoMonthKey(1405, 2)] = PwoMonth(
        year: 1405, month: 2, amounts: {'p0': 10},
        txs: [PwoTx(id: 1, personId: 'p0', amount: 5, note: 'n')]);
    final b = l.toBackupPayload();
    expect(b['entries'], [
      {'withdrawer': 'M', 'year': 1405, 'month': 2, 'amount': 10.0}
    ]);
    expect((b['transactions'] as List).single['amount'], 5.0);
    expect(b['overwrite'], isFalse);
  });

  test('v4 payload round-trips pwo + biz; v3 backups still load', () {
    final p = BackupService.buildFromMemory(
      settings: AppSettings(),
      assets: const [],
      openTrades: const [],
      closedTrades: const [],
      withdrawals: const [],
      pwo: {'entries': [], 'transactions': []},
      biz: {
        'trades': [
          {'buy_date': '1405/01/20', 'buy_amount': 1}
        ],
        'months': []
      },
    );
    final j = p.toJson();
    expect(j['format_version'], 4);
    expect((j['meta'] as Map)['includes'], containsAll(['pwo', 'biz']));
    final back = BackupPayload.fromJson(j);
    expect((back.biz!['trades'] as List).single['buy_date'], '1405/01/20');
    expect(back.pwo, isNotNull);
    final v3 = Map<String, dynamic>.from(j)
      ..remove('pwo')
      ..remove('biz')
      ..['format_version'] = 3;
    final old = BackupPayload.fromJson(v3);
    expect(old.pwo, isNull);
    expect(old.biz, isNull);
  });
}

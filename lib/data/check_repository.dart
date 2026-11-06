import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/check_payment.dart';
import 'package:sqflite/sqflite.dart';

class CheckRepository {
  CheckRepository(this._db);
  final Database _db;

  static const createSql = '''
CREATE TABLE IF NOT EXISTS checks (
  id INTEGER PRIMARY KEY,
  direction TEXT NOT NULL,
  amount REAL NOT NULL,
  issue_date TEXT NOT NULL,
  due_date TEXT NOT NULL,
  check_number TEXT NOT NULL DEFAULT '',
  sayad_id TEXT NOT NULL DEFAULT '',
  bank_name TEXT NOT NULL DEFAULT '',
  branch TEXT NOT NULL DEFAULT '',
  counterparty TEXT NOT NULL DEFAULT '',
  purpose TEXT NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT '',
  endorsed_to TEXT NOT NULL DEFAULT '',
  endorsed_for TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  settled_date TEXT,
  archived_at TEXT,
  kind TEXT NOT NULL DEFAULT 'check',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''';

  static const createPaymentsSql = '''
CREATE TABLE IF NOT EXISTS check_payments (
  id INTEGER PRIMARY KEY,
  check_id INTEGER NOT NULL,
  amount REAL NOT NULL,
  paid_at TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);
''';

  Future<List<BankCheck>> listAll() async {
    final rows = await _db.query('checks', orderBy: 'due_date ASC, id ASC');
    final payRows = await _db.query(
      'check_payments',
      orderBy: 'paid_at ASC, id ASC',
    );
    final byCheck = <int, List<CheckPayment>>{};
    for (final row in payRows) {
      final payment = CheckPayment.fromMap(row);
      byCheck.putIfAbsent(payment.checkId, () => <CheckPayment>[]).add(payment);
    }
    return [
      for (final row in rows)
        BankCheck.fromMap(row).copyWith(
          payments: byCheck[row['id']] ?? const <CheckPayment>[],
        ),
    ];
  }

  /// Replace cheque rows without wiping payment history for rows that
  /// return without a nested `payments` list (typical after a remote sync).
  Future<void> replaceAll(List<BankCheck> items) async {
    await _db.transaction((txn) async {
      final existing = await txn.query('checks', columns: ['id']);
      final newIds = <int>{
        for (final item in items)
          if (item.id != null) item.id!,
      };
      final removedIds = <int>[
        for (final row in existing)
          if (row['id'] is int && !newIds.contains(row['id'])) row['id'] as int,
      ];
      if (removedIds.isNotEmpty) {
        final placeholders = List.filled(removedIds.length, '?').join(',');
        await txn.delete(
          'check_payments',
          where: 'check_id IN ($placeholders)',
          whereArgs: removedIds,
        );
      }
      await txn.delete('checks');
      for (final item in items) {
        if (item.id == null) continue;
        await txn.insert('checks', item.toRow());
        if (item.payments.isEmpty) continue;
        await txn.delete(
          'check_payments',
          where: 'check_id = ?',
          whereArgs: [item.id],
        );
        for (final payment in item.payments) {
          final row = payment.toMap();
          row['check_id'] = item.id;
          await txn.insert('check_payments', row);
        }
      }
    });
  }
}

import 'package:invest/domain/models/bank_check.dart';
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
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''';

  Future<List<BankCheck>> listAll() async {
    final rows = await _db.query('checks', orderBy: 'due_date ASC, id ASC');
    return rows.map(BankCheck.fromMap).toList();
  }

  Future<void> replaceAll(List<BankCheck> items) async {
    await _db.transaction((txn) async {
      await txn.delete('checks');
      for (final item in items) {
        if (item.id == null) continue;
        await txn.insert('checks', item.toMap());
      }
    });
  }
}

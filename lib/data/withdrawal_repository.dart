import 'package:sqflite/sqflite.dart';

import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/utils/dates.dart';

class WithdrawalRepository {
  WithdrawalRepository(this._db);
  final Database _db;

  Future<List<Withdrawal>> listAll() async {
    final rows = await _db.query(
      'withdrawals',
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(Withdrawal.fromMap).toList();
  }

  Future<double> totalCompleted() async {
    final row = await _db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) AS t FROM withdrawals WHERE status != 'rejected'",
    );
    return (row.first['t'] as num?)?.toDouble() ?? 0;
  }

  Future<Withdrawal> create(Withdrawal item) async {
    item.createdAt = item.createdAt.isEmpty ? nowIso() : item.createdAt;
    if (item.status.isEmpty) item.status = 'completed';
    final id = await _db.insert('withdrawals', item.toMap());
    item.id = id;
    return item;
  }

  /// Updates an existing row. Inserts it when the id is not in this database yet.
  Future<Withdrawal> update(Withdrawal item) async {
    if (item.id == null) {
      throw ArgumentError('شناسه برداشت نامعتبر است.');
    }
    if (item.createdAt.trim().isEmpty) item.createdAt = nowIso();
    if (item.status.trim().isEmpty) item.status = 'completed';
    final changed = await _db.update(
      'withdrawals',
      {
        'amount': item.amount,
        'note': item.note,
        'status': item.status,
        'created_at': item.createdAt,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
    if (changed == 0) {
      await _db.insert(
        'withdrawals',
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return item;
  }
}

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
}

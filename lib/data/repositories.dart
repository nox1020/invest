import 'package:sqflite/sqflite.dart';

import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/utils/dates.dart';

class AssetRepository {
  AssetRepository(this._db);
  final Database _db;

  Future<List<Asset>> listAll() async {
    final rows = await _db.query('assets', orderBy: 'name COLLATE NOCASE');
    return rows.map(Asset.fromMap).toList();
  }

  Future<Asset?> get(int id) async {
    final rows = await _db.query('assets', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Asset.fromMap(rows.first);
  }

  Future<Asset?> findByNameSymbol(String name, String symbol) async {
    final rows = await _db.query(
      'assets',
      where: 'name = ? AND symbol = ?',
      whereArgs: [name, symbol],
    );
    if (rows.isEmpty) return null;
    return Asset.fromMap(rows.first);
  }

  Future<Asset> create(Asset asset) async {
    final stamp = nowIso();
    asset.createdAt = stamp;
    asset.updatedAt = stamp;
    final id = await _db.insert('assets', asset.toMap());
    asset.id = id;
    return asset;
  }

  Future<void> update(Asset asset) async {
    asset.updatedAt = nowIso();
    await _db.update(
      'assets',
      asset.toMap(),
      where: 'id = ?',
      whereArgs: [asset.id],
    );
  }

  Future<void> delete(int id) async {
    await _db.delete('assets', where: 'id = ?', whereArgs: [id]);
  }
}

class TradeRepository {
  TradeRepository(this._db);
  final Database _db;

  static const _joinSelect = '''
SELECT t.*, a.name AS asset_name, a.symbol AS asset_symbol,
       a.current_price AS current_price
FROM trades t
JOIN assets a ON a.id = t.asset_id
''';

  Future<List<Trade>> listByStatus(String status) async {
    final rows = await _db.rawQuery(
      '$_joinSelect WHERE t.status = ? ORDER BY '
      "${status == 'open' ? 't.buy_date' : 't.sell_date'} DESC, t.id DESC",
      [status],
    );
    return rows.map(Trade.fromMap).toList();
  }

  Future<List<Trade>> listOpen() => listByStatus('open');
  Future<List<Trade>> listClosed() => listByStatus('closed');

  Future<Trade?> get(int id) async {
    final rows = await _db.rawQuery('$_joinSelect WHERE t.id = ?', [id]);
    if (rows.isEmpty) return null;
    return Trade.fromMap(rows.first);
  }

  Future<List<Trade>> listByAsset(int assetId, String status) async {
    final rows = await _db.rawQuery(
      '$_joinSelect WHERE t.asset_id = ? AND t.status = ?',
      [assetId, status],
    );
    return rows.map(Trade.fromMap).toList();
  }

  Future<Trade> create(Trade trade) async {
    final stamp = nowIso();
    trade.createdAt = stamp;
    trade.updatedAt = stamp;
    final id = await _db.insert('trades', trade.toMap());
    trade.id = id;
    return (await get(id))!;
  }

  Future<void> update(Trade trade) async {
    trade.updatedAt = nowIso();
    await _db.update(
      'trades',
      trade.toMap(),
      where: 'id = ?',
      whereArgs: [trade.id],
    );
  }

  Future<void> delete(int id) async {
    await _db.delete('trades', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, double>> closedStats() async {
    final row = await _db.rawQuery('''
SELECT
  COALESCE(SUM(realized_pnl), 0) AS total_pnl,
  COALESCE(MAX(realized_pnl), 0) AS max_profit,
  COALESCE(MIN(realized_pnl), 0) AS max_loss,
  COUNT(*) AS cnt
FROM trades WHERE status = 'closed'
''');
    final r = row.first;
    return {
      'total_pnl': (r['total_pnl'] as num).toDouble(),
      'max_profit': (r['max_profit'] as num).toDouble(),
      'max_loss': (r['max_loss'] as num).toDouble(),
      'count': (r['cnt'] as num).toDouble(),
    };
  }

  Future<int> countByStatus(String status) async {
    final row = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM trades WHERE status = ?',
      [status],
    );
    return (row.first['c'] as int?) ?? 0;
  }
}

class SettingsRepository {
  SettingsRepository(this._db);
  final Database _db;

  Future<Map<String, String>> loadAll() async {
    final rows = await _db.query('settings');
    return {
      for (final r in rows) (r['key'] as String): (r['value'] as String),
    };
  }

  Future<void> set(String key, String value) async {
    await _db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveMap(Map<String, String> values) async {
    final batch = _db.batch();
    values.forEach((k, v) {
      batch.insert(
        'settings',
        {'key': k, 'value': v},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }
}

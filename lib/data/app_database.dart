import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:invest/config/app_config.dart';
import 'package:invest/domain/utils/dates.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  /// For unit tests with an in-memory / ffi database.
  Future<void> bind(Database db) async {
    _db = db;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'invest.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await _createSchema(db);
        await _seedSettings(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createWithdrawalsTable(db);
        }
      },
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS assets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  symbol TEXT NOT NULL DEFAULT '',
  quantity REAL NOT NULL DEFAULT 0,
  avg_buy_price REAL NOT NULL DEFAULT 0,
  current_price REAL NOT NULL DEFAULT 0,
  notes TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS trades (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  asset_id INTEGER NOT NULL,
  status TEXT NOT NULL,
  quantity REAL NOT NULL,
  buy_price REAL NOT NULL,
  buy_fee REAL NOT NULL DEFAULT 0,
  buy_date TEXT NOT NULL,
  buy_note TEXT NOT NULL DEFAULT '',
  sell_price REAL,
  sell_fee REAL NOT NULL DEFAULT 0,
  sell_date TEXT,
  sell_note TEXT NOT NULL DEFAULT '',
  realized_pnl REAL,
  return_pct REAL,
  holding_days INTEGER,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
);
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
);
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS capital_snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL UNIQUE,
  total_value REAL NOT NULL,
  created_at TEXT NOT NULL
);
''');
    await _createWithdrawalsTable(db);
  }

  static Future<void> _createWithdrawalsTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS withdrawals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  amount REAL NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'completed',
  created_at TEXT NOT NULL
);
''');
  }

  static Future<void> _seedSettings(Database db) async {
    final batch = db.batch();
    AppConfig.defaultSettings.forEach((k, v) {
      batch.insert(
        'settings',
        {'key': k, 'value': v},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
    await batch.commit(noResult: true);
  }

  /// Create schema on an arbitrary db (tests).
  static Future<void> migrateFresh(Database db) async {
    await _createSchema(db);
    await _seedSettings(db);
  }

  static String stamp() => nowIso();
}

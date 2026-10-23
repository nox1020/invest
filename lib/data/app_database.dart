import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:invest/config/app_config.dart';
import 'package:invest/data/check_repository.dart';
import 'package:invest/data/local_platform.dart';
import 'package:invest/domain/utils/dates.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  /// Test hook. When set, opening skips path_provider and uses this instead.
  @visibleForTesting
  Future<Database> Function()? debugOpenDatabase;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    _db = null;
    _db = await _openRecovering();
    return _db!;
  }

  /// For unit tests with an in-memory / ffi database.
  Future<void> bind(Database db) async {
    _db = db;
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    debugOpenDatabase = null;
    if (db == null) return;
    try {
      await db.close();
    } catch (e, st) {
      logLocalFailure('sqlite-close', e, st);
    }
  }

  /// A corrupt or unreadable cache file is deleted and created again.
  /// Server data is not touched. Callers still have to tolerate a second failure.
  Future<void> discardBroken() async {
    final db = _db;
    _db = null;
    if (db != null) {
      try {
        await db.close();
      } catch (e, st) {
        logLocalFailure('sqlite-close', e, st);
      }
    }
    await _deleteLocalFiles();
    try {
      _db = await _openOnce();
    } catch (e, st) {
      _db = null;
      logLocalFailure('sqlite-reopen', e, st);
    }
  }

  Future<Database> _openRecovering() async {
    try {
      return await _openOnce();
    } catch (e, st) {
      logLocalFailure('sqlite-open', e, st);
      await _deleteLocalFiles();
      try {
        return await _openOnce();
      } catch (e2, st2) {
        logLocalFailure('sqlite-reopen', e2, st2);
        Error.throwWithStackTrace(e2, st2);
      }
    }
  }

  Future<Database> _openOnce() {
    final hook = debugOpenDatabase;
    if (hook != null) return hook();
    return _open();
  }

  Future<void> _deleteLocalFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      await deleteDatabase(p.join(dir.path, 'invest.db'));
    } catch (e, st) {
      logLocalFailure('sqlite-delete', e, st);
    }
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'invest.db');
    return openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await _createSchema(db);
        await _seedSettings(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createWithdrawalsTable(db);
        }
        if (oldVersion < 3) {
          await _addBuyPriceUsdColumn(db);
        }
        if (oldVersion < 4) {
          await ensureChecksTable(db);
        }
        if (oldVersion < 5) {
          await addCheckArchiveColumn(db);
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
  buy_price_usd REAL,
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
    await ensureChecksTable(db);
  }

  static Future<void> ensureChecksTable(DatabaseExecutor db) async {
    await db.execute(CheckRepository.createSql);
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_checks_due ON checks(due_date)',
    );
  }

  /// Additive: a nullable column; existing cheques keep every field.
  static Future<void> addCheckArchiveColumn(DatabaseExecutor db) async {
    try {
      await db.execute('ALTER TABLE checks ADD COLUMN archived_at TEXT');
    } catch (_) {
      // Column already present (fresh v4 table created with it).
    }
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

  static Future<void> _addBuyPriceUsdColumn(Database db) async {
    try {
      await db.execute('ALTER TABLE trades ADD COLUMN buy_price_usd REAL');
    } catch (_) {
      // Column already present.
    }
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

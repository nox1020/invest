import 'dart:convert';
import 'dart:typed_data';

import 'package:invest/config/app_config.dart';
import 'package:invest/data/app_lock_store.dart';
import 'package:invest/data/offline_cache_store.dart';
import 'package:invest/data/repositories.dart';
import 'package:invest/data/withdrawal_repository.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/backup_payload.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/security/backup_crypto.dart';
import 'package:sqflite/sqflite.dart';

/// Builds / restores encrypted full-app backups.
class BackupService {
  static const fileExtension = 'vplusbak';
  static const mimeType = 'application/octet-stream';

  static Uint8List encode(BackupPayload payload, {int? iterations}) {
    final json = const JsonEncoder.withIndent('  ').convert(payload.toJson());
    return BackupCrypto.encryptUtf8(json, iterations: iterations);
  }

  static BackupPayload decode(Uint8List bytes) {
    final text = BackupCrypto.decryptToUtf8(bytes);
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('محتوای پشتیبان نامعتبر است.');
    }
    return BackupPayload.fromJson(Map<String, dynamic>.from(decoded));
  }

  static BackupPayload buildFromMemory({
    required AppSettings settings,
    required List<Asset> assets,
    required List<Trade> openTrades,
    required List<Trade> closedTrades,
    required List<Withdrawal> withdrawals,
    List<Map<String, Object?>> capitalSnapshots = const [],
    Map<String, String>? settingsRaw,
    String? appLockHash,
    bool biometricUnlockEnabled = false,
    String? userPhone,
    String? baseUrl,
  }) {
    final raw = Map<String, String>.from(settingsRaw ?? settings.toStorageMap());
    // Ensure typed settings always win for known keys.
    raw.addAll(settings.toStorageMap());
    return BackupPayload(
      exportedAt: nowIso(),
      settings: settings,
      settingsRaw: raw,
      assets: List<Asset>.from(assets),
      trades: [...openTrades, ...closedTrades],
      withdrawals: List<Withdrawal>.from(withdrawals),
      capitalSnapshots: capitalSnapshots,
      appLockHash: appLockHash,
      biometricUnlockEnabled: biometricUnlockEnabled,
      userPhone: userPhone,
      baseUrl: baseUrl,
    );
  }

  /// Wipe and rewrite local SQLite with [payload] (preserves original IDs).
  static Future<void> restoreLocalDatabase(
    Database db,
    BackupPayload payload,
  ) async {
    await db.transaction((txn) async {
      await txn.delete('trades');
      await txn.delete('withdrawals');
      await txn.delete('capital_snapshots');
      await txn.delete('assets');
      await txn.delete('settings');

      for (final e in AppConfig.defaultSettings.entries) {
        await txn.insert('settings', {'key': e.key, 'value': e.value});
      }
      final settingsMap = <String, String>{
        ...payload.settings.toStorageMap(),
        ...payload.settingsRaw,
        ...payload.settings.toStorageMap(),
      };
      for (final e in settingsMap.entries) {
        await txn.insert(
          'settings',
          {'key': e.key, 'value': e.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      for (final a in payload.assets) {
        final row = a.toMap();
        // Keep original id when present so trade FKs stay valid.
        await txn.insert('assets', row);
      }

      for (final t in payload.trades) {
        final row = Map<String, Object?>.from(t.toMap());
        // Drop join-only fields if any leaked.
        row.remove('asset_name');
        row.remove('asset_symbol');
        row.remove('current_price');
        await txn.insert('trades', row);
      }

      for (final w in payload.withdrawals) {
        await txn.insert('withdrawals', w.toMap());
      }

      for (final s in payload.capitalSnapshots) {
        final row = <String, Object?>{
          if (s['id'] != null) 'id': s['id'],
          'date': s['date'] ?? todayIso(),
          'total_value': s['total_value'] ?? 0,
          'created_at': s['created_at'] ?? nowIso(),
        };
        await txn.insert('capital_snapshots', row);
      }

      // Keep AUTOINCREMENT ahead of restored IDs to avoid collisions.
      await _syncSqliteSequence(txn, 'assets');
      await _syncSqliteSequence(txn, 'trades');
      await _syncSqliteSequence(txn, 'withdrawals');
      await _syncSqliteSequence(txn, 'capital_snapshots');
    });
  }

  static Future<void> _syncSqliteSequence(Transaction txn, String table) async {
    try {
      final row = await txn.rawQuery('SELECT MAX(id) AS m FROM $table');
      final maxId = (row.first['m'] as num?)?.toInt() ?? 0;
      if (maxId <= 0) return;
      final existing = await txn.rawQuery(
        'SELECT seq FROM sqlite_sequence WHERE name = ?',
        [table],
      );
      if (existing.isEmpty) {
        await txn.rawInsert(
          'INSERT INTO sqlite_sequence(name, seq) VALUES(?, ?)',
          [table, maxId],
        );
      } else {
        await txn.rawUpdate(
          'UPDATE sqlite_sequence SET seq = ? WHERE name = ?',
          [maxId, table],
        );
      }
    } catch (_) {
      // sqlite_sequence is absent until AUTOINCREMENT is used at least once.
    }
  }

  static Future<List<Map<String, Object?>>> loadCapitalSnapshots(
    Database db,
  ) async {
    final rows = await db.query('capital_snapshots', orderBy: 'date ASC');
    return rows.map((r) => Map<String, Object?>.from(r)).toList();
  }

  static Future<void> restoreAppLock(BackupPayload payload) async {
    final hash = payload.appLockHash?.trim();
    if (hash == null || hash.isEmpty) {
      await AppLockStore.saveHash('');
      await AppLockStore.saveBiometricEnabled(false);
      return;
    }
    await AppLockStore.saveHash(hash);
    await AppLockStore.saveBiometricEnabled(payload.biometricUnlockEnabled);
  }

  static Future<void> saveOfflineCache({
    required BackupPayload payload,
    DashboardMetrics? metrics,
  }) async {
    await OfflineCacheStore.savePortfolio(
      settings: payload.settings,
      metrics: metrics ??
          DashboardMetrics(
            totalValue: 0,
            totalPnl: 0,
            totalPnlPct: 0,
            realizedPnl: 0,
            unrealizedPnl: 0,
            openCount: payload.openTradeCount,
            closedCount: payload.closedTradeCount,
            yearRealizedPnl: 0,
            yearKey: yearPeriodKey(todayIso(), payload.settings.calendar),
            goldFund: const GoldFundMetrics(
              goldInG: 0,
              goldOutG: 0,
              goldHoldingG: 0,
            ),
          ),
      assets: payload.assets,
      openTrades: payload.trades
          .where((t) => t.status == AppConfig.tradeOpen)
          .toList(),
      closedTrades: payload.trades
          .where((t) => t.status == AppConfig.tradeClosed)
          .toList(),
      withdrawals: payload.withdrawals,
      liveUsdt: payload.settings.usdtTmnRate,
      liveGold: payload.settings.goldTmnPerGram,
    );
  }

  /// Convenience for tests / local-only apps after restore.
  static Future<({List<Asset> assets, List<Trade> open, List<Trade> closed, List<Withdrawal> withdrawals})>
      readLocalPortfolio(Database db) async {
    final assets = AssetRepository(db);
    final trades = TradeRepository(db);
    final withdrawals = WithdrawalRepository(db);
    return (
      assets: await assets.listAll(),
      open: await trades.listOpen(),
      closed: await trades.listClosed(),
      withdrawals: await withdrawals.listAll(),
    );
  }
}

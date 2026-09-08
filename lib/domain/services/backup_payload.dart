import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/utils/dates.dart';

const backupFormatId = 'vplus-backup';

/// Current writer version. Readers accept 1..[backupFormatVersion].
const backupFormatVersion = 2;

/// Full portable snapshot of app data (before encryption).
class BackupPayload {
  BackupPayload({
    required this.exportedAt,
    required this.settings,
    required this.assets,
    required this.trades,
    required this.withdrawals,
    this.capitalSnapshots = const <Map<String, Object?>>[],
    this.settingsRaw = const <String, String>{},
    this.appLockHash,
    this.biometricUnlockEnabled = false,
    this.userPhone,
    this.baseUrl,
  });

  final String exportedAt;
  final AppSettings settings;

  /// Complete settings table dump (all keys) for lossless restore.
  final Map<String, String> settingsRaw;
  final List<Asset> assets;
  final List<Trade> trades;
  final List<Withdrawal> withdrawals;
  final List<Map<String, Object?>> capitalSnapshots;
  final String? appLockHash;
  final bool biometricUnlockEnabled;
  final String? userPhone;
  final String? baseUrl;

  int get openTradeCount =>
      trades.where((t) => t.status == AppConfig.tradeOpen).length;
  int get closedTradeCount =>
      trades.where((t) => t.status == AppConfig.tradeClosed).length;

  Map<String, dynamic> toJson() => {
        'format': backupFormatId,
        'format_version': backupFormatVersion,
        'exported_at': exportedAt,
        'app_id': AppConfig.applicationId,
        'app_name': AppConfig.appName,
        'settings': settings.toJson(),
        'settings_raw': settingsRaw,
        'assets': assets.map(_assetToJson).toList(),
        'trades': trades.map(_tradeToJson).toList(),
        'withdrawals': withdrawals.map(_withdrawalToJson).toList(),
        'capital_snapshots': capitalSnapshots,
        'app_lock': {
          'hash': appLockHash,
          'biometric_enabled': biometricUnlockEnabled,
        },
        'meta': {
          'user_phone': userPhone,
          'base_url': baseUrl,
          'includes': const [
            'settings',
            'settings_raw',
            'assets',
            'trades',
            'withdrawals',
            'capital_snapshots',
            'app_lock',
          ],
        },
      };

  static BackupPayload fromJson(Map<String, dynamic> json) {
    final format = json['format'] as String?;
    if (format != backupFormatId) {
      throw const FormatException('قالب پشتیبان نامعتبر است.');
    }
    final ver = (json['format_version'] as num?)?.toInt() ?? 0;
    if (ver < 1 || ver > backupFormatVersion) {
      throw FormatException('نسخه پشتیبان پشتیبانی نمی‌شود ($ver).');
    }
    final appId = json['app_id'] as String?;
    if (appId != null && appId != AppConfig.applicationId) {
      throw const FormatException('این پشتیبان برای اپلیکیشن دیگری است.');
    }

    final settingsMap =
        Map<String, dynamic>.from(json['settings'] as Map? ?? {});
    final lock = Map<String, dynamic>.from(json['app_lock'] as Map? ?? {});
    final meta = Map<String, dynamic>.from(json['meta'] as Map? ?? {});

    final raw = <String, String>{};
    final rawJson = json['settings_raw'];
    if (rawJson is Map) {
      rawJson.forEach((k, v) {
        if (k == null) return;
        raw['$k'] = v == null ? '' : '$v';
      });
    }

    final assets = ((json['assets'] as List?) ?? const [])
        .map((e) => _assetFromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final trades = ((json['trades'] as List?) ?? const [])
        .map((e) => _tradeFromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final withdrawals = ((json['withdrawals'] as List?) ?? const [])
        .map((e) => _withdrawalFromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final snaps = ((json['capital_snapshots'] as List?) ?? const [])
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList();

    final settings = AppSettings.fromJson(settingsMap);
    // Prefer typed settings; fill gaps from raw table when present.
    if (raw.isNotEmpty) {
      final fromRaw = AppSettings.fromStorageMap(raw);
      if (settings.wallexUrl.trim().isEmpty) {
        settings.wallexUrl = fromRaw.wallexUrl;
      }
      if (settings.persianToolboxUrl.trim().isEmpty) {
        settings.persianToolboxUrl = fromRaw.persianToolboxUrl;
      }
      settings.usdtTmnRate ??= fromRaw.usdtTmnRate;
      settings.goldTmnPerGram ??= fromRaw.goldTmnPerGram;
      if (settings.priceAlerts.isEmpty && fromRaw.priceAlerts.isNotEmpty) {
        settings.priceAlerts = fromRaw.priceAlerts;
      }
      if (settings.profitAlerts.isEmpty && fromRaw.profitAlerts.isNotEmpty) {
        settings.profitAlerts = fromRaw.profitAlerts;
      }
      if (!settingsMap.containsKey('notify_background') &&
          raw.containsKey(AppConfig.settingNotifyBackground)) {
        settings.notifyBackground = fromRaw.notifyBackground;
      }
    }

    return BackupPayload(
      exportedAt: (json['exported_at'] as String?) ?? nowIso(),
      settings: settings,
      settingsRaw: raw.isEmpty ? settings.toStorageMap() : raw,
      assets: assets,
      trades: trades,
      withdrawals: withdrawals,
      capitalSnapshots: snaps,
      appLockHash: lock['hash'] as String?,
      biometricUnlockEnabled: lock['biometric_enabled'] == true,
      userPhone: meta['user_phone'] as String?,
      baseUrl: meta['base_url'] as String?,
    );
  }

  static Map<String, dynamic> _assetToJson(Asset a) => {
        'id': a.id,
        'name': a.name,
        'symbol': a.symbol,
        'quantity': a.quantity,
        'avg_buy_price': a.avgBuyPrice,
        'current_price': a.currentPrice,
        'notes': a.notes,
        'created_at': a.createdAt,
        'updated_at': a.updatedAt,
      };

  static Asset _assetFromJson(Map<String, dynamic> m) => Asset.fromMap({
        'id': (m['id'] as num?)?.toInt(),
        'name': m['name'],
        'symbol': m['symbol'],
        'quantity': m['quantity'],
        'avg_buy_price': m['avg_buy_price'],
        'current_price': m['current_price'],
        'notes': m['notes'],
        'created_at': m['created_at'],
        'updated_at': m['updated_at'],
      });

  static Map<String, dynamic> _tradeToJson(Trade t) => {
        'id': t.id,
        'asset_id': t.assetId,
        'status': t.status,
        'quantity': t.quantity,
        'buy_price': t.buyPrice,
        'buy_price_usd': t.buyPriceUsd,
        'buy_fee': t.buyFee,
        'buy_date': t.buyDate,
        'buy_note': t.buyNote,
        'sell_price': t.sellPrice,
        'sell_fee': t.sellFee,
        'sell_date': t.sellDate,
        'sell_note': t.sellNote,
        'realized_pnl': t.realizedPnl,
        'return_pct': t.returnPct,
        'holding_days': t.holdingDays,
        'created_at': t.createdAt,
        'updated_at': t.updatedAt,
        'asset_name': t.assetName,
        'asset_symbol': t.assetSymbol,
        'current_price': t.currentPrice,
      };

  static Trade _tradeFromJson(Map<String, dynamic> m) => Trade.fromMap({
        'id': (m['id'] as num?)?.toInt(),
        'asset_id': (m['asset_id'] as num?)?.toInt() ?? 0,
        'status': m['status'],
        'quantity': m['quantity'],
        'buy_price': m['buy_price'],
        'buy_price_usd': m['buy_price_usd'],
        'buy_fee': m['buy_fee'],
        'buy_date': m['buy_date'],
        'buy_note': m['buy_note'],
        'sell_price': m['sell_price'],
        'sell_fee': m['sell_fee'],
        'sell_date': m['sell_date'],
        'sell_note': m['sell_note'],
        'realized_pnl': m['realized_pnl'],
        'return_pct': m['return_pct'],
        'holding_days': (m['holding_days'] as num?)?.toInt(),
        'created_at': m['created_at'],
        'updated_at': m['updated_at'],
        'asset_name': m['asset_name'],
        'asset_symbol': m['asset_symbol'],
        'current_price': m['current_price'],
      });

  static Map<String, dynamic> _withdrawalToJson(Withdrawal w) => {
        'id': w.id,
        'amount': w.amount,
        'note': w.note,
        'status': w.status,
        'created_at': w.createdAt,
      };

  static Withdrawal _withdrawalFromJson(Map<String, dynamic> m) =>
      Withdrawal.fromMap({
        'id': (m['id'] as num?)?.toInt(),
        'amount': m['amount'],
        'note': m['note'],
        'status': m['status'],
        'created_at': m['created_at'],
      });
}

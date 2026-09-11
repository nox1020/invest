import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/iran_inflation.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';

/// Last-known portfolio snapshot for offline boot (read-only remote cache).
class OfflineCacheStore {
  static const _keySnapshot = 'offline_portfolio_snapshot_v1';
  static const _keyCommodities = 'offline_commodity_index_v2';
  static const _keyWallex = 'offline_wallex_markets_v1';
  static const _keyInflation = 'offline_iran_inflation_v1';

  static Future<void> savePortfolio({
    required AppSettings settings,
    required DashboardMetrics metrics,
    required List<Asset> assets,
    required List<Trade> openTrades,
    required List<Trade> closedTrades,
    List<Withdrawal> withdrawals = const [],
    double? liveUsdt,
    double? liveGold,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'saved_at': DateTime.now().toIso8601String(),
      'settings': settings.toJson(),
      'metrics': {
        'total_value': metrics.totalValue,
        'total_pnl': metrics.totalPnl,
        'total_pnl_pct': metrics.totalPnlPct,
        'realized_pnl': metrics.realizedPnl,
        'unrealized_pnl': metrics.unrealizedPnl,
        'open_count': metrics.openCount,
        'closed_count': metrics.closedCount,
        'year_realized_pnl': metrics.yearRealizedPnl,
        'year_key': metrics.yearKey,
        'gold_in_g': metrics.goldFund.goldInG,
        'gold_out_g': metrics.goldFund.goldOutG,
        'gold_holding_g': metrics.goldFund.goldHoldingG,
        'growth_series':
            metrics.growthSeries.map((p) => p.toJson()).toList(),
      },
      'assets': assets.map(_assetJson).toList(),
      'open_trades': openTrades.map(_tradeJson).toList(),
      'closed_trades': closedTrades.map(_tradeJson).toList(),
      'withdrawals': withdrawals.map(_withdrawalJson).toList(),
      'live_usdt': liveUsdt,
      'live_gold': liveGold,
    };
    await prefs.setString(_keySnapshot, jsonEncode(payload));
  }

  static Future<OfflinePortfolioSnapshot?> loadPortfolio() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySnapshot);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final s = Map<String, dynamic>.from(map['settings'] as Map? ?? {});
      final m = Map<String, dynamic>.from(map['metrics'] as Map? ?? {});
      final settings = AppSettings.fromJson(s);
      final metrics = DashboardMetrics(
        totalValue: _d(m['total_value']),
        totalPnl: _d(m['total_pnl']),
        totalPnlPct: _d(m['total_pnl_pct']),
        realizedPnl: _d(m['realized_pnl']),
        unrealizedPnl: _d(m['unrealized_pnl']),
        openCount: (m['open_count'] as num?)?.toInt() ?? 0,
        closedCount: (m['closed_count'] as num?)?.toInt() ?? 0,
        yearRealizedPnl: _d(m['year_realized_pnl']),
        yearKey: (m['year_key'] as String?) ?? '',
        goldFund: GoldFundMetrics(
          goldInG: _d(m['gold_in_g']),
          goldOutG: _d(m['gold_out_g']),
          goldHoldingG: _d(m['gold_holding_g']),
        ),
        growthSeries: SeriesPoint.fromJsonList(
          m['growth_series'] ?? map['growth_series'],
        ),
      );
      final assets = ((map['assets'] as List?) ?? const [])
          .map((e) => Asset.fromMap(_toObjMap(e as Map)))
          .toList();
      final open = ((map['open_trades'] as List?) ?? const [])
          .map((e) => Trade.fromMap(_toObjMap(e as Map)))
          .toList();
      final closed = ((map['closed_trades'] as List?) ?? const [])
          .map((e) => Trade.fromMap(_toObjMap(e as Map)))
          .toList();
      final withdrawals = ((map['withdrawals'] as List?) ?? const [])
          .map((e) => Withdrawal.fromMap(_toObjMap(e as Map)))
          .toList();
      return OfflinePortfolioSnapshot(
        savedAt: DateTime.tryParse(map['saved_at'] as String? ?? ''),
        settings: settings,
        metrics: metrics,
        assets: assets,
        openTrades: open,
        closedTrades: closed,
        withdrawals: withdrawals,
        liveUsdt: (map['live_usdt'] as num?)?.toDouble(),
        liveGold: (map['live_gold'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> hasPortfolioCache() async {
    final snap = await loadPortfolio();
    return snap != null;
  }

  static Future<void> saveCommodities(
    List<CommodityQuote> quotes, {
    List<CommodityQuote> wallexMarkets = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCommodities, jsonEncode(_quotesPayload(quotes)));
    await prefs.setString(
      _keyWallex,
      jsonEncode(_quotesPayload(wallexMarkets)),
    );
  }

  static Map<String, dynamic> _quotesPayload(List<CommodityQuote> quotes) => {
        'saved_at': DateTime.now().toIso8601String(),
        'items': quotes.map((q) => q.toJson()).toList(),
      };

  static Future<void> saveIranInflation(IranInflationSnapshot snap) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyInflation, jsonEncode(snap.toJson()));
  }

  static Future<IranInflationSnapshot?> loadIranInflation() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyInflation);
    if (raw == null || raw.isEmpty) return null;
    try {
      return IranInflationSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<OfflineCommoditySnapshot?> loadCommodities() async {
    final prefs = await SharedPreferences.getInstance();
    final essentials = _decodeQuotes(prefs.getString(_keyCommodities));
    final wallex = _decodeQuotes(prefs.getString(_keyWallex));
    if (essentials == null && wallex == null) return null;
    return OfflineCommoditySnapshot(
      savedAt: essentials?.savedAt ?? wallex?.savedAt,
      quotes: essentials?.quotes ?? const [],
      wallexMarkets: wallex?.quotes ?? const [],
    );
  }

  static OfflineCommoditySnapshot? _decodeQuotes(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final items = ((map['items'] as List?) ?? const [])
          .map((e) {
            try {
              return CommodityQuote.fromJson(
                Map<String, dynamic>.from(e as Map),
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<CommodityQuote>()
          .toList();
      if (items.isEmpty) return null;
      return OfflineCommoditySnapshot(
        savedAt: DateTime.tryParse(map['saved_at'] as String? ?? ''),
        quotes: items,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?> _toObjMap(Map raw) =>
      raw.map((k, v) => MapEntry(k.toString(), v as Object?));

  static Map<String, dynamic> _assetJson(Asset a) => {
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

  static Map<String, dynamic> _tradeJson(Trade t) => {
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

  static Map<String, dynamic> _withdrawalJson(Withdrawal w) => {
        'id': w.id,
        'amount': w.amount,
        'note': w.note,
        'status': w.status,
        'created_at': w.createdAt,
      };

  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
}

class OfflinePortfolioSnapshot {
  OfflinePortfolioSnapshot({
    required this.savedAt,
    required this.settings,
    required this.metrics,
    required this.assets,
    required this.openTrades,
    required this.closedTrades,
    this.withdrawals = const [],
    this.liveUsdt,
    this.liveGold,
  });

  final DateTime? savedAt;
  final AppSettings settings;
  final DashboardMetrics metrics;
  final List<Asset> assets;
  final List<Trade> openTrades;
  final List<Trade> closedTrades;
  final List<Withdrawal> withdrawals;
  final double? liveUsdt;
  final double? liveGold;
}

class OfflineCommoditySnapshot {
  OfflineCommoditySnapshot({
    required this.savedAt,
    required this.quotes,
    this.wallexMarkets = const [],
  });

  final DateTime? savedAt;
  final List<CommodityQuote> quotes;
  final List<CommodityQuote> wallexMarkets;
}

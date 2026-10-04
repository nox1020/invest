import 'dart:convert';

import 'package:invest/config/app_config.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_meta.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/iran_inflation.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/price_alert.dart';
import 'package:invest/domain/models/profit_alert.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/commodity_index_service.dart';
import 'package:invest/domain/services/invest_mutations.dart';
import 'package:invest/domain/utils/buy_usd.dart';
import 'package:invest/domain/utils/dates.dart';

/// Remote asset repository backed by Vinor Invest API.
class RemoteAssetRepository {
  RemoteAssetRepository(this._api);
  final InvestApiClient _api;

  Future<List<Asset>> listAll({String search = ''}) async {
    final query = search.trim().isEmpty ? null : {'q': search.trim()};
    final data = await _api.get('/invest/api/v1/assets', query: query);
    final items = (data['items'] as List?) ?? const [];
    return items
        .map((e) => Asset.fromMap(Map<String, Object?>.from(e as Map)))
        .toList();
  }

  Future<Asset> create(Asset asset) async {
    final data = await _api.post('/invest/api/v1/assets', body: {
      'name': asset.name,
      'symbol': asset.symbol,
      'quantity': asset.quantity,
      'avg_buy_price': asset.avgBuyPrice,
      'current_price': asset.currentPrice,
      'notes': asset.notes,
    });
    return Asset.fromMap(
      Map<String, Object?>.from(data['item'] as Map),
    );
  }

  Future<void> update(Asset asset) async {
    if (asset.id == null) throw ArgumentError('شناسه دارایی نامعتبر است.');
    final data = await _api.put('/invest/api/v1/assets/${asset.id}', body: {
      'name': asset.name,
      'symbol': asset.symbol,
      'quantity': asset.quantity,
      'avg_buy_price': asset.avgBuyPrice,
      'current_price': asset.currentPrice,
      'notes': asset.notes,
    });
    final saved = Asset.fromMap(
      Map<String, Object?>.from(data['item'] as Map),
    );
    asset
      ..name = saved.name
      ..symbol = saved.symbol
      ..quantity = saved.quantity
      ..avgBuyPrice = saved.avgBuyPrice
      ..currentPrice = saved.currentPrice
      ..notes = saved.notes
      ..updatedAt = saved.updatedAt;
  }

  Future<void> delete(int id) async {
    await _api.delete('/invest/api/v1/assets/$id');
  }
}

/// Invest operations via Vinor REST API (mirrors local [TradeService] surface).
class RemoteInvestService implements InvestMutations {
  RemoteInvestService(this._api) : assets = RemoteAssetRepository(_api);

  final InvestApiClient _api;
  final RemoteAssetRepository assets;

  Future<DashboardMetrics> fetchDashboard(String calendar) async {
    final data = await _api.get('/invest/api/v1/dashboard');
    final m = Map<String, dynamic>.from(data['metrics'] as Map);
    final g = Map<String, dynamic>.from(data['gold_fund'] as Map? ?? {});
    return DashboardMetrics(
      totalValue: _num(m['total_value']),
      totalPnl: _num(m['total_pnl']),
      totalPnlPct: _num(m['total_pnl_pct']),
      realizedPnl: _num(m['realized_pnl']),
      unrealizedPnl: _num(m['unrealized_pnl']),
      openCount: (m['open_count'] as num?)?.toInt() ?? 0,
      closedCount: (m['closed_count'] as num?)?.toInt() ?? 0,
      yearRealizedPnl: _num(m['year_realized_pnl']),
      yearKey: yearPeriodKey(todayIso(), calendar),
      goldFund: GoldFundMetrics(
        goldInG: _num(g['gold_in_g']),
        goldOutG: _num(g['gold_out_g']),
        goldHoldingG: _num(g['gold_holding_g']),
      ),
      growthSeries: SeriesPoint.fromJsonList(data['growth_series']),
    );
  }

  Future<List<Trade>> listOpen({String search = ''}) async {
    final query = search.trim().isEmpty ? null : {'q': search.trim()};
    final data = await _api.get('/invest/api/v1/trades/open', query: query);
    return _tradesFrom(data);
  }

  Future<List<Trade>> listClosed({String search = ''}) async {
    final query = search.trim().isEmpty ? null : {'q': search.trim()};
    final data = await _api.get('/invest/api/v1/trades/closed', query: query);
    return _tradesFrom(data);
  }

  Future<RemoteSettingsBundle> fetchSettings() async {
    final data = await _api.get('/invest/api/v1/settings');
    return _bundleFrom(Map<String, dynamic>.from(data['settings'] as Map));
  }

  /// Persist full user prefs to Vinor (typed fields + extras in settings bag).
  Future<RemoteSettingsBundle> saveSettings(
    AppSettings s, {
    List<Withdrawal>? clientWithdrawals,
    String? appLockHash,
    bool? appLockBiometric,
  }) async {
    final body = <String, dynamic>{
      'calendar': s.calendar,
      'currency': s.currency,
      'theme': s.theme,
      'live_prices_enabled': s.livePricesEnabled,
      'usdt_api_enabled': s.usdtApiEnabled,
      'gold_api_enabled': s.goldApiEnabled,
      'notifications_enabled': s.notificationsEnabled,
      'notify_trades': s.notifyTrades,
      'notify_withdrawals': s.notifyWithdrawals,
      'notify_price_moves': s.notifyPriceMoves,
      'notify_background': s.notifyBackground,
      'price_refresh_seconds': s.autoRefreshSeconds,
      'annual_withdrawal_pct': s.annualWithdrawalPct,
      'price_alerts': s.priceAlerts.map((e) => e.toJson()).toList(),
      'profit_alerts': s.profitAlerts.map((e) => e.toJson()).toList(),
    };
    if (s.wallexUrl.trim().isNotEmpty) {
      body['wallex_markets_url'] = s.wallexUrl.trim();
    }
    if (s.persianToolboxUrl.trim().isNotEmpty) {
      body['persiantoolbox_url'] = s.persianToolboxUrl.trim();
    }
    if (s.usdtTmnRate != null) {
      body['usdt_tmn_rate'] = s.usdtTmnRate;
    }
    if (s.goldTmnPerGram != null) {
      body['gold_tmn_per_gram'] = s.goldTmnPerGram;
    }
    if (appLockHash != null) {
      body[AppConfig.settingAppLockHash] = appLockHash;
    }
    if (appLockBiometric != null) {
      body[AppConfig.settingAppLockBiometric] = appLockBiometric;
    }
    if (clientWithdrawals != null) {
      body[AppConfig.settingClientWithdrawals] = clientWithdrawals
          .map(
            (w) => {
              'id': w.id,
              'amount': w.amount,
              'note': w.note,
              'status': w.status,
              'created_at': w.createdAt,
            },
          )
          .toList();
    }
    final data = await _api.put('/invest/api/v1/settings', body: body);
    final bundle =
        _bundleFrom(Map<String, dynamic>.from(data['settings'] as Map));
    return bundle.mergePreserving(
      sent: s,
      clientWithdrawals: clientWithdrawals,
      appLockHash: appLockHash,
      appLockBiometric: appLockBiometric,
    );
  }

  Future<({double? usdt, double? gold})> fetchQuotes() async {
    final data = await _api.get('/invest/api/v1/quotes');
    return (
      usdt: _numOrNull(data['usdt_tmn']),
      gold: _numOrNull(data['gold_tmn_per_gram']),
    );
  }

  /// Full شاخص bundle from Vinor (server fetch + persisted store).
  Future<MarketIndexRemoteBundle?> fetchMarketIndex(
      {bool force = false}) async {
    try {
      final data = await _api.get(
        '/invest/api/v1/markets/index',
        query: force ? {'force': '1'} : null,
        timeout: const Duration(seconds: 20),
      );
      final essentials = CommodityIndexService.alignDerivedQuotes(
        _parseQuotes(data['essentials']),
      );
      final wallex = _parseQuotes(data['wallex_markets']);
      IranInflationSnapshot? inflation;
      final rawInf = data['inflation'];
      if (rawInf is Map) {
        inflation = IranInflationSnapshot.fromJson(
          Map<String, dynamic>.from(rawInf),
        );
      }
      final updated = DateTime.tryParse('${data['updated_at'] ?? ''}');
      final hasPrice = essentials.any((q) => q.price != null) ||
          wallex.any((q) => q.price != null);
      if (!hasPrice && inflation == null) return null;
      return MarketIndexRemoteBundle(
        essentials: essentials,
        wallexMarkets: wallex,
        inflation: inflation,
        updatedAt: updated,
        stale: data['stale'] == true,
        error: data['error'] as String?,
        warning: data['warning'] as String?,
      );
    } on InvestApiException catch (e) {
      // Older servers without /markets/index → fall back to client fetch.
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> pushMarketIndex({
    required List<CommodityQuote> essentials,
    required List<CommodityQuote> wallexMarkets,
    IranInflationSnapshot? inflation,
  }) async {
    final body = <String, dynamic>{
      'essentials': essentials.map((e) => e.toJson()).toList(),
      'wallex_markets': wallexMarkets.map((e) => e.toJson()).toList(),
    };
    if (inflation != null) {
      body['inflation'] = inflation.toJson();
    }
    try {
      await _api.post('/invest/api/v1/markets/index', body: body);
    } on InvestApiException catch (e) {
      if (e.statusCode == 404) return;
      rethrow;
    }
  }

  Future<Asset> createAsset({
    required String name,
    String symbol = '',
    double quantity = 0,
    double avgBuyPrice = 0,
    double currentPrice = 0,
    String notes = '',
    String? buyDate,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('نام دارایی الزامی است.');
    }
    if (quantity < 0) {
      throw ArgumentError('مقدار نمی‌تواند منفی باشد.');
    }
    if (quantity > 0 && avgBuyPrice <= 0) {
      throw ArgumentError('برای موجودی اولیه، قیمت خرید الزامی است.');
    }
    final price = currentPrice > 0 ? currentPrice : avgBuyPrice;
    var asset = await assets.create(Asset(
      name: name.trim(),
      symbol: symbol.trim(),
      quantity: 0,
      avgBuyPrice: 0,
      currentPrice: price,
      notes: notes,
    ));
    if (quantity > 0) {
      if (asset.id == null) {
        throw StateError('ایجاد دارایی روی سرور ناموفق بود.');
      }
      final usd = parseAssetNotes(notes).meta.buyPriceUsd;
      final fx = parseAssetNotes(notes).meta.buyUsdTmn;
      await registerBuy(
        assetId: asset.id,
        quantity: quantity,
        buyPrice: avgBuyPrice,
        buyPriceUsd: (usd != null && usd > 0) ? usd : null,
        buyUsdTmn: (fx != null && fx > 0) ? fx : null,
        buyDate: (buyDate != null && buyDate.trim().isNotEmpty)
            ? buyDate.trim()
            : null,
        buyNote: 'موجودی اولیه',
        currentPrice: price,
      );
      final refreshed = await assets.listAll();
      asset =
          refreshed.firstWhere((a) => a.id == asset.id, orElse: () => asset);
    }
    return asset;
  }

  @override
  Future<void> updateAsset(Asset asset) => assets.update(asset);

  Future<Trade> registerBuy({
    int? assetId,
    String? name,
    String symbol = '',
    required double quantity,
    required double buyPrice,
    double? buyPriceUsd,
    double? buyUsdTmn,
    double buyFee = 0,
    String? buyDate,
    String buyNote = '',
    double? currentPrice,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('مقدار باید بزرگ‌تر از صفر باشد.');
    }
    if (buyPrice <= 0) {
      throw ArgumentError('قیمت خرید باید بزرگ‌تر از صفر باشد.');
    }
    if (buyFee < 0) throw ArgumentError('کارمزد نمی‌تواند منفی باشد.');
    final note = encodeBuyNoteUsd(
      usd: buyPriceUsd,
      fx: buyUsdTmn,
      note: buyNote,
    );
    final body = <String, dynamic>{
      'quantity': quantity,
      'buy_price': buyPrice,
      'buy_fee': buyFee,
      'buy_note': note,
      'symbol': symbol,
    };
    if (buyPriceUsd != null && buyPriceUsd > 0) {
      body['buy_price_usd'] = buyPriceUsd;
    }
    if (assetId != null) body['asset_id'] = assetId;
    if (name != null && name.trim().isNotEmpty) body['name'] = name.trim();
    if (buyDate != null) body['buy_date'] = buyDate;
    if (currentPrice != null) body['current_price'] = currentPrice;

    final data = await _api.post('/invest/api/v1/trades/buy', body: body);
    return Trade.fromMap(Map<String, Object?>.from(data['item'] as Map));
  }

  Future<Trade> updateOpenTrade({
    required int tradeId,
    required double quantity,
    required double buyPrice,
    double? buyPriceUsd,
    double? buyUsdTmn,
    double buyFee = 0,
    String? buyDate,
    String? buyNote,
  }) async {
    final body = <String, dynamic>{
      'quantity': quantity,
      'buy_price': buyPrice,
      'buy_fee': buyFee,
    };
    if (buyDate != null && buyDate.trim().isNotEmpty) {
      body['buy_date'] = buyDate.trim();
    }
    if (buyNote != null || buyPriceUsd != null || buyUsdTmn != null) {
      body['buy_note'] = encodeBuyNoteUsd(
        usd: buyPriceUsd,
        fx: buyUsdTmn,
        note: buyNote ?? '',
      );
    }
    if (buyPriceUsd != null && buyPriceUsd > 0) {
      body['buy_price_usd'] = buyPriceUsd;
    }

    try {
      final data = await _api.patch(
        '/invest/api/v1/trades/$tradeId',
        body: body,
      );
      return Trade.fromMap(Map<String, Object?>.from(data['item'] as Map));
    } on InvestApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 405) {
        final data = await _api.put(
          '/invest/api/v1/trades/$tradeId',
          body: body,
        );
        return Trade.fromMap(Map<String, Object?>.from(data['item'] as Map));
      }
      rethrow;
    }
  }

  Future<Trade> closeTrade({
    required int tradeId,
    required double sellPrice,
    double sellFee = 0,
    String? sellDate,
    String sellNote = '',
    double? quantity,
  }) async {
    final body = <String, dynamic>{
      'sell_price': sellPrice,
      'sell_fee': sellFee,
      'sell_note': sellNote,
    };
    if (sellDate != null) body['sell_date'] = sellDate;
    if (quantity != null) body['quantity'] = quantity;

    final data =
        await _api.post('/invest/api/v1/trades/$tradeId/sell', body: body);
    return Trade.fromMap(Map<String, Object?>.from(data['item'] as Map));
  }

  Future<void> deleteClosedTrade(int tradeId) async {
    try {
      await _api.delete('/invest/api/v1/trades/$tradeId');
    } on InvestApiException catch (e) {
      final code = e.statusCode;
      if (code == 404 || code == 405) {
        await _api.post('/invest/api/v1/trades/$tradeId/delete');
        return;
      }
      rethrow;
    }
  }

  /// Returns null when the backend has no withdrawals API yet.
  Future<List<Withdrawal>?> listWithdrawals() async {
    try {
      final data = await _api.get('/invest/api/v1/withdrawals');
      return _withdrawalsFrom(data);
    } on InvestApiException catch (e) {
      if (e.statusCode == 404 || e.errorCode == 'not_found') return null;
      rethrow;
    }
  }

  /// Returns null when the backend has no withdrawal update route yet.
  Future<Withdrawal?> updateWithdrawal(Withdrawal item) async {
    if (item.id == null) {
      throw ArgumentError('شناسه برداشت نامعتبر است.');
    }
    try {
      final data = await _api.put(
        '/invest/api/v1/withdrawals/${item.id}',
        body: {
          'amount': item.amount,
          'note': item.note,
          'status': item.status,
          'created_at': item.createdAt,
        },
      );
      final saved = data['item'];
      if (saved is Map) {
        return Withdrawal.fromMap(Map<String, Object?>.from(saved));
      }
      return item;
    } on InvestApiException catch (e) {
      if (e.statusCode == 404 ||
          e.statusCode == 405 ||
          e.errorCode == 'not_found') {
        return null;
      }
      rethrow;
    }
  }

  Future<Withdrawal?> createWithdrawal({
    required double amount,
    String note = '',
    String? createdAt,
    String? status,
  }) async {
    try {
      final body = <String, Object?>{
        'amount': amount,
        'note': note,
      };
      final when = (createdAt ?? '').trim();
      if (when.isNotEmpty) body['created_at'] = when;
      final st = (status ?? '').trim();
      if (st.isNotEmpty) body['status'] = st;
      final data = await _api.post('/invest/api/v1/withdrawals', body: body);
      final item = data['item'];
      if (item is Map) {
        return Withdrawal.fromMap(Map<String, Object?>.from(item));
      }
      return Withdrawal(
        amount: amount,
        note: note,
        status: st.isEmpty ? 'completed' : st,
        createdAt: when.isEmpty ? nowIso() : when,
      );
    } on InvestApiException catch (e) {
      if (e.statusCode == 404 || e.errorCode == 'not_found') return null;
      rethrow;
    }
  }

  List<Trade> _tradesFrom(Map<String, dynamic> data) {
    final items = (data['items'] as List?) ?? const [];
    return items
        .map((e) => Trade.fromMap(Map<String, Object?>.from(e as Map)))
        .toList();
  }

  List<Withdrawal> _withdrawalsFrom(Map<String, dynamic> data) {
    final items = (data['items'] as List?) ?? const [];
    return items
        .map((e) => Withdrawal.fromMap(Map<String, Object?>.from(e as Map)))
        .toList();
  }

  RemoteSettingsBundle _bundleFrom(Map<String, dynamic> s) =>
      RemoteSettingsBundle.fromApiMap(s);

  static double _num(dynamic v) => CommodityQuote.numOf(v) ?? 0;

  static double? _numOrNull(dynamic v) => CommodityQuote.numOf(v);

  static List<CommodityQuote> _parseQuotes(dynamic raw) {
    if (raw is! List) return const [];
    final out = <CommodityQuote>[];
    for (final e in raw) {
      if (e is! Map) continue;
      try {
        out.add(CommodityQuote.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {}
    }
    return out;
  }
}

class MarketIndexRemoteBundle {
  const MarketIndexRemoteBundle({
    required this.essentials,
    required this.wallexMarkets,
    this.inflation,
    this.updatedAt,
    this.stale = false,
    this.error,
    this.warning,
  });

  final List<CommodityQuote> essentials;
  final List<CommodityQuote> wallexMarkets;
  final IranInflationSnapshot? inflation;
  final DateTime? updatedAt;
  final bool stale;
  final String? error;
  final String? warning;

  bool get hasAnyPrice =>
      essentials.any((q) => q.price != null) ||
      wallexMarkets.any((q) => q.price != null);
}

/// Settings payload from Vinor including extras older servers may echo only in
/// `raw` (alerts, app lock, client withdrawal mirror).
class RemoteSettingsBundle {
  const RemoteSettingsBundle({
    required this.settings,
    this.presentKeys = const {},
    this.clientWithdrawals = const [],
    this.hasClientWithdrawals = false,
    this.appLockHash,
    this.appLockBiometric,
  });

  final AppSettings settings;
  final Set<String> presentKeys;
  final List<Withdrawal> clientWithdrawals;
  final bool hasClientWithdrawals;
  final String? appLockHash;
  final bool? appLockBiometric;

  factory RemoteSettingsBundle.fromApiMap(Map<String, dynamic> s) {
    bool on(dynamic v, {bool d = true}) {
      if (v == null) return d;
      if (v is bool) return v;
      if (v is num) return v != 0;
      final t = v.toString().trim().toLowerCase();
      return t == '1' || t == 'true' || t == 'yes' || t == 'on';
    }

    double? rate(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse('$v'.trim().replaceAll(',', ''));
    }

    final raw = s['raw'] is Map
        ? Map<String, dynamic>.from(s['raw'] as Map)
        : const <String, dynamic>{};

    dynamic pick(String key) => s.containsKey(key) ? s[key] : raw[key];

    bool hasKey(String key) => s.containsKey(key) || raw.containsKey(key);

    final present = <String>{
      for (final k in s.keys) k.toString(),
      for (final k in raw.keys) k.toString(),
    };

    final settings = AppSettings(
      calendar: (s['calendar'] as String?) ?? AppConfig.calendarJalali,
      currency: (s['currency'] as String?) ?? AppConfig.currencyToman,
      theme: (s['theme'] as String?) ?? AppConfig.themeDark,
      livePricesEnabled: on(s['live_prices_enabled']),
      usdtApiEnabled: on(s['usdt_api_enabled']),
      goldApiEnabled: on(s['gold_api_enabled']),
      wallexUrl: (s['wallex_markets_url'] as String?)?.trim().isNotEmpty == true
          ? (s['wallex_markets_url'] as String)
          : AppConfig.defaultWallexUrl,
      persianToolboxUrl:
          (s['persiantoolbox_url'] as String?)?.trim().isNotEmpty == true
              ? (s['persiantoolbox_url'] as String)
              : AppConfig.defaultPersianToolboxUrl,
      usdtTmnRate: rate(s['usdt_tmn_rate'] ?? raw['usdt_tmn_rate']),
      goldTmnPerGram: rate(s['gold_tmn_per_gram'] ?? raw['gold_tmn_per_gram']),
      notificationsEnabled: on(
        s['notifications_enabled'] ?? raw['notifications_enabled'],
      ),
      notifyTrades: on(s['notify_trades'] ?? raw['notify_trades']),
      notifyWithdrawals:
          on(s['notify_withdrawals'] ?? raw['notify_withdrawals']),
      notifyPriceMoves:
          on(s['notify_price_moves'] ?? raw['notify_price_moves']),
      notifyBackground: hasKey(AppConfig.settingNotifyBackground)
          ? on(pick(AppConfig.settingNotifyBackground))
          : true,
      autoRefreshSeconds: AppSettings.parseAutoRefreshSeconds(
        s['price_refresh_seconds'] ??
            raw['price_refresh_seconds'] ??
            s['auto_refresh_seconds'] ??
            raw['auto_refresh_seconds'],
      ),
      annualWithdrawalPct: AppSettings.parseAnnualWithdrawalPct(
        s['annual_withdrawal_pct'] ?? raw['annual_withdrawal_pct'],
      ),
      priceAlerts: PriceAlertList.parse(pick(AppConfig.settingPriceAlerts)),
      profitAlerts: ProfitAlertList.parse(pick(AppConfig.settingProfitAlerts)),
    );

    final lockRaw = pick(AppConfig.settingAppLockHash);
    final String? appLockHash = !hasKey(AppConfig.settingAppLockHash)
        ? null
        : lockRaw == null || '$lockRaw'.trim().isEmpty
            ? ''
            : '$lockRaw'.trim();

    bool? appLockBiometric;
    if (hasKey(AppConfig.settingAppLockBiometric)) {
      appLockBiometric = on(pick(AppConfig.settingAppLockBiometric), d: false);
    }

    final clientWithdrawals = _parseClientWithdrawals(
      pick(AppConfig.settingClientWithdrawals),
    );

    return RemoteSettingsBundle(
      settings: settings,
      presentKeys: present,
      clientWithdrawals: clientWithdrawals,
      hasClientWithdrawals: hasKey(AppConfig.settingClientWithdrawals),
      appLockHash: appLockHash,
      appLockBiometric: appLockBiometric,
    );
  }

  static List<Withdrawal> _parseClientWithdrawals(dynamic raw) {
    dynamic value = raw;
    if (value is String) {
      final t = value.trim();
      if (t.isEmpty) return const [];
      try {
        value = jsonDecode(t);
      } catch (_) {
        return const [];
      }
    }
    if (value is! List) return const [];
    final out = <Withdrawal>[];
    for (final e in value) {
      if (e is! Map) continue;
      try {
        out.add(Withdrawal.fromMap(Map<String, Object?>.from(e)));
      } catch (_) {}
    }
    return out;
  }

  /// When the PUT response omits extras the client just sent, keep the sent
  /// values so UI / local cache stay correct even on older backends.
  RemoteSettingsBundle mergePreserving({
    required AppSettings sent,
    List<Withdrawal>? clientWithdrawals,
    String? appLockHash,
    bool? appLockBiometric,
  }) {
    final merged = settings.copyWith(
      usdtTmnRate: sent.usdtTmnRate ?? settings.usdtTmnRate,
      goldTmnPerGram: sent.goldTmnPerGram ?? settings.goldTmnPerGram,
      notifyBackground: presentKeys.contains(AppConfig.settingNotifyBackground)
          ? settings.notifyBackground
          : sent.notifyBackground,
      priceAlerts: presentKeys.contains(AppConfig.settingPriceAlerts)
          ? settings.priceAlerts
          : sent.priceAlerts,
      profitAlerts: presentKeys.contains(AppConfig.settingProfitAlerts)
          ? settings.profitAlerts
          : sent.profitAlerts,
      autoRefreshSeconds: presentKeys.contains('price_refresh_seconds') ||
              presentKeys.contains('auto_refresh_seconds')
          ? settings.autoRefreshSeconds
          : sent.autoRefreshSeconds,
      // Always keep the value we just PUT. Older Vinor builds may leave a
      // stale `annual_withdrawal_pct` in `raw` without applying the update.
      annualWithdrawalPct: sent.annualWithdrawalPct,
    );
    if (merged.wallexUrl.trim().isEmpty && sent.wallexUrl.trim().isNotEmpty) {
      merged.wallexUrl = sent.wallexUrl;
    }
    if (merged.persianToolboxUrl.trim().isEmpty &&
        sent.persianToolboxUrl.trim().isNotEmpty) {
      merged.persianToolboxUrl = sent.persianToolboxUrl;
    }

    return RemoteSettingsBundle(
      settings: merged,
      presentKeys: presentKeys,
      clientWithdrawals: hasClientWithdrawals
          ? this.clientWithdrawals
          : (clientWithdrawals ?? this.clientWithdrawals),
      hasClientWithdrawals: hasClientWithdrawals || clientWithdrawals != null,
      appLockHash: presentKeys.contains(AppConfig.settingAppLockHash)
          ? this.appLockHash
          : (appLockHash ?? this.appLockHash),
      appLockBiometric: presentKeys.contains(AppConfig.settingAppLockBiometric)
          ? this.appLockBiometric
          : (appLockBiometric ?? this.appLockBiometric),
    );
  }
}

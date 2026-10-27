import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/biz_remote.dart';
import 'package:invest/data/projects_remote.dart';
import 'package:invest/data/pwo_remote.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_meta.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/iran_inflation.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/price_alert.dart';
import 'package:invest/domain/models/profit_alert.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/models/year_nav_entry.dart';
import 'package:invest/domain/services/commodity_index_service.dart';
import 'package:invest/domain/services/invest_mutations.dart';
import 'package:invest/domain/utils/buy_usd.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/json_values.dart';

/// Remote asset repository backed by Vinor Invest API.
class RemoteAssetRepository {
  RemoteAssetRepository(this._api);
  final InvestApiClient _api;

  Future<List<Asset>> listAll({String search = ''}) async {
    final query = search.trim().isEmpty ? null : {'q': search.trim()};
    final data = await _api.get('/invest/api/v1/assets', query: query);
    return RemoteInvestService.parseRows(
      data['items'],
      'assets',
      Asset.fromMap,
    );
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

  /// Per-account PWO ledger (`/pwo`).
  late final PwoRemote pwo = PwoRemote(_api);
  late final BizRemote biz = BizRemote(_api);
  late final ProjectsRemote projects = ProjectsRemote(_api);

  /// Set when `growth_series` cannot be read. Metrics themselves still return.
  Object? growthSeriesError;

  Future<DashboardMetrics> fetchDashboard(String calendar) async {
    final data = await _api.get('/invest/api/v1/dashboard');
    // `metrics as Map` threw when the field was missing or not an object,
    // and `open_count as num` threw when it arrived as a string. Either
    // abort used to blank the dashboard.
    final metricsRaw = data['metrics'];
    if (metricsRaw is! Map) {
      debugPrint(
        'GET /dashboard metrics is ${metricsRaw.runtimeType}, not a map',
      );
    }
    final m = metricsRaw is Map
        ? Map<String, dynamic>.from(metricsRaw)
        : const <String, dynamic>{};
    final goldRaw = data['gold_fund'];
    final g = goldRaw is Map
        ? Map<String, dynamic>.from(goldRaw)
        : const <String, dynamic>{};
    return DashboardMetrics(
      totalValue: _num(m['total_value']),
      totalPnl: _num(m['total_pnl']),
      totalPnlPct: _num(m['total_pnl_pct']),
      realizedPnl: _num(m['realized_pnl']),
      unrealizedPnl: _num(m['unrealized_pnl']),
      openCount: jsonInt(m['open_count']) ?? 0,
      closedCount: jsonInt(m['closed_count']) ?? 0,
      yearRealizedPnl: _num(m['year_realized_pnl']),
      yearKey: yearPeriodKey(todayIso(), calendar),
      goldFund: GoldFundMetrics(
        goldInG: _num(g['gold_in_g']),
        goldOutG: _num(g['gold_out_g']),
        goldHoldingG: _num(g['gold_holding_g']),
      ),
      growthSeries: _growthSeries(data['growth_series']),
    );
  }

  List<SeriesPoint> _growthSeries(Object? raw) {
    growthSeriesError = null;
    try {
      return SeriesPoint.fromJsonList(raw);
    } catch (e, st) {
      growthSeriesError = e;
      debugPrint('snapshots parse failed: $e\n$st');
      return const [];
    }
  }

  /// `GET /invest/api/v1/insights`. One bad row is skipped.
  Future<List<RemoteInsight>> fetchInsights() async {
    final data = await _api.get('/invest/api/v1/insights');
    return parseRows(data['items'], 'insights', RemoteInsight.fromMap);
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
    final raw = data['settings'];
    if (raw is! Map) {
      debugPrint('GET /settings is ${raw.runtimeType}, not a map');
      return _bundleFrom(const {});
    }
    return _bundleFrom(Map<String, dynamic>.from(raw));
  }

  /// Persist full user prefs to Vinor (typed fields + extras in settings bag).
  Future<RemoteSettingsBundle> saveSettings(
    AppSettings s, {
    List<Withdrawal>? clientWithdrawals,
    List<BankCheck>? clientChecks,
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
      AppConfig.settingWithdrawalCapBase: s.withdrawalCapBase,
      'price_alerts': s.priceAlerts.map((e) => e.toJson()).toList(),
      'profit_alerts': s.profitAlerts.map((e) => e.toJson()).toList(),
      'year_nav_history': s.yearNavHistory.map((e) => e.toJson()).toList(),
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
    if (clientChecks != null) {
      body[AppConfig.settingClientChecks] =
          clientChecks.map((c) => c.toMap()).toList();
    }
    final data = await _api.put('/invest/api/v1/settings', body: body);
    final bundle =
        _bundleFrom(Map<String, dynamic>.from(data['settings'] as Map));
    final bad = settingsMismatches(sent: s, echoed: bundle);
    if (bad.isNotEmpty) throw SettingsNotSavedException(bad);
    return bundle.mergePreserving(
      sent: s,
      clientWithdrawals: clientWithdrawals,
      clientChecks: clientChecks,
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
    double? sellUsdTmn,
  }) async {
    final body = <String, dynamic>{
      'sell_price': sellPrice,
      'sell_fee': sellFee,
      'sell_note': encodeSellNoteFx(fx: sellUsdTmn, note: sellNote),
    };
    if (sellDate != null) body['sell_date'] = sellDate;
    if (quantity != null) body['quantity'] = quantity;

    final data =
        await _api.post('/invest/api/v1/trades/$tradeId/sell', body: body);
    return Trade.fromMap(Map<String, Object?>.from(data['item'] as Map));
  }

  /// Asset + all its trades. Uses `POST /assets/{id}/purge` (idempotent);
  /// an older server without that route falls back to `DELETE /assets/{id}`,
  /// which only works when no open lot is left.
  @override
  Future<void> deleteAsset(int assetId) async {
    try {
      await _api.post('/invest/api/v1/assets/$assetId/purge', body: {'confirm': true});
    } on InvestApiException catch (e) {
      final code = e.statusCode;
      if (code != 404 && code != 405) rethrow;
      try {
        await _api.delete('/invest/api/v1/assets/$assetId');
      } on InvestApiException catch (old) {
        if (old.statusCode == 404) return;
        throw InvestApiException(
          'سرور هنوز حذف دارایی دارای موجودی باز را پشتیبانی نمی‌کند. '
          'پس از به‌روزرسانی سرور دوباره امتحان کنید.',
          statusCode: old.statusCode,
          errorCode: old.errorCode,
        );
      }
    }
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

  /// Null when this Vinor build has no `/checks` routes.
  Future<List<BankCheck>?> listChecks() async {
    try {
      final data = await _api.get('/invest/api/v1/checks');
      return _checksFrom(data);
    } on InvestApiException catch (e) {
      if (_missingRoute(e)) return null;
      rethrow;
    }
  }

  /// Null when `/checks/reminders` is not on this server.
  Future<CheckReminders?> fetchCheckReminders({int withinDays = 7}) async {
    try {
      final data = await _api.get(
        '/invest/api/v1/checks/reminders',
        query: {'within_days': '$withinDays'},
      );
      return CheckReminders.fromApi(data);
    } on InvestApiException catch (e) {
      if (_missingRoute(e)) return null;
      rethrow;
    }
  }

  Future<BankCheck> createCheck(BankCheck item) async {
    final data = await _api.post(
      '/invest/api/v1/checks',
      body: Map<String, dynamic>.from(item.toMap()),
    );
    return _checkItem(data, fallback: item);
  }

  Future<BankCheck> updateCheck(BankCheck item) async {
    if (item.id == null || item.id! <= 0) {
      throw ArgumentError('شناسه چک نامعتبر است.');
    }
    final data = await _api.patch(
      '/invest/api/v1/checks/${item.id}',
      body: Map<String, dynamic>.from(item.toMap()),
    );
    return _checkItem(data, fallback: item);
  }

  /// `DELETE /checks/<id>`, then `POST /checks/<id>/delete` when that verb
  /// is missing. A missing cheque still raises the server's Persian 404.
  Future<void> deleteCheck(int id) async {
    try {
      await _api.delete('/invest/api/v1/checks/$id');
    } on InvestApiException catch (e) {
      if (e.statusCode == 405 ||
          (e.statusCode == 404 && !e.message.contains('پیدا نشد'))) {
        await _api.post('/invest/api/v1/checks/$id/delete');
        return;
      }
      rethrow;
    }
  }

  List<BankCheck> _checksFrom(Map<String, dynamic> data) {
    return parseRows(data['items'], 'checks', BankCheck.fromMap);
  }

  BankCheck _checkItem(
    Map<String, dynamic> data, {
    required BankCheck fallback,
  }) {
    final item = data['item'];
    if (item is Map) {
      return BankCheck.fromMap(Map<String, Object?>.from(item));
    }
    return fallback;
  }

  static bool _missingRoute(InvestApiException e) =>
      e.statusCode == 404 && !e.message.contains('پیدا نشد');

  List<Trade> _tradesFrom(Map<String, dynamic> data) {
    return parseRows(data['items'], 'trades', Trade.fromMap);
  }

  List<Withdrawal> _withdrawalsFrom(Map<String, dynamic> data) {
    return parseRows(data['items'], 'withdrawals', Withdrawal.fromMap);
  }

  /// One unreadable row is skipped. The rest of the list still loads.
  static List<T> parseRows<T>(
    Object? raw,
    String label,
    T Function(Map<String, Object?>) parse,
  ) {
    final maps = _maps(raw, label);
    final out = <T>[];
    for (var i = 0; i < maps.length; i++) {
      try {
        out.add(parse(maps[i]));
      } catch (e, st) {
        debugPrint('skip $label row $i (${e.runtimeType}): $e\n$st');
      }
    }
    return out;
  }

  /// Skip a non-list body or a non-object row instead of failing the refresh.
  static List<Map<String, Object?>> _maps(Object? raw, String label) {
    if (raw == null) return const [];
    if (raw is! List) {
      debugPrint('GET $label items is ${raw.runtimeType}, not a list');
      return const [];
    }
    final out = <Map<String, Object?>>[];
    for (final item in raw) {
      if (item is! Map) {
        debugPrint('skip $label row of type ${item.runtimeType}');
        continue;
      }
      out.add(Map<String, Object?>.from(item));
    }
    return out;
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

/// Groups from `GET /invest/api/v1/checks/reminders`.
class CheckReminders {
  const CheckReminders({
    this.withinDays = 7,
    this.overdue = const [],
    this.dueSoon = const [],
    this.bounced = const [],
    this.items = const [],
  });

  final int withinDays;
  final List<BankCheck> overdue;
  final List<BankCheck> dueSoon;
  final List<BankCheck> bounced;
  final List<BankCheck> items;

  factory CheckReminders.fromApi(Map<String, dynamic> data) {
    List<BankCheck> parse(String key) {
      final raw = data[key];
      if (raw is! List) return const [];
      return RemoteInvestService.parseRows(raw, key, BankCheck.fromMap);
    }

    final window = data['within_days'];
    return CheckReminders(
      withinDays: window is int ? window : int.tryParse('$window') ?? 7,
      overdue: parse('overdue'),
      dueSoon: parse('due_soon'),
      bounced: parse('bounced'),
      items: parse('items'),
    );
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
/// The server answered the save but did not keep some of the values sent.
class SettingsNotSavedException implements Exception {
  const SettingsNotSavedException(this.fields);
  final List<String> fields;
  @override
  String toString() =>
      'سرور این تنظیمات را ذخیره نکرد: ${fields.join('، ')}. دوباره تلاش کنید.';
}

/// Persian labels of settings whose echoed value differs from what was PUT.
/// Only keys present in the response are checked (older servers omit some).
List<String> settingsMismatches({
  required AppSettings sent,
  required RemoteSettingsBundle echoed,
}) {
  final e = echoed.settings;
  final has = echoed.presentKeys.contains;
  final out = <String>[];
  void chk(String key, String label, Object? a, Object? b) {
    if (has(key) && a != b) out.add(label);
  }

  chk('calendar', 'تقویم', sent.calendar, e.calendar);
  chk('currency', 'واحد پول', sent.currency, e.currency);
  chk('theme', 'پوسته', sent.theme, e.theme);
  chk('live_prices_enabled', 'قیمت زنده', sent.livePricesEnabled, e.livePricesEnabled);
  chk('notifications_enabled', 'اعلان‌ها', sent.notificationsEnabled, e.notificationsEnabled);
  chk('notify_trades', 'اعلان معاملات', sent.notifyTrades, e.notifyTrades);
  chk('notify_withdrawals', 'اعلان برداشت', sent.notifyWithdrawals, e.notifyWithdrawals);
  chk('notify_price_moves', 'اعلان قیمت', sent.notifyPriceMoves, e.notifyPriceMoves);
  chk(AppConfig.settingNotifyBackground, 'اعلان پس‌زمینه', sent.notifyBackground, e.notifyBackground);
  chk('price_refresh_seconds', 'فاصلهٔ به‌روزرسانی', sent.autoRefreshSeconds, e.autoRefreshSeconds);
  chk('annual_withdrawal_pct', 'درصد برداشت سالانه', sent.annualWithdrawalPct, e.annualWithdrawalPct);
  chk(AppConfig.settingWithdrawalCapBase, 'مبنای سقف برداشت', sent.withdrawalCapBase, e.withdrawalCapBase);
  chk(AppConfig.settingPriceAlerts, 'هشدارهای قیمت', sent.priceAlerts.length, e.priceAlerts.length);
  chk(AppConfig.settingProfitAlerts, 'هشدارهای سود', sent.profitAlerts.length, e.profitAlerts.length);
  chk(AppConfig.settingYearNavHistory, 'ارزش پایان سال', sent.yearNavHistory.length, e.yearNavHistory.length);
  return out;
}

class RemoteSettingsBundle {
  const RemoteSettingsBundle({
    required this.settings,
    this.presentKeys = const {},
    this.clientWithdrawals = const [],
    this.hasClientWithdrawals = false,
    this.clientChecks = const [],
    this.hasClientChecks = false,
    this.serverEchoedChecks = false,
    this.echoedChecks = const [],
    this.clientChecksError,
    this.appLockHash,
    this.appLockBiometric,
  });

  final AppSettings settings;
  final Set<String> presentKeys;
  final List<Withdrawal> clientWithdrawals;
  final bool hasClientWithdrawals;
  final List<BankCheck> clientChecks;
  final bool hasClientChecks;

  /// True when this GET/PUT payload actually contained `client_checks`.
  ///
  /// Distinct from [hasClientChecks] after [mergePreserving], which keeps a
  /// book the server dropped.
  final bool serverEchoedChecks;

  /// The list the server sent, before a dropped echo is filled back in.
  final List<BankCheck> echoedChecks;

  /// Persian message from `settings.client_checks_error`, when the mirror
  /// rejected the book and kept the previous one.
  final String? clientChecksError;
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

    String text(Object? value, String fallback) {
      final parsed = jsonText(value).trim();
      return parsed.isEmpty ? fallback : parsed;
    }

    final settings = AppSettings(
      calendar: text(s['calendar'], AppConfig.calendarJalali),
      currency: text(s['currency'], AppConfig.currencyToman),
      theme: text(s['theme'], AppConfig.themeDark),
      livePricesEnabled: on(s['live_prices_enabled']),
      usdtApiEnabled: on(s['usdt_api_enabled']),
      goldApiEnabled: on(s['gold_api_enabled']),
      wallexUrl: text(s['wallex_markets_url'], AppConfig.defaultWallexUrl),
      persianToolboxUrl:
          text(s['persiantoolbox_url'], AppConfig.defaultPersianToolboxUrl),
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
      withdrawalCapBase:
          AppSettings.parseCapBase(pick(AppConfig.settingWithdrawalCapBase)),
      priceAlerts: PriceAlertList.parse(pick(AppConfig.settingPriceAlerts)),
      profitAlerts: ProfitAlertList.parse(pick(AppConfig.settingProfitAlerts)),
      yearNavHistory: YearNavList.parse(
        pick(AppConfig.settingYearNavHistory),
      ),
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
    final clientChecks = _parseClientChecks(
      pick(AppConfig.settingClientChecks),
    );
    final clientChecksError = _checksErrorMessage(
      pick('client_checks_error'),
    );

    return RemoteSettingsBundle(
      settings: settings,
      presentKeys: present,
      clientWithdrawals: clientWithdrawals,
      hasClientWithdrawals: hasKey(AppConfig.settingClientWithdrawals),
      clientChecks: clientChecks,
      hasClientChecks: hasKey(AppConfig.settingClientChecks),
      serverEchoedChecks: hasKey(AppConfig.settingClientChecks),
      echoedChecks: clientChecks,
      clientChecksError: clientChecksError,
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

  static String? _checksErrorMessage(dynamic raw) {
    if (raw is! Map) return null;
    final message = raw['message'];
    if (message is! String) return null;
    final text = message.trim();
    return text.isEmpty ? null : text;
  }

  static List<BankCheck> _parseClientChecks(dynamic raw) {
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
    final out = <BankCheck>[];
    for (final e in value) {
      if (e is! Map) continue;
      try {
        out.add(BankCheck.fromMap(Map<String, Object?>.from(e)));
      } catch (_) {}
    }
    return out;
  }

  /// When the PUT response omits extras the client just sent, keep the sent
  /// values so UI / local cache stay correct even on older backends.
  RemoteSettingsBundle mergePreserving({
    required AppSettings sent,
    List<Withdrawal>? clientWithdrawals,
    List<BankCheck>? clientChecks,
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
      yearNavHistory: sent.yearNavHistory,
      autoRefreshSeconds: presentKeys.contains('price_refresh_seconds') ||
              presentKeys.contains('auto_refresh_seconds')
          ? settings.autoRefreshSeconds
          : sent.autoRefreshSeconds,
      // Always keep the value we just PUT. Older Vinor builds may leave a
      // stale `annual_withdrawal_pct` in `raw` without applying the update.
      annualWithdrawalPct: sent.annualWithdrawalPct,
      withdrawalCapBase: presentKeys.contains(AppConfig.settingWithdrawalCapBase)
          ? settings.withdrawalCapBase
          : sent.withdrawalCapBase,
    );
    if (merged.wallexUrl.trim().isEmpty && sent.wallexUrl.trim().isNotEmpty) {
      merged.wallexUrl = sent.wallexUrl;
    }
    if (merged.persianToolboxUrl.trim().isEmpty &&
        sent.persianToolboxUrl.trim().isNotEmpty) {
      merged.persianToolboxUrl = sent.persianToolboxUrl;
    }

    final checks = _mergeChecks(
      echoed: hasClientChecks ? this.clientChecks : null,
      sent: clientChecks,
    );

    return RemoteSettingsBundle(
      settings: merged,
      presentKeys: presentKeys,
      clientWithdrawals: hasClientWithdrawals
          ? this.clientWithdrawals
          : (clientWithdrawals ?? this.clientWithdrawals),
      hasClientWithdrawals: hasClientWithdrawals || clientWithdrawals != null,
      clientChecks: checks.list,
      hasClientChecks: checks.present,
      serverEchoedChecks: hasClientChecks,
      echoedChecks: hasClientChecks
          ? List<BankCheck>.from(this.clientChecks)
          : const [],
      clientChecksError: clientChecksError,
      appLockHash: presentKeys.contains(AppConfig.settingAppLockHash)
          ? this.appLockHash
          : (appLockHash ?? this.appLockHash),
      appLockBiometric: presentKeys.contains(AppConfig.settingAppLockBiometric)
          ? this.appLockBiometric
          : (appLockBiometric ?? this.appLockBiometric),
    );
  }

  /// Prefer the list we just wrote when the server omits it or echoes empty
  /// after a non-empty write (older backends drop unknown settings keys).
  static ({List<BankCheck> list, bool present}) _mergeChecks({
    required List<BankCheck>? echoed,
    required List<BankCheck>? sent,
  }) {
    if (sent == null) {
      return (list: echoed ?? const [], present: echoed != null);
    }
    if (echoed == null) {
      return (list: sent, present: true);
    }
    if (sent.isNotEmpty && echoed.isEmpty) {
      return (list: sent, present: true);
    }
    return (list: echoed, present: true);
  }
}

/// One row from `GET /invest/api/v1/insights`.
class RemoteInsight {
  const RemoteInsight({
    required this.id,
    required this.title,
    required this.summary,
    required this.priority,
    required this.relatedAssets,
    required this.relatedTrades,
  });

  final String id;
  final String title;
  final String summary;
  final int priority;
  final List<String> relatedAssets;
  final List<int> relatedTrades;

  factory RemoteInsight.fromMap(Map<String, Object?> m) {
    List<String> strings(Object? raw) {
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (jsonText(item).isNotEmpty) jsonText(item),
      ];
    }

    List<int> ints(Object? raw) {
      if (raw is! List) return const [];
      final out = <int>[];
      for (final item in raw) {
        final value = jsonInt(item);
        if (value != null) out.add(value);
      }
      return out;
    }

    return RemoteInsight(
      id: jsonText(m['id']),
      title: jsonText(m['title']),
      summary: jsonText(m['summary']),
      priority: jsonInt(m['priority']) ?? 0,
      relatedAssets: strings(m['related_assets']),
      relatedTrades: ints(m['related_trades']),
    );
  }
}

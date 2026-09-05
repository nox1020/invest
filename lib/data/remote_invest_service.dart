import 'package:invest/config/app_config.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
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
class RemoteInvestService {
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
    final data =
        await _api.get('/invest/api/v1/trades/open', query: query);
    return _tradesFrom(data);
  }

  Future<List<Trade>> listClosed({String search = ''}) async {
    final query = search.trim().isEmpty ? null : {'q': search.trim()};
    final data =
        await _api.get('/invest/api/v1/trades/closed', query: query);
    return _tradesFrom(data);
  }

  Future<AppSettings> fetchSettings() async {
    final data = await _api.get('/invest/api/v1/settings');
    return _settingsFrom(Map<String, dynamic>.from(data['settings'] as Map));
  }

  Future<AppSettings> saveSettings(AppSettings s) async {
    final data = await _api.put('/invest/api/v1/settings', body: {
      'calendar': s.calendar,
      'currency': s.currency,
      'theme': s.theme,
      'live_prices_enabled': s.livePricesEnabled,
      'usdt_api_enabled': s.usdtApiEnabled,
      'gold_api_enabled': s.goldApiEnabled,
    });
    return _settingsFrom(Map<String, dynamic>.from(data['settings'] as Map));
  }

  Future<({double? usdt, double? gold})> fetchQuotes() async {
    final data = await _api.get('/invest/api/v1/quotes');
    return (
      usdt: _numOrNull(data['usdt_tmn']),
      gold: _numOrNull(data['gold_tmn_per_gram']),
    );
  }

  Future<Asset> createAsset({
    required String name,
    String symbol = '',
    double quantity = 0,
    double avgBuyPrice = 0,
    double currentPrice = 0,
    String notes = '',
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('نام دارایی الزامی است.');
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
      if (avgBuyPrice <= 0) {
        throw ArgumentError('برای موجودی اولیه، قیمت خرید الزامی است.');
      }
      await registerBuy(
        assetId: asset.id,
        quantity: quantity,
        buyPrice: avgBuyPrice,
        buyNote: 'موجودی اولیه',
        currentPrice: price,
      );
      final refreshed = await assets.listAll();
      asset = refreshed.firstWhere((a) => a.id == asset.id, orElse: () => asset);
    }
    return asset;
  }

  Future<Trade> registerBuy({
    int? assetId,
    String? name,
    String symbol = '',
    required double quantity,
    required double buyPrice,
    double buyFee = 0,
    String? buyDate,
    String buyNote = '',
    double? currentPrice,
  }) async {
    final body = <String, dynamic>{
      'quantity': quantity,
      'buy_price': buyPrice,
      'buy_fee': buyFee,
      'buy_note': buyNote,
      'symbol': symbol,
    };
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
    if (buyNote != null) body['buy_note'] = buyNote;

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

  Future<Withdrawal?> createWithdrawal({
    required double amount,
    String note = '',
  }) async {
    try {
      final data = await _api.post('/invest/api/v1/withdrawals', body: {
        'amount': amount,
        'note': note,
      });
      final item = data['item'];
      if (item is Map) {
        return Withdrawal.fromMap(Map<String, Object?>.from(item));
      }
      return Withdrawal(
        amount: amount,
        note: note,
        status: 'completed',
        createdAt: nowIso(),
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

  AppSettings _settingsFrom(Map<String, dynamic> s) {
    bool on(dynamic v, {bool d = true}) {
      if (v == null) return d;
      if (v is bool) return v;
      return v.toString() == '1' || v.toString().toLowerCase() == 'true';
    }

    return AppSettings(
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
    );
  }

  static double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;

  static double? _numOrNull(dynamic v) => (v as num?)?.toDouble();
}

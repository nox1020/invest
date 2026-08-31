import 'package:flutter/foundation.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/app_database.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/remote_invest_service.dart';
import 'package:invest/data/repositories.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/portfolio_service.dart';
import 'package:invest/domain/services/quote_clients.dart';
import 'package:invest/domain/services/trade_service.dart';
import 'package:sqflite/sqflite.dart';

/// App-wide state — online (Vinor API) or local SQLite (tests only).
class AppState extends ChangeNotifier {
  AppState();

  bool useRemote = true;
  bool authenticated = false;
  String? userPhone;
  String baseUrl = AppConfig.defaultBaseUrl;

  SessionStore? _session;
  InvestApiClient? _api;
  RemoteInvestService? remote;
  TradeService? trades;
  PortfolioService? portfolio;
  SettingsRepository? settingsRepo;
  QuoteClients? quotes;

  AppSettings settings = AppSettings();
  DashboardMetrics? metrics;
  List<Asset> assets = [];
  List<Trade> openTrades = [];
  List<Trade> closedTrades = [];
  bool loading = true;
  String? error;

  double? liveUsdt;
  double? liveGold;

  Future<void>? _activeRefresh;

  Future<void> init({Database? testDb}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (testDb != null) {
        useRemote = false;
        await AppDatabase.instance.bind(testDb);
        final db = testDb;
        trades = TradeService(db);
        portfolio = PortfolioService(db);
        settingsRepo = SettingsRepository(db);
        quotes = QuoteClients();
        authenticated = true;
        await _loadLocalSettings();
        await refresh();
      } else {
        _session = await SessionStore.load();
        baseUrl = _session!.baseUrl;
        _api = InvestApiClient(_session!);
        remote = RemoteInvestService(_api!);
        _api!.restoreSessionCookie();
        userPhone = _session!.phone;
        authenticated = await _api!.checkAuth();
        if (authenticated) {
          await _loadRemoteData();
        }
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<String?> requestOtp(String phone) async {
    if (_api == null) throw StateError('API آماده نیست');
    return _api!.requestOtp(phone);
  }

  Future<void> verifyOtp(String phone, String code) async {
    if (_api == null) throw StateError('API آماده نیست');
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _api!.verifyOtp(phone, code);
      userPhone = phone;
      authenticated = true;
      await _loadRemoteData();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _api?.logout();
    authenticated = false;
    userPhone = null;
    metrics = null;
    assets = [];
    openTrades = [];
    closedTrades = [];
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    final old = baseUrl;
    await _session?.setBaseUrl(url);
    baseUrl = _session?.baseUrl ?? AppConfig.defaultBaseUrl;
    if (old != baseUrl) {
      await logout();
    }
    notifyListeners();
  }

  Future<void> _loadRemoteData() async {
    await refresh();
  }

  /// Updates settings when backend API version changes (no nested refresh).
  Future<void> _syncApiVersion() async {
    if (_api == null || _session == null || !useRemote) return;
    final server = await _api!.fetchApiVersion();
    if (server == null || server.isEmpty) return;
    final stored = _session!.apiVersion;
    await _session!.setApiVersion(server);
    if (stored != null && stored != server) {
      settings = await remote!.fetchSettings();
    }
  }

  Future<void> _loadLocalSettings() async {
    final map = await settingsRepo!.loadAll();
    bool on(String k, {bool d = true}) =>
        (map[k] ?? (d ? '1' : '0')) == '1';
    settings = AppSettings(
      calendar: map[AppConfig.settingCalendar] ?? AppConfig.calendarJalali,
      currency: map[AppConfig.settingCurrency] ?? AppConfig.currencyToman,
      theme: map[AppConfig.settingTheme] ?? AppConfig.themeDark,
      livePricesEnabled: on(AppConfig.settingLivePrices),
      usdtApiEnabled: on(AppConfig.settingUsdtApi),
      goldApiEnabled: on(AppConfig.settingGoldApi),
      wallexUrl: map[AppConfig.settingWallexUrl] ?? AppConfig.defaultWallexUrl,
      persianToolboxUrl: map[AppConfig.settingPersianToolboxUrl] ??
          AppConfig.defaultPersianToolboxUrl,
      usdtTmnRate: double.tryParse(map[AppConfig.settingUsdtTmn] ?? ''),
      goldTmnPerGram: double.tryParse(map[AppConfig.settingGoldTmn] ?? ''),
    );
  }

  Future<void> saveSettings(AppSettings s) async {
    settings = s;
    if (useRemote) {
      settings = await remote!.saveSettings(s);
    } else {
      await settingsRepo!.saveMap({
        AppConfig.settingCalendar: s.calendar,
        AppConfig.settingCurrency: s.currency,
        AppConfig.settingTheme: s.theme,
        AppConfig.settingLivePrices: s.livePricesEnabled ? '1' : '0',
        AppConfig.settingUsdtApi: s.usdtApiEnabled ? '1' : '0',
        AppConfig.settingGoldApi: s.goldApiEnabled ? '1' : '0',
        AppConfig.settingWallexUrl: s.wallexUrl,
        AppConfig.settingPersianToolboxUrl: s.persianToolboxUrl,
        if (s.usdtTmnRate != null)
          AppConfig.settingUsdtTmn: s.usdtTmnRate!.toString(),
        if (s.goldTmnPerGram != null)
          AppConfig.settingGoldTmn: s.goldTmnPerGram!.toString(),
      });
    }
    notifyListeners();
    await refreshAll();
  }

  /// Single serialized refresh path — quotes (optional) then portfolio data.
  Future<void> refreshAll({bool includeQuotes = true}) {
    if (_activeRefresh != null) {
      return _activeRefresh!;
    }
    _activeRefresh = _runRefresh(includeQuotes: includeQuotes).whenComplete(() {
      _activeRefresh = null;
    });
    return _activeRefresh!;
  }

  Future<void> refresh() => refreshAll(includeQuotes: false);

  Future<void> refreshQuotes() => refreshAll(includeQuotes: true);

  Future<void> _runRefresh({required bool includeQuotes}) async {
    try {
      if (includeQuotes && settings.livePricesEnabled) {
        await _syncLiveQuotes();
      }
      if (useRemote) {
        await _syncApiVersion();
        settings = await remote!.fetchSettings();
        final svc = remote!;
        metrics = await svc.fetchDashboard(settings.calendar);
        assets = await svc.assets.listAll();
        openTrades = await svc.listOpen();
        closedTrades = await svc.listClosed();
      } else {
        assets = await trades!.assets.listAll();
        openTrades = await trades!.trades.listOpen();
        closedTrades = await trades!.trades.listClosed();
        metrics = await portfolio!.getMetrics(calendar: settings.calendar);
        await portfolio!.recordSnapshot();
      }
      error = null;
    } on InvestApiException catch (e) {
      if (e.statusCode == 401) {
        await logout();
      } else {
        error = e.message;
      }
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  Future<void> _syncLiveQuotes() async {
    if (useRemote) {
      final q = await remote!.fetchQuotes();
      if (q.usdt != null) {
        liveUsdt = q.usdt;
        settings.usdtTmnRate = q.usdt;
      }
      if (q.gold != null) {
        liveGold = q.gold;
        settings.goldTmnPerGram = q.gold;
      }
      return;
    }

    double? usdt;
    double? gold;
    if (settings.usdtApiEnabled) {
      usdt = await quotes!.fetchUsdtToman(wallexUrl: settings.wallexUrl);
      if (usdt != null) {
        liveUsdt = usdt;
        settings.usdtTmnRate = usdt;
        await settingsRepo!.set(AppConfig.settingUsdtTmn, usdt.toString());
      }
    }
    if (settings.goldApiEnabled) {
      final g =
          await quotes!.fetchGoldToman(persianUrl: settings.persianToolboxUrl);
      gold = g.price;
      if (gold != null) {
        liveGold = gold;
        settings.goldTmnPerGram = gold;
        await settingsRepo!.set(AppConfig.settingGoldTmn, gold.toString());
      }
    }
    await trades!.applyLivePrices(
      usdtTmn: usdt ?? settings.usdtTmnRate,
      goldTmn: gold ?? settings.goldTmnPerGram,
      updateUsdt: settings.usdtApiEnabled,
      updateGold: settings.goldApiEnabled,
    );
  }

  /// Used by UI for buy/sell/asset mutations.
  dynamic get tradeService => useRemote ? remote : trades;
}

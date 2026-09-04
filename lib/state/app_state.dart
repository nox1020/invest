import 'package:flutter/foundation.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/app_lock_store.dart';
import 'package:invest/data/app_database.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/offline_cache_store.dart';
import 'package:invest/data/remote_invest_service.dart';
import 'package:invest/data/repositories.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/services/commodity_index_service.dart';
import 'package:invest/domain/services/portfolio_service.dart';
import 'package:invest/domain/services/quote_clients.dart';
import 'package:invest/domain/services/trade_service.dart';
import 'package:invest/security/app_lock.dart';
import 'package:invest/security/biometric_auth.dart';
import 'package:invest/services/refresh_coordinator.dart';
import 'package:sqflite/sqflite.dart';

/// App-wide state — online (Vinor API), offline cache, or local SQLite.
class AppState extends ChangeNotifier {
  AppState();

  bool useRemote = true;
  bool authenticated = false;
  bool offline = false;
  bool readOnlyOffline = false;
  DateTime? lastSyncedAt;
  String? userPhone;
  String baseUrl = AppConfig.defaultBaseUrl;

  SessionStore? _session;
  InvestApiClient? _api;
  RemoteInvestService? remote;
  TradeService? trades;
  PortfolioService? portfolio;
  SettingsRepository? settingsRepo;
  QuoteClients? quotes;
  CommodityIndexService? commodityIndexService;

  AppSettings settings = AppSettings();
  DashboardMetrics? metrics;
  List<Asset> assets = [];
  List<Trade> openTrades = [];
  List<Trade> closedTrades = [];
  bool loading = true;
  bool refreshing = false;
  String? error;

  double? liveUsdt;
  double? liveGold;

  List<CommodityQuote> commodityIndex = [];
  List<CommodityQuote> wallexMarkets = [];
  bool commodityIndexLoading = false;
  String? commodityIndexError;
  DateTime? commodityIndexUpdatedAt;

  String? appLockHash;
  bool appLockEnabled = false;
  bool appUnlocked = false;
  bool biometricUnlockEnabled = false;
  bool biometricDeviceSupported = false;
  bool biometricAvailable = false;
  String biometricLabel = 'بیومتریک';

  final RefreshCoordinator _refreshCoordinator = RefreshCoordinator();
  final ResumeRefreshDebouncer _resumeDebouncer = ResumeRefreshDebouncer();

  bool get canMutate => authenticated && !readOnlyOffline;

  Future<void> init({Database? testDb}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _loadAppLock();

      if (testDb != null) {
        await _bootLocalWorkspace(testDb);
        return;
      }

      _session = await SessionStore.load();
      baseUrl = _session!.baseUrl;
      _api = InvestApiClient(_session!);
      remote = RemoteInvestService(_api!);
      commodityIndexService = CommodityIndexService();
      quotes = QuoteClients();
      _api!.restoreSessionCookie();
      userPhone = _session!.phone;

      final auth = await _api!.checkAuthDetailed();
      switch (auth.status) {
        case AuthCheckStatus.authenticated:
          offline = false;
          readOnlyOffline = false;
          useRemote = true;
          authenticated = true;
          try {
            await _loadRemoteData();
          } on InvestApiException catch (e) {
            if (e.errorCode == 'network_error' || e.statusCode == null) {
              await _bootOfflineWithSession();
            } else {
              rethrow;
            }
          }
        case AuthCheckStatus.offline:
          await _bootOfflineWithSession();
        case AuthCheckStatus.unauthenticated:
          authenticated = false;
          offline = false;
          await _loadCommodityCacheQuietly();
      }
    } catch (e) {
      error = e.toString();
      if (metrics == null) {
        final recovered = await _tryBootFromCache();
        if (recovered) {
          error = null;
        }
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadAppLock() async {
    appLockHash = await AppLockStore.loadHash();
    appLockEnabled = isAppLockEnabled(appLockHash);
    appUnlocked = !appLockEnabled;
    biometricUnlockEnabled = await AppLockStore.loadBiometricEnabled();
    await refreshBiometricCapability();
    if (!appLockEnabled && biometricUnlockEnabled) {
      biometricUnlockEnabled = false;
      await AppLockStore.saveBiometricEnabled(false);
    }
  }

  Future<void> _bootLocalWorkspace(Database db) async {
    useRemote = false;
    offline = true;
    readOnlyOffline = false;
    await AppDatabase.instance.bind(db);
    trades = TradeService(db);
    portfolio = PortfolioService(db);
    settingsRepo = SettingsRepository(db);
    quotes = QuoteClients();
    commodityIndexService = CommodityIndexService();
    authenticated = true;
    await _loadLocalSettings();
    await refresh();
  }

  Future<void> _bootOfflineWithSession() async {
    offline = true;
    authenticated = true;
    userPhone = _session?.phone;
    final loaded = await _applyPortfolioCache();
    if (loaded) {
      useRemote = true;
      readOnlyOffline = true;
      return;
    }
    // No remote cache — open writable local SQLite workspace.
    await _enterLocalSqliteMode(markOffline: true);
  }

  Future<bool> _tryBootFromCache() async {
    final loaded = await _applyPortfolioCache();
    if (!loaded) return false;
    offline = true;
    authenticated = true;
    readOnlyOffline = true;
    useRemote = true;
    return true;
  }

  Future<bool> _applyPortfolioCache() async {
    final snap = await OfflineCacheStore.loadPortfolio();
    if (snap == null) return false;
    settings = snap.settings;
    if (settings.wallexUrl.isEmpty) {
      settings.wallexUrl = AppConfig.defaultWallexUrl;
    }
    if (settings.persianToolboxUrl.isEmpty) {
      settings.persianToolboxUrl = AppConfig.defaultPersianToolboxUrl;
    }
    metrics = snap.metrics;
    assets = snap.assets;
    openTrades = snap.openTrades;
    closedTrades = snap.closedTrades;
    liveUsdt = snap.liveUsdt ?? settings.usdtTmnRate;
    liveGold = snap.liveGold ?? settings.goldTmnPerGram;
    lastSyncedAt = snap.savedAt;
    await _loadCommodityCacheQuietly();
    return true;
  }

  Future<void> _loadCommodityCacheQuietly() async {
    final snap = await OfflineCacheStore.loadCommodities();
    if (snap == null) return;
    commodityIndex = snap.quotes;
    wallexMarkets = snap.wallexMarkets;
    commodityIndexUpdatedAt = snap.savedAt;
  }

  Future<void> _enterLocalSqliteMode({required bool markOffline}) async {
    final db = await AppDatabase.instance.database;
    useRemote = false;
    offline = markOffline;
    readOnlyOffline = false;
    trades = TradeService(db);
    portfolio = PortfolioService(db);
    settingsRepo = SettingsRepository(db);
    quotes ??= QuoteClients();
    commodityIndexService ??= CommodityIndexService();
    authenticated = true;
    await _loadLocalSettings();
    // Prefer remote cache settings/theme if local DB is empty-ish.
    final cache = await OfflineCacheStore.loadPortfolio();
    if (cache != null && assets.isEmpty) {
      settings.theme = cache.settings.theme;
      settings.calendar = cache.settings.calendar;
      settings.currency = cache.settings.currency;
    }
    await refresh();
    await _loadCommodityCacheQuietly();
  }

  /// Try reconnect to Vinor after offline boot.
  Future<bool> tryGoOnline() async {
    if (_api == null || _session == null) return false;
    refreshing = true;
    notifyListeners();
    try {
      if (!await _probeOnline()) return false;
      offline = false;
      readOnlyOffline = false;
      useRemote = true;
      authenticated = true;
      userPhone = _session?.phone;
      await _fetchRemotePortfolio(
        includeQuotes: true,
        fetchSettings: true,
        checkApiVersion: true,
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  Future<bool> _probeOnline() async {
    if (_api == null) return false;
    try {
      final auth = await _api!.checkAuthDetailed();
      return auth.status == AuthCheckStatus.authenticated;
    } catch (_) {
      return false;
    }
  }

  /// Debounced refresh after returning from Vinor WebView / app resume.
  void onAppResumed() {
    if (!authenticated || loading) return;
    _resumeDebouncer.schedule(() async {
      if (offline) {
        await tryGoOnline();
        return;
      }
      await refreshAll(
        includeQuotes: true,
        fetchSettings: true,
        checkApiVersion: true,
      );
    });
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
      offline = false;
      readOnlyOffline = false;
      useRemote = true;
      await _loadRemoteData();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _api?.logout();
    authenticated = false;
    offline = false;
    readOnlyOffline = false;
    userPhone = null;
    metrics = null;
    assets = [];
    openTrades = [];
    closedTrades = [];
    if (appLockEnabled) {
      appUnlocked = false;
    }
    notifyListeners();
  }

  Future<bool> unlockApp(String password) async {
    if (!appLockEnabled) {
      appUnlocked = true;
      notifyListeners();
      return true;
    }
    if (verifyAppLockPassword(password, appLockHash!)) {
      appUnlocked = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> refreshBiometricCapability() async {
    biometricDeviceSupported = await BiometricAuth.isDeviceSupported();
    biometricAvailable = await BiometricAuth.hasEnrolledBiometrics();
    if (biometricDeviceSupported) {
      biometricLabel =
          BiometricAuth.labelForTypes(await BiometricAuth.availableTypes());
    }
    notifyListeners();
  }

  Future<bool> unlockWithBiometric() async {
    if (!appLockEnabled || !biometricUnlockEnabled || !biometricAvailable) {
      return false;
    }
    final result = await BiometricAuth.authenticate(
      reason: 'برای باز کردن V+ احراز هویت کنید',
      biometricOnly: true,
    );
    if (result.success) {
      appUnlocked = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Returns an error message on failure, or null on success.
  Future<String?> setBiometricUnlockEnabled(bool enabled) async {
    if (enabled) {
      if (!appLockEnabled) {
        return 'ابتدا رمز ورود برنامه را تنظیم کنید.';
      }
      await refreshBiometricCapability();
      if (!biometricDeviceSupported) {
        return 'این دستگاه از بیومتریک پشتیبانی نمی‌کند.';
      }
      if (!biometricAvailable) {
        return 'ابتدا اثر انگشت یا چهره را در تنظیمات گوشی ثبت کنید.';
      }
      final result = await BiometricAuth.authenticate(
        reason: 'برای فعال‌سازی $biometricLabel احراز هویت کنید',
        biometricOnly: false,
      );
      if (!result.success) {
        return result.message ?? 'فعال‌سازی بیومتریک انجام نشد.';
      }
      await AppLockStore.saveBiometricEnabled(true);
      biometricUnlockEnabled = true;
    } else {
      await AppLockStore.saveBiometricEnabled(false);
      biometricUnlockEnabled = false;
    }
    notifyListeners();
    return null;
  }

  Future<void> setAppLockPassword(String password) async {
    final hash = hashAppLockPassword(password);
    await AppLockStore.saveHash(hash);
    appLockHash = hash;
    appLockEnabled = true;
    appUnlocked = true;
    notifyListeners();
  }

  Future<void> removeAppLock() async {
    await AppLockStore.saveHash('');
    appLockHash = null;
    appLockEnabled = false;
    biometricUnlockEnabled = false;
    appUnlocked = true;
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

  Future<void> refreshCommodityIndex() async {
    if (commodityIndexService == null) return;
    commodityIndexLoading = true;
    commodityIndexError = null;
    notifyListeners();
    try {
      final bundle = await commodityIndexService!.fetchAll(
        wallexUrl: settings.wallexUrl.isEmpty
            ? AppConfig.defaultWallexUrl
            : settings.wallexUrl,
      );
      if (bundle.hasAnyPrice) {
        commodityIndex = bundle.essentials;
        wallexMarkets = bundle.wallexMarkets;
        commodityIndexUpdatedAt = DateTime.now();
        await OfflineCacheStore.saveCommodities(
          bundle.essentials,
          wallexMarkets: bundle.wallexMarkets,
        );
        commodityIndexError = null;
      } else {
        final cached = await OfflineCacheStore.loadCommodities();
        if (cached != null) {
          commodityIndex = cached.quotes;
          wallexMarkets = cached.wallexMarkets;
          commodityIndexUpdatedAt = cached.savedAt;
          commodityIndexError = 'آفلاین — قیمت‌های ذخیره‌شده نمایش داده می‌شود';
        } else {
          commodityIndexError = 'دریافت قیمت‌ها ممکن نشد';
        }
      }
    } catch (e) {
      final cached = await OfflineCacheStore.loadCommodities();
      if (cached != null) {
        commodityIndex = cached.quotes;
        wallexMarkets = cached.wallexMarkets;
        commodityIndexUpdatedAt = cached.savedAt;
        commodityIndexError = 'آفلاین — قیمت‌های ذخیره‌شده نمایش داده می‌شود';
      } else {
        commodityIndexError = e.toString();
      }
    } finally {
      commodityIndexLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadRemoteData() async {
    await refresh();
  }

  /// Updates settings when backend API version changes (no nested refresh).
  Future<void> _syncApiVersion() async {
    if (_api == null || _session == null || !useRemote || offline) return;
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
    if (readOnlyOffline) {
      error = 'در حالت آفلاین فقط مشاهده ممکن است. برای ذخیره آنلاین شوید.';
      notifyListeners();
      return;
    }
    settings = s;
    if (useRemote && !offline) {
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
    await refreshAll(
      includeQuotes: false,
      fetchSettings: false,
      checkApiVersion: false,
    );
  }

  /// Coalesced refresh — overlapping pulls merge into one run.
  Future<void> refreshAll({
    bool includeQuotes = true,
    bool fetchSettings = true,
    bool checkApiVersion = true,
  }) {
    return _refreshCoordinator.run(
      (plan) => _runRefresh(plan),
      includeQuotes: includeQuotes,
      fetchSettings: fetchSettings,
      checkApiVersion: checkApiVersion,
    );
  }

  Future<void> refresh() =>
      refreshAll(includeQuotes: false, fetchSettings: true, checkApiVersion: true);

  Future<void> refreshQuotes() => refreshAll(
        includeQuotes: true,
        fetchSettings: false,
        checkApiVersion: false,
      );

  Future<void> _runRefresh(RefreshPlan plan) async {
    refreshing = true;
    notifyListeners();
    try {
      if (offline && readOnlyOffline && useRemote) {
        if (await _probeOnline()) {
          offline = false;
          readOnlyOffline = false;
        } else {
          error = null;
          return;
        }
      }

      if (plan.includeQuotes && settings.livePricesEnabled) {
        await _syncLiveQuotes();
      }
      if (useRemote && !offline) {
        await _fetchRemotePortfolio(
          includeQuotes: false,
          fetchSettings: plan.fetchSettings,
          checkApiVersion: plan.checkApiVersion,
        );
      } else if (!useRemote) {
        assets = await trades!.assets.listAll();
        openTrades = await trades!.trades.listOpen();
        closedTrades = await trades!.trades.listClosed();
        metrics = await portfolio!.getMetrics(calendar: settings.calendar);
        await portfolio!.recordSnapshot();
        lastSyncedAt = DateTime.now();
      }
      error = null;
    } on InvestApiException catch (e) {
      if (e.statusCode == 401) {
        await logout();
      } else if (e.errorCode == 'network_error') {
        offline = true;
        final loaded = await _applyPortfolioCache();
        if (loaded) {
          readOnlyOffline = true;
          error = null;
        } else {
          error = e.message;
        }
      } else {
        error = e.message;
      }
    } catch (e) {
      error = e.toString();
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  Future<void> _fetchRemotePortfolio({
    required bool includeQuotes,
    required bool fetchSettings,
    required bool checkApiVersion,
  }) async {
    if (includeQuotes && settings.livePricesEnabled) {
      await _syncLiveQuotes();
    }
    if (checkApiVersion) {
      await _syncApiVersion();
    }
    if (fetchSettings) {
      settings = await remote!.fetchSettings();
    }
    final svc = remote!;
    metrics = await svc.fetchDashboard(settings.calendar);
    assets = await svc.assets.listAll();
    openTrades = await svc.listOpen();
    closedTrades = await svc.listClosed();
    lastSyncedAt = DateTime.now();
    await OfflineCacheStore.savePortfolio(
      settings: settings,
      metrics: metrics!,
      assets: assets,
      openTrades: openTrades,
      closedTrades: closedTrades,
      liveUsdt: liveUsdt,
      liveGold: liveGold,
    );
  }

  Future<void> _syncLiveQuotes() async {
    if (useRemote && !offline) {
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

    if (trades == null || quotes == null) return;

    double? usdt;
    double? gold;
    if (settings.usdtApiEnabled) {
      usdt = await quotes!.fetchUsdtToman(wallexUrl: settings.wallexUrl);
      if (usdt != null) {
        liveUsdt = usdt;
        settings.usdtTmnRate = usdt;
        await settingsRepo?.set(AppConfig.settingUsdtTmn, usdt.toString());
      }
    }
    if (settings.goldApiEnabled) {
      final g =
          await quotes!.fetchGoldToman(persianUrl: settings.persianToolboxUrl);
      gold = g.price;
      if (gold != null) {
        liveGold = gold;
        settings.goldTmnPerGram = gold;
        await settingsRepo?.set(AppConfig.settingGoldTmn, gold.toString());
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
  dynamic get tradeService => useRemote && !offline ? remote : trades;
}

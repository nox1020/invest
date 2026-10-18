import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:invest/config/app_config.dart';
import 'package:invest/data/app_lock_store.dart';
import 'package:invest/data/app_database.dart';
import 'package:invest/data/check_repository.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/notification_inbox_store.dart';
import 'package:invest/data/offline_cache_store.dart';
import 'package:invest/data/remote_invest_service.dart';
import 'package:invest/data/repositories.dart';
import 'package:invest/data/session_store.dart';
import 'package:invest/data/withdrawal_repository.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/models/year_nav_entry.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/iran_inflation.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/models/profit_alert.dart';
import 'package:invest/domain/services/backup_payload.dart';
import 'package:invest/domain/services/backup_service.dart';
import 'package:invest/domain/services/chart_series.dart';
import 'package:invest/domain/services/check_ledger.dart';
import 'package:invest/domain/services/commodity_index_service.dart';
import 'package:invest/domain/services/iran_inflation_service.dart';
import 'package:invest/domain/services/notification_service.dart';
import 'package:invest/domain/services/portfolio_service.dart';
import 'package:invest/domain/services/price_alert_engine.dart';
import 'package:invest/domain/services/price_alert_prefs.dart';
import 'package:invest/domain/services/profit_alert_engine.dart';
import 'package:invest/domain/services/background_price_worker.dart';
import 'package:invest/domain/services/quote_clients.dart';
import 'package:invest/domain/services/gold_quote_parser.dart';
import 'package:invest/domain/services/live_toman_price.dart';
import 'package:invest/domain/services/trade_service.dart';
import 'package:invest/domain/services/invest_mutations.dart';
import 'package:invest/domain/services/withdrawal_allowance.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/security/app_lock.dart';
import 'package:invest/security/biometric_auth.dart';
import 'package:invest/services/refresh_coordinator.dart';
import 'package:invest/ui/widgets/user_error.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// App-wide state — online (Vinor API), offline cache, or local SQLite.
class AppState extends ChangeNotifier {
  AppState({http.Client? httpClient}) : _httpClient = httpClient;

  final http.Client? _httpClient;

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
  WithdrawalRepository? _withdrawalsRepo;
  CheckRepository? _checksRepo;
  QuoteClients? quotes;
  CommodityIndexService? commodityIndexService;

  AppSettings settings = AppSettings();
  DashboardMetrics? metrics;
  List<Asset> assets = [];
  List<Trade> openTrades = [];
  List<Trade> closedTrades = [];
  List<Withdrawal> withdrawals = [];
  List<BankCheck> checks = [];
  bool _withdrawalsFromRemote = false;

  /// True when withdrawals are stored in Vinor settings (`client_withdrawals`)
  /// because the dedicated withdrawals API is unavailable.
  bool _withdrawalsViaSettings = false;

  /// Set after withdrawals have been loaded/restored this session so settings
  /// pushes cannot wipe the server mirror with an empty default list.
  bool _withdrawalsHydrated = false;

  /// Set after the cheque book has been loaded so a settings push cannot
  /// wipe the server mirror with an empty default list.
  bool _checksHydrated = false;

  /// Local cheque book differs from the server and must be pushed before a
  /// fetch is allowed to replace it.
  bool _checksPendingSync = false;

  /// `GET /checks` answered, so that resource — not the settings blob — owns
  /// the book.
  bool _checksFromRemote = false;

  /// Ids removed on this phone that the server may still have.
  final Set<int> _pendingDeletedCheckIds = {};

  bool _checksSyncing = false;

  /// Persian message from the last rejected cheque write, if any.
  String? checkSyncError;

  /// Online, and the server has not echoed this device's cheque book yet.
  bool get checksAwaitingServer =>
      _checksPendingSync && useRemote && !offline && !readOnlyOffline;

  final Set<String> _checkAlertKeys = {};
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

  IranInflationService? iranInflationService;
  IranInflationSnapshot? iranInflation;
  bool iranInflationLoading = false;
  String? iranInflationError;

  String? appLockHash;
  bool appLockEnabled = false;
  bool appUnlocked = false;
  bool biometricUnlockEnabled = false;
  bool biometricDeviceSupported = false;
  bool biometricAvailable = false;
  String biometricLabel = 'بیومتریک';

  final RefreshCoordinator _refreshCoordinator = RefreshCoordinator();
  final ResumeRefreshDebouncer _resumeDebouncer = ResumeRefreshDebouncer();
  Timer? _autoRefreshTimer;
  Future<void>? _indexRefreshFuture;
  bool _indexRefreshWantForce = false;
  bool _autoRefreshBusy = false;
  int _autoRefreshTicks = 0;

  /// When true, [notifyListeners] is a no-op so a half-applied portfolio
  /// fetch (server marks before live overlay) cannot flash the NAV card.
  bool _holdUiNotifications = false;

  @visibleForTesting
  set debugHoldUiNotifications(bool value) => _holdUiNotifications = value;

  bool get canMutate => authenticated && !readOnlyOffline;

  @override
  void notifyListeners() {
    if (_holdUiNotifications) return;
    super.notifyListeners();
  }

  List<SeriesPoint> get capitalGrowthSeries {
    final holdings = HoldingMetrics.activeHoldings(
      assets: assets,
      openTrades: openTrades,
    );
    final liveValue =
        holdings.fold<double>(0, (s, h) => s + h.metrics.marketValue);
    return ensureChartSeries(
      metrics?.growthSeries ?? const [],
      todayValue: liveValue,
    );
  }

  List<SeriesPoint> get yearRealizedChartSeries {
    final m = metrics;
    if (m == null) return const [];
    return yearRealizedSeries(
      closedTrades: closedTrades,
      yearKey: m.yearKey,
      calendar: settings.calendar,
    );
  }

  double get withdrawnTotal => withdrawals
      .where((w) => w.status != 'rejected')
      .fold<double>(0, (s, w) => s + w.amount);

  WithdrawalAllowance get withdrawalAllowance {
    // Prefer Σ closed lots so allowance matches the dashboard realized ledger
    // even when remote metrics lag local closed trades.
    final realized = closedTrades.fold<double>(
      0,
      (s, t) => s + (t.realizedPnl ?? 0),
    );
    return WithdrawalAllowance.compute(
      realizedPnl: realized,
      openTrades: openTrades,
      closedTrades: closedTrades,
      withdrawals: withdrawals,
      annualPct: settings.annualWithdrawalPct,
      calendar: settings.calendar,
      yearKey: metrics?.yearKey,
    );
  }

  double get withdrawableAmount => withdrawalAllowance.available;

  CheckLedger get checkLedger => CheckLedger.summarize(checks);

  Future<WithdrawalRepository> _localWithdrawals() async {
    _withdrawalsRepo ??=
        WithdrawalRepository(await AppDatabase.instance.database);
    return _withdrawalsRepo!;
  }

  Future<CheckRepository> _localChecks() async {
    _checksRepo ??= CheckRepository(await AppDatabase.instance.database);
    return _checksRepo!;
  }

  Future<void> init({Database? testDb}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      // The login screen only needs this client. App lock, biometrics, and
      // local storage must not run first: if they throw, OTP used to fail
      // with «API آماده نیست» because the client was never created.
      await _ensureRemoteClient();
      try {
        await _loadAppLock();
      } catch (_) {}

      if (testDb != null) {
        await _bootLocalWorkspace(testDb);
        return;
      }

      await _ensureRemoteClient();
      commodityIndexService = CommodityIndexService();
      iranInflationService = IranInflationService();
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
            _startAutoRefreshTimer();
          } on InvestApiException catch (e) {
            if (e.errorCode == 'network_error' || e.statusCode == null) {
              await _bootOfflineWithSession();
              _startAutoRefreshTimer();
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
      error = formatUserError(e);
      if (metrics == null) {
        final recovered = await _tryBootFromCache();
        if (recovered) {
          error = null;
        }
      }
    } finally {
      loading = false;
      await _loadPriceAlertRuntime();
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
    _withdrawalsRepo = WithdrawalRepository(db);
    _checksRepo = CheckRepository(db);
    quotes = QuoteClients();
    commodityIndexService = CommodityIndexService();
    iranInflationService = IranInflationService();
    authenticated = true;
    await _loadLocalSettings();
    await _loadPriceAlertRuntime();
    await refresh();
    _startAutoRefreshTimer();
  }

  Future<void> _bootOfflineWithSession() async {
    offline = true;
    authenticated = true;
    userPhone = _session?.phone;
    final loaded = await _applyPortfolioCache();
    if (loaded) {
      useRemote = true;
      readOnlyOffline = true;
      _startAutoRefreshTimer();
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
    _startAutoRefreshTimer();
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
    _normalizeGoldApiUrl();
    metrics = snap.metrics;
    assets = snap.assets;
    openTrades = snap.openTrades;
    closedTrades = snap.closedTrades;
    withdrawals = snap.withdrawals;
    checks = List<BankCheck>.from(snap.checks);
    if (checks.isEmpty) {
      await _loadLocalChecks();
    } else {
      await _persistChecksLocal();
    }
    _withdrawalsHydrated = true;
    _checksHydrated = true;
    liveUsdt = snap.liveUsdt ?? settings.usdtTmnRate;
    liveGold = snap.liveGold ?? settings.goldTmnPerGram;
    lastSyncedAt = snap.savedAt;
    await _loadCommodityCacheQuietly();
    await _loadPriceAlertRuntime();
    return true;
  }

  Future<void> _loadCommodityCacheQuietly() async {
    final snap = await OfflineCacheStore.loadCommodities();
    if (snap != null) {
      commodityIndex = CommodityIndexService.alignDerivedQuotes(snap.quotes);
      wallexMarkets = snap.wallexMarkets;
      commodityIndexUpdatedAt = snap.savedAt;
    }
    final inflation = await OfflineCacheStore.loadIranInflation();
    if (inflation != null) {
      iranInflation = inflation;
    }
  }

  Future<void> _enterLocalSqliteMode({required bool markOffline}) async {
    final db = await AppDatabase.instance.database;
    useRemote = false;
    offline = markOffline;
    readOnlyOffline = false;
    trades = TradeService(db);
    portfolio = PortfolioService(db);
    settingsRepo = SettingsRepository(db);
    _withdrawalsRepo = WithdrawalRepository(db);
    _checksRepo = CheckRepository(db);
    quotes ??= QuoteClients();
    commodityIndexService ??= CommodityIndexService();
    iranInflationService ??= IranInflationService();
    authenticated = true;
    await _loadLocalSettings();
    await _loadPriceAlertRuntime();
    // Prefer remote cache settings/theme if local DB is empty-ish.
    final cache = await OfflineCacheStore.loadPortfolio();
    if (cache != null && assets.isEmpty) {
      settings.theme = cache.settings.theme;
      settings.calendar = cache.settings.calendar;
      settings.currency = cache.settings.currency;
    }
    await refresh();
    await _loadCommodityCacheQuietly();
    _startAutoRefreshTimer();
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
      _startAutoRefreshTimer();
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
      await refreshCommodityIndex(force: true);
    });
  }

  /// Builds the Vinor client even when [init] has not finished or an earlier
  /// startup step failed. Login calls this directly.
  Future<void> _ensureRemoteClient() async {
    if (_api != null && _session != null) return;
    _session ??= await SessionStore.load();
    final url = _session!.baseUrl.trim();
    baseUrl = url.isEmpty ? AppConfig.defaultBaseUrl : url;
    _api ??= InvestApiClient(_session!, client: _httpClient);
    remote ??= RemoteInvestService(_api!);
    quotes ??= QuoteClients();
  }

  Future<String?> requestOtp(String phone) async {
    await _ensureRemoteClient();
    return _api!.requestOtp(phone);
  }

  Future<void> verifyOtp(String phone, String code) async {
    await _ensureRemoteClient();
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
      _startAutoRefreshTimer();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _stopAutoRefreshTimer();
    if (!_checksHydrated) {
      await _loadLocalChecks();
    }
    await _stashChecksForCurrentPhone();
    await _clearActiveCheckTable();
    await _api?.logout();
    authenticated = false;
    offline = false;
    readOnlyOffline = false;
    userPhone = null;
    metrics = null;
    assets = [];
    openTrades = [];
    closedTrades = [];
    withdrawals = [];
    checks = [];
    _withdrawalsFromRemote = false;
    _withdrawalsViaSettings = false;
    _withdrawalsHydrated = false;
    _checksHydrated = false;
    _checksPendingSync = false;
    _checksFromRemote = false;
    _pendingDeletedCheckIds.clear();
    checkSyncError = null;
    _checkAlertKeys.clear();
    try {
      await OfflineCacheStore.clearUserData();
      await PriceAlertPrefs.clear();
      await NotificationInboxStore.clear();
    } catch (_) {}
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
    await _pushUserExtrasToServer();
    return null;
  }

  Future<void> setAppLockPassword(String password) async {
    final hash = hashAppLockPassword(password);
    await AppLockStore.saveHash(hash);
    appLockHash = hash;
    appLockEnabled = true;
    appUnlocked = true;
    notifyListeners();
    await _pushUserExtrasToServer();
  }

  Future<void> removeAppLock() async {
    await AppLockStore.saveHash('');
    await AppLockStore.saveBiometricEnabled(false);
    appLockHash = null;
    appLockEnabled = false;
    biometricUnlockEnabled = false;
    appUnlocked = true;
    notifyListeners();
    await _pushUserExtrasToServer();
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

  Future<void> refreshCommodityIndex({bool force = false}) async {
    if (commodityIndexService == null) return;
    if (_indexRefreshFuture != null) {
      if (force) _indexRefreshWantForce = true;
      return _indexRefreshFuture!;
    }
    _indexRefreshWantForce = force;
    final run = _runCommodityIndexRefresh();
    _indexRefreshFuture = run;
    try {
      await run;
    } finally {
      _indexRefreshFuture = null;
      if (_indexRefreshWantForce) {
        _indexRefreshWantForce = false;
        // A force request arrived while we were busy — follow up once.
        unawaited(refreshCommodityIndex(force: true));
      }
    }
  }

  Future<void> _runCommodityIndexRefresh() async {
    final force = _indexRefreshWantForce;
    _indexRefreshWantForce = false;
    commodityIndexLoading = true;
    commodityIndexError = null;
    notifyListeners();
    try {
      IranInflationSnapshot? appliedInflation;

      // Prefer Vinor shared store (server refresh + persistence).
      if (useRemote && !offline && remote != null && authenticated) {
        try {
          final remoteBundle = await remote!.fetchMarketIndex(force: force);
          if (remoteBundle != null &&
              (remoteBundle.hasAnyPrice || remoteBundle.inflation != null)) {
            if (remoteBundle.hasAnyPrice) {
              var essentials = remoteBundle.essentials;
              // Vinor index gold is often understated toolbox spot — patch 18k.
              final freeGold = await _fetchFreeMarketGold();
              if (freeGold?.price != null) {
                essentials = [
                  for (final q in essentials)
                    if (q.id == 'gold')
                      q.copyWith(
                        price: freeGold!.price,
                        change24h: freeGold.change24h,
                        goldKarat: 18,
                        unit: 'toman_per_gram',
                        clearChange: freeGold.change24h == null,
                      )
                    else
                      q,
                ];
              }
              await _applyIndexBundle(
                essentials: essentials,
                wallex: remoteBundle.wallexMarkets,
                inflation: remoteBundle.inflation,
                updatedAt: remoteBundle.updatedAt ?? DateTime.now(),
                error: remoteBundle.stale
                    ? (remoteBundle.warning ??
                        remoteBundle.error ??
                        'آفلاین — قیمت‌های ذخیره‌شده روی سرور')
                    : (remoteBundle.error ?? remoteBundle.warning),
              );
              appliedInflation = remoteBundle.inflation ?? iranInflation;
            } else if (remoteBundle.inflation != null) {
              iranInflation = remoteBundle.inflation;
              iranInflationError = null;
              await OfflineCacheStore.saveIranInflation(
                  remoteBundle.inflation!);
              appliedInflation = remoteBundle.inflation;
            }
            // Markets ok but inflation missing → fill from Hugging Face.
            if (appliedInflation == null ||
                force ||
                DateTime.now().difference(appliedInflation.fetchedAt) >
                    const Duration(hours: 6)) {
              await _ensureIranInflation(
                  force: force || appliedInflation == null);
            }
            return;
          }
        } catch (_) {
          // Fall through to direct external fetch + push.
        }
      }

      final bundle = await commodityIndexService!.fetchAll(
        wallexUrl: settings.wallexUrl.isEmpty
            ? AppConfig.defaultWallexUrl
            : settings.wallexUrl,
        goldUrl: settings.persianToolboxUrl,
      );
      if (bundle.hasAnyPrice) {
        IranInflationSnapshot? inflation = iranInflation;
        try {
          inflation = await _fetchIranInflationIfNeeded(
            force: force,
            current: inflation,
          );
        } catch (_) {}

        await _applyIndexBundle(
          essentials: bundle.essentials,
          wallex: bundle.wallexMarkets,
          inflation: inflation,
          updatedAt: DateTime.now(),
        );

        if (useRemote && !offline && remote != null && authenticated) {
          try {
            await remote!.pushMarketIndex(
              essentials: bundle.essentials,
              wallexMarkets: bundle.wallexMarkets,
              inflation: inflation,
            );
          } catch (_) {}
        }
      } else {
        await _loadIndexFromCache(
          message: 'آفلاین — قیمت‌های ذخیره‌شده نمایش داده می‌شود',
        );
        await _ensureIranInflation(force: false);
      }
    } catch (e) {
      await _loadIndexFromCache(
        message: 'آفلاین — قیمت‌های ذخیره‌شده نمایش داده می‌شود',
        fallbackError: formatUserError(e),
      );
    } finally {
      commodityIndexLoading = false;
      notifyListeners();
    }
  }

  Future<IranInflationSnapshot?> _fetchIranInflationIfNeeded({
    required bool force,
    IranInflationSnapshot? current,
  }) async {
    if (!force &&
        current != null &&
        DateTime.now().difference(current.fetchedAt) <
            const Duration(hours: 6)) {
      return current;
    }
    iranInflationService ??= IranInflationService();
    return iranInflationService!.fetchLatest();
  }

  Future<void> _ensureIranInflation({required bool force}) async {
    try {
      final next = await _fetchIranInflationIfNeeded(
        force: force,
        current: iranInflation,
      );
      if (next == null) return;
      iranInflation = next;
      iranInflationError = null;
      await OfflineCacheStore.saveIranInflation(next);
      if (useRemote && !offline && remote != null && authenticated) {
        try {
          await remote!.pushMarketIndex(
            essentials: commodityIndex,
            wallexMarkets: wallexMarkets,
            inflation: next,
          );
        } catch (_) {}
      }
    } catch (e) {
      if (iranInflation == null) {
        final cached = await OfflineCacheStore.loadIranInflation();
        if (cached != null) {
          iranInflation = cached;
          iranInflationError = 'آفلاین — آخرین داده تورم ذخیره‌شده';
        } else {
          iranInflationError = formatUserError(e);
        }
      }
    }
  }

  Future<void> _applyIndexBundle({
    required List<CommodityQuote> essentials,
    required List<CommodityQuote> wallex,
    IranInflationSnapshot? inflation,
    required DateTime updatedAt,
    String? error,
  }) async {
    commodityIndex = essentials.isNotEmpty
        ? CommodityIndexService.alignDerivedQuotes(essentials)
        : commodityIndex;
    wallexMarkets = wallex.isNotEmpty ? wallex : wallexMarkets;
    commodityIndexUpdatedAt = updatedAt;
    commodityIndexError = (error != null && error.trim().isNotEmpty)
        ? formatUserError(error)
        : error;
    await OfflineCacheStore.saveCommodities(
      commodityIndex,
      wallexMarkets: wallexMarkets,
    );
    if (inflation != null) {
      iranInflation = inflation;
      iranInflationError = null;
      await OfflineCacheStore.saveIranInflation(inflation);
    }
    for (final q in essentials) {
      if (q.id == 'usdt' && q.price != null && q.price! > 0) {
        liveUsdt = q.price;
      }
      if (q.id == 'gold' && q.price != null && q.price! > 0) {
        liveGold = q.price;
        settings.goldTmnPerGram = q.price;
      }
    }
    await _overlayLiveMarks(persistLocal: true);
    await _dispatchPriceAlerts();
  }

  Future<void> _loadIndexFromCache({
    required String message,
    String? fallbackError,
  }) async {
    final cached = await OfflineCacheStore.loadCommodities();
    if (cached != null) {
      commodityIndex = CommodityIndexService.alignDerivedQuotes(cached.quotes);
      wallexMarkets = cached.wallexMarkets;
      commodityIndexUpdatedAt = cached.savedAt;
      commodityIndexError = message;
    } else {
      commodityIndexError = fallbackError ?? 'دریافت قیمت‌ها ممکن نشد';
    }
    final inf = await OfflineCacheStore.loadIranInflation();
    if (inf != null) {
      iranInflation = inf;
    }
  }

  void _startAutoRefreshTimer({bool immediate = true}) {
    _autoRefreshTimer?.cancel();
    if (!authenticated) return;
    _autoRefreshTimer = Timer.periodic(settings.autoRefreshInterval, (_) {
      unawaited(_tickAutoRefresh());
    });
    if (immediate) {
      // Run after the current boot/login `finally` so `loading` is already false.
      Timer.run(() => unawaited(_tickAutoRefresh(forceIndex: true)));
    }
  }

  void _stopAutoRefreshTimer() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  Future<void> _tickAutoRefresh({bool forceIndex = false}) async {
    if (!authenticated || loading || _autoRefreshBusy) return;
    _autoRefreshBusy = true;
    try {
      _autoRefreshTicks++;
      if (settings.livePricesEnabled) {
        await _syncLiveQuotes();
        await refreshCommodityIndex(force: forceIndex);
      }
      // Full portfolio every ~30s (or on the first forced tick).
      final full = forceIndex || _autoRefreshTicks % 6 == 1;
      if (full) {
        await refreshAll(
          includeQuotes: false,
          fetchSettings: false,
          checkApiVersion: false,
        );
      }
    } finally {
      _autoRefreshBusy = false;
    }
  }

  @override
  void dispose() {
    _stopAutoRefreshTimer();
    _resumeDebouncer.dispose();
    super.dispose();
  }

  Future<void> refreshIranInflation({bool force = true}) async {
    if (!force &&
        iranInflation != null &&
        DateTime.now().difference(iranInflation!.fetchedAt) <
            const Duration(hours: 6)) {
      return;
    }
    iranInflationLoading = true;
    notifyListeners();
    try {
      // Prefer lightweight inflation fill; markets refresh only when forced.
      if (force) {
        await refreshCommodityIndex(force: true);
      } else {
        await _ensureIranInflation(force: false);
      }
    } finally {
      iranInflationLoading = false;
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
      final prevRefresh = settings.autoRefreshSeconds;
      final bundle = await remote!.fetchSettings();
      await _applyRemoteSettingsBundle(bundle, migrate: true);
      _normalizeGoldApiUrl();
      if (settings.autoRefreshSeconds != prevRefresh) {
        _startAutoRefreshTimer(immediate: false);
      }
    }
  }

  Future<void> _loadLocalSettings() async {
    final map = await settingsRepo!.loadAll();
    settings = AppSettings.fromStorageMap(map);
    _normalizeGoldApiUrl();
  }

  /// Migrate dead / understated gold feeds to the free 18k WallGold default.
  void _normalizeGoldApiUrl() {
    final current = settings.persianToolboxUrl.trim();
    final resolved = GoldQuoteParser.resolveConfiguredUrl(current);
    if (resolved != current) {
      settings.persianToolboxUrl = resolved;
    }
  }

  Future<void> saveSettings(AppSettings s) async {
    if (readOnlyOffline) {
      throw StateError(
        'در حالت آفلاین فقط مشاهده ممکن است. برای ذخیره آنلاین شوید.',
      );
    }
    final prevUsdt = s.usdtTmnRate ?? settings.usdtTmnRate;
    final prevGold = s.goldTmnPerGram ?? settings.goldTmnPerGram;
    final prevWallex =
        s.wallexUrl.trim().isNotEmpty ? s.wallexUrl : settings.wallexUrl;
    final prevPersian = s.persianToolboxUrl.trim().isNotEmpty
        ? s.persianToolboxUrl
        : settings.persianToolboxUrl;
    final sentAnnualPct =
        AppSettings.clampAnnualWithdrawalPct(s.annualWithdrawalPct);
    final sentYearNav = List<YearNavEntry>.from(s.yearNavHistory);

    settings = s
      ..usdtTmnRate = prevUsdt
      ..goldTmnPerGram = prevGold
      ..wallexUrl = prevWallex
      ..persianToolboxUrl = prevPersian
      ..annualWithdrawalPct = sentAnnualPct
      ..yearNavHistory = sentYearNav;
    notifyListeners();

    Object? remoteError;
    if (useRemote && !offline && remote != null) {
      try {
        final bundle = await _putRemoteSettings(
          includeChecks: !_checksFromRemote,
        );
        settings = bundle.settings;
        _noteCheckEcho(bundle);
        // Re-assert the percent we wrote — response/raw may still carry the
        // previous server value on older backends.
        settings.annualWithdrawalPct = sentAnnualPct;
        settings.yearNavHistory = List<YearNavEntry>.from(sentYearNav);
        if (settings.wallexUrl.trim().isEmpty) {
          settings.wallexUrl = prevWallex;
        }
        if (settings.persianToolboxUrl.trim().isEmpty) {
          settings.persianToolboxUrl = prevPersian;
        }
        await _applyRemoteLockFromBundle(bundle);
        if (bundle.hasClientWithdrawals && !_withdrawalsFromRemote) {
          withdrawals = List<Withdrawal>.from(bundle.clientWithdrawals);
          _withdrawalsViaSettings = true;
        }
        // Cheque edits are pushed from memory. Do not replace that book with
        // the PUT echo — an older server may echo a stale list.
      } catch (e) {
        remoteError = e;
      }
    }
    // Always persist locally so the wheel choice survives even if Vinor lags.
    await _persistSettingsLocal(settings);
    await PriceAlertPrefs.saveFrom(settings);
    await BackgroundPriceWorker.sync(settings);
    notifyListeners();
    _startAutoRefreshTimer(immediate: false);
    if (remoteError != null) {
      throw remoteError;
    }
    await refreshAll(
      includeQuotes: false,
      fetchSettings: false,
      checkApiVersion: false,
    );
    // Refresh must not drop the percent / year-nav we just saved.
    if (settings.annualWithdrawalPct != sentAnnualPct) {
      settings.annualWithdrawalPct = sentAnnualPct;
      await _persistSettingsLocal(settings);
      await PriceAlertPrefs.saveFrom(settings);
      notifyListeners();
    }
    if (!_sameYearNav(settings.yearNavHistory, sentYearNav)) {
      settings.yearNavHistory = List<YearNavEntry>.from(sentYearNav);
      await _persistSettingsLocal(settings);
      await PriceAlertPrefs.saveFrom(settings);
      notifyListeners();
    }
  }

  static bool _sameYearNav(List<YearNavEntry> a, List<YearNavEntry> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].yearKey != b[i].yearKey ||
          (a[i].navToman - b[i].navToman).abs() > 1e-6) {
        return false;
      }
      final au = a[i].navUsd;
      final bu = b[i].navUsd;
      if (au == null && bu == null) continue;
      if (au == null || bu == null || (au - bu).abs() > 1e-6) return false;
    }
    return true;
  }

  /// Saves only the annual withdrawal policy percent (1–100) to memory,
  /// local store, and Vinor settings.
  Future<void> saveAnnualWithdrawalPct(int pct) async {
    final next = settings.copyWith(
      annualWithdrawalPct: AppSettings.clampAnnualWithdrawalPct(pct),
    );
    await saveSettings(next);
  }

  /// Upsert a year-end NAV. [navUsd] is optional manual dollar; when omitted,
  /// USD is derived from live USDT.
  Future<void> upsertYearNav({
    required String yearKey,
    required double navToman,
    double? navUsd,
    bool clearNavUsd = false,
  }) async {
    final key = YearNavList.normalizeYearKey(yearKey);
    if (key.isEmpty) {
      throw ArgumentError('سال الزامی است.');
    }
    if (navToman <= 0) {
      throw ArgumentError('ارزش پایان سال باید بزرگ‌تر از صفر باشد.');
    }
    final live = liveUsdt ?? settings.usdtTmnRate;
    double? usd;
    double? rate;
    if (!clearNavUsd && navUsd != null && navUsd > 0) {
      usd = navUsd;
      rate = navToman / navUsd;
    } else if (live != null && live > 0) {
      rate = live;
      usd = null; // auto via rate
    }
    final entry = YearNavEntry(
      yearKey: key,
      navToman: navToman,
      navUsd: usd,
      usdtRate: rate,
      updatedAt: nowIso(),
    );
    final next = settings.copyWith(
      yearNavHistory: YearNavList.upsert(settings.yearNavHistory, entry),
    );
    await saveSettings(next);
  }

  Future<void> deleteYearNav(String yearKey) async {
    final key = YearNavList.normalizeYearKey(yearKey);
    final next = settings.copyWith(
      yearNavHistory: YearNavList.remove(settings.yearNavHistory, key),
    );
    await saveSettings(next);
  }

  Future<void> _persistSettingsLocal(AppSettings s) async {
    await _ensureLocalSettingsRepo();
    final repo = settingsRepo;
    if (repo == null) return;
    await repo.saveMap(s.toStorageMap());
  }

  Future<void> _ensureLocalSettingsRepo() async {
    if (settingsRepo != null) return;
    try {
      settingsRepo = SettingsRepository(await AppDatabase.instance.database);
    } catch (_) {}
  }

  /// Push settings + lock + optional withdrawal mirror to Vinor.
  Future<RemoteSettingsBundle?> _pushUserExtrasToServer({
    List<Withdrawal>? clientWithdrawals,
    List<BankCheck>? clientChecks,
    bool rethrowErrors = false,
  }) async {
    if (!useRemote || offline || remote == null || readOnlyOffline) return null;
    try {
      final sentYearNav = List<YearNavEntry>.from(settings.yearNavHistory);
      final sentAnnualPct = settings.annualWithdrawalPct;
      // Once `/checks` exists, a settings snapshot must not replace that book.
      final sentChecks = _checksFromRemote
          ? null
          : (clientChecks ?? (_checksHydrated ? checks : null));
      final bundle = await _putRemoteSettings(
        includeChecks: sentChecks != null,
        clientWithdrawals: clientWithdrawals ??
            (_withdrawalsHydrated ? withdrawals : null),
        clientChecks: sentChecks,
      );
      settings = bundle.settings;
      settings.annualWithdrawalPct = sentAnnualPct;
      settings.yearNavHistory = List<YearNavEntry>.from(sentYearNav);
      await _applyRemoteLockFromBundle(bundle);
      await _persistSettingsLocal(settings);
      await PriceAlertPrefs.saveFrom(settings);
      if (sentChecks != null) _noteCheckEcho(bundle);
      return bundle;
    } catch (e) {
      // Best-effort for background migrate; mutations pass [rethrowErrors].
      if (rethrowErrors) rethrow;
      return null;
    }
  }

  /// PUT settings. A 400 caused by the cheque book is retried without it so
  /// the rest of the account settings still save.
  Future<RemoteSettingsBundle> _putRemoteSettings({
    required bool includeChecks,
    List<Withdrawal>? clientWithdrawals,
    List<BankCheck>? clientChecks,
  }) async {
    final withdrawals = clientWithdrawals ??
        (_withdrawalsHydrated ? this.withdrawals : null);
    Future<RemoteSettingsBundle> send(List<BankCheck>? checks) {
      return remote!.saveSettings(
        settings,
        clientWithdrawals: withdrawals,
        clientChecks: checks,
        appLockHash: appLockHash ?? '',
        appLockBiometric: biometricUnlockEnabled,
      );
    }

    final checksToSend =
        includeChecks ? (clientChecks ?? (_checksHydrated ? checks : null)) : null;
    try {
      return await send(checksToSend);
    } on InvestApiException catch (e) {
      if (e.statusCode != 400 || checksToSend == null) rethrow;
      checkSyncError = formatUserError(e);
      _checksPendingSync = true;
      return send(null);
    }
  }

  void _noteCheckEcho(RemoteSettingsBundle bundle) {
    if (_checksFromRemote) return;
    if (!_checksHydrated && checks.isEmpty) return;
    final echoed = bundle.serverEchoedChecks &&
        sameCheckIds(bundle.echoedChecks, checks);
    if (echoed) {
      _checksPendingSync = false;
      checkSyncError = null;
      return;
    }
    if (checks.isNotEmpty || _checksPendingSync) {
      _checksPendingSync = true;
    }
  }

  Future<void> _applyRemoteSettingsBundle(
    RemoteSettingsBundle bundle, {
    required bool migrate,
  }) async {
    settings = bundle.settings;
    var filledGaps = await PriceAlertPrefs.fillGapsOnto(settings);
    // Also heal from SQLite when Vinor returns empty year-nav history.
    if (settings.yearNavHistory.isEmpty) {
      await _ensureLocalSettingsRepo();
      final map = await settingsRepo?.loadAll();
      final fromDb = YearNavList.parse(map?[AppConfig.settingYearNavHistory]);
      if (fromDb.isNotEmpty) {
        settings.yearNavHistory = fromDb;
        filledGaps = true;
      }
    }
    await _applyRemoteLockFromBundle(bundle, migrateLocal: migrate);
    await _persistSettingsLocal(settings);
    await PriceAlertPrefs.saveFrom(settings);
    await BackgroundPriceWorker.sync(settings);

    final shouldMigrateLock = migrate &&
        bundle.appLockHash == null &&
        appLockHash != null &&
        appLockHash!.trim().isNotEmpty;
    if (migrate && (filledGaps || shouldMigrateLock)) {
      await _pushUserExtrasToServer();
    }
  }

  Future<void> _applyRemoteLockFromBundle(
    RemoteSettingsBundle bundle, {
    bool migrateLocal = false,
  }) async {
    if (bundle.appLockHash != null) {
      final hash = bundle.appLockHash!.trim();
      if (hash.isEmpty) {
        await AppLockStore.saveHash('');
        appLockHash = null;
        appLockEnabled = false;
        if (bundle.appLockBiometric == false || bundle.appLockBiometric == null) {
          biometricUnlockEnabled = false;
          await AppLockStore.saveBiometricEnabled(false);
        }
        appUnlocked = true;
      } else {
        await AppLockStore.saveHash(hash);
        appLockHash = hash;
        appLockEnabled = true;
      }
    } else if (!migrateLocal) {
      // Key absent and not migrating — leave local lock as-is.
    }

    if (bundle.appLockBiometric != null) {
      biometricUnlockEnabled = bundle.appLockBiometric!;
      await AppLockStore.saveBiometricEnabled(biometricUnlockEnabled);
      if (!appLockEnabled && biometricUnlockEnabled) {
        biometricUnlockEnabled = false;
        await AppLockStore.saveBiometricEnabled(false);
      }
    }
    await refreshBiometricCapability();
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

  Future<void> refresh() => refreshAll(
      includeQuotes: false, fetchSettings: true, checkApiVersion: true);

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
        await _publishLocalPortfolio();
      }
      error = null;
      await _dispatchProfitAlerts();
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
          error = formatUserError(e);
        }
      } else {
        error = formatUserError(e);
      }
    } catch (e) {
      error = formatUserError(e);
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
    RemoteSettingsBundle? settingsBundle;
    if (fetchSettings) {
      final prevRefresh = settings.autoRefreshSeconds;
      settingsBundle = await remote!.fetchSettings();
      await _applyRemoteSettingsBundle(settingsBundle, migrate: true);
      _normalizeGoldApiUrl();
      if (settings.autoRefreshSeconds != prevRefresh) {
        _startAutoRefreshTimer(immediate: false);
      }
    }
    final svc = remote!;
    // Fetch into locals first, then publish + overlay under a UI hold so a
    // concurrent index tick cannot rebuild the dashboard on bare server marks.
    final dashF = svc.fetchDashboard(settings.calendar);
    final assetsF = svc.assets.listAll();
    final openF = svc.listOpen();
    final closedF = svc.listClosed();
    final wdF = svc.listWithdrawals();

    final dash = await dashF;
    final nextAssets = await assetsF;
    final nextOpen = await openF;
    final nextClosed = await closedF;
    final remoteWithdrawals = await wdF;

    _holdUiNotifications = true;
    try {
      metrics = dash;
      assets = nextAssets;
      openTrades = nextOpen;
      closedTrades = nextClosed;
      await _applyWithdrawalsAfterFetch(
        remote: svc,
        remoteItems: remoteWithdrawals,
        settingsBundle: settingsBundle,
      );
      await _applyChecksAfterFetch(settingsBundle);
      await _overlayLiveMarks();
      lastSyncedAt = DateTime.now();
      await OfflineCacheStore.savePortfolio(
        settings: settings,
        metrics: metrics!,
        assets: assets,
        openTrades: openTrades,
        closedTrades: closedTrades,
        withdrawals: withdrawals,
        checks: checks,
        liveUsdt: liveUsdt,
        liveGold: liveGold,
      );
    } finally {
      _holdUiNotifications = false;
    }
  }

  Future<void> _publishLocalPortfolio() async {
    final nextAssets = await trades!.assets.listAll();
    final nextOpen = await trades!.trades.listOpen();
    final nextClosed = await trades!.trades.listClosed();
    _holdUiNotifications = true;
    try {
      assets = nextAssets;
      openTrades = nextOpen;
      closedTrades = nextClosed;
      await _overlayLiveMarks();
      metrics = await portfolio!.getMetrics(calendar: settings.calendar);
      await _loadLocalWithdrawals();
      _withdrawalsHydrated = true;
      await _loadLocalChecks();
      _checksHydrated = true;
      await _remindCheckDues();
      await portfolio!.recordSnapshot();
      lastSyncedAt = DateTime.now();
    } finally {
      _holdUiNotifications = false;
    }
  }

  Future<void> _applyWithdrawalsAfterFetch({
    required RemoteInvestService remote,
    required List<Withdrawal>? remoteItems,
    RemoteSettingsBundle? settingsBundle,
  }) async {
    try {
      // Non-empty dedicated API is authoritative.
      if (remoteItems != null && remoteItems.isNotEmpty) {
        withdrawals = remoteItems;
        _withdrawalsFromRemote = true;
        _withdrawalsViaSettings = false;
        return;
      }

      _withdrawalsFromRemote = false;
      var bundle = settingsBundle;
      bundle ??= await remote.fetchSettings();
      if (bundle.hasClientWithdrawals && bundle.clientWithdrawals.isNotEmpty) {
        withdrawals = List<Withdrawal>.from(bundle.clientWithdrawals);
        _withdrawalsViaSettings = true;
        // Heal empty dedicated API from the settings mirror when present.
        if (remoteItems != null &&
            remoteItems.isEmpty &&
            useRemote &&
            !offline &&
            !readOnlyOffline) {
          await _migrateWithdrawalsToRemoteApi(withdrawals);
        }
        return;
      }

      await _loadLocalWithdrawals();
      if (withdrawals.isNotEmpty && useRemote && !offline && !readOnlyOffline) {
        if (remoteItems != null) {
          await _migrateWithdrawalsToRemoteApi(withdrawals);
        } else {
          await _pushUserExtrasToServer(clientWithdrawals: withdrawals);
          _withdrawalsViaSettings = true;
        }
      } else if (remoteItems != null) {
        // Dedicated API exists and both server + local are empty.
        withdrawals = remoteItems;
        _withdrawalsFromRemote = true;
        _withdrawalsViaSettings = false;
      } else if (bundle.hasClientWithdrawals) {
        withdrawals = List<Withdrawal>.from(bundle.clientWithdrawals);
        _withdrawalsViaSettings = true;
      }
    } finally {
      _withdrawalsHydrated = true;
    }
  }

  /// Push local/settings withdrawals through the dedicated API when available,
  /// falling back to the settings mirror so nothing is lost after restore.
  Future<void> _migrateWithdrawalsToRemoteApi(List<Withdrawal> items) async {
    if (remote == null || items.isEmpty) return;
    var apiOk = false;
    final created = <Withdrawal>[];
    for (final w in items) {
      try {
        final item = await remote!.createWithdrawal(
          amount: w.amount,
          note: w.note,
          createdAt: w.createdAt,
          status: w.status,
        );
        if (item != null) {
          apiOk = true;
          created.add(item);
        }
      } catch (_) {}
    }
    if (apiOk && created.length == items.length) {
      withdrawals = created;
      _withdrawalsFromRemote = true;
      _withdrawalsViaSettings = false;
      // Keep a settings mirror so backups/older clients still see history.
      await _pushUserExtrasToServer(clientWithdrawals: items);
      return;
    }
    await _pushUserExtrasToServer(clientWithdrawals: items);
    _withdrawalsViaSettings = true;
    _withdrawalsFromRemote = false;
  }

  Future<void> _loadLocalWithdrawals() async {
    try {
      withdrawals = await (await _localWithdrawals()).listAll();
    } catch (_) {
      // Older local DBs without the table still render an empty history.
      withdrawals = [];
    }
  }

  Future<void> _loadLocalChecks() async {
    try {
      checks = await (await _localChecks()).listAll();
    } catch (_) {
      checks = [];
    }
    if (checks.isEmpty) {
      final stashed = await _readStashedChecks();
      if (stashed.isNotEmpty) {
        checks = stashed;
        try {
          await (await _localChecks()).replaceAll(checks);
        } catch (_) {}
      }
    }
  }

  Future<void> _persistChecksLocal() async {
    try {
      await (await _localChecks()).replaceAll(checks);
    } catch (_) {}
    await _stashChecksForCurrentPhone();
  }

  String get _checkBookKey =>
      'check_book_v1_${(userPhone ?? '').trim()}';

  Future<void> _stashChecksForCurrentPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _checkBookKey,
        jsonEncode(checks.map((c) => c.toMap()).toList()),
      );
    } catch (_) {}
  }

  Future<List<BankCheck>> _readStashedChecks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_checkBookKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <BankCheck>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        out.add(BankCheck.fromMap(Map<String, Object?>.from(e)));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _clearActiveCheckTable() async {
    try {
      await (await _localChecks()).replaceAll(const []);
    } catch (_) {}
  }

  bool get _checksApiReady =>
      useRemote && !offline && !readOnlyOffline && remote != null;

  String get _checkDeleteKey =>
      'check_deleted_v1_${(userPhone ?? '').trim()}';

  Future<void> _applyChecksAfterFetch(RemoteSettingsBundle? bundle) async {
    if (_checksSyncing) return;
    _checksSyncing = true;
    try {
      if (!_checksHydrated) await _loadLocalChecks();
      await _loadPendingDeletedChecks();
      if (!_checksApiReady) {
        _checksHydrated = true;
        await _remindCheckDues();
        return;
      }
      List<BankCheck>? remoteItems;
      try {
        remoteItems = await remote!.listChecks();
      } on InvestApiException catch (e) {
        checkSyncError = formatUserError(e);
        _checksHydrated = true;
        await _remindCheckDues();
        return;
      }
      if (remoteItems == null) {
        _checksFromRemote = false;
        await _applyChecksViaSettings(bundle);
        return;
      }
      _checksFromRemote = true;
      await _pushChecksToApi(remoteItems);
    } finally {
      _checksSyncing = false;
    }
  }

  /// Older Vinor builds that only store the book inside settings.
  Future<void> _applyChecksViaSettings(RemoteSettingsBundle? bundle) async {
    if (_checksPendingSync) {
      await _flushChecks();
      await _remindCheckDues();
      return;
    }
    if (bundle != null && bundle.hasClientChecks) {
      checks = _withoutPendingDeletes(bundle.clientChecks);
      await _persistChecksLocal();
    } else if (!_checksHydrated) {
      await _loadLocalChecks();
    }
    _checksHydrated = true;
    if (bundle != null &&
        !bundle.hasClientChecks &&
        checks.isNotEmpty &&
        _checksApiReady) {
      await _flushChecks();
    }
    await _remindCheckDues();
  }

  /// Upload local-only rows, then adopt the server book without dropping
  /// anything the server refused.
  Future<void> _pushChecksToApi(List<BankCheck> remoteItems) async {
    checkSyncError = null;
    Object? failure = await _flushPendingDeletes();
    final visibleRemote = _withoutPendingDeletes(remoteItems);
    final visibleLocal = _withoutPendingDeletes(checks);
    final plan = planCheckUpload(
      local: visibleLocal,
      remote: visibleRemote,
      pushLocalEdits: _checksPendingSync,
    );
    for (final row in plan.toCreate) {
      try {
        await remote!.createCheck(row);
      } on InvestApiException catch (e) {
        if (_isDuplicateCheckId(e)) continue;
        failure ??= e;
      }
    }
    for (final row in plan.toUpdate) {
      try {
        await remote!.updateCheck(row);
      } on InvestApiException catch (e) {
        if (e.statusCode == 404 && e.message.contains('پیدا نشد')) {
          try {
            await remote!.createCheck(row);
            continue;
          } on InvestApiException catch (e2) {
            if (_isDuplicateCheckId(e2)) continue;
            failure ??= e2;
            continue;
          }
        }
        failure ??= e;
      }
    }

    List<BankCheck>? fetched;
    try {
      fetched = await remote!.listChecks();
    } on InvestApiException catch (e) {
      failure ??= e;
    }
    var serverBook = _withoutPendingDeletes(fetched ?? visibleRemote);
    var merged = _withoutPendingDeletes(
      mergeRemoteBook(local: visibleLocal, remote: serverBook),
    );
    final missing = [
      for (final row in visibleLocal)
        if (row.id != null && !serverBook.any((item) => item.id == row.id)) row,
    ];
    if (missing.isNotEmpty) {
      final mirrored = await _uploadBookViaSettings(merged);
      if (mirrored != null) {
        final echoed = _withoutPendingDeletes(mirrored);
        final echoedIds = {for (final row in echoed) row.id};
        final stillMissing =
            missing.where((row) => !echoedIds.contains(row.id));
        if (stillMissing.isEmpty) {
          merged = _withoutPendingDeletes(
            mergeRemoteBook(local: visibleLocal, remote: echoed),
          );
          serverBook = echoed;
        }
      }
    }

    checks = merged;
    final serverIds = {for (final row in serverBook) row.id};
    final unsynced = merged.where(
      (row) => row.id != null && !serverIds.contains(row.id),
    );
    final mirrorError = checkSyncError;
    _checksPendingSync =
        unsynced.isNotEmpty || _pendingDeletedCheckIds.isNotEmpty;
    if (failure != null) {
      checkSyncError = formatUserError(failure);
      _checksPendingSync = true;
    } else if (_checksPendingSync) {
      checkSyncError = mirrorError;
    } else {
      checkSyncError = null;
    }
    _checksHydrated = true;
    await _persistChecksLocal();
    await _remindCheckDues();
    notifyListeners();
  }

  Future<List<BankCheck>?> _uploadBookViaSettings(List<BankCheck> book) async {
    if (remote == null || book.isEmpty) return null;
    try {
      final bundle = await remote!.saveSettings(
        settings,
        clientWithdrawals: _withdrawalsHydrated ? withdrawals : null,
        clientChecks: book,
        appLockHash: appLockHash ?? '',
        appLockBiometric: biometricUnlockEnabled,
      );
      final err = bundle.clientChecksError?.trim();
      if (err != null && err.isNotEmpty) {
        checkSyncError = err;
        return null;
      }
      if (!bundle.serverEchoedChecks) return null;
      return bundle.echoedChecks;
    } catch (_) {
      return null;
    }
  }

  Future<void> _mirrorChecksToSettings() async {
    if (!_checksFromRemote || !_checksApiReady || _checksPendingSync) return;
    try {
      await remote!.saveSettings(
        settings,
        clientWithdrawals: _withdrawalsHydrated ? withdrawals : null,
        clientChecks: _withoutPendingDeletes(checks),
        appLockHash: appLockHash ?? '',
        appLockBiometric: biometricUnlockEnabled,
      );
    } catch (_) {}
  }

  List<BankCheck> _withoutPendingDeletes(List<BankCheck> rows) => [
        for (final row in rows)
          if (row.id == null || !_pendingDeletedCheckIds.contains(row.id)) row,
      ];

  List<BankCheck> _replaceCheck(List<BankCheck> book, BankCheck item) => [
        for (final row in book)
          if (row.id != item.id) row,
        item,
      ];

  bool _checksRouteMissing(InvestApiException e) =>
      e.statusCode == 405 ||
      (e.statusCode == 404 && !e.message.contains('پیدا نشد'));

  bool _isDuplicateCheckId(InvestApiException e) =>
      e.statusCode == 409 && e.message.contains('شناسه چک تکراری');

  bool _isTransportError(InvestApiException e) =>
      e.errorCode == 'network_error' ||
      e.statusCode == null ||
      (e.statusCode != null && e.statusCode! >= 500);

  Future<BankCheck> _upsertRemoteCheck(
    BankCheck saved, {
    required bool isNew,
  }) async {
    if (!isNew) {
      try {
        final updated = await remote!.updateCheck(saved);
        _checksFromRemote = true;
        return updated;
      } on InvestApiException catch (e) {
        if (_checksRouteMissing(e) || e.statusCode != 404) rethrow;
        final created = await remote!.createCheck(saved);
        _checksFromRemote = true;
        return created;
      }
    }
    final created = await remote!.createCheck(saved);
    _checksFromRemote = true;
    return created;
  }

  /// Insert or update one cheque.
  ///
  /// Online writes go to `/checks` first. A rejected cheque is not stored.
  /// A network failure keeps the row on the device and retries on the next
  /// refresh. [synced] is false when the server does not have this row yet.
  Future<({BankCheck check, bool synced})> saveCheck(BankCheck draft) async {
    if (!canMutate) {
      throw StateError(
        'در حالت آفلاین فقط مشاهده ممکن است. برای ذخیره آنلاین شوید.',
      );
    }
    final prepared = prepareBankCheck(draft, others: checks);
    final now = nowIso();
    final isNew = draft.id == null;
    final id = prepared.id ?? _nextCheckId();
    final saved = prepared.copyWith(
      id: id,
      createdAt: prepared.createdAt.trim().isEmpty ? now : prepared.createdAt,
      updatedAt: now,
    );

    if (_checksApiReady) {
      try {
        final remoteItem = await _upsertRemoteCheck(saved, isNew: isNew);
        final synced = await _commitChecks(
          _replaceCheck(checks, remoteItem),
          alreadyRemote: true,
        );
        await _alertCheckSaved(isNew: isNew, item: remoteItem);
        unawaited(_mirrorChecksToSettings());
        return (check: remoteItem, synced: synced);
      } on InvestApiException catch (e) {
        if (_checksRouteMissing(e)) {
          _checksFromRemote = false;
        } else if (_isTransportError(e)) {
          await _writeChecksLocal(_replaceCheck(checks, saved), pending: true);
          checkSyncError = formatUserError(e);
          notifyListeners();
          await _alertCheckSaved(isNew: isNew, item: saved);
          return (check: saved, synced: false);
        } else {
          checkSyncError = formatUserError(e);
          notifyListeners();
          rethrow;
        }
      }
    }

    final synced = await _commitChecks(_replaceCheck(checks, saved));
    await _alertCheckSaved(isNew: isNew, item: saved);
    return (check: saved, synced: synced);
  }

  Future<void> _alertCheckSaved({
    required bool isNew,
    required BankCheck item,
  }) {
    return emitLocalAlert(
      kind: NotificationKind.checks,
      title: isNew ? 'چک ثبت شد' : 'چک ویرایش شد',
      body:
          '${item.directionLabel} · ${item.statusLabel} · ${formatMoney(item.amount)}',
    );
  }

  Future<bool> setCheckStatus(
    BankCheck item,
    String status, {
    String? settledDate,
  }) async {
    if (item.id == null) {
      throw ArgumentError('شناسه چک نامعتبر است.');
    }
    final result = await saveCheck(
      item.copyWith(
        status: status,
        settledDate: settledDate,
        clearSettledDate: status == checkStatusPending,
      ),
    );
    return result.synced;
  }

  Future<bool> deleteCheck(BankCheck item) async {
    if (!canMutate) {
      throw StateError(
        'در حالت آفلاین فقط مشاهده ممکن است. برای ذخیره آنلاین شوید.',
      );
    }
    final id = item.id;
    if (id == null) {
      throw ArgumentError('شناسه چک نامعتبر است.');
    }
    final next = [for (final row in checks) if (row.id != id) row];
    if (_checksApiReady) {
      try {
        await remote!.deleteCheck(id);
        _checksFromRemote = true;
        _pendingDeletedCheckIds.remove(id);
        await _persistPendingDeletes();
        final synced = await _commitChecks(next, alreadyRemote: true);
        unawaited(_mirrorChecksToSettings());
        return synced;
      } on InvestApiException catch (e) {
        if (_checksRouteMissing(e)) {
          _checksFromRemote = false;
        } else if (e.statusCode == 404 && e.message.contains('پیدا نشد')) {
          _pendingDeletedCheckIds.remove(id);
          await _persistPendingDeletes();
          return _commitChecks(next, alreadyRemote: true);
        } else if (_isTransportError(e)) {
          _pendingDeletedCheckIds.add(id);
          await _persistPendingDeletes();
          await _writeChecksLocal(next, pending: true);
          checkSyncError = formatUserError(e);
          notifyListeners();
          return false;
        } else {
          checkSyncError = formatUserError(e);
          notifyListeners();
          rethrow;
        }
      }
    }
    _pendingDeletedCheckIds.add(id);
    await _persistPendingDeletes();
    return _commitChecks(next);
  }

  Future<bool> _writeChecksLocal(
    List<BankCheck> next, {
    required bool pending,
  }) async {
    checks = next;
    _checksHydrated = true;
    _checksPendingSync = pending || _pendingDeletedCheckIds.isNotEmpty;
    await _persistChecksLocal();
    notifyListeners();
    return !_checksPendingSync;
  }

  Future<bool> _commitChecks(
    List<BankCheck> next, {
    bool alreadyRemote = false,
  }) async {
    checks = next;
    _checksHydrated = true;
    if (alreadyRemote) {
      _checksPendingSync = _pendingDeletedCheckIds.isNotEmpty;
      if (!_checksPendingSync) checkSyncError = null;
      _checksFromRemote = true;
    } else {
      _checksPendingSync = true;
    }
    await _persistChecksLocal();
    notifyListeners();
    final synced = alreadyRemote ? !_checksPendingSync : await _flushChecks();
    await _persistWithdrawalCache();
    await _remindCheckDues();
    notifyListeners();
    return synced;
  }

  Future<bool> _flushChecks() async {
    if (!_checksApiReady) {
      // The row is already on the device. Keep [_checksPendingSync] so the
      // next online refresh uploads it instead of letting the server copy win.
      return true;
    }
    if (_checksFromRemote) {
      await _applyChecksAfterFetch(null);
      return !_checksPendingSync;
    }
    try {
      final bundle = await _pushUserExtrasToServer(
        clientChecks: _withoutPendingDeletes(checks),
        rethrowErrors: true,
      );
      if (bundle == null) {
        _checksPendingSync = true;
        return false;
      }
      final echoed = bundle.serverEchoedChecks &&
          sameCheckIds(bundle.echoedChecks, _withoutPendingDeletes(checks));
      final mirrorError = bundle.clientChecksError?.trim();
      if (mirrorError != null && mirrorError.isNotEmpty) {
        _checksPendingSync = true;
        checkSyncError = mirrorError;
        return false;
      }
      _checksPendingSync = !echoed || _pendingDeletedCheckIds.isNotEmpty;
      if (!_checksPendingSync) checkSyncError = null;
      return !_checksPendingSync;
    } on InvestApiException catch (e) {
      _checksPendingSync = true;
      checkSyncError = formatUserError(e);
      return false;
    } catch (_) {
      _checksPendingSync = true;
      return false;
    }
  }

  Future<Object?> _flushPendingDeletes() async {
    Object? failure;
    if (remote == null || _pendingDeletedCheckIds.isEmpty) return null;
    for (final id in _pendingDeletedCheckIds.toList()) {
      try {
        await remote!.deleteCheck(id);
        _pendingDeletedCheckIds.remove(id);
      } on InvestApiException catch (e) {
        if (e.statusCode == 404) {
          _pendingDeletedCheckIds.remove(id);
          continue;
        }
        failure ??= e;
      }
    }
    await _persistPendingDeletes();
    return failure;
  }

  Future<void> _loadPendingDeletedChecks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_checkDeleteKey);
      _pendingDeletedCheckIds.clear();
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final entry in decoded) {
        final id = entry is int ? entry : int.tryParse('$entry');
        if (id != null) _pendingDeletedCheckIds.add(id);
      }
    } catch (_) {}
  }

  Future<void> _persistPendingDeletes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _checkDeleteKey,
        jsonEncode(_pendingDeletedCheckIds.toList()),
      );
    } catch (_) {}
  }

  int _nextCheckId() {
    var maxId = 0;
    for (final c in checks) {
      final id = c.id ?? 0;
      if (id > maxId) maxId = id;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return now > maxId ? now : maxId + 1;
  }

  Future<void> _remindCheckDues() async {
    if (!settings.notificationsEnabled) return;
    final rows = await _reminderRows();
    if (rows.isEmpty) return;
    final today = todayIso();
    Map<String, dynamic> seen = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('check_due_alerts_v1');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) seen = Map<String, dynamic>.from(decoded);
      }
      final dueToday = <String, String>{};
      for (final c in rows) {
        final key = '${c.id}|$today';
        if (_checkAlertKeys.contains(key) || seen[key] == today) {
          _checkAlertKeys.add(key);
          continue;
        }
        final when = c.dueRelativeLabel();
        final who = c.counterparty.trim().isEmpty
            ? c.bankName.trim()
            : c.counterparty.trim();
        await emitLocalAlert(
          kind: NotificationKind.checks,
          title: _reminderTitle(c),
          body:
              '${c.directionLabel} · ${c.statusLabel} · ${formatMoney(c.amount)} · $when${who.isEmpty ? '' : ' · $who'}',
          id: 70000 + ((c.id ?? 0).abs() % 20000),
        );
        _checkAlertKeys.add(key);
        dueToday[key] = today;
      }
      if (dueToday.isEmpty) return;
      seen.addAll(dueToday);
      final keep = <String, String>{};
      for (final e in seen.entries) {
        if (e.value == today) keep[e.key] = today;
      }
      await prefs.setString('check_due_alerts_v1', jsonEncode(keep));
    } catch (_) {}
  }

  Future<List<BankCheck>> _reminderRows() async {
    if (_checksFromRemote && _checksApiReady) {
      try {
        final groups = await remote!.fetchCheckReminders(
          withinDays: checkReminderWithinDays,
        );
        if (groups != null) {
          return _dedupeChecks([
            ...groups.overdue,
            ...groups.dueSoon,
            ...groups.bounced,
          ]);
        }
      } on InvestApiException {
        // The book on the device still knows which cheques are due.
      }
    }
    return _dedupeChecks([
      ...checksNeedingReminder(checks),
      for (final row in checks)
        if (row.isBounced) row,
    ]);
  }

  List<BankCheck> _dedupeChecks(List<BankCheck> rows) {
    final seen = <int>{};
    final out = <BankCheck>[];
    for (final row in rows) {
      final id = row.id;
      if (id == null || !seen.add(id)) continue;
      out.add(row);
    }
    return out;
  }

  String _reminderTitle(BankCheck item) {
    final days = item.daysUntilDue();
    if (item.isBounced && days >= 0) return 'چک برگشتی';
    if (days < 0) return 'سررسید چک گذشته است';
    if (days == 0) return 'سررسید چک امروز است';
    return 'سررسید چک نزدیک است';
  }

  Future<void> recordWithdrawal({
    required double amount,
    String note = '',
    String? createdAt,
  }) async {
    if (!canMutate) {
      throw StateError(
          'در حالت آفلاین فقط مشاهده ممکن است. برای ذخیره آنلاین شوید.');
    }
    if (amount <= 0) {
      throw ArgumentError('مبلغ برداشت باید بزرگ‌تر از صفر باشد.');
    }
    var saved = false;
    if (useRemote && !offline && remote != null) {
      final created = await remote!.createWithdrawal(
        amount: amount,
        note: note,
        createdAt: createdAt,
      );
      if (created != null) {
        withdrawals = [created, ...withdrawals];
        _withdrawalsFromRemote = true;
        _withdrawalsViaSettings = false;
        saved = true;
        // Mirror into settings so backups and older Vinor builds keep history.
        await _pushUserExtrasToServer(
          clientWithdrawals: withdrawals,
          rethrowErrors: true,
        );
      }
    }
    if (!saved) {
      final repo = await _localWithdrawals();
      await repo.create(
        Withdrawal(
          amount: amount,
          note: note.trim(),
          createdAt: (createdAt ?? '').trim(),
        ),
      );
      await _loadLocalWithdrawals();
      if (useRemote && !offline && remote != null) {
        await _pushUserExtrasToServer(
          clientWithdrawals: withdrawals,
          rethrowErrors: true,
        );
        _withdrawalsViaSettings = true;
      }
    }
    _withdrawalsHydrated = true;
    await _persistWithdrawalCache();
    notifyListeners();
    await emitLocalAlert(
      kind: NotificationKind.withdrawals,
      title: 'برداشت ثبت شد',
      body: formatMoney(amount),
    );
  }

  Future<void> updateWithdrawal({
    required Withdrawal item,
    required double amount,
    String note = '',
    String? createdAt,
  }) async {
    if (!canMutate) {
      throw StateError(
          'در حالت آفلاین فقط مشاهده ممکن است. برای ذخیره آنلاین شوید.');
    }
    if (item.id == null) {
      throw ArgumentError('شناسه برداشت نامعتبر است.');
    }
    if (amount <= 0) {
      throw ArgumentError('مبلغ برداشت باید بزرگ‌تر از صفر باشد.');
    }
    final when = (createdAt ?? item.createdAt).trim();
    if (when.isEmpty) {
      throw ArgumentError('تاریخ برداشت نامعتبر است.');
    }
    final updated = Withdrawal(
      id: item.id,
      amount: amount,
      note: note.trim(),
      status: item.status.trim().isEmpty ? 'completed' : item.status,
      createdAt: when,
    );
    var saved = false;
    if (_withdrawalsFromRemote && useRemote && !offline && remote != null) {
      final result = await remote!.updateWithdrawal(updated);
      if (result != null) {
        _replaceWithdrawal(result);
        saved = true;
        await _pushUserExtrasToServer(
          clientWithdrawals: withdrawals,
          rethrowErrors: true,
        );
      }
    }
    if (!saved) {
      final repo = await _localWithdrawals();
      await repo.update(updated);
      if (_withdrawalsFromRemote || _withdrawalsViaSettings) {
        _replaceWithdrawal(updated);
      } else {
        await _loadLocalWithdrawals();
      }
      // Dedicated update missing/failed — settings mirror is the server store.
      if (useRemote && !offline && remote != null) {
        await _pushUserExtrasToServer(
          clientWithdrawals: withdrawals,
          rethrowErrors: true,
        );
        _withdrawalsViaSettings = true;
        _withdrawalsFromRemote = false;
      }
    }
    _withdrawalsHydrated = true;
    await _persistWithdrawalCache();
    notifyListeners();
  }

  void _replaceWithdrawal(Withdrawal updated) {
    withdrawals = [
      for (final w in withdrawals)
        if (w.id == updated.id) updated else w,
    ];
  }

  /// Shows a local notification when the matching preference is on.
  Future<void> emitLocalAlert({
    required NotificationKind kind,
    required String title,
    required String body,
    int? id,
  }) async {
    final s = settings;
    final allowed = switch (kind) {
      NotificationKind.trades => s.tradesAlertsOn,
      NotificationKind.withdrawals => s.withdrawalAlertsOn,
      NotificationKind.prices => s.priceAlertsOn,
      NotificationKind.checks => s.notificationsEnabled,
      NotificationKind.general => s.notificationsEnabled,
    };
    if (!allowed) return;
    try {
      await NotificationService.instance.show(
        title: title,
        body: body,
        kind: kind,
        id: id,
      );
    } catch (_) {}
  }

  Future<void> _persistWithdrawalCache() async {
    if (metrics == null) return;
    await OfflineCacheStore.savePortfolio(
      settings: settings,
      metrics: metrics!,
      assets: assets,
      openTrades: openTrades,
      closedTrades: closedTrades,
      withdrawals: withdrawals,
      checks: checks,
      liveUsdt: liveUsdt,
      liveGold: liveGold,
    );
  }

  Future<void> _syncLiveQuotes() async {
    quotes ??= QuoteClients();

    double? remoteUsdt;
    double? remoteGold;
    if (useRemote && !offline && remote != null) {
      try {
        final q = await remote!.fetchQuotes();
        remoteUsdt = q.usdt;
        remoteGold = q.gold;
      } catch (_) {}
    }

    double? localUsdt;
    double? localGold;
    final tasks = <Future<void>>[];
    if (settings.usdtApiEnabled) {
      tasks.add(() async {
        localUsdt = await quotes!.fetchUsdtToman(wallexUrl: settings.wallexUrl);
      }());
    }
    if (settings.goldApiEnabled) {
      // Always hit free bazaar feeds — Vinor gold is often understated toolbox spot.
      tasks.add(() async {
        final g = await quotes!
            .fetchGoldToman(persianUrl: settings.persianToolboxUrl);
        localGold = g.price;
      }());
    }
    if (tasks.isNotEmpty) {
      await Future.wait(tasks);
    }

    final fetchedUsdt = localUsdt ?? remoteUsdt;
    final fetchedGold = GoldQuoteParser.preferFreeMarketGold(
      freeMarket: localGold,
      remoteOrCached: remoteGold ?? settings.goldTmnPerGram,
    );

    if (fetchedUsdt != null) {
      liveUsdt = fetchedUsdt;
      settings.usdtTmnRate = fetchedUsdt;
      await settingsRepo?.set(AppConfig.settingUsdtTmn, fetchedUsdt.toString());
    }
    if (fetchedGold != null) {
      liveGold = fetchedGold;
      settings.goldTmnPerGram = fetchedGold;
      await settingsRepo?.set(AppConfig.settingGoldTmn, fetchedGold.toString());
    }

    if (!useRemote && trades != null) {
      await trades!.applyLivePrices(
        usdtTmn: fetchedUsdt ?? settings.usdtTmnRate,
        goldTmn: fetchedGold ?? settings.goldTmnPerGram,
        updateUsdt: settings.usdtApiEnabled,
        updateGold: settings.goldApiEnabled,
        quotes: [...commodityIndex, ...wallexMarkets],
      );
    }
    await _overlayLiveMarks();
    await _dispatchPriceAlerts();
  }

  /// Replace شاخص / live gold with the free 18k bazaar feed when Vinor is stale.
  Future<({double? price, double? change24h})?> _fetchFreeMarketGold() async {
    if (!settings.goldApiEnabled) return null;
    quotes ??= QuoteClients();
    try {
      final g = await quotes!
          .fetchGoldToman(persianUrl: settings.persianToolboxUrl);
      if (g.price == null || g.price! <= 0) return null;
      if (GoldQuoteParser.isUnderstated18kToman(g.price)) return null;
      return g;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadPriceAlertRuntime() async {
    try {
      final snap = await PriceAlertPrefs.loadSnapshot();
      if (snap != null) {
        // Online: never overwrite server prefs; only fill gaps for migration.
        if (useRemote && !offline) {
          await PriceAlertPrefs.fillGapsOnto(settings);
        } else {
          await PriceAlertPrefs.overlayOnto(settings);
        }
      }
      await PriceAlertPrefs.saveFrom(settings);
      _normalizeGoldApiUrl();
      await BackgroundPriceWorker.sync(settings);
    } catch (_) {}
  }

  /// Stamp gold / USDT / crypto holdings with the live Toman unit mark.
  /// Buy prices are never touched. Remote current_price is not PUT every
  /// index tick — overlay is in-memory (and local SQLite when [persistLocal]).
  Future<void> _overlayLiveMarks({bool persistLocal = false}) async {
    final quotes = [...commodityIndex, ...wallexMarkets];
    final usdt = liveUsdt ?? settings.usdtTmnRate;
    final gold = liveGold ?? settings.goldTmnPerGram;
    if (quotes.isEmpty &&
        (usdt == null || usdt <= 0) &&
        (gold == null || gold <= 0)) {
      return;
    }
    for (final a in assets) {
      final p = liveTomanPriceFor(
        name: a.name,
        symbol: a.symbol,
        notes: a.notes,
        quotes: quotes,
        usdtTmn: usdt,
        goldTmn: gold,
      );
      if (p != null) a.currentPrice = p;
    }
    final notesByAssetId = <int, String>{
      for (final a in assets)
        if (a.id != null) a.id!: a.notes,
    };
    for (final t in openTrades) {
      final p = liveTomanPriceFor(
        name: t.assetName,
        symbol: t.assetSymbol,
        notes: notesByAssetId[t.assetId] ?? '',
        quotes: quotes,
        usdtTmn: usdt,
        goldTmn: gold,
      );
      if (p != null) t.currentPrice = p;
    }
    if (!persistLocal || useRemote || trades == null) return;
    try {
      await trades!.applyLivePrices(
        usdtTmn: usdt,
        goldTmn: gold,
        quotes: quotes,
      );
    } catch (_) {}
  }

  Future<void> _dispatchPriceAlerts() async {
    if (!settings.priceAlertsOn) return;
    final prices = PriceAlertEngine.pricesFrom(
      quotes: [...commodityIndex, ...wallexMarkets],
      usdt: liveUsdt ?? settings.usdtTmnRate,
      gold: liveGold ?? settings.goldTmnPerGram,
    );
    await BackgroundPriceMonitor.dispatchHits(
      alerts: settings.priceAlerts,
      prices: prices,
    );
    await _dispatchProfitAlerts();
  }

  List<ProfitPosition> _profitPositions() {
    final out = <ProfitPosition>[];
    for (final asset in assets) {
      final id = asset.id;
      if (id == null) continue;
      final m = HoldingMetrics.forAsset(asset, openTrades);
      if (!m.hasPosition) continue;
      out.add(
        ProfitPosition(
          id: ProfitAlert.forAsset(id),
          name: asset.name,
          symbol: asset.symbol,
          pnl: m.unrealizedPnl,
          pnlPct: m.unrealizedPnlPct,
          qty: m.quantity,
          cost: m.costBasis,
          price: m.currentPrice,
        ),
      );
    }
    for (final t in openTrades) {
      final id = t.id;
      if (id == null || t.quantity <= 1e-9) continue;
      out.add(
        ProfitPosition(
          id: ProfitAlert.forTrade(id),
          name: t.assetName,
          symbol: t.assetSymbol,
          pnl: t.unrealizedPnl,
          pnlPct: t.unrealizedPnlPct,
          qty: t.quantity,
          cost: t.buyCost,
          price: t.currentPrice,
        ),
      );
    }
    return out;
  }

  Future<void> _dispatchProfitAlerts() async {
    final positions = _profitPositions();
    try {
      await PriceAlertPrefs.savePositions(positions);
    } catch (_) {}
    if (!settings.tradesAlertsOn) return;
    await BackgroundPriceMonitor.dispatchProfitHits(
      alerts: settings.profitAlerts,
      positions: {for (final p in positions) p.id: p},
    );
  }

  /// Used by UI for buy/sell/asset mutations.
  InvestMutations get tradeService {
    if (useRemote && !offline) {
      final svc = remote;
      if (svc == null) {
        throw StateError('اتصال به سرور آماده نیست.');
      }
      return svc;
    }
    final local = trades;
    if (local == null) {
      throw StateError('داده‌های محلی آماده نیست.');
    }
    return local;
  }

  /// Encrypted full backup bytes (`.vplusbak`).
  Future<Uint8List> exportEncryptedBackup() async {
    if (!authenticated) {
      throw StateError('برای صدور پشتیبان باید وارد برنامه شوید.');
    }
    List<Map<String, Object?>> snaps = <Map<String, Object?>>[];
    Map<String, String> settingsRaw = settings.toStorageMap();
    try {
      final db = await AppDatabase.instance.database;
      snaps = await BackupService.loadCapitalSnapshots(db);
      settingsRepo ??= SettingsRepository(db);
      final fromDb = await settingsRepo!.loadAll();
      if (fromDb.isNotEmpty) {
        settingsRaw = {...fromDb, ...settings.toStorageMap()};
      }
    } catch (_) {
      snaps = <Map<String, Object?>>[];
    }
    final payload = BackupService.buildFromMemory(
      settings: settings,
      settingsRaw: settingsRaw,
      assets: assets,
      openTrades: openTrades,
      closedTrades: closedTrades,
      withdrawals: withdrawals,
      checks: checks,
      capitalSnapshots: snaps,
      appLockHash: appLockHash,
      biometricUnlockEnabled: biometricUnlockEnabled,
      userPhone: userPhone,
      baseUrl: baseUrl,
    );
    return BackupService.encode(payload);
  }

  /// Decrypt + validate backup file without applying it.
  BackupPayload peekEncryptedBackup(Uint8List bytes) =>
      BackupService.decode(bytes);

  /// Restore encrypted backup into local DB, offline cache, lock, and memory.
  ///
  /// When online with remote API and [pushToRemote], also rebuilds Vinor data.
  Future<BackupRestoreReport> importEncryptedBackup(
    Uint8List bytes, {
    bool pushToRemote = true,
  }) async {
    if (!authenticated) {
      throw StateError('برای وارد کردن پشتیبان باید وارد برنامه شوید.');
    }
    final payload = BackupService.decode(bytes);

    final db = await AppDatabase.instance.database;
    // Ensure local service handles exist even in remote mode.
    trades ??= TradeService(db);
    portfolio ??= PortfolioService(db);
    settingsRepo ??= SettingsRepository(db);
    _withdrawalsRepo ??= WithdrawalRepository(db);
    _checksRepo ??= CheckRepository(db);

    await BackupService.restoreLocalDatabase(db, payload);
    await BackupService.restoreAppLock(payload);
    await BackupService.saveOfflineCache(
      payload: payload,
      metrics: metrics,
    );

    var remotePushed = false;
    String? remoteWarning;
    if (pushToRemote &&
        useRemote &&
        !offline &&
        remote != null &&
        !readOnlyOffline) {
      try {
        await _rebuildRemoteFromBackup(payload);
        remotePushed = true;
      } catch (e) {
        remoteWarning =
            'پشتیبان محلی اعمال شد، اما همگام‌سازی با سرور کامل نشد: ${formatUserError(e)}';
      }
    } else if (useRemote && (offline || readOnlyOffline)) {
      remoteWarning =
          'پشتیبان روی دستگاه ذخیره شد. در حالت آفلاین به سرور ارسال نشد؛ '
          'با آنلاین شدن، همگام‌سازی از سرور ممکن است داده‌ها را بازنویسی کند.';
    }

    await _loadAppLock();
    // Keep session unlocked after restore so the user isn't locked out mid-flow.
    appUnlocked = true;

    settings = payload.settings.copyWith();
    if (settings.wallexUrl.isEmpty) {
      settings.wallexUrl = AppConfig.defaultWallexUrl;
    }
    if (settings.persianToolboxUrl.isEmpty) {
      settings.persianToolboxUrl = AppConfig.defaultPersianToolboxUrl;
    }
    assets = List<Asset>.from(payload.assets);
    openTrades =
        payload.trades.where((t) => t.status == AppConfig.tradeOpen).toList();
    closedTrades =
        payload.trades.where((t) => t.status == AppConfig.tradeClosed).toList();
    withdrawals = List<Withdrawal>.from(payload.withdrawals);
    checks = List<BankCheck>.from(payload.checks);
    _withdrawalsFromRemote = false;
    _withdrawalsViaSettings = payload.withdrawals.isNotEmpty;
    _withdrawalsHydrated = true;
    _checksHydrated = true;
    liveUsdt = settings.usdtTmnRate;
    liveGold = settings.goldTmnPerGram;

    if (remotePushed) {
      await refreshAll(
        includeQuotes: false,
        fetchSettings: true,
        checkApiVersion: false,
      );
      // Never let a refresh drop restored withdrawals.
      if (withdrawals.isEmpty && payload.withdrawals.isNotEmpty) {
        withdrawals = List<Withdrawal>.from(payload.withdrawals);
        await _pushUserExtrasToServer(
          clientWithdrawals: withdrawals,
          rethrowErrors: true,
        );
        _withdrawalsViaSettings = true;
        _withdrawalsFromRemote = false;
      }
      if (checks.isEmpty && payload.checks.isNotEmpty) {
        checks = List<BankCheck>.from(payload.checks);
        _checksHydrated = true;
        await _persistChecksLocal();
        await _pushUserExtrasToServer(
          clientChecks: checks,
          rethrowErrors: true,
        );
      }
    } else if (!useRemote) {
      await refreshAll(
        includeQuotes: false,
        fetchSettings: true,
        checkApiVersion: false,
      );
      withdrawals = List<Withdrawal>.from(payload.withdrawals);
      checks = List<BankCheck>.from(payload.checks);
      _checksHydrated = true;
    } else if (payload.withdrawals.isNotEmpty) {
      // Offline / read-only remote: keep restored history in local DB + cache.
      final repo = await _localWithdrawals();
      for (final w in payload.withdrawals) {
        try {
          if (w.id != null) {
            await repo.update(w);
          }
        } catch (_) {}
      }
      await _loadLocalWithdrawals();
      if (withdrawals.isEmpty) {
        withdrawals = List<Withdrawal>.from(payload.withdrawals);
      }
      _withdrawalsViaSettings = false;
      _withdrawalsFromRemote = false;
    }

    // Always re-apply backed-up settings last so a server refresh cannot drop them.
    settings = payload.settings.copyWith(
      wallexUrl: payload.settings.wallexUrl.trim().isEmpty
          ? AppConfig.defaultWallexUrl
          : payload.settings.wallexUrl,
      persianToolboxUrl: payload.settings.persianToolboxUrl.trim().isEmpty
          ? AppConfig.defaultPersianToolboxUrl
          : payload.settings.persianToolboxUrl,
    );
    await _persistSettingsLocal(settings);
    await PriceAlertPrefs.saveFrom(settings);
    await BackgroundPriceWorker.sync(settings);
    liveUsdt = settings.usdtTmnRate ?? liveUsdt;
    liveGold = settings.goldTmnPerGram ?? liveGold;
    await _persistWithdrawalCache();
    notifyListeners();

    return BackupRestoreReport(
      payload: payload,
      remotePushed: remotePushed,
      remoteWarning: remoteWarning,
    );
  }

  Future<void> _rebuildRemoteFromBackup(BackupPayload payload) async {
    final svc = remote!;
    // Always seed settings mirror first so withdrawals survive even if the
    // dedicated API is missing or only partially accepts create calls.
    await svc.saveSettings(
      payload.settings,
      clientWithdrawals: payload.withdrawals,
      clientChecks: payload.checks,
      appLockHash: payload.appLockHash ?? '',
      appLockBiometric: payload.biometricUnlockEnabled,
    );

    // Clear existing remote portfolio (closed → open → assets).
    final existingClosed = await svc.listClosed();
    for (final t in existingClosed) {
      if (t.id != null) {
        try {
          await svc.deleteClosedTrade(t.id!);
        } catch (_) {}
      }
    }
    final existingOpen = await svc.listOpen();
    for (final t in existingOpen) {
      if (t.id == null) continue;
      try {
        await svc.closeTrade(
          tradeId: t.id!,
          sellPrice: t.buyPrice > 0 ? t.buyPrice : 1,
          sellFee: 0,
          quantity: t.quantity,
          sellNote: 'پاکسازی قبل از بازیابی پشتیبان',
        );
      } catch (_) {}
    }
    final closedAfter = await svc.listClosed();
    for (final t in closedAfter) {
      if (t.id != null) {
        try {
          await svc.deleteClosedTrade(t.id!);
        } catch (_) {}
      }
    }
    final existingAssets = await svc.assets.listAll();
    for (final a in existingAssets) {
      if (a.id != null) {
        try {
          await svc.assets.delete(a.id!);
        } catch (_) {}
      }
    }

    // Recreate assets, then trades keyed by previous asset id.
    final idMap = <int, int>{};
    for (final a in payload.assets) {
      final created = await svc.assets.create(
        Asset(
          name: a.name,
          symbol: a.symbol,
          quantity: 0,
          avgBuyPrice: 0,
          currentPrice: a.currentPrice > 0 ? a.currentPrice : a.avgBuyPrice,
          notes: a.notes,
        ),
      );
      if (a.id != null && created.id != null) {
        idMap[a.id!] = created.id!;
      }
      if (a.currentPrice > 0 && created.id != null) {
        created.currentPrice = a.currentPrice;
        await svc.assets.update(created);
      }
    }

    int? mapAssetId(int oldId) => idMap[oldId];

    final open = payload.trades
        .where((t) => t.status == AppConfig.tradeOpen)
        .toList()
      ..sort((a, b) => a.buyDate.compareTo(b.buyDate));
    for (final t in open) {
      final newId = mapAssetId(t.assetId);
      if (newId == null) continue;
      await svc.registerBuy(
        assetId: newId,
        quantity: t.quantity,
        buyPrice: t.buyPrice,
        buyPriceUsd: t.buyPriceUsd,
        buyUsdTmn: t.buyUsdTmn,
        buyFee: t.buyFee,
        buyDate: t.buyDate.isEmpty ? null : t.buyDate,
        buyNote: t.buyNoteDisplay,
        currentPrice: t.currentPrice > 0 ? t.currentPrice : null,
      );
    }

    final closed = payload.trades
        .where((t) => t.status == AppConfig.tradeClosed)
        .toList()
      ..sort((a, b) => a.buyDate.compareTo(b.buyDate));
    for (final t in closed) {
      final newId = mapAssetId(t.assetId);
      if (newId == null) continue;
      final bought = await svc.registerBuy(
        assetId: newId,
        quantity: t.quantity,
        buyPrice: t.buyPrice,
        buyPriceUsd: t.buyPriceUsd,
        buyUsdTmn: t.buyUsdTmn,
        buyFee: t.buyFee,
        buyDate: t.buyDate.isEmpty ? null : t.buyDate,
        buyNote: t.buyNoteDisplay,
      );
      if (bought.id == null) continue;
      await svc.closeTrade(
        tradeId: bought.id!,
        sellPrice: t.sellPrice ?? t.buyPrice,
        sellFee: t.sellFee,
        quantity: t.quantity,
        sellDate: t.sellDate,
        sellNote: t.sellNoteDisplay,
        sellUsdTmn: t.sellUsdTmn,
      );
    }

    var createdCount = 0;
    for (final w in payload.withdrawals) {
      try {
        final created = await svc.createWithdrawal(
          amount: w.amount,
          note: w.note,
          createdAt: w.createdAt,
          status: w.status,
        );
        if (created != null) createdCount++;
      } catch (_) {}
    }

    // Always keep the settings mirror: dedicated API may omit created_at or
    // only accept a subset of rows after restore.
    await svc.saveSettings(
      payload.settings,
      clientWithdrawals: payload.withdrawals,
      clientChecks: payload.checks,
      appLockHash: payload.appLockHash ?? '',
      appLockBiometric: payload.biometricUnlockEnabled,
    );
    if (createdCount == payload.withdrawals.length &&
        payload.withdrawals.isNotEmpty) {
      _withdrawalsFromRemote = true;
      _withdrawalsViaSettings = false;
    } else if (payload.withdrawals.isNotEmpty) {
      _withdrawalsFromRemote = false;
      _withdrawalsViaSettings = true;
    }
  }
}

class BackupRestoreReport {
  const BackupRestoreReport({
    required this.payload,
    required this.remotePushed,
    this.remoteWarning,
  });

  final BackupPayload payload;
  final bool remotePushed;
  final String? remoteWarning;
}

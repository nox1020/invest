import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:invest/config/app_config.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/data/app_lock_store.dart';
import 'package:invest/data/account_cache.dart';
import 'package:invest/data/app_database.dart';
import 'package:invest/data/check_repository.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/local_platform.dart';
import 'package:invest/data/notification_inbox_store.dart';
import 'package:invest/data/offline_cache_store.dart';
import 'package:invest/domain/services/connection_status.dart';
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
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/check_ledger.dart';
import 'package:invest/domain/services/commodity_index_service.dart';
import 'package:invest/domain/services/iran_inflation_service.dart';
import 'package:invest/domain/services/notification_service.dart';
import 'package:invest/domain/services/portfolio_service.dart';
import 'package:invest/domain/services/portfolio_upload.dart';
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

part 'app_state_lock.dart';
part 'app_state_index.dart';
part 'app_state_portfolio.dart';
part 'app_state_withdrawals.dart';
part 'app_state_checks.dart';
part 'app_state_quotes.dart';
part 'app_state_backup.dart';

class _StepFailure {
  _StepFailure(this.step, this.error);
  final String step;
  final Object error;
}

class _RefreshStepException implements Exception {
  _RefreshStepException(this.step, this.cause);
  final String step;
  final Object cause;

  @override
  String toString() => '$step: $cause';
}

/// App-wide state — online (Vinor API), offline cache, or local SQLite.
class AppState extends ChangeNotifier {
  AppState({http.Client? httpClient}) : _httpClient = httpClient;

  final http.Client? _httpClient;

  bool useRemote = true;
  bool authenticated = false;

  /// The server rejected this cookie. Local data and the stored session stay.
  /// The dashboard remains visible and asks for OTP again.
  bool reauthRequired = false;
  bool offline = false;
  bool readOnlyOffline = false;

  /// Why the last server check failed (null when online or unknown).
  OfflineCause? offlineCause;
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

  /// When a USDT rate last came from a live feed in this session. Null means
  /// [liveUsdt] is the stored rate (settings or offline cache), not live.
  DateTime? usdtLiveAt;

  /// When live prices (USDT, gold or the index) were last fetched.
  DateTime? pricesUpdatedAt;

  /// The rate is "live" when fetched within the last hour and we are online.
  bool get usdtIsLive =>
      !offline &&
      usdtLiveAt != null &&
      DateTime.now().difference(usdtLiveAt!) < const Duration(hours: 1);

  /// Best known time of the prices behind the portfolio value.
  DateTime? get pricesAsOf {
    final a = pricesUpdatedAt, b = offline ? null : lastSyncedAt;
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

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

  /// Per-phone cheque book and pending-delete caches (same keys as before).
  static final checkBookCache =
      AccountCache(keyOf: (a, _) => 'check_book_v1_$a');
  static final checkDeleteCache =
      AccountCache(keyOf: (a, _) => 'check_deleted_v1_$a');

  bool get canMutate => authenticated && !readOnlyOffline;

  @override
  void notifyListeners() {
    if (_holdUiNotifications) return;
    super.notifyListeners();
  }

  List<SeriesPoint> get capitalGrowthSeries {
    final snap = DashboardSnapshot.compute(
      assets: assets,
      openTrades: openTrades,
      closedTrades: closedTrades,
      usdtTmn: liveUsdt ?? settings.usdtTmnRate,
      calendar: settings.calendar,
      metrics: metrics,
      checks: checks,
    );
    // Like for like: the stored series is holdings only (no cheques).
    return ensureChartSeries(
      metrics?.growthSeries ?? const [],
      todayValue: snap.holdingsValue,
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
    // Year is always "today" in the current calendar: a cached/offline
    // metrics.yearKey can be from another year or calendar.
    final cal = settings.calendar;
    final key = yearPeriodKey(todayIso(), cal);
    final pwo = PwoStore.instance;
    var pwoYear = 0.0, pwoAll = 0.0;
    if (pwo.loaded) {
      for (final m in pwo.ledger.months.values) {
        final t = m.total;
        if (!(t > 0)) continue;
        pwoAll += t;
        if (WithdrawalAllowance.pwoYearKey(m.year, m.month, cal) == key) {
          pwoYear += t;
        }
      }
    }
    return WithdrawalAllowance.compute(
      realizedPnl: realized,
      openTrades: openTrades,
      closedTrades: closedTrades,
      withdrawals: withdrawals,
      annualPct: settings.annualWithdrawalPct,
      calendar: cal,
      yearKey: key,
      pwoYearWithdrawn: pwoYear,
      pwoAllTime: pwoAll,
      capBase: settings.withdrawalCapBase,
      navValue: settings.withdrawalCapBase == AppConfig.capBaseNav
          ? DashboardSnapshot.compute(
              assets: assets,
              openTrades: openTrades,
              closedTrades: closedTrades,
              usdtTmn: liveUsdt ?? settings.usdtTmnRate,
              calendar: cal,
              metrics: metrics,
              checks: checks,
            ).marketValue
          : null,
    );
  }

  Future<void> saveWithdrawalCapBase(String base) async {
    await saveSettings(
        settings.copyWith(withdrawalCapBase: AppSettings.parseCapBase(base)));
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
      await _noteServerPhone(auth.phone);
      switch (auth.status) {
        case AuthCheckStatus.authenticated:
          offline = false;
          readOnlyOffline = false;
          useRemote = true;
          authenticated = true;
          reauthRequired = false;
          try {
            await _loadRemoteData();
            _startAutoRefreshTimer();
          } on InvestApiException catch (e) {
            if (e.errorCode == 'network_error' || e.statusCode == null) {
              offlineCause = OfflineCause.network;
              await _bootOfflineWithSession();
              _startAutoRefreshTimer();
            } else {
              rethrow;
            }
          }
        case AuthCheckStatus.offline:
          offlineCause = auth.cause;
          await _bootOfflineWithSession();
        case AuthCheckStatus.unauthenticated:
          if ((_session?.sessionCookie ?? '').trim().isNotEmpty) {
            reauthRequired = true;
            await _bootOfflineWithSession();
          } else {
            authenticated = false;
            reauthRequired = false;
            offline = false;
            await _loadCommodityCacheQuietly();
          }
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
      error = await _fetchRemotePortfolio(
        includeQuotes: true,
        fetchSettings: true,
        checkApiVersion: true,
      );
      _startAutoRefreshTimer();
      _flushStoreQueuesAfterReconnect();
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
      if (auth.status == AuthCheckStatus.authenticated) {
        await _noteServerPhone(auth.phone);
        reauthRequired = false;
        offlineCause = null;
        return true;
      }
      if (auth.status == AuthCheckStatus.offline) {
        offlineCause = auth.cause ?? OfflineCause.network;
      }
      if (auth.status == AuthCheckStatus.unauthenticated &&
          (_session?.sessionCookie ?? '').trim().isNotEmpty) {
        // The server rejected this session. Keep the cached book and ask
        // for a new OTP without deleting the stored cookie.
        reauthRequired = true;
        authenticated = true;
      }
      return false;
    } catch (_) {
      offlineCause = OfflineCause.network;
      return false;
    }
  }

  /// Unsent writes across the PWO, ملک و دفتر and projects queues.
  int get pendingWrites =>
      PwoStore.instance.queue.items.length +
      BizStore.instance.queue.items.length +
      ProjectsStore.instance.queue.items.length;

  /// Status the AppBar subtitle, dashboard tag and banners all read.
  AppConnectionStatus get connectionStatus => AppConnectionStatus.resolve(
        offline: offline,
        updating: refreshing,
        localOnly: !useRemote,
        reauth: reauthRequired,
        cause: offlineCause,
      );

  /// Back online: send what the stores queued while offline. The stores
  /// fetch fresh data after flushing; failures stay queued with their keys.
  void _flushStoreQueuesAfterReconnect() {
    for (final r in <Future<void> Function()>[
      PwoStore.instance.refresh,
      BizStore.instance.refresh,
      ProjectsStore.instance.refresh,
    ]) {
      unawaited(r().catchError((Object e, StackTrace st) {
        logLocalFailure('reconnect-flush', e, st);
      }));
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
      reauthRequired = false;
      offline = false;
      readOnlyOffline = false;
      useRemote = true;
      offlineCause = null;
      await _loadRemoteData();
      _startAutoRefreshTimer();
      _flushStoreQueuesAfterReconnect();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _stopAutoRefreshTimer();
    PwoStore.instance.unbind();
    BizStore.instance.unbind();
    ProjectsStore.instance.unbind();
    try {
      if (!_checksHydrated) {
        await _loadLocalChecks();
      }
      await _stashChecksForCurrentPhone();
      await _clearActiveCheckTable();
    } catch (e, st) {
      logLocalFailure('logout-checks', e, st);
    }
    try {
      if (_api != null) {
        await _api!.logout();
      } else {
        await _session?.clearAuth();
      }
    } catch (e, st) {
      logLocalFailure('logout-session', e, st);
      try {
        await _session?.clearAuth();
      } catch (_) {}
    }
    authenticated = false;
    reauthRequired = false;
    offline = false;
    readOnlyOffline = false;
    offlineCause = null;
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

  Future<void> setBaseUrl(String url) async {
    final old = baseUrl;
    await _session?.setBaseUrl(url);
    baseUrl = _session?.baseUrl ?? AppConfig.defaultBaseUrl;
    if (old != baseUrl) {
      await logout();
    }
    notifyListeners();
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

  /// Local cache, keystore, and background-worker failures must not fail an
  /// online refresh. A broken SQLite file is recreated empty and refilled
  /// from the server book already in memory.
  Future<T?> _local<T>(String where, Future<T> Function() body) async {
    try {
      return await body();
    } catch (e, st) {
      logLocalFailure(where, e, st);
      if (isDatabaseFailure(e)) {
        settingsRepo = null;
        trades = null;
        portfolio = null;
        _withdrawalsRepo = null;
        _checksRepo = null;
        await AppDatabase.instance.discardBroken();
      }
      return null;
    }
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
    var filledGaps = false;
    final gaps = await _local(
      'settings-prefs',
      () => PriceAlertPrefs.fillGapsOnto(settings),
    );
    filledGaps = gaps ?? false;
    // Also heal from SQLite when Vinor returns empty year-nav history.
    if (settings.yearNavHistory.isEmpty) {
      await _local('settings-sqlite', () async {
        await _ensureLocalSettingsRepo();
        final map = await settingsRepo?.loadAll();
        final fromDb = YearNavList.parse(map?[AppConfig.settingYearNavHistory]);
        if (fromDb.isNotEmpty) {
          settings.yearNavHistory = fromDb;
          filledGaps = true;
        }
      });
    }
    await _local(
      'settings-lock',
      () => _applyRemoteLockFromBundle(bundle, migrateLocal: migrate),
    );
    await _local('settings-persist', () => _persistSettingsLocal(settings));
    await _local('settings-prefs-save', () => PriceAlertPrefs.saveFrom(settings));
    await _local('settings-worker', () => BackgroundPriceWorker.sync(settings));

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
      // Any remote-backed offline state probes (not only read-only), so the
      // app always finds its way back once the server answers.
      var reconnected = false;
      if (offline && useRemote) {
        if (await _probeOnline()) {
          offline = false;
          readOnlyOffline = false;
          reconnected = true;
        } else {
          error = null;
          return;
        }
      }

      if (useRemote && !offline) {
        error = await _fetchRemotePortfolio(
          includeQuotes: plan.includeQuotes,
          fetchSettings: plan.fetchSettings,
          checkApiVersion: plan.checkApiVersion,
        );
        // Flush store queues after the book loaded, not in parallel with it.
        if (reconnected && !offline) _flushStoreQueuesAfterReconnect();
      } else if (!useRemote) {
        await _publishLocalPortfolio();
        error = null;
      }
      try {
        await _dispatchProfitAlerts();
      } catch (e, st) {
        debugPrint('Invest refresh alerts failed: $e\n$st');
      }
    } on _RefreshStepException catch (e, st) {
      await _handleRefreshFailure(e.step, e.cause, st);
    } on InvestApiException catch (e, st) {
      await _handleRefreshFailure('refresh', e, st);
    } catch (e, st) {
      await _handleRefreshFailure('refresh', e, st);
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  /// Cookie is the account. A mismatch is logged and the label follows the
  /// server phone. The stored cookie is not replaced and the user is not
  /// logged out.
  Future<void> _noteServerPhone(String? serverPhone) async {
    final server = (serverPhone ?? '').trim();
    if (server.isEmpty) return;
    final stored = (userPhone ?? _session?.phone ?? '').trim();
    if (stored.isNotEmpty && stored != server) {
      await _switchCheckAccount(stored);
      String tail(String value) =>
          value.length <= 4 ? value : value.substring(value.length - 4);
      debugPrint(
        'session phone …${tail(stored)} differs from server …${tail(server)}',
      );
    }
    userPhone = server;
    final session = _session;
    if (session != null && session.phone != server) {
      unawaited(session.setPhone(server));
    }
  }

  Future<void> _handleRefreshFailure(
    String step,
    Object cause,
    StackTrace st,
  ) async {
    final tag = '$step: ${refreshFailureCode(cause)}';
    if (cause is InvestApiException && cause.isDefinitiveAuthRejection) {
      await _keepSessionAfterAuthRejection(tag, cause, st);
      return;
    }
    if (cause is InvestApiException && cause.errorCode == 'network_error') {
      debugPrint('Invest refresh failed: $cause\n$st');
      offline = true;
      offlineCause = OfflineCause.network;
      // A book already on screen stays (read-only) even if the disk cache
      // cannot be read; before, this path left offline+writable with a raw
      // error banner and the auto-probe never ran again (stuck «connecting»).
      final hadBook = assets.isNotEmpty ||
          openTrades.isNotEmpty ||
          closedTrades.isNotEmpty;
      final loaded = hadBook || await _applyPortfolioCache();
      if (loaded) {
        readOnlyOffline = true;
        error = null;
      } else {
        error = _refreshBanner(tag, showedServer: false, kept: false);
      }
      return;
    }
    debugPrint('Invest refresh failed: $cause\n$st');
    await _keepBookAfterRefreshFailure(tag);
  }

  /// A rejected cookie is re-checked once. Network, HTML, and 5xx never
  /// reach this. The stored cookie and the cached book stay either way.
  Future<void> _keepSessionAfterAuthRejection(
    String tag,
    InvestApiException cause,
    StackTrace st,
  ) async {
    debugPrint('Invest refresh auth rejected: $cause\n$st');
    var again = const AuthCheckResult(AuthCheckStatus.offline);
    if (_api != null) {
      try {
        again = await _api!.checkAuthDetailed();
      } catch (e, st2) {
        logLocalFailure('auth-recheck', e, st2);
      }
    }
    if (again.status == AuthCheckStatus.authenticated) {
      reauthRequired = false;
      await _keepBookAfterRefreshFailure(tag);
      return;
    }
    if (again.status == AuthCheckStatus.offline) {
      offline = true;
      offlineCause = again.cause ?? OfflineCause.network;
      final loaded = await _applyPortfolioCache();
      if (loaded) {
        readOnlyOffline = true;
        error = null;
      } else {
        error = _refreshBanner(tag, showedServer: false, kept: false);
      }
      return;
    }
    final hasSession = (_session?.sessionCookie ?? '').trim().isNotEmpty;
    if (!hasSession) {
      await _keepBookAfterRefreshFailure(tag);
      return;
    }
    reauthRequired = true;
    authenticated = true;
    offline = true;
    final loaded = await _applyPortfolioCache();
    if (loaded) readOnlyOffline = true;
    error = null;
  }

  String _refreshBanner(
    String tag, {
    required bool showedServer,
    required bool kept,
  }) {
    final tail = showedServer
        ? 'داده‌های سرور نشان داده می‌شود.'
        : kept
            ? 'داده‌های ذخیره‌شده نشان داده می‌شود.'
            : 'دوباره تلاش کنید.';
    return 'به‌روزرسانی داشبورد انجام نشد ($tag). $tail';
  }

  String _failureTag(List<_StepFailure> failures) {
    final tags = [
      for (final failure in failures)
        '${failure.step}: ${refreshFailureCode(failure.error)}',
    ];
    if (tags.length <= 4) return tags.join(', ');
    return '${tags.take(4).join(', ')} +${tags.length - 4}';
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

class _PhoneBook {
  const _PhoneBook({required this.assets, required this.trades});

  final List<Asset> assets;
  final List<Trade> trades;

  bool get hasRows => assets.isNotEmpty || trades.isNotEmpty;

  static const empty = _PhoneBook(assets: [], trades: []);
}

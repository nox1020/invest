import 'package:flutter/foundation.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/app_database.dart';
import 'package:invest/data/repositories.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/portfolio_service.dart';
import 'package:invest/domain/services/quote_clients.dart';
import 'package:invest/domain/services/trade_service.dart';
import 'package:sqflite/sqflite.dart';

class AppState extends ChangeNotifier {
  AppState();

  late Database db;
  late TradeService trades;
  late PortfolioService portfolio;
  late SettingsRepository settingsRepo;
  late QuoteClients quotes;

  AppSettings settings = AppSettings();
  DashboardMetrics? metrics;
  List<Asset> assets = [];
  List<Trade> openTrades = [];
  List<Trade> closedTrades = [];
  bool loading = true;
  String? error;
  double? liveUsdt;
  double? liveGold;

  Future<void> init({Database? testDb}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (testDb != null) {
        await AppDatabase.instance.bind(testDb);
        db = testDb;
      } else {
        db = await AppDatabase.instance.database;
      }
      trades = TradeService(db);
      portfolio = PortfolioService(db);
      settingsRepo = SettingsRepository(db);
      quotes = QuoteClients();
      await _loadSettings();
      await refresh();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadSettings() async {
    final map = await settingsRepo.loadAll();
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
    await settingsRepo.saveMap({
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
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    assets = await trades.assets.listAll();
    openTrades = await trades.trades.listOpen();
    closedTrades = await trades.trades.listClosed();
    metrics = await portfolio.getMetrics(calendar: settings.calendar);
    await portfolio.recordSnapshot();
    notifyListeners();
  }

  Future<void> refreshQuotes() async {
    if (!settings.livePricesEnabled) return;
    double? usdt;
    double? gold;
    if (settings.usdtApiEnabled) {
      usdt = await quotes.fetchUsdtToman(wallexUrl: settings.wallexUrl);
      if (usdt != null) {
        liveUsdt = usdt;
        settings.usdtTmnRate = usdt;
        await settingsRepo.set(AppConfig.settingUsdtTmn, usdt.toString());
      }
    }
    if (settings.goldApiEnabled) {
      final g =
          await quotes.fetchGoldToman(persianUrl: settings.persianToolboxUrl);
      gold = g.price;
      if (gold != null) {
        liveGold = gold;
        settings.goldTmnPerGram = gold;
        await settingsRepo.set(AppConfig.settingGoldTmn, gold.toString());
      }
    }
    await trades.applyLivePrices(
      usdtTmn: usdt ?? settings.usdtTmnRate,
      goldTmn: gold ?? settings.goldTmnPerGram,
      updateUsdt: settings.usdtApiEnabled,
      updateGold: settings.goldApiEnabled,
    );
    await refresh();
  }
}

part of 'app_state.dart';

// Split out of app_state.dart (pure move, no behaviour change).
extension AppStateQuotes on AppState {
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
      await _local(
        'quotes-settings',
        () async => settingsRepo?.set(
          AppConfig.settingUsdtTmn,
          fetchedUsdt.toString(),
        ),
      );
    }
    if (fetchedGold != null) {
      liveGold = fetchedGold;
      settings.goldTmnPerGram = fetchedGold;
      await _local(
        'quotes-settings',
        () async => settingsRepo?.set(
          AppConfig.settingGoldTmn,
          fetchedGold.toString(),
        ),
      );
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
    await _local('quotes-alerts', _dispatchPriceAlerts);
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
}

part of 'app_state.dart';

// Split out of app_state.dart (pure move, no behaviour change).
extension AppStatePortfolio on AppState {
  /// Each sub-request fails on its own. A non-empty assets or trades list
  /// from the server is shown and written over an empty snapshot.
  ///
  /// Returns a banner when a side step failed, or null when the book loaded
  /// cleanly. Throws [_RefreshStepException] only when assets, open trades,
  /// and closed trades all failed (or the session is 401).
  Future<String?> _fetchRemotePortfolio({
    required bool includeQuotes,
    required bool fetchSettings,
    required bool checkApiVersion,
  }) async {
    final failures = <_StepFailure>[];

    Future<T?> guard<T>(String step, Future<T> Function() run) async {
      try {
        return await run();
      } catch (e, st) {
        debugPrint('Invest refresh $step failed: $e\n$st');
        if (e is InvestApiException && e.isDefinitiveAuthRejection) {
          throw _RefreshStepException(step, e);
        }
        failures.add(_StepFailure(step, e));
        return null;
      }
    }

    final svc = remote!;
    final assetsF = guard('assets', () => svc.assets.listAll());
    final openF = guard('trades-open', () => svc.listOpen());
    final closedF = guard('trades-closed', () => svc.listClosed());
    final withdrawalsF = guard('withdrawals', () => svc.listWithdrawals());
    final insightsF = guard('insights', () => svc.fetchInsights());
    final settingsF = fetchSettings
        ? guard('settings', () => svc.fetchSettings())
        : Future<RemoteSettingsBundle?>.value(null);
    final healthF = checkApiVersion
        ? guard('health', () => _syncApiVersion())
        : Future<void>.value();

    final serverAssets = await assetsF;
    final serverOpen = await openF;
    final serverClosed = await closedF;
    final assetsOk = serverAssets != null;
    final openOk = serverOpen != null;
    final closedOk = serverClosed != null;
    if (!assetsOk && !openOk && !closedOk) {
      final book = failures.where(
        (f) =>
            f.step == 'assets' ||
            f.step == 'trades-open' ||
            f.step == 'trades-closed',
      );
      final first = book.isEmpty ? failures.first : book.first;
      throw _RefreshStepException(first.step, first.error);
    }

    final settingsBundle = await settingsF;
    if (settingsBundle != null) {
      await guard('settings', () async {
        final prevRefresh = settings.autoRefreshSeconds;
        await _applyRemoteSettingsBundle(settingsBundle, migrate: true);
        _normalizeGoldApiUrl();
        if (settings.autoRefreshSeconds != prevRefresh) {
          _startAutoRefreshTimer(immediate: false);
        }
      });
    }
    await healthF;
    final dash =
        await guard('dashboard', () => svc.fetchDashboard(settings.calendar));
    if (dash != null && svc.growthSeriesError != null) {
      failures.add(_StepFailure('snapshots', svc.growthSeriesError!));
    }
    final remoteWithdrawals = await withdrawalsF;
    final withdrawalsFailed = failures.any((f) => f.step == 'withdrawals');
    await insightsF;

    final bookComplete = assetsOk && openOk && closedOk;
    final merged = bookComplete
        ? await guard(
            'merge',
            () => _mergeLocalBook(
              serverAssets: serverAssets,
              serverOpen: serverOpen,
              serverClosed: serverClosed,
            ),
          )
        : null;
    final nextAssets = assetsOk ? (merged?.assets ?? serverAssets) : assets;
    final nextOpen = openOk ? (merged?.open ?? serverOpen) : openTrades;
    final nextClosed = closedOk ? (merged?.closed ?? serverClosed) : closedTrades;
    final showedServer = (assetsOk && serverAssets.isNotEmpty) ||
        (openOk && serverOpen.isNotEmpty) ||
        (closedOk && serverClosed.isNotEmpty);

    _holdUiNotifications = true;
    try {
      if (dash != null) {
        metrics = dash;
      } else if (metrics == null && showedServer) {
        metrics = _zeroMetrics();
      }
      assets = nextAssets;
      openTrades = nextOpen;
      closedTrades = nextClosed;
      if (!withdrawalsFailed) {
        await guard(
          'withdrawals',
          () => _applyWithdrawalsAfterFetch(
            remote: svc,
            remoteItems: remoteWithdrawals,
            settingsBundle: settingsBundle,
          ),
        );
      }
      await guard('checks', () => _applyChecksAfterFetch(settingsBundle));
      if (includeQuotes && settings.livePricesEnabled) {
        await guard('quotes', () => _syncLiveQuotes());
      } else {
        await guard('quotes', () => _overlayLiveMarks());
      }
      lastSyncedAt = DateTime.now();
      final nextEmpty = nextAssets.isEmpty &&
          nextOpen.isEmpty &&
          nextClosed.isEmpty;
      if (showedServer || (bookComplete && !nextEmpty)) {
        if (metrics == null) metrics = _zeroMetrics();
        await guard('snapshots', () => _savePortfolioUnlessEmptyWipesCache());
      }
    } finally {
      _holdUiNotifications = false;
    }

    if (failures.isEmpty) return null;
    final kept = assets.isNotEmpty ||
        openTrades.isNotEmpty ||
        closedTrades.isNotEmpty;
    return _refreshBanner(
      _failureTag(failures),
      showedServer: showedServer,
      kept: kept,
    );
  }

  DashboardMetrics _zeroMetrics() {
    return DashboardMetrics(
      totalValue: 0,
      totalPnl: 0,
      totalPnlPct: 0,
      realizedPnl: 0,
      unrealizedPnl: 0,
      openCount: openTrades.length,
      closedCount: closedTrades.length,
      yearRealizedPnl: 0,
      yearKey: '',
      goldFund: const GoldFundMetrics(goldInG: 0, goldOutG: 0, goldHoldingG: 0),
    );
  }

  /// A failed refresh must keep the book already on screen, or the last
  /// snapshot, and say which step failed. A 401 still logs out above.
  Future<void> _keepBookAfterRefreshFailure(String tag) async {
    final hadBook = assets.isNotEmpty ||
        openTrades.isNotEmpty ||
        closedTrades.isNotEmpty;
    var kept = hadBook;
    if (!hadBook) {
      try {
        kept = await _applyPortfolioCache();
      } catch (e, st) {
        debugPrint('cached book restore failed: $e\n$st');
        kept = false;
      }
    }
    error = _refreshBanner(tag, showedServer: false, kept: kept);
  }

  /// An empty server book must not replace rows that still live on the phone.
  /// A non-empty book is always written, even when dashboard metrics failed.
  Future<void> _savePortfolioUnlessEmptyWipesCache() async {
    try {
      await _savePortfolioCache();
    } catch (e, st) {
      logLocalFailure('snapshots', e, st);
    }
  }

  Future<void> _savePortfolioCache() async {
    final bookEmpty =
        assets.isEmpty && openTrades.isEmpty && closedTrades.isEmpty;
    if (bookEmpty && await OfflineCacheStore.hasPortfolioCache()) {
      debugPrint('skip empty portfolio snapshot; keeping the saved book');
      return;
    }
    final snapMetrics = metrics ?? _zeroMetrics();
    metrics ??= snapMetrics;
    await OfflineCacheStore.savePortfolio(
      settings: settings,
      metrics: snapMetrics,
      assets: assets,
      openTrades: openTrades,
      closedTrades: closedTrades,
      withdrawals: withdrawals,
      checks: checks,
      liveUsdt: liveUsdt,
      liveGold: liveGold,
    );
  }

  String get _portfolioUploadPendingKey =>
      'portfolio_upload_pending_v1_${(userPhone ?? _session?.phone ?? '').trim()}';

  Future<bool> _isPortfolioUploadPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_portfolioUploadPendingKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _setPortfolioUploadPending(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setBool(_portfolioUploadPendingKey, true);
      } else {
        await prefs.remove(_portfolioUploadPendingKey);
      }
    } catch (e, st) {
      debugPrint('portfolio upload flag failed: $e\n$st');
    }
  }

  /// SQLite wins when it has rows. Otherwise the offline snapshot.
  Future<_PhoneBook> _loadPhoneBook() async {
    try {
      final db = await AppDatabase.instance.database;
      final storedAssets = await AssetRepository(db).listAll();
      final tradeRepo = TradeRepository(db);
      final open = await tradeRepo.listOpen();
      final closed = await tradeRepo.listClosed();
      if (storedAssets.isNotEmpty || open.isNotEmpty || closed.isNotEmpty) {
        return _PhoneBook(
          assets: storedAssets,
          trades: [...open, ...closed],
        );
      }
    } catch (e, st) {
      debugPrint('local portfolio read failed: $e\n$st');
    }
    OfflinePortfolioSnapshot? snap;
    try {
      snap = await OfflineCacheStore.loadPortfolio();
    } catch (e, st) {
      logLocalFailure('merge-cache', e, st);
      return _PhoneBook.empty;
    }
    if (snap == null) return _PhoneBook.empty;
    return _PhoneBook(
      assets: snap.assets,
      trades: [...snap.openTrades, ...snap.closedTrades],
    );
  }

  /// Show and upload the phone book when the server lists are empty, or when
  /// a previous upload is still unfinished. Server rows are never removed.
  Future<({List<Asset> assets, List<Trade> open, List<Trade> closed})>
      _mergeLocalBook({
    required List<Asset> serverAssets,
    required List<Trade> serverOpen,
    required List<Trade> serverClosed,
  }) async {
    final local = await _loadPhoneBook();
    final pending = await _isPortfolioUploadPending();
    final serverEmpty = serverAssets.isEmpty &&
        serverOpen.isEmpty &&
        serverClosed.isEmpty;
    if (!((serverEmpty && local.hasRows) || pending)) {
      return (assets: serverAssets, open: serverOpen, closed: serverClosed);
    }
    final serverTrades = [...serverOpen, ...serverClosed];
    final plan = planPortfolioUpload(
      localAssets: local.assets,
      localTrades: local.trades,
      serverAssets: serverAssets,
      serverTrades: serverTrades,
    );
    if (plan.isComplete) {
      if (pending) await _setPortfolioUploadPending(false);
    } else {
      await _setPortfolioUploadPending(true);
      await _pushPlannedPortfolio(
        plan,
        localTrades: local.trades,
        serverTrades: serverTrades,
      );
    }
    return (
      assets: plan.displayAssets,
      open: plan.displayOpen,
      closed: plan.displayClosed,
    );
  }

  /// Creates missing rows only. A failed row stays on the phone and the
  /// pending flag makes the next refresh try it again.
  Future<void> _pushPlannedPortfolio(
    PortfolioUploadPlan plan, {
    required List<Trade> localTrades,
    required List<Trade> serverTrades,
  }) async {
    final svc = remote;
    if (svc == null) return;
    final ids = Map<String, int>.from(plan.assetIdsByKey);
    for (final asset in plan.assetsToCreate) {
      try {
        final hasLots = assetHasLocalTrades(asset, localTrades);
        final created = await svc.assets.create(Asset(
          name: asset.name,
          symbol: asset.symbol,
          quantity: hasLots ? 0 : asset.quantity,
          avgBuyPrice: hasLots ? 0 : asset.avgBuyPrice,
          currentPrice: asset.currentPrice,
          notes: asset.notes,
        ));
        final id = created.id;
        if (id != null) {
          ids[portfolioAssetKey(asset.name, asset.symbol)] = id;
        }
      } catch (e, st) {
        debugPrint('portfolio asset upload failed: $e\n$st');
      }
    }
    for (final trade in plan.tradesToCreate) {
      try {
        final key = portfolioAssetKey(trade.assetName, trade.assetSymbol);
        if (trade.isClosed) {
          final openMatch = _matchingOpenServerTrade(trade, serverTrades);
          final openId = openMatch?.id;
          if (openId != null) {
            await svc.closeTrade(
              tradeId: openId,
              sellPrice: trade.sellPrice!,
              sellFee: trade.sellFee,
              sellDate: trade.sellDate,
              sellNote: trade.sellNote,
              quantity: trade.quantity,
            );
            continue;
          }
        }
        final bought = await svc.registerBuy(
          assetId: ids[key],
          name: trade.assetName,
          symbol: trade.assetSymbol,
          quantity: trade.quantity,
          buyPrice: trade.buyPrice,
          buyPriceUsd: trade.buyPriceUsd,
          buyUsdTmn: trade.buyUsdTmn,
          buyFee: trade.buyFee,
          buyDate: trade.buyDate.trim().isEmpty ? null : trade.buyDate,
          buyNote: trade.buyNote,
          currentPrice: trade.currentPrice > 0 ? trade.currentPrice : null,
        );
        if (trade.isClosed && bought.id != null) {
          await svc.closeTrade(
            tradeId: bought.id!,
            sellPrice: trade.sellPrice!,
            sellFee: trade.sellFee,
            sellDate: trade.sellDate,
            sellNote: trade.sellNote,
            quantity: trade.quantity,
          );
        }
      } catch (e, st) {
        debugPrint('portfolio trade upload failed: $e\n$st');
      }
    }
  }

  Trade? _matchingOpenServerTrade(Trade local, List<Trade> serverTrades) {
    final key = portfolioAssetKey(local.assetName, local.assetSymbol);
    for (final server in serverTrades) {
      if (!server.isOpen || server.id == null) continue;
      if (portfolioAssetKey(server.assetName, server.assetSymbol) != key) {
        continue;
      }
      if ((server.quantity - local.quantity).abs() > 0.0001) continue;
      if ((server.buyPrice - local.buyPrice).abs() > 0.0001) continue;
      if (server.buyDate != local.buyDate) continue;
      return server;
    }
    return null;
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
}

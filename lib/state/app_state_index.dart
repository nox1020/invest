part of 'app_state.dart';

// Split out of app_state.dart (pure move, no behaviour change).
extension AppStateIndex on AppState {
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
}

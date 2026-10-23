part of 'app_state.dart';

// Split out of app_state.dart (pure move, no behaviour change).
extension AppStateBackup on AppState {
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
    // PWO + ملک و دفتر: server is the source of truth when connected;
    // otherwise the last loaded / cached copy.
    Map<String, dynamic>? pwo;
    Map<String, dynamic>? biz;
    final pwoStore = PwoStore.instance;
    if (pwoStore.loaded) pwo = pwoStore.ledger.toBackupPayload();
    final svc = remote;
    if (useRemote && svc != null && !offline) {
      try {
        biz = await svc.biz.export();
      } catch (_) {}
    }
    if (biz == null && BizStore.instance.loaded) {
      final s = BizStore.instance.snap;
      biz = {
        'trades': [
          for (final t in s.trades)
            {
              for (final k in const ['buy_date', 'sell_date', 'buy_amount', 'sell_amount', 'area', 'title', 'extra_cost', 'note'])
                k: t.raw[k],
            }
        ],
        'months': [
          for (final m in s.months)
            if (m.hasOps)
              {for (final k in const ['year', 'month', 'staff', 'ads', 'income', 'note']) k: m.raw[k]}
        ],
      };
    }
    Map<String, dynamic>? projects;
    if (useRemote && svc != null && !offline) {
      try {
        projects = await svc.projects.export();
      } catch (_) {}
    }
    final ps = ProjectsStore.instance;
    if (projects == null && ps.loaded && ps.snap.hasData) {
      projects = {
        'projects': [
          for (final p in ps.snap.items)
            {
              for (final k in const ['title', 'work_type', 'start_date', 'end_date', 'contract_amount', 'cost', 'status_mode', 'note'])
                k: p.raw[k],
              'archived': p.archived,
            }
        ],
      };
    }
    final payload = BackupService.buildFromMemory(
      pwo: pwo,
      biz: biz,
      projects: projects,
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
    final extrasNote = await _restorePwoBiz(payload);
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
      remoteWarning: _joinNotes([remoteWarning, extrasNote]),
    );
  }

  static String? _joinNotes(List<String?> xs) {
    final s = xs.whereType<String>().where((x) => x.isNotEmpty).join('\n');
    return s.isEmpty ? null : s;
  }

  /// PWO + ملک و دفتر go only through the servers' guarded imports: an
  /// account that already has data is never overwritten.
  Future<String?> _restorePwoBiz(BackupPayload payload) async {
    if (payload.pwo == null && payload.biz == null && payload.projects == null) return null;
    final svc = remote;
    if (!useRemote || svc == null || offline || readOnlyOffline) {
      return 'PWO و ملک و دفتر فقط با اتصال به حساب وینور بازیابی می‌شوند.';
    }
    final notes = <String>[];
    if (payload.pwo != null) {
      try {
        final r = await svc.pwo.importRaw(payload.pwo!);
        if (r['already_has_data'] == true) {
          notes.add('PWO روی سرور داده داشت و بازنویسی نشد.');
        }
        await PwoStore.instance.refresh();
      } catch (e) {
        notes.add('بازیابی PWO انجام نشد: ${formatUserError(e)}');
      }
    }
    if (payload.biz != null) {
      try {
        final r = await svc.biz.import(payload.biz!);
        if (r['already_has_data'] == true) {
          notes.add('ملک و دفتر روی سرور داده داشت و بازنویسی نشد.');
        }
        await BizStore.instance.refresh();
      } catch (e) {
        notes.add('بازیابی ملک و دفتر انجام نشد: ${formatUserError(e)}');
      }
    }
    if (payload.projects != null) {
      // Append-only on the server: rows already there are skipped.
      try {
        await svc.projects.import(payload.projects!);
        await ProjectsStore.instance.refresh();
      } catch (e) {
        notes.add('بازیابی پروژه‌ها انجام نشد: ${formatUserError(e)}');
      }
    }
    return notes.isEmpty ? null : notes.join('\n');
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

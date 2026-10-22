part of 'app_state.dart';

// Split out of app_state.dart (pure move, no behaviour change).
extension AppStateWithdrawals on AppState {
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
}

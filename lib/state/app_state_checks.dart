part of 'app_state.dart';

// Split out of app_state.dart (pure move, no behaviour change).
extension AppStateChecks on AppState {
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
}

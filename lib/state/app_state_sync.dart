part of 'app_state.dart';

/// Offline-first core book: every create/edit/delete of assets, trades and
/// system withdrawals works offline. Changes go to the persisted
/// [AppState.coreOutbox] (ordered, idempotent keys), show at once through an
/// idempotent overlay on the lists, and are sent as soon as the server is
/// reachable (reconnect, resume, refresh, periodic retry with backoff).
extension AppStateSync on AppState {
  bool get _serverWritable =>
      useRemote && !offline && !readOnlyOffline && remote != null;

  Future<void> _bindOutbox() => coreOutbox.bind(userPhone ?? _session?.phone);

  /// Re-applies queued ops to the current lists (idempotent) and drops
  /// stale temp rows (op sent or discarded). Called before every redraw.
  void _overlayCore() {
    if (!useRemote) return;
    final ob = coreOutbox;
    final acc = AccountCache.norm(userPhone ?? _session?.phone);
    if (acc.isNotEmpty && ob.account != acc) {
      unawaited(ob.bind(acc));
      return;
    }
    final live = ob.liveTempIds;
    bool stale(int? id) => id != null && id < 0 && !live.contains(id);
    if (assets.any((a) => stale(a.id)) ||
        openTrades.any((t) => stale(t.id) || stale(t.assetId)) ||
        closedTrades.any((t) => stale(t.id)) ||
        withdrawals.any((w) => stale(w.id))) {
      assets = [for (final a in assets) if (!stale(a.id)) a];
      openTrades = [for (final t in openTrades) if (!stale(t.id) && !stale(t.assetId)) t];
      closedTrades = [for (final t in closedTrades) if (!stale(t.id)) t];
      withdrawals = [for (final w in withdrawals) if (!stale(w.id)) w];
    }
    if (ob.isEmpty) return;
    final book = CoreBook(assets: assets, open: openTrades, closed: closedTrades, withdrawals: withdrawals);
    final touched = <int>{};
    for (final op in ob.ops) {
      applyCoreOp(book, op);
      if (op.kind.startsWith('trade.') || op.kind == 'asset.create') {
        final aid = op.args['assetId'] ?? op.args['tmp'];
        if (aid is num) touched.add(aid.toInt());
        final tid = op.args['tradeId'];
        if (tid is num) {
          for (final t in [...book.open, ...book.closed]) {
            if (t.id == tid) touched.add(t.assetId);
          }
        }
        if (op.kind == 'trade.buy') {
          for (final t in book.open) {
            if (t.id == op.args['tmp']) touched.add(t.assetId);
          }
        }
      }
    }
    recomputeAssetHoldings(book, touched);
    assets = book.assets;
    openTrades = book.open;
    closedTrades = book.closed;
    withdrawals = book.withdrawals;
  }

  /// Pending (not yet on the server) items across the whole app.
  int get pendingSyncCount =>
      coreOutbox.length +
      PwoStore.instance.queue.length +
      BizStore.instance.queue.length +
      ProjectsStore.instance.queue.length +
      (_checksPendingSync ? (dirtyCheckIds.length + _pendingDeletedCheckIds.length).clamp(1, 1 << 30) : 0);

  bool isPendingId(int? id) => id != null && id < 0;

  /// Runs [direct] when the server is writable; otherwise (or on a network
  /// failure) queues [kind] with the same idempotency key and shows it now.
  Future<T> _queueable<T>({
    required String kind,
    required Map<String, dynamic> args,
    required String label,
    required Future<T> Function() direct,
    required T Function() placeholder,
  }) async {
    await _bindOutbox();
    final key = newIdempotencyKey();
    if (_serverWritable && coreOutbox.isEmpty) {
      try {
        return await IdempotencyScope.run(key, direct);
      } catch (e) {
        if (!isRetryableWriteError(e)) rethrow;
      }
    }
    await coreOutbox.add(kind, args, label, key: key);
    notifyListeners();
    unawaited(_persistPortfolioCacheQuiet());
    scheduleSync(soon: true);
    return placeholder();
  }

  Future<void> _persistPortfolioCacheQuiet() async {
    try {
      await _persistWithdrawalCache();
    } catch (_) {}
  }

  int _mapId(int id) => coreOutbox.idMap[id] ?? id;

  /// Sends the core outbox; then pulls fresh lists. Safe to call any time.
  Future<bool> flushCoreOutbox() async {
    await _bindOutbox();
    if (coreOutbox.isEmpty) return true;
    if (!_serverWritable) return false;
    final svc = remote!;
    final drained = await coreOutbox.flush((op) => sendCoreOp(
          svc,
          op,
          createWithdrawal: (a) async {
            final tmp = (a['tmp'] as num).toInt();
            var w = await svc.createWithdrawal(
                amount: (a['amount'] as num).toDouble(),
                note: '${a['note'] ?? ''}',
                createdAt: a['createdAt'] as String?);
            // Older server: the settings mirror is the store (as online).
            w ??= await (await _localWithdrawals()).create(Withdrawal(
                amount: (a['amount'] as num).toDouble(),
                note: '${a['note'] ?? ''}',
                createdAt: '${a['createdAt'] ?? ''}'.trim()));
            final real = w;
            withdrawals = withdrawals.any((x) => x.id == tmp)
                ? [for (final x in withdrawals) if (x.id == tmp) real else x]
                : [real, ...withdrawals];
            await _pushUserExtrasToServer(
                clientWithdrawals: withdrawals, rethrowErrors: true);
            await _persistWithdrawalCache();
            return real;
          },
          updateWithdrawal: (a) async {
            final id = (a['id'] as num).toInt();
            final cur = withdrawals.where((w) => w.id == id).firstOrNull;
            final next = Withdrawal(
                id: id,
                amount: (a['amount'] as num).toDouble(),
                note: '${a['note'] ?? ''}',
                status: cur?.status ?? 'completed',
                createdAt: '${a['createdAt'] ?? cur?.createdAt ?? ''}');
            if (await svc.updateWithdrawal(next) == null) {
              try {
                await (await _localWithdrawals()).update(next);
              } catch (_) {}
            }
            withdrawals = [for (final x in withdrawals) if (x.id == id) next else x];
            await _pushUserExtrasToServer(
                clientWithdrawals: withdrawals, rethrowErrors: true);
            await _persistWithdrawalCache();
          },
          pushSettings: () async {
            final b = await _pushUserExtrasToServer(rethrowErrors: true);
            if (b == null) {
              throw InvestApiException('ارتباط با سرور برقرار نشد (آفلاین).',
                  errorCode: 'network_error');
            }
          },
        ));
    notifyListeners();
    return drained;
  }

  /// Flushes every queue in the app (core, PWO, ملک و دفتر, projects, cheques).
  Future<void> syncNow() async {
    if (!useRemote) return;
    if (offline) {
      await tryGoOnline();
      if (offline) {
        scheduleSync();
        return;
      }
    }
    var ok = await flushCoreOutbox();
    _flushStoreQueuesAfterReconnect();
    if (_checksPendingSync && _checksApiReady) {
      try {
        await _applyChecksAfterFetch(null);
      } catch (_) {}
    }
    if (ok) {
      try {
        await refresh();
      } catch (_) {}
    }
    ok = ok && coreOutbox.isEmpty;
    if (!ok || pendingSyncCount > 0) scheduleSync();
  }

  /// Periodic retry with exponential backoff (15 s … 5 min) while anything
  /// is pending. [soon] retries after a couple of seconds.
  void scheduleSync({bool soon = false}) {
    _syncTimer?.cancel();
    if (pendingSyncCount == 0 && !soon) {
      _syncBackoff = 0;
      return;
    }
    final secs = soon ? 2 : (15 * (1 << _syncBackoff.clamp(0, 5))).clamp(15, 300);
    if (!soon) _syncBackoff++;
    _syncTimer = Timer(Duration(seconds: secs), () {
      unawaited(syncNow().catchError((Object e, StackTrace st) {
        logLocalFailure('sync-retry', e, st);
      }));
    });
  }
}

/// [InvestMutations] for server mode that keeps working offline.
class QueueingMutations implements InvestMutations {
  QueueingMutations(this.s);
  final AppState s;

  RemoteInvestService get _r => s.remote!;

  @override
  Future<Asset> createAsset({required String name, String symbol = '', double quantity = 0, double avgBuyPrice = 0, double currentPrice = 0, String notes = '', String? buyDate}) {
    if (name.trim().isEmpty) throw ArgumentError('نام دارایی الزامی است.');
    if (quantity > 0 && avgBuyPrice <= 0) throw ArgumentError('برای موجودی اولیه، قیمت خرید الزامی است.');
    final tmp = newTempId();
    final args = {'tmp': tmp, 'lot_tmp': tmp - 1, 'name': name.trim(), 'symbol': symbol.trim(), 'quantity': quantity, 'avgBuyPrice': avgBuyPrice, 'currentPrice': currentPrice, 'notes': notes, 'buyDate': buyDate};
    return s._queueable(
      kind: 'asset.create', args: args, label: 'دارایی «${name.trim()}»',
      direct: () => _r.createAsset(name: name, symbol: symbol, quantity: quantity, avgBuyPrice: avgBuyPrice, currentPrice: currentPrice, notes: notes, buyDate: buyDate),
      placeholder: () => s.assets.firstWhere((a) => a.id == tmp, orElse: () => Asset(id: tmp, name: name)),
    );
  }

  @override
  Future<void> updateAsset(Asset asset) {
    final a = Asset.fromMap(asset.toMap())..id = s._mapId(asset.id!);
    return s._queueable(
      kind: 'asset.update', args: {'asset': a.toMap()}, label: 'ویرایش «${a.name}»',
      direct: () => _r.updateAsset(a), placeholder: () {});
  }

  @override
  Future<Trade> registerBuy({int? assetId, String? name, String symbol = '', required double quantity, required double buyPrice, double? buyPriceUsd, double? buyUsdTmn, double buyFee = 0, String? buyDate, String buyNote = '', double? currentPrice}) {
    if (quantity <= 0 || buyPrice <= 0) throw ArgumentError('مقدار و قیمت خرید باید بیشتر از صفر باشد.');
    final aid = assetId == null ? null : s._mapId(assetId);
    final tmp = newTempId();
    final args = {'tmp': tmp, 'asset_tmp': tmp - 1, 'assetId': aid, 'name': name, 'symbol': symbol, 'quantity': quantity, 'buyPrice': buyPrice, 'buyPriceUsd': buyPriceUsd, 'buyUsdTmn': buyUsdTmn, 'buyFee': buyFee, 'buyDate': buyDate, 'buyNote': buyNote, 'currentPrice': currentPrice};
    final who = s.assets.where((a) => a.id == aid).firstOrNull?.name ?? name ?? '';
    return s._queueable(
      kind: 'trade.buy', args: args, label: 'خرید $who',
      direct: () => _r.registerBuy(assetId: aid, name: name, symbol: symbol, quantity: quantity, buyPrice: buyPrice, buyPriceUsd: buyPriceUsd, buyUsdTmn: buyUsdTmn, buyFee: buyFee, buyDate: buyDate, buyNote: buyNote, currentPrice: currentPrice),
      placeholder: () => s.openTrades.firstWhere((t) => t.id == tmp, orElse: () => Trade(id: tmp, assetId: aid ?? 0, status: AppConfig.tradeOpen, quantity: quantity, buyPrice: buyPrice)),
    );
  }

  @override
  Future<Trade> updateOpenTrade({required int tradeId, required double quantity, required double buyPrice, double? buyPriceUsd, double? buyUsdTmn, double buyFee = 0, String? buyDate, String? buyNote}) {
    final id = s._mapId(tradeId);
    final args = {'tradeId': id, 'quantity': quantity, 'buyPrice': buyPrice, 'buyPriceUsd': buyPriceUsd, 'buyUsdTmn': buyUsdTmn, 'buyFee': buyFee, 'buyDate': buyDate, 'buyNote': buyNote};
    return s._queueable(
      kind: 'trade.update', args: args, label: 'ویرایش خرید',
      direct: () => _r.updateOpenTrade(tradeId: id, quantity: quantity, buyPrice: buyPrice, buyPriceUsd: buyPriceUsd, buyUsdTmn: buyUsdTmn, buyFee: buyFee, buyDate: buyDate, buyNote: buyNote),
      placeholder: () => s.openTrades.firstWhere((t) => t.id == id, orElse: () => Trade(id: id, assetId: 0, status: AppConfig.tradeOpen, quantity: quantity, buyPrice: buyPrice)),
    );
  }

  @override
  Future<Trade> closeTrade({required int tradeId, required double sellPrice, double sellFee = 0, String? sellDate, String sellNote = '', double? quantity, double? sellUsdTmn}) {
    final id = s._mapId(tradeId);
    final args = {'tradeId': id, 'closed_tmp': newTempId(), 'sellPrice': sellPrice, 'sellFee': sellFee, 'sellDate': sellDate, 'sellNote': sellNote, 'quantity': quantity, 'sellUsdTmn': sellUsdTmn};
    return s._queueable(
      kind: 'trade.close', args: args, label: 'فروش',
      direct: () => _r.closeTrade(tradeId: id, sellPrice: sellPrice, sellFee: sellFee, sellDate: sellDate, sellNote: sellNote, quantity: quantity, sellUsdTmn: sellUsdTmn),
      placeholder: () => s.closedTrades.firstWhere((t) => t.id == id || t.id == args['closed_tmp'], orElse: () => Trade(id: id, assetId: 0, status: AppConfig.tradeClosed, quantity: quantity ?? 0, buyPrice: 0, sellPrice: sellPrice)),
    );
  }

  @override
  Future<void> deleteClosedTrade(int tradeId) {
    final id = s._mapId(tradeId);
    return s._queueable(
      kind: 'trade.delete', args: {'tradeId': id}, label: 'حذف معاملهٔ بسته',
      direct: () => _r.deleteClosedTrade(id), placeholder: () {});
  }
}

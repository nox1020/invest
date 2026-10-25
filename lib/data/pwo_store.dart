import 'package:flutter/foundation.dart';

import 'package:invest/data/account_cache.dart';
import 'package:invest/data/local_platform.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/pwo_remote.dart';
import 'package:invest/data/write_queue.dart';
import 'package:invest/domain/services/pwo_ledger.dart';

/// Thrown for writes while only a read-only account cache is shown.
class PwoReadOnlyException implements Exception {
  const PwoReadOnlyException();
  @override
  String toString() =>
      'اتصال به حساب وینور برقرار نیست؛ PWO فعلاً فقط خواندنی است.';
}

/// PWO ledger state.
///
/// * Local mode (no Vinor account bound): device-only, legacy key.
/// * Remote mode: Vinor `/pwo` is the source of truth for the bound account,
///   with a per-account cache for offline display. The first sync per
///   account runs `POST /pwo/import` once; the device's pre-server data
///   (incl. the 1405 seed) goes only to the first account that claims it.
class PwoStore extends ChangeNotifier {
  PwoStore._();
  static final PwoStore instance = PwoStore._();

  static const prefsKey = 'vplus_pwo_ledger_v1';
  static const legacyOwnerKey = 'vplus_pwo_legacy_owner_v1';
  static String cacheKey(String account) => 'vplus_pwo_cache_v1_$account';
  static String migratedKey(String account) => 'vplus_pwo_migrated_v1_$account';

  /// Last account bound on this device. While set, device-only mode shows
  /// that account's cache read-only instead of the legacy local ledger/seed.
  static const lastAccountKey = 'vplus_pwo_last_account_v1';
  static final cache = AccountCache(
      keyOf: (a, _) => cacheKey(a), lastAccountKey: lastAccountKey);
  bool _cacheOnly = false;

  /// Offline edits of a bound account are queued, never refused.
  bool get readOnly => false;

  /// Writes waiting to be sent for the bound account (offline queue).
  final WriteQueue queue = WriteQueue('pwo');

  /// Remote semantics (server ids, queue) apply: bound, or its cache shown.
  bool get _accountMode => isRemote || (_cacheOnly && _account != null);

  PwoLedger _ledger = PwoLedger();
  bool _loaded = false;
  PwoRemote? _remote;
  String? _account;
  bool _syncing = false;
  Future<void>? _sync;

  /// Last server/network error text (Persian, from the server when given).
  String? lastError;

  /// True when showing cached data because the server could not be reached.
  bool showingCache = false;

  PwoLedger get ledger => _ledger;
  bool get loaded => _loaded;
  bool get isRemote => _remote != null && _account != null;
  bool get syncing => _syncing;
  String? get account => _account;

  /// Binds the store to a Vinor account. Switching accounts drops the
  /// previous account's in-memory data before anything else is shown.
  Future<void> bindAccount(PwoRemote remote, String account) async {
    final acc = account.trim();
    if (acc.isEmpty) return;
    _remote = remote;
    if (_cacheOnly) {
      _cacheOnly = false;
      _account = null;
    }
    if (_account != acc) {
      _account = acc;
      _loaded = false;
      _sync = null;
      lastError = null;
      showingCache = false;
      _ledger = PwoLedger(people: []);
      notifyListeners();
      await queue.bind(acc);
      await cache.setLastAccount(acc);
      final raw = await cache.read(acc);
      if (_account != acc) return;
      if (raw != null) {
        _ledger = PwoLedger.decode(raw);
        _loaded = true;
      }
      notifyListeners();
    }
    await refresh();
  }

  /// App left server mode (e.g. offline start) without logging out: keep
  /// the last account so [load] shows its cache, not the device seed.
  void detachRemote() {
    _remote = null;
    _account = null;
    _sync = null;
    _loaded = false;
    _cacheOnly = false;
    notifyListeners();
  }

  /// Back to device-only mode (logout).
  void unbind() {
    _cacheOnly = false;
    cache.clearLastAccount();
    queue.bind(null); // the queue stays on disk for that account
    _remote = null;
    _account = null;
    _sync = null;
    _loaded = false;
    lastError = null;
    showingCache = false;
    _ledger = PwoLedger();
    notifyListeners();
  }

  Future<void> load() async {
    if (isRemote) return _sync ?? refresh();
    if (_loaded) return;
    final prefs = await LocalPrefs.open();
    if (isRemote) return;
    final last = prefs?.getString(lastAccountKey);
    if (last != null && last.isNotEmpty) {
      // This device syncs PWO with a Vinor account: never fall back to the
      // legacy device ledger / 1405 seed. Show that account's cache only.
      _cacheOnly = true;
      _account = last;
      await queue.bind(last);
      _ledger = PwoLedger.decode(prefs?.getString(cacheKey(last)));
      _loaded = true;
      showingCache = true;
      lastError = offlineQueueNote;
      notifyListeners();
      return;
    }
    final raw = prefs?.getString(prefsKey);
    _ledger = PwoLedger.decode(raw);
    _loaded = true;
    if (_ledger.applySeed()) await _save();
    notifyListeners();
  }

  /// Pulls the server snapshot (importing local data once per account).
  Future<void> refresh() {
    if (!isRemote) return load();
    final existing = _sync;
    if (existing != null) return existing;
    late final Future<void> f;
    f = _doSync().whenComplete(() {
      if (identical(_sync, f)) _sync = null;
    });
    return _sync = f;
  }

  Future<void> _doSync() async {
    final remote = _remote!, acc = _account!;
    _syncing = true;
    notifyListeners();
    try {
      final prefs = await LocalPrefs.open();
      final migrated = prefs?.getBool(migratedKey(acc)) ?? false;
      Map<String, dynamic>? snap;
      if (!migrated) {
        // Never import over an account that already has data (reinstall,
        // cleared storage, another phone). Server is the source of truth.
        final current = await remote.fetch();
        bool nonEmpty(Object? v) => v is List && v.isNotEmpty;
        final hasData =
            nonEmpty(current['entries']) || nonEmpty(current['transactions']);
        if (hasData) {
          snap = current;
          if (prefs != null) {
            await prefs.setBool(migratedKey(acc), true);
            if (prefs.getString(legacyOwnerKey) == null) {
              await prefs.setString(legacyOwnerKey, acc);
            }
          }
        }
      }
      if (snap != null) {
        // already resolved above
      } else if (!migrated) {
        final owner = prefs?.getString(legacyOwnerKey);
        final PwoLedger source;
        if (owner == null || owner == acc) {
          source = PwoLedger.decode(prefs?.getString(prefsKey))..applySeed();
          if (prefs != null) await prefs.setString(legacyOwnerKey, acc);
        } else {
          source = PwoLedger(); // default names only, no entries.
        }
        snap = await remote.import(source.toImportPayload());
        if (prefs != null) await prefs.setBool(migratedKey(acc), true);
      } else {
        if (!queue.isEmpty && queue.account == acc) {
          await queue.flush(acc, (w, key) => remote.run(w, idempotencyKey: key));
        }
        snap = await remote.fetch();
      }
      if (_account != acc) return;
      await _apply(snap);
      showingCache = false;
      lastError = null;
    } catch (e) {
      if (_account != acc) return;
      lastError = e.toString();
      showingCache = _loaded;
    } finally {
      if (_account == acc) {
        _syncing = false;
        notifyListeners();
      }
    }
  }

  Future<void> _apply(Map<String, dynamic> snap) async {
    _ledger = PwoLedger.fromServer(snap);
    _loaded = true;
    await _save();
  }

  /// Owner and data are captured before any await, so an account switch
  /// mid-save can never put this ledger under another account's key.
  Future<void> _save() async {
    final acc = _accountMode ? _account : null;
    final data = _ledger.encode();
    if (acc != null) return cache.write(acc, data);
    final prefs = await LocalPrefs.open();
    if (prefs == null) return;
    await LocalPrefs.setString(prefs, prefsKey, data);
  }

  /// Online: sent at once and its snapshot applied. Offline, or the answer
  /// never arrived: kept in this account's queue (same idempotency key) and
  /// [WriteQueuedException] thrown. Throws the server's refusal otherwise.
  Future<void> _write(String label, WriteRequest req, {String? idemKey}) async {
    final acc = _account;
    if (acc == null) throw const PwoReadOnlyException();
    if (queue.account != acc) await queue.bind(acc);
    final r = _remote;
    final key = idemKey ?? newIdempotencyKey();
    if (r != null && queue.isEmpty) {
      try {
        final snap = await r.run(req, idempotencyKey: key);
        if (_account != acc) return;
        await _apply(snap);
        lastError = null;
        showingCache = false;
        notifyListeners();
        return;
      } catch (e) {
        if (!isRetryableWriteError(e) || _account != acc) rethrow;
        await queue.add(acc, req, label, key: key);
        lastError = e.toString();
        showingCache = _loaded;
        notifyListeners();
        throw const WriteQueuedException();
      }
    }
    final w = await queue.add(acc, req, label, key: key);
    if (r != null) {
      await refresh();
      final left = queue.items.where((x) => x.key == w.key).firstOrNull;
      if (left == null) return;
      if (left.error != null) throw InvestApiException(left.error!);
    }
    throw const WriteQueuedException();
  }

  void _ensureWritable() {}

  String _who(String id) => _ledger.personById(id)?.name ?? id;

  Future<void> _local(void Function() change) async {
    _ensureWritable();
    change();
    notifyListeners();
    await _save();
  }

  /// Saves a month. [replacing] is the month being edited (its old key is
  /// cleared when the month/year changed).
  Future<void> saveMonth(PwoMonth m, {PwoMonth? replacing}) async {
    _ensureWritable();
    if (!_accountMode) {
      return _local(() {
        final keep = <PwoTx>[
          ...?_ledger.months[m.key]?.txs,
          if (replacing != null && replacing.key != m.key) ...replacing.txs,
        ];
        if (replacing != null && replacing.key != m.key) {
          _ledger.remove(replacing.year, replacing.month);
        }
        m.txs
          ..clear()
          ..addAll(keep);
        _ledger.upsert(m);
      });
    }
    if (m.amounts.isEmpty) {
      throw ArgumentError('حداقل یک برداشت‌کننده لازم است.');
    }
    await _write('PWO ماه ${m.year}/${m.month}', PwoRemote.putMonthReq(m.year, m.month, m.amounts));
    if (replacing != null && replacing.key != m.key) {
      await deleteMonth(replacing.year, replacing.month);
    }
  }

  Future<void> deleteMonth(int year, int month) async {
    _ensureWritable();
    if (!_accountMode) return _local(() => _ledger.remove(year, month));
    final m = _ledger.months[pwoMonthKey(year, month)];
    final ids = m?.entryIds.values.toList() ?? const <int>[];
    final txIds = [for (final t in m?.txs ?? const <PwoTx>[]) if (t.id != null) t.id!];
    if (ids.isEmpty && txIds.isEmpty) return isRemote ? refresh() : Future.value();
    for (final id in ids) {
      await _write('حذف ردیف PWO ماه $year/$month', PwoRemote.deleteEntryReq(id));
    }
    for (final id in txIds) {
      await _write('حذف برداشت تکی ماه $year/$month', PwoRemote.deleteTxReq(id));
    }
  }

  Future<void> setTarget(double v) async {
    _ensureWritable();
    if (!v.isFinite || v <= 0) return;
    if (!_accountMode) return _local(() => _ledger.target = v);
    if (v == _ledger.target) return;
    await _write('هدف ماهانهٔ PWO', PwoRemote.setTargetReq(v));
  }

  void _checkUnique(String name, {String? except}) {
    if (_ledger.activePeople.any((p) => p.id != except && p.name == name)) {
      throw ArgumentError('این نام تکراری است.');
    }
  }

  Future<void> setName(String id, String name) async {
    _ensureWritable();
    final s = name.trim().split(RegExp(r'\s+')).join(' ');
    final p = _ledger.personById(id);
    if (p == null || s.isEmpty || s == p.name) return;
    if (p.active) _checkUnique(s, except: id);
    if (!_accountMode) return _local(() => p.name = s);
    await _write('تغییر نام ${p.name} به $s', PwoRemote.patchWithdrawerReq(id, name: s));
  }

  Future<PwoPerson?> addPerson(String name) async {
    _ensureWritable();
    final s = name.trim().split(RegExp(r'\s+')).join(' ');
    if (s.isEmpty) return null;
    _checkUnique(s);
    if (!_accountMode) {
      late PwoPerson p;
      await _local(() => p = _ledger.addPerson(s));
      return p;
    }
    await _write('افزودن $s', PwoRemote.addWithdrawerReq(s));
    return _ledger.people.lastWhere((p) => p.name == s,
        orElse: () => _ledger.people.last);
  }

  Future<bool> removePerson(String id) async {
    _ensureWritable();
    if (!_accountMode) {
      final ok = _ledger.removePerson(id);
      if (ok) await _local(() {});
      return ok;
    }
    if (_ledger.activePeople.length <= 1) return false;
    await _write('بایگانی ${_who(id)}', PwoRemote.deleteWithdrawerReq(id));
    return true;
  }

  Future<void> restorePerson(String id) async {
    _ensureWritable();
    final p = _ledger.personById(id);
    if (p == null) return;
    _checkUnique(p.name, except: id);
    if (!_accountMode) return _local(() => p.active = true);
    await _write('بازگرداندن ${p.name}', PwoRemote.patchWithdrawerReq(id, archived: false));
  }

  int _localTxSeq = -1;

  int _nextLocalTxId() {
    var id = _localTxSeq;
    final used = {
      for (final m in _ledger.months.values)
        for (final t in m.txs) t.id
    };
    while (used.contains(id)) {
      id--;
    }
    _localTxSeq = id - 1;
    return id;
  }

  PwoMonth? _monthOfTx(int id) {
    for (final m in _ledger.months.values) {
      if (m.txs.any((t) => t.id == id)) return m;
    }
    return null;
  }

  /// Adds one withdrawal (toman) to a month; it is summed into the month.
  Future<void> addTx(int year, int month, String personId, double toman,
      {String note = '', String? idempotencyKey}) async {
    _ensureWritable();
    if (!toman.isFinite || toman <= 0) {
      throw ArgumentError('مبلغ برداشت باید بیشتر از صفر باشد.');
    }
    if (_ledger.personById(personId) == null) {
      throw ArgumentError('برداشت‌کننده پیدا نشد.');
    }
    final n = note.trim();
    if (!_accountMode) {
      return _local(() {
        _ledger.months
            .putIfAbsent(pwoMonthKey(year, month),
                () => PwoMonth(year: year, month: month))
            .txs
            .add(PwoTx(
                id: _nextLocalTxId(), personId: personId, amount: toman, note: n));
      });
    }
    await _write('برداشت تکی ${_who(personId)} ماه $year/$month', PwoRemote.addTxReq(personId, year, month, toman, n), idemKey: idempotencyKey);
  }

  Future<void> updateTx(int id, String personId, double toman,
      {String note = ''}) async {
    _ensureWritable();
    if (!toman.isFinite || toman <= 0) {
      throw ArgumentError('مبلغ برداشت باید بیشتر از صفر باشد.');
    }
    final n = note.trim();
    if (!_accountMode) {
      final m = _monthOfTx(id);
      if (m == null) throw ArgumentError('برداشت پیدا نشد.');
      return _local(() {
        final t = m.txs.firstWhere((t) => t.id == id);
        t
          ..personId = personId
          ..amount = toman
          ..note = n;
      });
    }
    await _write('ویرایش برداشت تکی ${_who(personId)}', PwoRemote.patchTxReq(id, personId, toman, n));
  }

  Future<void> deleteTx(int id) async {
    _ensureWritable();
    if (!_accountMode) {
      final m = _monthOfTx(id);
      if (m == null) return;
      return _local(() => m.txs.removeWhere((t) => t.id == id));
    }
    await _write('حذف برداشت تکی', PwoRemote.deleteTxReq(id));
  }

  @visibleForTesting
  void debugReset() {
    _cacheOnly = false;
    _ledger = PwoLedger();
    _loaded = false;
    _remote = null;
    _account = null;
    _sync = null;
    lastError = null;
    showingCache = false;
  }
}

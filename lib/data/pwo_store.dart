import 'package:flutter/foundation.dart';

import 'package:invest/data/account_cache.dart';
import 'package:invest/data/local_platform.dart';
import 'package:invest/data/pwo_remote.dart';
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
  bool get readOnly => _cacheOnly;

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
      _ledger = PwoLedger.decode(prefs?.getString(cacheKey(last)));
      _loaded = true;
      showingCache = true;
      lastError = const PwoReadOnlyException().toString();
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
    final acc = isRemote ? _account! : null;
    final data = _ledger.encode();
    if (acc != null) return cache.write(acc, data);
    final prefs = await LocalPrefs.open();
    if (prefs == null) return;
    await LocalPrefs.setString(prefs, prefsKey, data);
  }

  /// Runs a server write and applies its snapshot. Throws the server error.
  Future<void> _write(Future<Map<String, dynamic>> Function(PwoRemote r) op) async {
    _ensureWritable();
    final acc = _account;
    final snap = await op(_remote!);
    if (_account != acc) return;
    await _apply(snap);
    lastError = null;
    showingCache = false;
    notifyListeners();
  }

  void _ensureWritable() {
    if (_cacheOnly) throw const PwoReadOnlyException();
  }

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
    if (!isRemote) {
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
    await _write((r) => r.putMonth(m.year, m.month, m.amounts));
    if (replacing != null && replacing.key != m.key) {
      await deleteMonth(replacing.year, replacing.month);
    }
  }

  Future<void> deleteMonth(int year, int month) async {
    _ensureWritable();
    if (!isRemote) return _local(() => _ledger.remove(year, month));
    final m = _ledger.months[pwoMonthKey(year, month)];
    final ids = m?.entryIds.values.toList() ?? const <int>[];
    final txIds = [for (final t in m?.txs ?? const <PwoTx>[]) if (t.id != null) t.id!];
    if (ids.isEmpty && txIds.isEmpty) return _write((r) => r.fetch());
    for (final id in ids) {
      await _write((r) => r.deleteEntry(id));
    }
    for (final id in txIds) {
      await _write((r) => r.deleteTx(id));
    }
  }

  Future<void> setTarget(double v) async {
    _ensureWritable();
    if (!v.isFinite || v <= 0) return;
    if (!isRemote) return _local(() => _ledger.target = v);
    if (v == _ledger.target) return;
    await _write((r) => r.setTarget(v));
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
    if (!isRemote) return _local(() => p.name = s);
    await _write((r) => r.patchWithdrawer(id, name: s));
  }

  Future<PwoPerson?> addPerson(String name) async {
    _ensureWritable();
    final s = name.trim().split(RegExp(r'\s+')).join(' ');
    if (s.isEmpty) return null;
    _checkUnique(s);
    if (!isRemote) {
      late PwoPerson p;
      await _local(() => p = _ledger.addPerson(s));
      return p;
    }
    await _write((r) => r.addWithdrawer(s));
    return _ledger.people.lastWhere((p) => p.name == s,
        orElse: () => _ledger.people.last);
  }

  Future<bool> removePerson(String id) async {
    _ensureWritable();
    if (!isRemote) {
      final ok = _ledger.removePerson(id);
      if (ok) await _local(() {});
      return ok;
    }
    if (_ledger.activePeople.length <= 1) return false;
    await _write((r) => r.deleteWithdrawer(id));
    return true;
  }

  Future<void> restorePerson(String id) async {
    _ensureWritable();
    final p = _ledger.personById(id);
    if (p == null) return;
    _checkUnique(p.name, except: id);
    if (!isRemote) return _local(() => p.active = true);
    await _write((r) => r.patchWithdrawer(id, archived: false));
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
      {String note = ''}) async {
    _ensureWritable();
    if (!toman.isFinite || toman <= 0) {
      throw ArgumentError('مبلغ برداشت باید بیشتر از صفر باشد.');
    }
    if (_ledger.personById(personId) == null) {
      throw ArgumentError('برداشت‌کننده پیدا نشد.');
    }
    final n = note.trim();
    if (!isRemote) {
      return _local(() {
        _ledger.months
            .putIfAbsent(pwoMonthKey(year, month),
                () => PwoMonth(year: year, month: month))
            .txs
            .add(PwoTx(
                id: _nextLocalTxId(), personId: personId, amount: toman, note: n));
      });
    }
    await _write((r) => r.addTx(personId, year, month, toman, n));
  }

  Future<void> updateTx(int id, String personId, double toman,
      {String note = ''}) async {
    _ensureWritable();
    if (!toman.isFinite || toman <= 0) {
      throw ArgumentError('مبلغ برداشت باید بیشتر از صفر باشد.');
    }
    final n = note.trim();
    if (!isRemote) {
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
    await _write((r) => r.patchTx(id, personId, toman, n));
  }

  Future<void> deleteTx(int id) async {
    _ensureWritable();
    if (!isRemote) {
      final m = _monthOfTx(id);
      if (m == null) return;
      return _local(() => m.txs.removeWhere((t) => t.id == id));
    }
    await _write((r) => r.deleteTx(id));
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

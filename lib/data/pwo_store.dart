import 'package:flutter/foundation.dart';

import 'package:invest/data/local_platform.dart';
import 'package:invest/data/pwo_remote.dart';
import 'package:invest/domain/services/pwo_ledger.dart';

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
    if (_account != acc) {
      _account = acc;
      _loaded = false;
      _sync = null;
      lastError = null;
      showingCache = false;
      _ledger = PwoLedger(people: []);
      final prefs = await LocalPrefs.open();
      if (_account != acc) return;
      final raw = prefs?.getString(cacheKey(acc));
      if (raw != null) {
        _ledger = PwoLedger.decode(raw);
        _loaded = true;
      }
      notifyListeners();
    }
    await refresh();
  }

  /// Back to device-only mode (logout).
  void unbind() {
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
    final raw = prefs?.getString(prefsKey);
    if (isRemote) return;
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
      Map<String, dynamic> snap;
      if (!migrated) {
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

  Future<void> _save() async {
    final prefs = await LocalPrefs.open();
    if (prefs == null) return;
    final key = isRemote ? cacheKey(_account!) : prefsKey;
    await LocalPrefs.setString(prefs, key, _ledger.encode());
  }

  /// Runs a server write and applies its snapshot. Throws the server error.
  Future<void> _write(Future<Map<String, dynamic>> Function(PwoRemote r) op) async {
    final acc = _account;
    final snap = await op(_remote!);
    if (_account != acc) return;
    await _apply(snap);
    lastError = null;
    showingCache = false;
    notifyListeners();
  }

  Future<void> _local(void Function() change) async {
    change();
    notifyListeners();
    await _save();
  }

  /// Saves a month. [replacing] is the month being edited (its old key is
  /// cleared when the month/year changed).
  Future<void> saveMonth(PwoMonth m, {PwoMonth? replacing}) async {
    if (!isRemote) {
      return _local(() {
        if (replacing != null && replacing.key != m.key) {
          _ledger.remove(replacing.year, replacing.month);
        }
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
    if (!isRemote) return _local(() => _ledger.remove(year, month));
    final m = _ledger.months[pwoMonthKey(year, month)];
    final ids = m?.entryIds.values.toList() ?? const <int>[];
    if (ids.isEmpty) return _write((r) => r.fetch());
    for (final id in ids) {
      await _write((r) => r.deleteEntry(id));
    }
  }

  Future<void> setTarget(double v) async {
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
    final s = name.trim().split(RegExp(r'\s+')).join(' ');
    final p = _ledger.personById(id);
    if (p == null || s.isEmpty || s == p.name) return;
    if (p.active) _checkUnique(s, except: id);
    if (!isRemote) return _local(() => p.name = s);
    await _write((r) => r.patchWithdrawer(id, name: s));
  }

  Future<PwoPerson?> addPerson(String name) async {
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
    final p = _ledger.personById(id);
    if (p == null) return;
    _checkUnique(p.name, except: id);
    if (!isRemote) return _local(() => p.active = true);
    await _write((r) => r.patchWithdrawer(id, archived: false));
  }

  @visibleForTesting
  void debugReset() {
    _ledger = PwoLedger();
    _loaded = false;
    _remote = null;
    _account = null;
    _sync = null;
    lastError = null;
    showingCache = false;
  }
}

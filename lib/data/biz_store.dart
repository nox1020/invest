import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:invest/data/biz_remote.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/write_queue.dart';
import 'package:invest/data/account_cache.dart';

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
double? _dn(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

class PropertyTrade {
  PropertyTrade(this.raw);
  final Map<String, dynamic> raw;
  int get id => (raw['id'] as num).toInt();
  String get buyDate => '${raw['buy_date'] ?? ''}';
  String get sellDate => '${raw['sell_date'] ?? ''}';
  double get buyAmount => _d(raw['buy_amount']);
  double get sellAmount => _d(raw['sell_amount']);
  double? get area => _dn(raw['area']);
  String get title => '${raw['title'] ?? ''}';
  double get extraCost => _d(raw['extra_cost']);
  String get note => '${raw['note'] ?? ''}';
  int? get days => (raw['days'] as num?)?.toInt();
  double? get profit => _dn(raw['profit']);
  double? get profitPct => _dn(raw['profit_pct']);
  bool get sold => profit != null;
}

class BizMonth {
  BizMonth(this.raw);
  final Map<String, dynamic> raw;
  int get year => (raw['year'] as num).toInt();
  int get month => (raw['month'] as num).toInt();
  double get staff => _d(raw['staff']);
  double get pwo => _d(raw['pwo']);
  double get ads => _d(raw['ads']);
  double get income => _d(raw['income']);
  double get net => _d(raw['net']);
  bool get hasOps => raw['has_ops'] == true;
  bool get isEmpty => !hasOps && pwo == 0;
}

class BizSnapshot {
  BizSnapshot(this.raw);
  final Map<String, dynamic> raw;
  static final empty = BizSnapshot(const {});

  List<PropertyTrade> get trades => [
        for (final t in (raw['trades'] as List? ?? const []))
          if (t is Map) PropertyTrade(Map<String, dynamic>.from(t)),
      ];
  Map<String, dynamic> get tradesTotals =>
      Map<String, dynamic>.from(raw['trades_totals'] as Map? ?? const {});
  double get totalProfit => _d(tradesTotals['profit']);
  double get totalExtraCost => _d(tradesTotals['extra_cost']);
  int? get year => (raw['year'] as num?)?.toInt();
  List<int> get years => [
        for (final y in (raw['years'] as List? ?? const []))
          if (y is num) y.toInt(),
      ];
  List<BizMonth> get months => [
        for (final m in (raw['months'] as List? ?? const []))
          if (m is Map) BizMonth(Map<String, dynamic>.from(m)),
      ];
  Map<String, double> get monthTotals => {
        for (final e in (raw['months_totals'] as Map? ?? const {}).entries)
          '${e.key}': _d(e.value),
      };
}

class BizReadOnlyException implements Exception {
  const BizReadOnlyException();
  @override
  String toString() =>
      'اتصال به حساب وینور برقرار نیست؛ این جدول فعلاً فقط خواندنی است.';
}

/// Property trades + monthly business table. Server (`/biz`) is the only
/// source of truth; a per-account cache is shown read-only when offline.
class BizStore extends ChangeNotifier {
  BizStore._();
  static final BizStore instance = BizStore._();

  static String cacheKey(String account, int? year) =>
      'vplus_biz_cache_v1_${account}_${year ?? 'cur'}';
  static const lastAccountKey = 'vplus_biz_last_account_v1';
  static final cache = AccountCache(
      keyOf: (a, y) => cacheKey(a, y as int?), lastAccountKey: lastAccountKey);

  BizRemote? _remote;
  String? _account;
  int? _year;
  BizSnapshot _snap = BizSnapshot.empty;
  bool loaded = false;
  bool syncing = false;
  bool showingCache = false;
  String? lastError;

  /// Writes waiting to be sent for the bound account (offline queue).
  final WriteQueue queue = WriteQueue('biz');

  BizSnapshot get snap => _snap;
  bool get isRemote => _remote != null && _account != null;

  /// Offline writes are queued, so only "no account at all" is read-only.
  bool get readOnly => _account == null;
  String? get account => _account;
  int? get year => _year ?? _snap.year;

  Future<void> bindAccount(BizRemote remote, String account) async {
    final acc = account.trim();
    if (acc.isEmpty) return;
    _remote = remote;
    if (_account != acc) {
      _account = acc;
      _year = null;
      _snap = BizSnapshot.empty;
      loaded = false;
      // Previous account's error / cache banner must not carry over.
      showingCache = false;
      lastError = null;
      notifyListeners();
      await queue.bind(acc);
      await _loadCache(acc);
      if (_account != acc) return;
    }
    await refresh();
  }

  /// No server connection: show the last account's cache, read-only.
  Future<void> loadOffline() async {
    _remote = null;
    final last = await cache.lastAccount();
    if (last == null) {
      loaded = true;
      notifyListeners();
      return;
    }
    if (_account != last) {
      // Never show another account's in-memory snapshot as this one's.
      _account = last;
      _year = null;
      _snap = BizSnapshot.empty;
      loaded = false;
    }
    await queue.bind(last);
    await _loadCache(last);
    if (_account != last) return;
    _remote = null;
    showingCache = true;
    lastError = offlineQueueNote;
    loaded = true;
    notifyListeners();
  }

  @visibleForTesting
  void debugSet(BizSnapshot s) {
    _snap = s;
    loaded = true;
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() {
    _remote = null;
    _account = null;
    _year = null;
    _snap = BizSnapshot.empty;
    loaded = false;
    syncing = false;
    showingCache = false;
    lastError = null;
  }

  void unbind() {
    cache.clearLastAccount();
    queue.bind(null); // the queue stays on disk for that account
    _remote = null;
    _account = null;
    _year = null;
    _snap = BizSnapshot.empty;
    loaded = false;
    showingCache = false;
    lastError = null;
    notifyListeners();
  }

  Future<void> _loadCache(String acc) async {
    await cache.setLastAccount(acc);
    final raw = await cache.read(acc, _year);
    if (_account != acc) return;
    if (raw != null) {
      try {
        _snap = BizSnapshot(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        loaded = true;
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Applies [snap] fetched for [acc]; dropped if the account changed.
  Future<void> _apply(String acc, Map<String, dynamic> snap) async {
    if (_account != acc) return;
    final year = _year;
    _snap = BizSnapshot(snap);
    loaded = true;
    showingCache = false;
    lastError = null;
    final s = jsonEncode(snap);
    final snapYear = _snap.year;
    notifyListeners();
    await cache.write(acc, s, year);
    if (year == null || year == snapYear) await cache.write(acc, s, snapYear);
  }

  Future<void> refresh() async {
    final remote = _remote, acc = _account;
    if (remote == null || acc == null) return;
    syncing = true;
    notifyListeners();
    try {
      await _flush(remote, acc);
      final s = await remote.fetch(year: _year);
      await _apply(acc, s);
    } catch (e) {
      if (_account != acc) return;
      lastError = e.toString();
      showingCache = loaded;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> selectYear(int y) async {
    _year = y;
    final acc = _account;
    if (acc != null) {
      final raw = await cache.read(acc, y);
      if (_account != acc || _year != y) return;
      if (raw != null) {
        try {
          _snap = BizSnapshot(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        } catch (_) {}
      }
    }
    notifyListeners();
    await refresh();
  }

  /// Sends queued writes of [acc] (in order, each with its idempotency key).
  Future<void> _flush(BizRemote r, String acc) async {
    if (queue.isEmpty || queue.account != acc) return;
    await queue.flush(acc, (w, key) => r.run(w, idempotencyKey: key));
  }

  /// Online: sent at once. Offline, or the answer never arrived: kept in the
  /// account's queue (same idempotency key) and [WriteQueuedException] thrown.
  Future<void> _write(String label, WriteRequest req) async {
    final r = _remote, acc = _account;
    if (acc == null) throw const BizReadOnlyException();
    if (queue.account != acc) await queue.bind(acc);
    if (r != null && queue.isEmpty) {
      final key = newIdempotencyKey();
      try {
        await _apply(acc, await r.run(req, idempotencyKey: key));
        return;
      } catch (e) {
        if (!isRetryableWriteError(e) || _account != acc) rethrow;
        await queue.add(acc, req, label, key: key);
        lastError = e.toString();
        showingCache = loaded;
        notifyListeners();
        throw const WriteQueuedException();
      }
    }
    final w = await queue.add(acc, req, label);
    if (r != null) {
      await refresh();
      final left = queue.items.where((x) => x.key == w.key).firstOrNull;
      if (left == null) return;
      if (left.error != null) throw InvestApiException(left.error!);
    }
    throw const WriteQueuedException();
  }

  /// True when nothing is stored yet (import button is offered only then).
  bool get isEmpty =>
      loaded &&
      _snap.raw.isNotEmpty &&
      _snap.trades.isEmpty &&
      !_snap.months.any((m) => m.hasOps);

  /// Parses pasted sheet JSON `{"trades": [...], "months": [...]}` and sends
  /// it to the guarded import. Returns rows written (0 = account had data).
  Future<int> importSheet(String text) async {
    final r = _remote, acc = _account;
    if (r == null || acc == null) throw const BizReadOnlyException();
    Object? data;
    try {
      data = jsonDecode(text.trim());
    } catch (_) {
      throw const FormatException('متن واردشده JSON معتبر نیست.');
    }
    if (data is! Map ||
        (data['trades'] is! List && data['months'] is! List)) {
      throw const FormatException('متن باید شامل trades یا months باشد.');
    }
    final res = await r.import(Map<String, dynamic>.from(data));
    final snap = res['biz'];
    if (snap is Map) await _apply(acc, Map<String, dynamic>.from(snap));
    if (res['already_has_data'] == true) return 0;
    return (res['written'] as num?)?.toInt() ?? 0;
  }

  static String _t(Map<String, dynamic> b) {
    final s = '${b['title'] ?? ''}'.trim();
    return s.isEmpty ? '${b['buy_date'] ?? ''}' : s;
  }

  Future<void> addTrade(Map<String, dynamic> body) => _write(
      'ثبت معامله «${_t(body)}»', BizRemote.addTradeReq(body, year: _year));
  Future<void> updateTrade(int id, Map<String, dynamic> body) => _write(
      'ویرایش معامله «${_t(body)}»',
      BizRemote.updateTradeReq(id, body, year: _year));
  Future<void> deleteTrade(int id) {
    final t = _snap.trades.where((x) => x.id == id).firstOrNull;
    return _write('حذف معامله «${t == null ? id : _t(t.raw)}»',
        BizRemote.deleteTradeReq(id, year: _year));
  }

  Future<void> saveMonth(int y, int m, Map<String, dynamic> body) =>
      _write('جدول ماهانه $y/$m', BizRemote.putMonthReq(y, m, body));
  Future<void> clearMonth(int y, int m) =>
      _write('پاک کردن ماه $y/$m', BizRemote.deleteMonthReq(y, m));
}

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:invest/data/biz_remote.dart';
import 'package:invest/data/local_platform.dart';

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

  BizRemote? _remote;
  String? _account;
  int? _year;
  BizSnapshot _snap = BizSnapshot.empty;
  bool loaded = false;
  bool syncing = false;
  bool showingCache = false;
  String? lastError;

  BizSnapshot get snap => _snap;
  bool get isRemote => _remote != null && _account != null;
  bool get readOnly => !isRemote || showingCache;
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
      await _loadCache(acc);
    }
    await refresh();
  }

  /// No server connection: show the last account's cache, read-only.
  Future<void> loadOffline() async {
    _remote = null;
    final prefs = await LocalPrefs.open();
    final last = prefs?.getString(lastAccountKey);
    if (last == null || last.isEmpty) {
      loaded = true;
      notifyListeners();
      return;
    }
    _account = last;
    await _loadCache(last);
    _remote = null;
    showingCache = true;
    lastError = const BizReadOnlyException().toString();
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
    LocalPrefs.open().then((p) async {
      await p?.remove(lastAccountKey);
    });
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
    final prefs = await LocalPrefs.open();
    if (prefs != null) await prefs.setString(lastAccountKey, acc);
    final raw = prefs?.getString(cacheKey(acc, _year));
    if (raw != null) {
      try {
        _snap = BizSnapshot(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        loaded = true;
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _apply(Map<String, dynamic> snap) async {
    _snap = BizSnapshot(snap);
    loaded = true;
    showingCache = false;
    lastError = null;
    final acc = _account;
    if (acc != null) {
      final prefs = await LocalPrefs.open();
      final s = jsonEncode(snap);
      await prefs?.setString(cacheKey(acc, _year), s);
      if (_year == null || _year == _snap.year) {
        await prefs?.setString(cacheKey(acc, _snap.year), s);
      }
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    final remote = _remote, acc = _account;
    if (remote == null || acc == null) return;
    syncing = true;
    notifyListeners();
    try {
      final s = await remote.fetch(year: _year);
      if (_account != acc) return;
      await _apply(s);
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
      final prefs = await LocalPrefs.open();
      final raw = prefs?.getString(cacheKey(acc, y));
      if (raw != null) {
        try {
          _snap = BizSnapshot(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        } catch (_) {}
      }
    }
    notifyListeners();
    await refresh();
  }

  Future<void> _write(
      Future<Map<String, dynamic>> Function(BizRemote r) op) async {
    final r = _remote;
    if (r == null || _account == null) throw const BizReadOnlyException();
    await _apply(await op(r));
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
    final r = _remote;
    if (r == null || _account == null) throw const BizReadOnlyException();
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
    if (snap is Map) await _apply(Map<String, dynamic>.from(snap));
    if (res['already_has_data'] == true) return 0;
    return (res['written'] as num?)?.toInt() ?? 0;
  }

  Future<void> addTrade(Map<String, dynamic> body) =>
      _write((r) => r.addTrade(body, year: _year));
  Future<void> updateTrade(int id, Map<String, dynamic> body) =>
      _write((r) => r.updateTrade(id, body, year: _year));
  Future<void> deleteTrade(int id) =>
      _write((r) => r.deleteTrade(id, year: _year));
  Future<void> saveMonth(int y, int m, Map<String, dynamic> body) =>
      _write((r) => r.putMonth(y, m, body));
  Future<void> clearMonth(int y, int m) =>
      _write((r) => r.deleteMonth(y, m));
}

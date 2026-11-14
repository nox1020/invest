import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:invest/data/biz_remote.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/optimistic.dart';
import 'package:invest/data/write_queue.dart';
import 'package:invest/data/account_cache.dart';
import 'package:invest/domain/utils/biz_dates.dart';

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

  /// Sold = has a sell date and a sell amount (same rule as the server).
  /// Computed here, so an older server's `profit` (without extra cost) or a
  /// queued edit never disagrees with the monthly table.
  bool get sold => sellDate.trim().isNotEmpty && sellAmount > 0;

  /// Sell − buy, before extra costs.
  double? get grossProfit => sold ? sellAmount - buyAmount : null;

  /// Net deal profit: sell − buy − extra cost («هزینه جانبی»).
  double? get profit => sold ? sellAmount - buyAmount - extraCost : null;

  /// Net profit as a percent of the SELL amount (the sheet's convention).
  double? get profitPct {
    final p = profit;
    return p != null && sellAmount > 0 ? p / sellAmount * 100 : null;
  }

  /// Jalali 'YYYY/MM' of the buy / sell date (null when empty or invalid).
  String? get buyMonth => bizMonthKey(buyDate);
  String? get sellMonth => sold ? bizMonthKey(sellDate) : null;
}

/// Income that equals the month's sold-deal profit (net or gross, within
/// 1,000 toman) was typed in by hand from those deals (the old «پر کردن
/// درآمد»): it is not counted again on top of the automatic deal profit.
/// Tolerance: 1,000 toman, but never more than 0.5% of the deal profit.
bool incomeDuplicatesTrades(double income, double tradeProfit, double tradeGross) {
  if (income == 0) return false;
  bool near(double ref) {
    if (ref == 0) return false;
    final tol = ref.abs() * 0.005 < 1000 ? ref.abs() * 0.005 : 1000.0;
    return (income - ref).abs() <= tol;
  }
  return near(tradeProfit) || near(tradeGross);
}

class BizMonth {
  BizMonth(this.raw);
  final Map<String, dynamic> raw;
  int get year => (raw['year'] as num).toInt();
  int get month => (raw['month'] as num).toInt();
  double get staff => _d(raw['staff']);
  double get pwo => _d(raw['pwo']);
  double get ads => _d(raw['ads']);

  /// Office income as stored (typed by the user).
  double get income => _d(raw['income']);

  /// Income counted in net: 0 when it only repeats the deal profit.
  double get incomeEffective =>
      raw.containsKey('income_effective') ? _d(raw['income_effective']) : income;
  bool get incomeDupTrades => raw['income_dup_trades'] == true;

  /// Net profit of deals SOLD in this month (added to net automatically).
  double get tradeProfit => _d(raw['trade_profit']);
  double get tradeGross => _d(raw['trade_gross']);
  int get soldCount => (raw['sold_count'] as num?)?.toInt() ?? 0;
  double get soldAmount => _d(raw['sold_amount']);

  /// Deals BOUGHT in this month (count and total buy amount).
  int get boughtCount => (raw['bought_count'] as num?)?.toInt() ?? 0;
  double get boughtAmount => _d(raw['bought_amount']);

  /// income(effective) − staff − PWO − ads + deal profit.
  double get net => _d(raw['net']);
  bool get hasOps => raw['has_ops'] == true;
  bool get hasDeals => soldCount > 0 || boughtCount > 0;
  String get note => '${raw['note'] ?? ''}';
  bool get isEmpty => !hasOps && pwo == 0 && !hasDeals;
}

/// Adds the deal columns to month rows and recomputes net, so an older
/// server (net without deals) and the offline overlay show the same numbers
/// as the current server.
Map<String, dynamic> deriveBizMonth(Map<String, dynamic> m, Iterable<PropertyTrade> trades) {
  final out = Map<String, dynamic>.from(m);
  final y = (m['year'] as num?)?.toInt(), mo = (m['month'] as num?)?.toInt();
  if (y == null || mo == null) return out;
  final key = bizMonthKeyOf(y, mo);
  var tp = 0.0, tg = 0.0, sAmt = 0.0, bAmt = 0.0;
  var sN = 0, bN = 0;
  for (final t in trades) {
    if (t.sellMonth == key) {
      sN++;
      tp += t.profit!;
      tg += t.grossProfit!;
      sAmt += t.sellAmount;
    }
    if (t.buyMonth == key) {
      bN++;
      bAmt += t.buyAmount;
    }
  }
  final income = _d(m['income']);
  final dup = incomeDuplicatesTrades(income, tp, tg);
  final eff = dup ? 0.0 : income;
  out
    ..['trade_profit'] = tp
    ..['trade_gross'] = tg
    ..['sold_count'] = sN
    ..['sold_amount'] = sAmt
    ..['bought_count'] = bN
    ..['bought_amount'] = bAmt
    ..['income_dup_trades'] = dup
    ..['income_effective'] = eff
    ..['net'] = eff - _d(m['staff']) - _d(m['pwo']) - _d(m['ads']) + tp;
  return out;
}

const bizMonthTotalKeys = [
  'staff', 'pwo', 'ads', 'income', 'income_effective', 'trade_profit', 'net',
];

class BizSnapshot {
  BizSnapshot(this.raw);
  final Map<String, dynamic> raw;
  static final empty = BizSnapshot(const {});

  late final List<PropertyTrade> trades = [
    for (final t in (raw['trades'] as List? ?? const []))
      if (t is Map) PropertyTrade(Map<String, dynamic>.from(t)),
  ];
  Map<String, dynamic> get tradesTotals =>
      Map<String, dynamic>.from(raw['trades_totals'] as Map? ?? const {});

  /// Net profit of all sold deals (computed from the trades).
  double get totalProfit =>
      trades.where((t) => t.sold).fold<double>(0, (a, t) => a + t.profit!);
  double get totalExtraCost => trades.fold<double>(0, (a, t) => a + t.extraCost);
  int? get year => (raw['year'] as num?)?.toInt();
  List<int> get years => [
        for (final y in (raw['years'] as List? ?? const []))
          if (y is num) y.toInt(),
      ];
  late final List<BizMonth> months = [
    for (final m in (raw['months'] as List? ?? const []))
      if (m is Map) BizMonth(deriveBizMonth(Map<String, dynamic>.from(m), trades)),
  ];
  late final Map<String, double> monthTotals = months.isEmpty
      ? {
          for (final e in (raw['months_totals'] as Map? ?? const {}).entries)
            '${e.key}': _d(e.value),
        }
      : {
          for (final k in bizMonthTotalKeys)
            k: months.fold<double>(0, (a, m) => a + _d(m.raw[k])),
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
  BizStore._() {
    queue.addListener(notifyListeners);
  }
  static final BizStore instance = BizStore._();

  /// The phone's Jalali year; replaceable in tests.
  @visibleForTesting
  static int Function() yearNow = currentJalaliYear;

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

  /// Server snapshot with queued (not yet sent) writes applied on top.
  BizSnapshot get snap {
    if (queue.isEmpty || queue.account != _account) return _snap;
    final memo = _view;
    if (memo != null && memo.$1 == queue.revision && identical(memo.$2, _snap)) {
      return memo.$3;
    }
    final v = BizSnapshot(overlay(_snap.raw, queue.items, applyBiz));
    _view = (queue.revision, _snap, v);
    return v;
  }

  BizSnapshot get serverSnap => _snap;
  (int, BizSnapshot, BizSnapshot)? _view;
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
  void debugSet(BizSnapshot s, {String? account}) {
    _snap = s;
    _account = account;
    loaded = true;
    notifyListeners();
  }

  int _refreshSeq = 0;

  @visibleForTesting
  void debugReset() {
    _refreshSeq++;
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
    _refreshSeq++;
    cache.clearLastAccount();
    queue.bind(null); // the queue stays on disk for that account
    _remote = null;
    _account = null;
    _year = null;
    _snap = BizSnapshot.empty;
    loaded = false;
    syncing = false;
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
    final seq = ++_refreshSeq;
    final reqYear = _year;
    syncing = true;
    notifyListeners();
    try {
      await _flush(remote, acc);
      if (_account != acc || _year != reqYear || _refreshSeq != seq) return;
      // Always name the year: the server's clock/timezone must not decide
      // which Jalali year is «امسال» (around Nowruz they can differ).
      final s = await remote.fetch(year: reqYear ?? yearNow());
      if (_account != acc || _year != reqYear || _refreshSeq != seq) return;
      await _apply(acc, s);
    } catch (e) {
      if (_account != acc || _year != reqYear || _refreshSeq != seq) return;
      lastError = e.toString();
      showingCache = loaded;
    } finally {
      if (_refreshSeq == seq) {
        syncing = false;
        notifyListeners();
      }
    }
  }

  Future<void> selectYear(int y) async {
    final seq = ++_refreshSeq;
    _year = y;
    final acc = _account;
    if (acc != null) {
      final raw = await cache.read(acc, y);
      if (_account != acc || _year != y || _refreshSeq != seq) return;
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
    await queue.flush(acc, (w, key) => r.run(w, idempotencyKey: key),
        before: _snap.raw);
  }

  /// Online: sent at once. Offline, or the answer never arrived: kept in the
  /// account's queue (same idempotency key) and [WriteQueuedException] thrown.
  Future<void> _write(String label, WriteRequest req) async {
    final r = _remote, acc = _account;
    if (acc == null) throw const BizReadOnlyException();
    if (queue.account != acc) await queue.bind(acc);
    final meta = createMeta(req);
    if (r != null && queue.isEmpty && !syncOffline.value) {
      final key = newIdempotencyKey();
      try {
        await _apply(acc, await r.run(req, idempotencyKey: key));
        return;
      } catch (e) {
        if (!isRetryableWriteError(e) || _account != acc) rethrow;
        await queue.add(acc, req, label,
            key: key, tempId: meta.tempId, collection: meta.collection);
        lastError = e.toString();
        showingCache = loaded;
        notifyListeners();
        throw const WriteQueuedException();
      }
    }
    final w = await queue.add(acc, req, label,
        tempId: meta.tempId, collection: meta.collection);
    if (r != null && !syncOffline.value) {
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

  /// Year sent with trade writes (the snapshot that comes back).
  int get _reqYear => _year ?? _snap.year ?? yearNow();

  /// Canonical dates before a trade is sent or queued, so the queued view,
  /// the monthly table and the annual report all read the same month.
  static Map<String, dynamic> normalizeTradeBody(Map<String, dynamic> body) => {
        ...body,
        if (body.containsKey('buy_date')) 'buy_date': normalizeBizDate(body['buy_date']),
        if (body.containsKey('sell_date')) 'sell_date': normalizeBizDate(body['sell_date']),
      };

  /// Queued writes the server refused (kept until fixed or discarded).
  List<QueuedWrite> get rejectedWrites => queue.account == _account
      ? [for (final w in queue.items) if (w.error != null) w]
      : const [];

  /// Years whose monthly rows could not be fetched by the last
  /// [monthsAllYears] (an export then misses them; the UI says so).
  List<int> lastFailedYears = const [];

  static String _t(Map<String, dynamic> b) {
    final s = '${b['title'] ?? ''}'.trim();
    return s.isEmpty ? '${b['buy_date'] ?? ''}' : s;
  }

  Future<void> addTrade(Map<String, dynamic> body) {
    final b = normalizeTradeBody(body);
    return _write('ثبت معامله «${_t(b)}»', BizRemote.addTradeReq(b, year: _reqYear));
  }

  Future<void> updateTrade(int id, Map<String, dynamic> body) {
    final b = normalizeTradeBody(body);
    return _write('ویرایش معامله «${_t(b)}»',
        BizRemote.updateTradeReq(id, b, year: _reqYear));
  }
  Future<void> deleteTrade(int id) {
    final t = _snap.trades.where((x) => x.id == id).firstOrNull;
    return _write('حذف معامله «${t == null ? id : _t(t.raw)}»',
        BizRemote.deleteTradeReq(id, year: _reqYear));
  }

  /// Monthly rows of every year the server knows (read-only fetches; the
  /// selected year is not changed). Falls back to the loaded year offline.
  Future<List<BizMonth>> monthsAllYears() async {
    final out = <int, List<BizMonth>>{};
    final failed = <int>[];
    final cur = _snap.year;
    if (cur != null) out[cur] = [for (final m in _snap.months) if (m.year == cur) m];
    final r = _remote;
    if (r != null) {
      for (final y in _snap.years) {
        if (out.containsKey(y)) continue;
        try {
          final raw = await r.fetch(year: y).timeout(const Duration(seconds: 8));
          out[y] = [for (final m in BizSnapshot(raw).months) if (m.year == y) m];
        } catch (_) {
          failed.add(y);
        }
      }
    }
    lastFailedYears = failed;
    return [for (final y in out.keys.toList()..sort()) ...out[y]!];
  }

  /// Adds an advertising cost to month [m] of year [y] (adds to the month's
  /// «تبلیغات» total and logs one line in its note). Only `ads` and `note`
  /// are sent; staff/income stay as they are on the server.
  Future<void> addAds(int y, int m, double amount, {required String date, String note = ''}) async {
    if (amount <= 0) throw ArgumentError('amount');
    if (_snap.year != y) await selectYear(y);
    if (_snap.year != y) {
      throw StateError('جدول ماهانهٔ سال $y بارگیری نشد؛ دوباره تلاش کنید.');
    }
    // Overlaid view: an earlier ads entry still queued offline is kept.
    final cur = snap.months.where((x) => x.year == y && x.month == m).firstOrNull;
    final ads = (cur?.ads ?? 0) + amount;
    final n = note.trim().replaceAll('\n', ' ');
    final line = 'تبلیغات $date: ${amount.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}${n.isEmpty ? '' : ' — $n'}';
    final old = cur?.note ?? '';
    var newNote = old.isEmpty ? line : '$old\n$line';
    // Server keeps 500 chars: never cut the existing note, skip the log line.
    if (newNote.length > 500) newNote = old;
    await _write('تبلیغات $y/$m', BizRemote.putMonthReq(y, m, {'ads': ads, 'note': newNote}));
  }

  Future<void> saveMonth(int y, int m, Map<String, dynamic> body) =>
      _write('جدول ماهانه $y/$m', BizRemote.putMonthReq(y, m, body));
  Future<void> clearMonth(int y, int m) =>
      _write('پاک کردن ماه $y/$m', BizRemote.deleteMonthReq(y, m));
}

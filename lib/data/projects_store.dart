import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:invest/data/account_cache.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/projects_remote.dart';
import 'package:invest/data/optimistic.dart';
import 'package:invest/data/write_queue.dart';

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
double? _dn(Object? v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// Effective state of a contracting project.
enum ProjectStatus { pipeline, active, finished }

ProjectStatus projectStatusOf(String raw) => switch (raw) {
      'finished' => ProjectStatus.finished,
      'active' => ProjectStatus.active,
      _ => ProjectStatus.pipeline,
    };

String projectStatusLabel(ProjectStatus s) => switch (s) {
      ProjectStatus.pipeline => 'در صف',
      ProjectStatus.active => 'در جریان',
      ProjectStatus.finished => 'تمام‌شده',
    };

/// One row of the «پیمانکاری» sheet.
class Project {
  Project(this.raw);
  final Map<String, dynamic> raw;
  int get id => (raw['id'] as num).toInt();
  String get title => '${raw['title'] ?? ''}';
  String get workType => '${raw['work_type'] ?? ''}';
  String get description =>
      workType.isEmpty ? title : '$title - $workType';
  String get startDate => '${raw['start_date'] ?? ''}';
  String get endDate => '${raw['end_date'] ?? ''}';
  double get contract => _d(raw['contract_amount']);
  double get cost => _d(raw['cost']);

  /// قرارداد − هزینه; null when there is no contract amount yet.
  double? get profit => _dn(raw['profit']);

  /// سود ÷ مبلغ قرارداد (as in the sheet).
  double? get profitPct => _dn(raw['profit_pct']);
  ProjectStatus get status => projectStatusOf('${raw['status'] ?? ''}');
  String get statusMode => '${raw['status_mode'] ?? 'auto'}';
  String get note => '${raw['note'] ?? ''}';
  int? get days => (raw['days'] as num?)?.toInt();
  bool get archived => raw['archived'] == true;

  /// 'YYYY/MM' the project belongs to: end month when finished, else start.
  String? get monthKey {
    final d = status == ProjectStatus.finished && endDate.isNotEmpty
        ? endDate
        : startDate;
    return d.length >= 7 ? d.substring(0, 7) : null;
  }

  int? get year => int.tryParse((monthKey ?? '').split('/').first);
}

/// Totals over a set of projects. Archived rows are left out.
class ProjectTotals {
  const ProjectTotals({
    this.realized = 0,
    this.expected = 0,
    this.finishedCount = 0,
    this.activeCount = 0,
    this.pipelineCount = 0,
    this.contract = 0,
    this.cost = 0,
  });

  /// Profit of finished projects (تحقق‌یافته).
  final double realized;

  /// Contract − cost of projects still running (پیش‌بینی، تحقق‌نیافته).
  final double expected;
  final int finishedCount;
  final int activeCount;
  final int pipelineCount;
  final double contract;
  final double cost;

  /// Same as the sheet's top cell: every row with an amount.
  double get sheetProfit => realized + expected;
  int get count => finishedCount + activeCount + pipelineCount;

  static ProjectTotals of(Iterable<Project> rows) {
    var realized = 0.0, expected = 0.0, contract = 0.0, cost = 0.0;
    var f = 0, a = 0, p = 0;
    for (final r in rows) {
      if (r.archived) continue;
      switch (r.status) {
        case ProjectStatus.finished:
          f++;
          realized += r.profit ?? 0;
        case ProjectStatus.active:
          a++;
          expected += r.profit ?? 0;
        case ProjectStatus.pipeline:
          p++;
      }
      contract += r.contract;
      cost += r.cost;
    }
    return ProjectTotals(
      realized: realized,
      expected: expected,
      finishedCount: f,
      activeCount: a,
      pipelineCount: p,
      contract: contract,
      cost: cost,
    );
  }
}

class ProjectsSnapshot {
  ProjectsSnapshot(this.raw);
  final Map<String, dynamic> raw;
  static final empty = ProjectsSnapshot(const {});

  List<Project> get items => [
        for (final t in (raw['items'] as List? ?? const []))
          if (t is Map) Project(Map<String, dynamic>.from(t)),
      ];
  ProjectTotals get totals => ProjectTotals.of(items);
  int get archivedCount => items.where((p) => p.archived).length;
  bool get hasData => items.isNotEmpty;
}

class ProjectsReadOnlyException implements Exception {
  const ProjectsReadOnlyException();
  @override
  String toString() =>
      'اتصال به حساب وینور برقرار نیست؛ پروژه‌ها فعلاً فقط خواندنی است.';
}

/// Parses pasted sheet JSON. Accepts `{"projects": [...]}` or a bare list.
List<Map<String, dynamic>> parseProjectsSheet(String text) {
  Object? data;
  try {
    data = jsonDecode(text.trim());
  } catch (_) {
    throw const FormatException('متن واردشده JSON معتبر نیست.');
  }
  final rows = data is Map ? data['projects'] : data;
  if (rows is! List) {
    throw const FormatException('متن باید شامل projects باشد.');
  }
  return [
    for (final r in rows)
      if (r is Map) Map<String, dynamic>.from(r),
  ];
}

/// Contracting projects. The server (`/projects`) is the source of truth; a
/// per-account cache is shown offline and writes wait in the account queue.
class ProjectsStore extends ChangeNotifier {
  ProjectsStore._() {
    queue.addListener(notifyListeners);
  }
  static final ProjectsStore instance = ProjectsStore._();

  static String cacheKey(String account) => 'vplus_projects_cache_v1_$account';
  static const lastAccountKey = 'vplus_projects_last_account_v1';
  static final cache = AccountCache(
      keyOf: (a, _) => cacheKey(a), lastAccountKey: lastAccountKey);

  ProjectsRemote? _remote;
  String? _account;
  ProjectsSnapshot _snap = ProjectsSnapshot.empty;
  bool loaded = false;
  bool syncing = false;
  bool showingCache = false;
  String? lastError;

  final WriteQueue queue = WriteQueue('projects');

  /// Server snapshot with queued (not yet sent) writes applied on top.
  ProjectsSnapshot get snap {
    if (queue.isEmpty || queue.account != _account) return _snap;
    final memo = _view;
    if (memo != null && memo.$1 == queue.revision && identical(memo.$2, _snap)) {
      return memo.$3;
    }
    final v = ProjectsSnapshot(overlay(_snap.raw, queue.items, applyProjects));
    _view = (queue.revision, _snap, v);
    return v;
  }

  ProjectsSnapshot get serverSnap => _snap;
  (int, ProjectsSnapshot, ProjectsSnapshot)? _view;
  bool get isRemote => _remote != null && _account != null;
  bool get readOnly => _account == null;
  String? get account => _account;

  Future<void> bindAccount(ProjectsRemote remote, String account) async {
    final acc = account.trim();
    if (acc.isEmpty) return;
    _remote = remote;
    if (_account != acc) {
      _account = acc;
      _snap = ProjectsSnapshot.empty;
      loaded = false;
      showingCache = false;
      lastError = null;
      notifyListeners();
      await queue.bind(acc);
      await _loadCache(acc);
      if (_account != acc) return;
    }
    await refresh();
  }

  Future<void> loadOffline() async {
    _remote = null;
    final last = await cache.lastAccount();
    if (last == null) {
      loaded = true;
      notifyListeners();
      return;
    }
    if (_account != last) {
      _account = last;
      _snap = ProjectsSnapshot.empty;
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
  void debugSet(ProjectsSnapshot s, {String? account}) {
    _snap = s;
    _account = account;
    loaded = true;
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() {
    _remote = null;
    _account = null;
    _snap = ProjectsSnapshot.empty;
    loaded = false;
    syncing = false;
    showingCache = false;
    lastError = null;
  }

  void unbind() {
    cache.clearLastAccount();
    queue.bind(null);
    _remote = null;
    _account = null;
    _snap = ProjectsSnapshot.empty;
    loaded = false;
    showingCache = false;
    lastError = null;
    notifyListeners();
  }

  Future<void> _loadCache(String acc) async {
    await cache.setLastAccount(acc);
    final raw = await cache.read(acc, null);
    if (_account != acc) return;
    if (raw != null) {
      try {
        _snap = ProjectsSnapshot(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
        loaded = true;
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _apply(String acc, Map<String, dynamic> snap) async {
    if (_account != acc) return;
    _snap = ProjectsSnapshot(snap);
    loaded = true;
    showingCache = false;
    lastError = null;
    notifyListeners();
    await cache.write(acc, jsonEncode(snap), null);
  }

  Future<void> refresh() async {
    final remote = _remote, acc = _account;
    if (remote == null || acc == null) return;
    syncing = true;
    notifyListeners();
    try {
      if (!queue.isEmpty && queue.account == acc) {
        await queue.flush(acc, (w, key) => remote.run(w, idempotencyKey: key),
            before: _snap.raw);
      }
      await _apply(acc, await remote.fetch());
    } catch (e) {
      if (_account != acc) return;
      lastError = e.toString();
      showingCache = loaded;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// Online: sent at once. Offline, or the answer never arrived: kept in the
  /// account's queue (same idempotency key) and [WriteQueuedException] thrown.
  Future<void> _write(String label, WriteRequest req) async {
    final r = _remote, acc = _account;
    if (acc == null) throw const ProjectsReadOnlyException();
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

  static String _t(Map<String, dynamic> b) {
    final s = '${b['title'] ?? b['description'] ?? ''}'.trim();
    return s.isEmpty ? 'پروژه' : s;
  }

  Future<void> add(Map<String, dynamic> body) =>
      _write('ثبت پروژه «${_t(body)}»', ProjectsRemote.addReq(body));
  Future<void> update(int id, Map<String, dynamic> body) =>
      _write('ویرایش پروژه «${_t(body)}»', ProjectsRemote.updateReq(id, body));
  Future<void> setArchived(Project p, bool archived) => _write(
      archived ? 'بایگانی پروژه «${p.title}»' : 'بازگردانی پروژه «${p.title}»',
      ProjectsRemote.updateReq(p.id, {'archived': archived}));
  Future<void> delete(Project p) =>
      _write('حذف پروژه «${p.title}»', ProjectsRemote.deleteReq(p.id));

  /// Sends pasted sheet rows to the append-only import.
  /// Returns (written, skipped).
  Future<(int, int)> importSheet(String text) async {
    final rows = parseProjectsSheet(text);
    return importRows(rows);
  }

  Future<(int, int)> importRows(List<Map<String, dynamic>> rows) async {
    final r = _remote, acc = _account;
    if (r == null || acc == null) throw const ProjectsReadOnlyException();
    final res = await r.import({'projects': rows});
    final snap = res['projects'];
    if (snap is Map) await _apply(acc, Map<String, dynamic>.from(snap));
    return (
      (res['written'] as num?)?.toInt() ?? 0,
      (res['skipped'] as num?)?.toInt() ?? 0,
    );
  }
}

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:invest/data/account_cache.dart';
import 'package:invest/data/invest_api_client.dart';

/// One server write, described so it can be sent later.
class WriteRequest {
  const WriteRequest(this.method, this.path, [this.body]);
  final String method;
  final String path;
  final Map<String, dynamic>? body;
}

/// A write made while offline (or whose answer never arrived), waiting to be
/// sent for exactly one account. [key] is the `Idempotency-Key`: the server
/// runs it at most once, so a retry after a lost answer never duplicates.
class QueuedWrite {
  QueuedWrite({
    required this.key,
    required this.account,
    required this.request,
    required this.label,
    required this.createdAt,
    this.error,
    this.tempId,
    this.collection,
    this.attempts = 0,
  });

  final String key;
  final String account;
  final WriteRequest request;
  final String label;
  final String createdAt;

  /// Server refused it (e.g. validation). Kept until the user discards it.
  String? error;

  /// For a create: the temporary (negative) id the optimistic view gives
  /// the new row, and the snapshot list ([collection]) it lands in. After the
  /// create is sent, the real id is found by diffing that list and every
  /// later queued write that used [tempId] is rewritten to it.
  final int? tempId;
  final String? collection;

  /// Failed send attempts (network); drives the retry backoff.
  int attempts;

  Map<String, dynamic> toJson() => {
        'key': key,
        'account': account,
        'method': request.method,
        'path': request.path,
        if (request.body != null) 'body': request.body,
        'label': label,
        'created_at': createdAt,
        if (error != null) 'error': error,
        if (tempId != null) 'temp_id': tempId,
        if (collection != null) 'collection': collection,
        if (attempts > 0) 'attempts': attempts,
      };

  static QueuedWrite? fromJson(Object? j) {
    if (j is! Map) return null;
    final key = j['key'], acc = j['account'], m = j['method'], p = j['path'];
    if (key is! String || acc is! String || m is! String || p is! String) {
      return null;
    }
    final b = j['body'];
    return QueuedWrite(
      key: key,
      account: acc,
      request: WriteRequest(m, p, b is Map ? Map<String, dynamic>.from(b) : null),
      label: '${j['label'] ?? ''}',
      createdAt: '${j['created_at'] ?? ''}',
      error: j['error'] is String ? j['error'] as String : null,
      tempId: (j['temp_id'] as num?)?.toInt(),
      collection: j['collection'] is String ? j['collection'] as String : null,
      attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// True for failures where the request may not have reached the server or
/// the server is temporarily down: safe to retry with the same key.
bool isRetryableWriteError(Object e) {
  if (e is! InvestApiException) return false;
  final s = e.statusCode;
  // 401: session expired; kept for this same account after sign-in.
  return s == null || e.errorCode == 'network_error' || s >= 500 || s == 408 || s == 401;
}

String newIdempotencyKey() {
  final r = Random.secure();
  return 'q-${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

/// Per-account persistent queue for one store (PWO or ملک و دفتر).
class WriteQueue extends ChangeNotifier {
  WriteQueue(this.name)
      : _cache = AccountCache(keyOf: (a, _) => 'vplus_write_queue_v1_${name}_$a');

  final String name;
  final AccountCache _cache;
  String? _account;
  List<QueuedWrite> _items = [];
  bool flushing = false;

  /// Bumped on every change (memo key for optimistic views).
  int revision = 0;

  @override
  void notifyListeners() {
    revision++;
    super.notifyListeners();
  }

  String? get account => _account;
  List<QueuedWrite> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  /// Shows only [account]'s queue. Other accounts' queues stay on disk.
  Future<void> bind(String? account) async {
    final acc = AccountCache.norm(account);
    if (acc == _account) return;
    _account = acc.isEmpty ? null : acc;
    _items = [];
    notifyListeners();
    if (_account == null) return;
    final raw = await _cache.read(acc);
    if (_account != acc) return;
    try {
      final l = raw == null ? const [] : jsonDecode(raw) as List;
      _items = [
        for (final e in l)
          if (QueuedWrite.fromJson(e) case final w? when w.account == acc) w,
      ];
    } catch (_) {
      _items = [];
    }
    notifyListeners();
  }

  Future<void> _persist(String acc) =>
      _cache.write(acc, jsonEncode([for (final w in _items) w.toJson()]));

  Future<QueuedWrite> add(String account, WriteRequest req, String label,
      {String? key, int? tempId, String? collection}) async {
    final acc = AccountCache.norm(account);
    if (acc.isEmpty || acc != _account) {
      throw StateError('write queue is bound to another account');
    }
    final w = QueuedWrite(
        key: key ?? newIdempotencyKey(),
        account: acc,
        request: req,
        label: label,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        tempId: tempId,
        collection: collection);
    _items.add(w);
    notifyListeners();
    await _persist(acc);
    return w;
  }

  /// User discards a pending write. It is never sent.
  Future<void> discard(String key) async {
    final acc = _account;
    if (acc == null) return;
    _items.removeWhere((w) => w.key == key);
    notifyListeners();
    await _persist(acc);
  }

  /// Sends pending writes in order for [account] only. Stops at the first
  /// network failure (kept) or server refusal (kept with its error).
  /// Returns the last snapshot the server sent, if any.
  Future<Map<String, dynamic>?> flush(
    String account,
    Future<Map<String, dynamic>> Function(WriteRequest r, String key) send, {
    Map<String, dynamic>? before,
  }) async {
    final acc = AccountCache.norm(account);
    if (flushing || acc.isEmpty || acc != _account) return null;
    flushing = true;
    notifyListeners();
    Map<String, dynamic>? last;
    try {
      while (_items.isNotEmpty && _account == acc) {
        final w = _items.first;
        if (w.account != acc) {
          _items.removeAt(0); // never send under a different account
          continue;
        }
        if (w.error != null) break; // waits for the user
        try {
          last = await send(w.request, w.key);
        } catch (e) {
          if (_account != acc) break;
          if (!isRetryableWriteError(e)) {
            w.error = e.toString();
          } else {
            w.attempts++;
          }
          await _persist(acc);
          break;
        }
        if (_account != acc) break;
        final tmp = w.tempId, col = w.collection;
        if (tmp != null && col != null) {
          final real = newIdIn(before, last, col);
          if (real != null) _rewriteId(tmp, real);
        }
        before = last;
        _items.remove(w);
        await _persist(acc);
      }
    } finally {
      flushing = false;
      notifyListeners();
    }
    return last;
  }

  /// Later queued writes that point at [tmp] now point at the server [real].
  void _rewriteId(int tmp, int real) {
    final seg = RegExp('/${RegExp.escape('$tmp')}(?=/|\\?|\$)');
    for (var i = 0; i < _items.length; i++) {
      final w = _items[i];
      final r = w.request;
      final body = r.body == null ? null : _swap(r.body!, tmp, real);
      final path = r.path.replaceAll(seg, '/$real');
      if (path == r.path && identical(body, r.body)) continue;
      _items[i] = QueuedWrite(
        key: w.key,
        account: w.account,
        request: WriteRequest(r.method, path, body),
        label: w.label,
        createdAt: w.createdAt,
        error: w.error,
        tempId: w.tempId,
        collection: w.collection,
        attempts: w.attempts,
      );
    }
  }

  static Map<String, dynamic> _swap(Map<String, dynamic> b, int tmp, int real) {
    var changed = false;
    final out = <String, dynamic>{};
    b.forEach((k, v) {
      if (v is num && v == tmp) {
        out[k] = real;
        changed = true;
      } else if (v is String && v == '$tmp') {
        out[k] = '$real';
        changed = true;
      } else if (v is Map) {
        final m = Map<String, dynamic>.from(v);
        final keys = {
          for (final e in m.entries) e.key == '$tmp' ? '$real' : e.key: e.value
        };
        if (keys.length != m.length || m.containsKey('$tmp')) changed = true;
        out[k] = keys;
      } else {
        out[k] = v;
      }
    });
    return changed ? out : b;
  }

  /// Total pending (including refused) for the bound account.
  int get length => _items.length;

  /// Clears a refused item's error so the next flush tries it again.
  Future<void> retry(String key) async {
    final acc = _account;
    if (acc == null) return;
    for (final w in _items) {
      if (w.key == key) w.error = null;
    }
    notifyListeners();
    await _persist(acc);
  }
}

/// The one id in [after]`[collection]` that [before] did not have.
int? newIdIn(Map<String, dynamic>? before, Map<String, dynamic>? after, String collection) {
  Set<int> ids(Map<String, dynamic>? s) {
    final l = s?[collection];
    return {
      if (l is List)
        for (final e in l)
          if (e is Map && e['id'] is num) (e['id'] as num).toInt()
    };
  }

  final added = ids(after).difference(ids(before));
  return added.length == 1 ? added.first : null;
}

/// Temporary id for a row created offline (negative, never sent as-is).
int newTempId() => -(1 + Random.secure().nextInt(1 << 30));

/// Thrown after a write was queued instead of sent (not a failure).
class WriteQueuedException implements Exception {
  const WriteQueuedException();
  @override
  String toString() =>
      'ذخیره شد (آفلاین)؛ به محض اتصال خودکار ارسال می‌شود.';
}

/// Banner text while a bound account's cache is shown offline.
const offlineQueueNote =
    'اتصال به حساب وینور برقرار نیست؛ دادهٔ ذخیره‌شده نمایش داده می‌شود و تغییرهای تازه در صف ارسال می‌مانند.';

/// App-wide connectivity hint set by AppState. While true, stores queue a
/// write at once (optimistic) instead of waiting for a request to time out.
final ValueNotifier<bool> syncOffline = ValueNotifier<bool>(false);

/// Create requests get a temp id (for the optimistic row) and the snapshot
/// list the new row lands in (to learn its real id after sending).
({int? tempId, String? collection}) createMeta(WriteRequest r) {
  if (r.method != 'POST') return (tempId: null, collection: null);
  final p = r.path.split('?').first;
  String? col;
  if (p.endsWith('/biz/trades')) col = 'trades';
  if (p.endsWith('/projects')) col = 'items';
  if (p.endsWith('/pwo/withdrawers')) col = 'withdrawers';
  if (p.endsWith('/pwo/transactions')) col = 'transactions';
  return col == null ? (tempId: null, collection: null) : (tempId: newTempId(), collection: col);
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/account_cache.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/data/write_queue.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/invest_mutations.dart';

/// One offline change to the core book (assets, trades, system withdrawals,
/// settings), kept until the server confirms it. [key] doubles as the
/// Idempotency-Key prefix, so a retry after a lost answer never duplicates.
class CoreOp {
  CoreOp({
    required this.key,
    required this.kind,
    required this.args,
    required this.label,
    required this.createdAt,
    this.error,
    this.attempts = 0,
  });

  final String key;
  final String kind;
  Map<String, dynamic> args;
  final String label;
  final String createdAt;
  String? error;
  int attempts;

  Map<String, dynamic> toJson() => {
        'key': key,
        'kind': kind,
        'args': args,
        'label': label,
        'created_at': createdAt,
        if (error != null) 'error': error,
        if (attempts > 0) 'attempts': attempts,
      };

  static CoreOp? fromJson(Object? j) {
    if (j is! Map || j['key'] is! String || j['kind'] is! String) return null;
    return CoreOp(
      key: j['key'] as String,
      kind: j['kind'] as String,
      args: Map<String, dynamic>.from(j['args'] as Map? ?? const {}),
      label: '${j['label'] ?? ''}',
      createdAt: '${j['created_at'] ?? ''}',
      error: j['error'] as String?,
      attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    );
  }

  /// Temp ids this op introduces (negative).
  Iterable<int> get tempIds sync* {
    for (final k in const ['tmp', 'lot_tmp', 'closed_tmp']) {
      final v = args[k];
      if (v is num) yield v.toInt();
    }
  }
}

/// The lists an op touches. Mutated in place by [applyCoreOp].
class CoreBook {
  CoreBook({
    required this.assets,
    required this.open,
    required this.closed,
    required this.withdrawals,
  });
  List<Asset> assets;
  List<Trade> open;
  List<Trade> closed;
  List<Withdrawal> withdrawals;
}

double? _d(Object? v) => v is num ? v.toDouble() : null;

/// Applies one op to [b] optimistically. Idempotent: applying the same op to
/// a book that already shows it changes nothing, so it is safe to re-run on
/// every redraw over whatever lists the last pull/cache produced.
void applyCoreOp(CoreBook b, CoreOp op) {
  final a = op.args;
  final now = op.createdAt;
  Asset? assetById(int? id) => id == null ? null : b.assets.where((x) => x.id == id).firstOrNull;
  switch (op.kind) {
    case 'asset.create':
      final id = (a['tmp'] as num).toInt();
      if (assetById(id) != null) return;
      final qty = _d(a['quantity']) ?? 0, price = _d(a['avgBuyPrice']) ?? 0;
      final cur = (_d(a['currentPrice']) ?? 0) > 0 ? _d(a['currentPrice'])! : price;
      final asset = Asset(id: id, name: '${a['name']}', symbol: '${a['symbol'] ?? ''}', currentPrice: cur, notes: '${a['notes'] ?? ''}', createdAt: now, updatedAt: now);
      b.assets = [...b.assets, asset];
      if (qty > 0) {
        b.open = [
          ...b.open,
          Trade(id: (a['lot_tmp'] as num).toInt(), assetId: id, status: AppConfig.tradeOpen, quantity: qty, buyPrice: price, buyDate: '${a['buyDate'] ?? ''}', buyNote: 'موجودی اولیه', assetName: asset.name, assetSymbol: asset.symbol, currentPrice: cur, createdAt: now),
        ];
      }
    case 'asset.update':
      final next = Asset.fromMap(Map<String, Object?>.from(a['asset'] as Map));
      b.assets = [for (final x in b.assets) x.id == next.id ? next : x];
      b.open = [
        for (final t in b.open)
          if (t.assetId == next.id) (t..assetName = next.name..assetSymbol = next.symbol..currentPrice = next.currentPrice) else t
      ];
    case 'trade.buy':
      final id = (a['tmp'] as num).toInt();
      if (b.open.any((t) => t.id == id) || b.closed.any((t) => t.id == id)) return;
      var assetId = (a['assetId'] as num?)?.toInt();
      var asset = assetById(assetId);
      final name = '${a['name'] ?? ''}'.trim(), sym = '${a['symbol'] ?? ''}'.trim();
      if (asset == null && name.isNotEmpty) {
        asset = b.assets.where((x) => x.name == name && x.symbol == sym).firstOrNull;
        if (asset == null) {
          asset = Asset(id: (a['asset_tmp'] as num?)?.toInt() ?? id - 1, name: name, symbol: sym, currentPrice: _d(a['currentPrice']) ?? _d(a['buyPrice']) ?? 0, createdAt: now);
          b.assets = [...b.assets, asset];
        }
      }
      if (asset == null) return;
      assetId = asset.id;
      b.open = [
        ...b.open,
        Trade(
          id: id,
          assetId: assetId!,
          status: AppConfig.tradeOpen,
          quantity: _d(a['quantity']) ?? 0,
          buyPrice: _d(a['buyPrice']) ?? 0,
          buyPriceUsd: _d(a['buyPriceUsd']),
          buyUsdTmn: _d(a['buyUsdTmn']),
          buyFee: _d(a['buyFee']) ?? 0,
          buyDate: '${a['buyDate'] ?? ''}',
          buyNote: '${a['buyNote'] ?? ''}',
          assetName: asset.name,
          assetSymbol: asset.symbol,
          currentPrice: (_d(a['currentPrice']) ?? 0) > 0 ? _d(a['currentPrice'])! : asset.currentPrice,
          createdAt: now,
        ),
      ];
    case 'trade.update':
      final id = (a['tradeId'] as num).toInt();
      for (final t in b.open) {
        if (t.id != id) continue;
        t
          ..quantity = _d(a['quantity']) ?? t.quantity
          ..buyPrice = _d(a['buyPrice']) ?? t.buyPrice
          ..buyPriceUsd = _d(a['buyPriceUsd'])
          ..buyUsdTmn = _d(a['buyUsdTmn'])
          ..buyFee = _d(a['buyFee']) ?? t.buyFee;
        if (a['buyDate'] != null) t.buyDate = '${a['buyDate']}';
        if (a['buyNote'] != null) t.buyNote = '${a['buyNote']}';
      }
    case 'trade.close':
      final id = (a['tradeId'] as num).toInt();
      final t = b.open.where((x) => x.id == id).firstOrNull;
      if (t == null) return;
      final qty = _d(a['quantity']) ?? t.quantity;
      final sell = _d(a['sellPrice']) ?? 0, fee = _d(a['sellFee']) ?? 0;
      final part = qty < t.quantity - 1e-9;
      final cid = part ? (a['closed_tmp'] as num).toInt() : t.id;
      if (b.closed.any((x) => x.id == cid && cid != t.id)) return;
      final pnl = (sell - t.buyPrice) * qty - fee - (t.buyFee * qty / (t.quantity == 0 ? 1 : t.quantity));
      final closed = Trade(
        id: cid,
        assetId: t.assetId,
        status: AppConfig.tradeClosed,
        quantity: qty,
        buyPrice: t.buyPrice,
        buyPriceUsd: t.buyPriceUsd,
        buyUsdTmn: t.buyUsdTmn,
        buyFee: part ? t.buyFee * qty / t.quantity : t.buyFee,
        buyDate: t.buyDate,
        buyNote: t.buyNote,
        sellPrice: sell,
        sellFee: fee,
        sellDate: '${a['sellDate'] ?? ''}',
        sellNote: '${a['sellNote'] ?? ''}',
        realizedPnl: pnl,
        returnPct: t.buyPrice * qty == 0 ? null : pnl / (t.buyPrice * qty) * 100,
        assetName: t.assetName,
        assetSymbol: t.assetSymbol,
        currentPrice: t.currentPrice,
        createdAt: t.createdAt,
        updatedAt: now,
      );
      if (part) {
        t
          ..buyFee = t.buyFee * (t.quantity - qty) / t.quantity
          ..quantity = t.quantity - qty;
      } else {
        b.open = [for (final x in b.open) if (x.id != id) x];
      }
      b.closed = [closed, ...b.closed];
    case 'trade.delete':
      final id = (a['tradeId'] as num).toInt();
      b.closed = [for (final x in b.closed) if (x.id != id) x];
    case 'wd.create':
      final id = (a['tmp'] as num).toInt();
      if (b.withdrawals.any((w) => w.id == id)) return;
      b.withdrawals = [
        Withdrawal(id: id, amount: _d(a['amount']) ?? 0, note: '${a['note'] ?? ''}', createdAt: '${a['createdAt'] ?? now}'),
        ...b.withdrawals,
      ];
    case 'wd.update':
      final id = (a['id'] as num).toInt();
      b.withdrawals = [
        for (final w in b.withdrawals)
          if (w.id == id)
            Withdrawal(id: id, amount: _d(a['amount']) ?? w.amount, note: '${a['note'] ?? w.note}', status: w.status, createdAt: '${a['createdAt'] ?? w.createdAt}')
          else
            w
      ];
  }
}

/// Assets touched by trade ops show quantity / average cost from their open
/// lots (what the server derives), recomputed so re-applying is harmless.
void recomputeAssetHoldings(CoreBook b, Set<int> assetIds) {
  for (final asset in b.assets) {
    if (!assetIds.contains(asset.id)) continue;
    final lots = b.open.where((t) => t.assetId == asset.id).toList();
    final q = lots.fold<double>(0, (s, t) => s + t.quantity);
    asset.quantity = q;
    asset.avgBuyPrice = q <= 0 ? 0 : lots.fold<double>(0, (s, t) => s + t.quantity * t.buyPrice) / q;
  }
}

/// Persistent, ordered outbox for one account's core-book writes.
class CoreOutbox extends ChangeNotifier {
  CoreOutbox({AccountCache? cache})
      : _cache = cache ?? AccountCache(keyOf: (a, _) => 'vplus_core_outbox_v1_$a');

  final AccountCache _cache;
  String? _account;
  List<CoreOp> _ops = [];

  /// tmp id → server id learned while flushing (kept so stale cached rows
  /// with a temp id are dropped once the real row exists).
  final Map<int, int> idMap = {};
  bool flushing = false;
  int revision = 0;

  String? get account => _account;
  List<CoreOp> get ops => List.unmodifiable(_ops);
  bool get isEmpty => _ops.isEmpty;
  int get length => _ops.length;

  @override
  void notifyListeners() {
    revision++;
    super.notifyListeners();
  }

  Future<void> bind(String? account) async {
    final acc = AccountCache.norm(account);
    if (acc == (_account ?? '')) return;
    _account = acc.isEmpty ? null : acc;
    _ops = [];
    idMap.clear();
    notifyListeners();
    if (_account == null) return;
    final raw = await _cache.read(acc);
    if (_account != acc) return;
    try {
      final j = raw == null ? null : jsonDecode(raw);
      final list = j is Map ? j['ops'] as List? : j as List?;
      _ops = [for (final e in list ?? const []) if (CoreOp.fromJson(e) case final o?) o];
      if (j is Map && j['ids'] is Map) {
        (j['ids'] as Map).forEach((k, v) {
          final kk = int.tryParse('$k');
          if (kk != null && v is num) idMap[kk] = v.toInt();
        });
      }
    } catch (_) {
      _ops = [];
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final acc = _account;
    if (acc == null) return;
    await _cache.write(acc, jsonEncode({
      'ops': [for (final o in _ops) o.toJson()],
      'ids': {for (final e in idMap.entries) '${e.key}': e.value},
    }));
  }

  /// Queues [kind]. Settings pushes coalesce (only the latest matters).
  Future<CoreOp> add(String kind, Map<String, dynamic> args, String label, {String? key}) async {
    if (_account == null) throw StateError('حساب وینور مشخص نیست.');
    if (kind == 'settings.push') {
      final old = _ops.where((o) => o.kind == kind && o.error == null).firstOrNull;
      if (old != null) return old;
    }
    final op = CoreOp(key: key ?? newIdempotencyKey(), kind: kind, args: args, label: label, createdAt: DateTime.now().toIso8601String());
    _ops.add(op);
    notifyListeners();
    await _persist();
    return op;
  }

  Future<void> discard(String key) async {
    _ops.removeWhere((o) => o.key == key);
    notifyListeners();
    await _persist();
  }

  Future<void> retry(String key) async {
    for (final o in _ops) {
      if (o.key == key) o.error = null;
    }
    notifyListeners();
    await _persist();
  }

  /// Every temp id still waiting for the server.
  Set<int> get liveTempIds => {for (final o in _ops) ...o.tempIds};

  /// Sends ops in order. Each runs inside an [IdempotencyScope] keyed by the
  /// op, so a resend reuses the same keys. Stops at a network failure (kept,
  /// attempt counted) or a refusal (kept with its error for the user).
  /// Returns true when the queue drained.
  Future<bool> flush(Future<int?> Function(CoreOp op) send) async {
    final acc = _account;
    if (flushing || acc == null) return _ops.isEmpty;
    flushing = true;
    notifyListeners();
    try {
      while (_ops.isNotEmpty && _account == acc) {
        final op = _ops.first;
        if (op.error != null) return false;
        int? created;
        try {
          created = await IdempotencyScope.run(op.key, () => send(op));
        } catch (e) {
          if (_account != acc) return false;
          if (isRetryableWriteError(e)) {
            op.attempts++;
          } else {
            op.error = e is InvestApiException ? e.message : '$e'.replaceFirst('Invalid argument(s): ', '').replaceFirst('Bad state: ', '');
          }
          await _persist();
          return false;
        }
        if (_account != acc) return false;
        final tmp = op.args['tmp'];
        if (tmp is num && created != null) {
          idMap[tmp.toInt()] = created;
          _rewrite(tmp.toInt(), created);
        }
        _ops.remove(op);
        await _persist();
        notifyListeners();
      }
      return _ops.isEmpty;
    } finally {
      flushing = false;
      notifyListeners();
    }
  }

  void _rewrite(int tmp, int real) {
    for (final o in _ops) {
      final next = <String, dynamic>{};
      o.args.forEach((k, v) {
        if ((k == 'assetId' || k == 'tradeId' || k == 'id') && v is num && v.toInt() == tmp) {
          next[k] = real;
        } else if (k == 'asset' && v is Map && v['id'] == tmp) {
          next[k] = {...Map<String, dynamic>.from(v), 'id': real};
        } else {
          next[k] = v;
        }
      });
      o.args = next;
    }
  }
}

/// Sends one core op through [svc]; returns the server id of a created row.
/// The created lot of `asset.create` is learnt on the next pull.
Future<int?> sendCoreOp(InvestMutations svc, CoreOp op,
    {Future<Withdrawal?> Function(Map<String, dynamic> a)? createWithdrawal,
    Future<void> Function(Map<String, dynamic> a)? updateWithdrawal,
    Future<void> Function()? pushSettings}) async {
  final a = op.args;
  switch (op.kind) {
    case 'asset.create':
      final x = await svc.createAsset(
        name: '${a['name']}',
        symbol: '${a['symbol'] ?? ''}',
        quantity: _d(a['quantity']) ?? 0,
        avgBuyPrice: _d(a['avgBuyPrice']) ?? 0,
        currentPrice: _d(a['currentPrice']) ?? 0,
        notes: '${a['notes'] ?? ''}',
        buyDate: a['buyDate'] as String?,
      );
      return x.id;
    case 'asset.update':
      await svc.updateAsset(Asset.fromMap(Map<String, Object?>.from(a['asset'] as Map)));
      return null;
    case 'trade.buy':
      final t = await svc.registerBuy(
        assetId: (a['assetId'] as num?)?.toInt(),
        name: a['name'] as String?,
        symbol: '${a['symbol'] ?? ''}',
        quantity: _d(a['quantity']) ?? 0,
        buyPrice: _d(a['buyPrice']) ?? 0,
        buyPriceUsd: _d(a['buyPriceUsd']),
        buyUsdTmn: _d(a['buyUsdTmn']),
        buyFee: _d(a['buyFee']) ?? 0,
        buyDate: a['buyDate'] as String?,
        buyNote: '${a['buyNote'] ?? ''}',
        currentPrice: _d(a['currentPrice']),
      );
      return t.id;
    case 'trade.update':
      await svc.updateOpenTrade(
        tradeId: (a['tradeId'] as num).toInt(),
        quantity: _d(a['quantity']) ?? 0,
        buyPrice: _d(a['buyPrice']) ?? 0,
        buyPriceUsd: _d(a['buyPriceUsd']),
        buyUsdTmn: _d(a['buyUsdTmn']),
        buyFee: _d(a['buyFee']) ?? 0,
        buyDate: a['buyDate'] as String?,
        buyNote: a['buyNote'] as String?,
      );
      return null;
    case 'trade.close':
      await svc.closeTrade(
        tradeId: (a['tradeId'] as num).toInt(),
        sellPrice: _d(a['sellPrice']) ?? 0,
        sellFee: _d(a['sellFee']) ?? 0,
        sellDate: a['sellDate'] as String?,
        sellNote: '${a['sellNote'] ?? ''}',
        quantity: _d(a['quantity']),
        sellUsdTmn: _d(a['sellUsdTmn']),
      );
      return null;
    case 'trade.delete':
      try {
        await svc.deleteClosedTrade((a['tradeId'] as num).toInt());
      } on InvestApiException catch (e) {
        if (e.statusCode != 404) rethrow; // already gone: done
      }
      return null;
    case 'wd.create':
      return (await createWithdrawal?.call(a))?.id;
    case 'wd.update':
      await updateWithdrawal?.call(a);
      return null;
    case 'settings.push':
      await pushSettings?.call();
      return null;
  }
  return null;
}

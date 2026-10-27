import 'dart:convert';

import 'package:invest/data/write_queue.dart';

/// Optimistic view: the last server snapshot with every queued write applied
/// locally, in order. Pure functions over the server's JSON snapshot shape,
/// so the UI shows offline edits at once and a later pull simply replaces
/// the base (writes still queued are re-applied on top).
typedef SnapReducer = Map<String, dynamic> Function(
    Map<String, dynamic> snap, QueuedWrite w);

Map<String, dynamic> overlay(Map<String, dynamic> server, List<QueuedWrite> queue, SnapReducer apply) {
  if (queue.isEmpty) return server;
  var s = jsonDecode(jsonEncode(server)) as Map<String, dynamic>;
  for (final w in queue) {
    try {
      s = apply(s, w);
    } catch (_) {
      // A write the reducer cannot model still syncs; it just is not shown.
    }
  }
  return s;
}

double _num(Object? v) {
  if (v is num) return v.toDouble();
  final t = '${v ?? ''}'.replaceAll(RegExp(r'[,،٬\s]'), '');
  return double.tryParse(t) ?? 0;
}

List<Map<String, dynamic>> _list(Map<String, dynamic> s, String k) {
  final l = [
    for (final e in (s[k] as List? ?? const []))
      if (e is Map) Map<String, dynamic>.from(e)
  ];
  s[k] = l;
  return l;
}

/// `/a/b/123` → 123 (negative temp ids included); query string ignored.
int? _lastId(String path) {
  final p = path.split('?').first.split('/').where((x) => x.isNotEmpty).toList();
  return p.isEmpty ? null : int.tryParse(p.last);
}

List<String> _segs(String path) =>
    path.split('?').first.split('/').where((x) => x.isNotEmpty).toList();

void _upd(Map<String, dynamic> row, String pending) {
  row['pending_sync'] = true;
  row['pending_label'] = pending;
}

// ---------------------------------------------------------------- PWO -----

Map<String, dynamic> applyPwo(Map<String, dynamic> s, QueuedWrite w) {
  final r = w.request, b = r.body ?? const {};
  final seg = _segs(r.path);
  final i = seg.indexOf('pwo');
  final kind = i >= 0 && seg.length > i + 1 ? seg[i + 1] : '';
  final id = _lastId(r.path);
  switch ((r.method, kind)) {
    case ('PUT', 'target'):
      s['target'] = _num(b['target']);
    case ('POST', 'withdrawers'):
      _list(s, 'withdrawers').add({'id': w.tempId ?? newTempId(), 'name': b['name'], 'archived': false, 'sort_order': 9999, 'pending_sync': true});
    case ('PATCH', 'withdrawers'):
      for (final x in _list(s, 'withdrawers')) {
        if (x['id'] == id) {
          if (b.containsKey('name')) x['name'] = b['name'];
          if (b.containsKey('archived')) x['archived'] = b['archived'] == true;
          x['pending_sync'] = true;
        }
      }
    case ('DELETE', 'withdrawers'):
      for (final x in _list(s, 'withdrawers')) {
        if (x['id'] == id) x['archived'] = true;
      }
    case ('PUT', 'months'):
      final y = int.parse(seg[seg.length - 2]), m = int.parse(seg.last);
      final amounts = Map<String, dynamic>.from(b['amounts'] as Map? ?? const {});
      final es = _list(s, 'entries');
      es.removeWhere((e) => e['year'] == y && e['month'] == m && amounts.containsKey('${e['withdrawer_id']}'));
      amounts.forEach((wid, a) {
        final v = _num(a);
        if (v > 0) {
          es.add({'id': null, 'withdrawer_id': int.tryParse(wid) ?? wid, 'year': y, 'month': m, 'amount': v, 'note': '', 'pending_sync': true});
        }
      });
    case ('DELETE', 'entries'):
      _list(s, 'entries').removeWhere((e) => e['id'] == id);
    case ('POST', 'transactions'):
      _list(s, 'transactions').add({
        'id': w.tempId ?? newTempId(),
        'withdrawer_id': b['withdrawer_id'],
        'year': b['year'],
        'month': b['month'],
        'amount': _num(b['amount']),
        'note': b['note'] ?? '',
        'pending_sync': true,
      });
    case ('PATCH', 'transactions'):
      for (final x in _list(s, 'transactions')) {
        if (x['id'] == id) {
          for (final k in ['withdrawer_id', 'note', 'year', 'month']) {
            if (b.containsKey(k)) x[k] = b[k];
          }
          if (b.containsKey('amount')) x['amount'] = _num(b['amount']);
          x['pending_sync'] = true;
        }
      }
    case ('DELETE', 'transactions'):
      _list(s, 'transactions').removeWhere((e) => e['id'] == id);
  }
  return s;
}

// ---------------------------------------------------------------- Biz -----

void _bizTradeDerived(Map<String, dynamic> t) {
  final buy = _num(t['buy_amount']), sell = _num(t['sell_amount']);
  t['buy_amount'] = buy;
  t['sell_amount'] = sell;
  t['extra_cost'] = _num(t['extra_cost']);
  final sold = '${t['sell_date'] ?? ''}'.isNotEmpty && sell > 0;
  final profit = sold ? sell - buy : null;
  t['profit'] = profit;
  t['profit_pct'] = profit != null && sell > 0 ? profit / sell * 100 : null;
}

void _bizTotals(Map<String, dynamic> s) {
  final ts = _list(s, 'trades');
  final sold = ts.where((t) => t['profit'] != null);
  s['trades_totals'] = {
    'count': ts.length,
    'profit': sold.fold<double>(0, (a, t) => a + _num(t['profit'])),
    'buy': ts.fold<double>(0, (a, t) => a + _num(t['buy_amount'])),
    'sell': sold.fold<double>(0, (a, t) => a + _num(t['sell_amount'])),
    'extra_cost': ts.fold<double>(0, (a, t) => a + _num(t['extra_cost'])),
  };
  final ms = _list(s, 'months');
  final tot = <String, double>{};
  for (final m in ms) {
    m['net'] = _num(m['income']) - _num(m['staff']) - _num(m['pwo']) - _num(m['ads']);
    for (final k in ['staff', 'pwo', 'ads', 'income', 'net']) {
      tot[k] = (tot[k] ?? 0) + _num(m[k]);
    }
  }
  if (ms.isNotEmpty) s['months_totals'] = tot;
}

Map<String, dynamic> applyBiz(Map<String, dynamic> s, QueuedWrite w) {
  final r = w.request, b = r.body ?? const {};
  final seg = _segs(r.path);
  final i = seg.indexOf('biz');
  final kind = i >= 0 && seg.length > i + 1 ? seg[i + 1] : '';
  final id = _lastId(r.path);
  const fields = ['buy_date', 'sell_date', 'buy_amount', 'sell_amount', 'area', 'title', 'extra_cost', 'note'];
  switch ((r.method, kind)) {
    case ('POST', 'trades'):
      final t = <String, dynamic>{
        'id': w.tempId ?? newTempId(),
        'buy_date': '', 'sell_date': '', 'buy_amount': 0, 'sell_amount': 0,
        'area': '', 'title': '', 'extra_cost': 0, 'note': '',
        for (final k in fields)
          if (b.containsKey(k)) k: b[k],
      };
      _bizTradeDerived(t);
      _upd(t, w.label);
      _list(s, 'trades').add(t);
    case ('PATCH', 'trades'):
      for (final t in _list(s, 'trades')) {
        if (t['id'] == id) {
          for (final k in fields) {
            if (b.containsKey(k)) t[k] = b[k];
          }
          _bizTradeDerived(t);
          _upd(t, w.label);
        }
      }
    case ('DELETE', 'trades'):
      _list(s, 'trades').removeWhere((t) => t['id'] == id);
    case ('PUT', 'months'):
      final y = int.parse(seg[seg.length - 2]), mo = int.parse(seg.last);
      if (s['year'] == y) {
        for (final m in _list(s, 'months')) {
          if (m['month'] == mo) {
            for (final k in ['staff', 'ads', 'income']) {
              if (b.containsKey(k)) m[k] = _num(b[k]);
            }
            if (b.containsKey('note')) m['note'] = b['note'];
            m['has_ops'] = true;
            _upd(m, w.label);
          }
        }
      }
    case ('DELETE', 'months'):
      final y = int.parse(seg[seg.length - 2]), mo = int.parse(seg.last);
      if (s['year'] == y) {
        for (final m in _list(s, 'months')) {
          if (m['month'] == mo) {
            m
              ..['staff'] = 0.0
              ..['ads'] = 0.0
              ..['income'] = 0.0
              ..['note'] = ''
              ..['has_ops'] = false;
            _upd(m, w.label);
          }
        }
      }
  }
  _bizTotals(s);
  return s;
}

// ----------------------------------------------------------- Projects -----

void _projDerived(Map<String, dynamic> p) {
  final c = _num(p['contract_amount']), cost = _num(p['cost']);
  p['contract_amount'] = c;
  p['cost'] = cost;
  final profit = c > 0 ? c - cost : null;
  p['profit'] = profit;
  p['profit_pct'] = profit != null ? profit / c * 100 : null;
  final wt = '${p['work_type'] ?? ''}';
  p['description'] = '${p['title'] ?? ''}${wt.isEmpty ? '' : ' - $wt'}';
  final mode = '${p['status_mode'] ?? 'auto'}';
  if (mode != 'auto' && mode.isNotEmpty) {
    p['status'] = mode;
  } else if ((p['status'] ?? '') == '') {
    p['status'] = '${p['end_date'] ?? ''}'.isNotEmpty ? 'finished' : 'active';
  }
}

Map<String, dynamic> applyProjects(Map<String, dynamic> s, QueuedWrite w) {
  final r = w.request, b = r.body ?? const {};
  final id = _lastId(r.path);
  final items = _list(s, 'items');
  const fields = ['title', 'work_type', 'start_date', 'end_date', 'contract_amount', 'cost', 'note', 'status_mode'];
  void archive(Map<String, dynamic> p) {
    if (!b.containsKey('archived')) return;
    final a = b['archived'] == true;
    p['archived'] = a;
    p['archived_at'] = a ? DateTime.now().toIso8601String() : null;
  }

  switch (r.method) {
    case 'POST' when id == null:
      final p = <String, dynamic>{
        'id': w.tempId ?? newTempId(),
        'title': '', 'work_type': '', 'start_date': '', 'end_date': '',
        'contract_amount': 0, 'cost': 0, 'note': '', 'status_mode': 'auto', 'status': '',
        'archived': false,
        for (final k in fields)
          if (b.containsKey(k)) k: b[k],
      };
      _projDerived(p);
      _upd(p, w.label);
      items.add(p);
    case 'PATCH' || 'PUT':
      for (final p in items) {
        if (p['id'] == id) {
          for (final k in fields) {
            if (b.containsKey(k)) p[k] = b[k];
          }
          if (b.containsKey('status_mode') || b.containsKey('end_date')) p['status'] = '';
          archive(p);
          _projDerived(p);
          _upd(p, w.label);
        }
      }
    case 'DELETE':
      items.removeWhere((p) => p['id'] == id);
  }
  return s;
}

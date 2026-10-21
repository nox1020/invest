import 'dart:convert';

/// PWO: monthly personal withdrawals of N people against a monthly target.
const pwoMonthNames = <String>[
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];

const pwoDefaultTarget = 100000000.0;
const pwoDefaultNames = <String>['M', 'A', 'N'];
const pwoSeedTag = 'seed_1405_v1';

/// 1405 rows from the old Excel sheet, in millions of toman (M, A, N).
const Map<int, List<double>> pwoSeed1405Millions = {
  1: [96.7, 15, 15],
  2: [253.53, 315, 15],
  3: [200.6, 15, 15],
  4: [149, 15, 30],
  5: [309.3, 15, 30],
  6: [230.5, 37, 30],
};

String pwoMonthKey(int year, int month) =>
    '$year-${month.toString().padLeft(2, '0')}';

class PwoPerson {
  PwoPerson({required this.id, required this.name, this.active = true});
  final String id;
  String name;

  /// Archived people keep their history but get no new entry fields.
  bool active;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'active': active};
}

class PwoMonth {
  PwoMonth({
    required this.year,
    required this.month,
    Map<String, double>? amounts,
    Map<String, int>? entryIds,
  })  : amounts = Map<String, double>.from(amounts ?? const {}),
        entryIds = Map<String, int>.from(entryIds ?? const {});

  /// Server entry id per person id (remote mode only).
  final Map<String, int> entryIds;

  final int year;
  final int month;

  /// person id -> toman.
  final Map<String, double> amounts;

  String get key => pwoMonthKey(year, month);
  double get total => amounts.values.fold(0.0, (a, b) => a + b);
  double of(String id) => amounts[id] ?? 0;
  bool meets(double target) => total >= target;

  Map<String, dynamic> toJson() =>
      {'y': year, 'm': month, 'a': amounts, if (entryIds.isNotEmpty) 'e': entryIds};

  /// Accepts v2 maps and v1 positional lists (mapped to p0, p1, p2...).
  static PwoMonth? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final y = raw['y'], m = raw['m'], a = raw['a'];
    if (y is! num || m is! num) return null;
    if (m < 1 || m > 12) return null;
    final vals = <String, double>{};
    void put(String k, Object? v) {
      if (v is num && v.isFinite && v > 0) vals[k] = v.toDouble();
    }

    if (a is List) {
      for (var i = 0; i < a.length; i++) {
        put('p$i', a[i]);
      }
    } else if (a is Map) {
      a.forEach((k, v) => put(k.toString(), v));
    } else {
      return null;
    }
    final ids = <String, int>{};
    final e = raw['e'];
    if (e is Map) {
      e.forEach((k, v) {
        if (v is num) ids[k.toString()] = v.toInt();
      });
    }
    return PwoMonth(
        year: y.toInt(), month: m.toInt(), amounts: vals, entryIds: ids);
  }
}

class PwoLedger {
  PwoLedger({
    List<PwoPerson>? people,
    this.target = pwoDefaultTarget,
    Map<String, PwoMonth>? months,
    Set<String>? tags,
  })  : people = people ??
            [
              for (var i = 0; i < pwoDefaultNames.length; i++)
                PwoPerson(id: 'p$i', name: pwoDefaultNames[i]),
            ],
        months = months ?? {},
        tags = tags ?? {};

  final List<PwoPerson> people;
  double target;
  final Map<String, PwoMonth> months;
  final Set<String> tags;

  List<PwoPerson> get activePeople => people.where((p) => p.active).toList();

  PwoPerson? personById(String id) {
    for (final p in people) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Adds the 1405 Excel rows once. Never overwrites a month already present.
  bool applySeed() {
    if (tags.contains(pwoSeedTag)) return false;
    for (var i = 0; i < pwoDefaultNames.length; i++) {
      if (personById('p$i') == null) {
        people.add(PwoPerson(id: 'p$i', name: pwoDefaultNames[i]));
      }
    }
    pwoSeed1405Millions.forEach((m, vals) {
      months.putIfAbsent(
        pwoMonthKey(1405, m),
        () => PwoMonth(year: 1405, month: m, amounts: {
          for (var i = 0; i < vals.length; i++)
            'p$i': (vals[i] * 1000000).roundToDouble(),
        }),
      );
    });
    tags.add(pwoSeedTag);
    return true;
  }

  String _newId() {
    var n = people.length;
    while (personById('p$n') != null) {
      n++;
    }
    return 'p$n';
  }

  PwoPerson addPerson(String name) {
    final p = PwoPerson(id: _newId(), name: name.trim());
    people.add(p);
    return p;
  }

  bool hasEntries(String id) => months.values.any((m) => m.of(id) > 0);

  /// Removes a person. With entries they are archived (history kept);
  /// without entries they are deleted. The last active person stays.
  bool removePerson(String id) {
    final p = personById(id);
    if (p == null || !p.active || activePeople.length <= 1) return false;
    if (hasEntries(id)) {
      p.active = false;
    } else {
      people.remove(p);
    }
    return true;
  }

  /// People shown for a given month: active + anyone with an amount there.
  List<PwoPerson> peopleFor(PwoMonth? m) => people
      .where((p) => p.active || (m != null && m.of(p.id) > 0))
      .toList();

  /// People shown in totals: active + archived with history.
  List<PwoPerson> get peopleWithHistory =>
      people.where((p) => p.active || hasEntries(p.id)).toList();

  List<int> get years {
    final ys = months.values.map((e) => e.year).toSet().toList()..sort();
    return ys.reversed.toList();
  }

  List<PwoMonth> monthsOf(int year) {
    final list = months.values.where((e) => e.year == year).toList()
      ..sort((a, b) => a.month.compareTo(b.month));
    return list;
  }

  double yearTotal(int year) =>
      monthsOf(year).fold(0.0, (a, b) => a + b.total);

  double personTotal(int year, String id) =>
      monthsOf(year).fold(0.0, (a, b) => a + b.of(id));

  int monthsMeeting(int year) =>
      monthsOf(year).where((m) => m.meets(target)).length;

  PwoMonth? previousOf(PwoMonth m) {
    final py = m.month == 1 ? m.year - 1 : m.year;
    final pm = m.month == 1 ? 12 : m.month - 1;
    return months[pwoMonthKey(py, pm)];
  }

  void upsert(PwoMonth m) => months[m.key] = m;
  void remove(int year, int month) => months.remove(pwoMonthKey(year, month));

  /// Server snapshot (`pwo` object) -> ledger. Amounts stay in toman.
  static PwoLedger fromServer(Map<String, dynamic> snap) {
    final people = <PwoPerson>[];
    final ws = snap['withdrawers'];
    if (ws is List) {
      for (final w in ws) {
        if (w is! Map || w['id'] == null) continue;
        final id = w['id'].toString();
        if (people.any((p) => p.id == id)) continue;
        final name = w['name']?.toString().trim() ?? '';
        people.add(PwoPerson(
            id: id, name: name.isEmpty ? id : name, active: w['archived'] != true));
      }
    }
    final t = snap['target'];
    final months = <String, PwoMonth>{};
    final es = snap['entries'];
    if (es is List) {
      for (final e in es) {
        if (e is! Map) continue;
        final y = e['year'], m = e['month'], a = e['amount'];
        if (y is! num || m is! num || m < 1 || m > 12) continue;
        final wid = e['withdrawer_id']?.toString();
        if (wid == null) continue;
        final mo = months.putIfAbsent(pwoMonthKey(y.toInt(), m.toInt()),
            () => PwoMonth(year: y.toInt(), month: m.toInt()));
        final amt = a is num ? a.toDouble() : double.tryParse('$a') ?? 0;
        if (amt.isFinite && amt > 0) mo.amounts[wid] = amt;
        final eid = e['id'];
        if (eid is num) mo.entryIds[wid] = eid.toInt();
      }
    }
    final l = PwoLedger(
      people: people,
      target: (t is num && t > 0) ? t.toDouble() : pwoDefaultTarget,
      months: months,
      tags: {pwoSeedTag},
    );
    for (final m in months.values) {
      for (final id in m.amounts.keys) {
        if (l.personById(id) == null) {
          l.people.add(PwoPerson(id: id, name: id, active: false));
        }
      }
    }
    return l;
  }

  /// Payload for `POST /pwo/import` (names are the join key on the server).
  Map<String, dynamic> toImportPayload() => {
        'target': target,
        'withdrawers': [
          for (final p in people) {'name': p.name, 'archived': !p.active},
        ],
        'entries': [
          for (final m in months.values)
            for (final e in m.amounts.entries)
              if (e.value > 0 && personById(e.key) != null)
                {
                  'withdrawer': personById(e.key)!.name,
                  'year': m.year,
                  'month': m.month,
                  'amount': e.value,
                },
        ],
        'overwrite': false,
      };

  String encode() => jsonEncode({
        'v': 2,
        'people': people.map((e) => e.toJson()).toList(),
        'target': target,
        'tags': tags.toList(),
        'months': months.values.map((e) => e.toJson()).toList(),
      });

  static PwoLedger decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return PwoLedger();
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return PwoLedger();
      List<PwoPerson>? people;
      final pp = j['people'];
      if (pp is List) {
        people = [];
        for (final r in pp) {
          if (r is! Map) continue;
          final id = r['id']?.toString() ?? '';
          final name = r['name']?.toString().trim() ?? '';
          if (id.isEmpty || people.any((e) => e.id == id)) continue;
          people.add(PwoPerson(
              id: id, name: name.isEmpty ? id : name, active: r['active'] != false));
        }
      } else if (j['names'] is List) {
        // v1: fixed three names.
        final n = j['names'] as List;
        people = [
          for (var i = 0; i < pwoDefaultNames.length; i++)
            PwoPerson(
              id: 'p$i',
              name: (i < n.length && (n[i]?.toString().trim() ?? '').isNotEmpty)
                  ? n[i].toString().trim()
                  : pwoDefaultNames[i],
            ),
        ];
      }
      final t = j['target'];
      final target =
          (t is num && t.isFinite && t > 0) ? t.toDouble() : pwoDefaultTarget;
      final months = <String, PwoMonth>{};
      final ms = j['months'];
      if (ms is List) {
        for (final r in ms) {
          final m = PwoMonth.fromJson(r);
          if (m != null) months[m.key] = m;
        }
      }
      final tags = <String>{};
      final tg = j['tags'];
      if (tg is List) tags.addAll(tg.map((e) => e.toString()));
      final l = PwoLedger(
          people: people, target: target, months: months, tags: tags);
      // Any id referenced by a month but unknown becomes an archived person.
      for (final m in months.values) {
        for (final id in m.amounts.keys) {
          if (l.personById(id) == null) {
            l.people.add(PwoPerson(id: id, name: id, active: false));
          }
        }
      }
      if (l.activePeople.isEmpty) {
        if (l.people.isNotEmpty) {
          l.people.first.active = true;
        } else {
          l.people.add(PwoPerson(id: 'p0', name: pwoDefaultNames[0]));
        }
      }
      return l;
    } catch (_) {
      return PwoLedger();
    }
  }
}

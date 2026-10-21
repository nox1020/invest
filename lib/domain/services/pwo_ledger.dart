import 'dart:convert';

/// PWO: monthly personal withdrawals of three people against a monthly target.
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

class PwoMonth {
  PwoMonth({required this.year, required this.month, List<double>? amounts})
      : amounts = List<double>.from(amounts ?? const [0, 0, 0]);

  final int year;
  final int month;
  final List<double> amounts;

  String get key => pwoMonthKey(year, month);
  double get total => amounts.fold(0.0, (a, b) => a + b);
  bool meets(double target) => total >= target;

  Map<String, dynamic> toJson() => {'y': year, 'm': month, 'a': amounts};

  static PwoMonth? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final y = raw['y'], m = raw['m'], a = raw['a'];
    if (y is! num || m is! num || a is! List) return null;
    if (m < 1 || m > 12) return null;
    final vals = <double>[0, 0, 0];
    for (var i = 0; i < 3 && i < a.length; i++) {
      final v = a[i];
      if (v is num && v.isFinite && v >= 0) vals[i] = v.toDouble();
    }
    return PwoMonth(year: y.toInt(), month: m.toInt(), amounts: vals);
  }
}

class PwoLedger {
  PwoLedger({
    List<String>? names,
    this.target = pwoDefaultTarget,
    Map<String, PwoMonth>? months,
    Set<String>? tags,
  })  : names = List<String>.from(names ?? pwoDefaultNames),
        months = months ?? {},
        tags = tags ?? {};

  final List<String> names;
  double target;
  final Map<String, PwoMonth> months;
  final Set<String> tags;

  /// Adds the 1405 Excel rows once. Never overwrites a month already present.
  bool applySeed() {
    if (tags.contains(pwoSeedTag)) return false;
    pwoSeed1405Millions.forEach((m, vals) {
      final k = pwoMonthKey(1405, m);
      months.putIfAbsent(
        k,
        () => PwoMonth(
          year: 1405,
          month: m,
          amounts: vals.map((v) => (v * 1000000).roundToDouble()).toList(),
        ),
      );
    });
    tags.add(pwoSeedTag);
    return true;
  }

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

  List<double> personTotals(int year) {
    final t = <double>[0, 0, 0];
    for (final m in monthsOf(year)) {
      for (var i = 0; i < 3; i++) {
        t[i] += m.amounts[i];
      }
    }
    return t;
  }

  int monthsMeeting(int year) =>
      monthsOf(year).where((m) => m.meets(target)).length;

  /// Previous calendar month's total (crosses year boundary). Null when absent.
  PwoMonth? previousOf(PwoMonth m) {
    final py = m.month == 1 ? m.year - 1 : m.year;
    final pm = m.month == 1 ? 12 : m.month - 1;
    return months[pwoMonthKey(py, pm)];
  }

  void upsert(PwoMonth m) => months[m.key] = m;
  void remove(int year, int month) => months.remove(pwoMonthKey(year, month));

  String encode() => jsonEncode({
        'v': 1,
        'names': names,
        'target': target,
        'tags': tags.toList(),
        'months': months.values.map((e) => e.toJson()).toList(),
      });

  static PwoLedger decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return PwoLedger();
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return PwoLedger();
      final names = <String>[...pwoDefaultNames];
      final n = j['names'];
      if (n is List) {
        for (var i = 0; i < 3 && i < n.length; i++) {
          final s = n[i]?.toString().trim() ?? '';
          if (s.isNotEmpty) names[i] = s;
        }
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
      return PwoLedger(names: names, target: target, months: months, tags: tags);
    } catch (_) {
      return PwoLedger();
    }
  }
}

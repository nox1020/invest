import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/year_nav_entry.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';

/// Compare live NAV against a prior year-end figure for annual growth.
class YearNavCompare {
  const YearNavCompare({
    required this.currentNav,
    required this.currentYearKey,
    this.prior,
    this.liveUsdt,
    this.currentNavUsd,
  });

  final double currentNav;
  final String currentYearKey;
  final YearNavEntry? prior;
  final double? liveUsdt;
  final double? currentNavUsd;

  bool get hasPrior => prior != null && prior!.navToman > 0;

  String get priorYearKey => prior?.yearKey ?? '';

  double get deltaToman =>
      hasPrior ? currentNav - prior!.navToman : 0;

  double get pct =>
      hasPrior && prior!.navToman > 0 ? deltaToman / prior!.navToman * 100 : 0;

  double? get deltaUsd {
    if (!hasPrior) return null;
    final priorUsd = prior!.navUsdWith(liveUsdt);
    final currentUsd =
        currentNavUsd ?? tomanToUsd(currentNav, liveUsdt);
    if (priorUsd == null || currentUsd == null) return null;
    return currentUsd - priorUsd;
  }

  static YearNavCompare fromHistory({
    required double currentNav,
    required String currentYearKey,
    required List<YearNavEntry> history,
    double? liveUsdt,
    double? currentNavUsd,
  }) {
    final priorKey = YearNavList.priorYearKey(currentYearKey);
    final prior =
        priorKey.isEmpty ? null : YearNavList.find(history, priorKey);
    return YearNavCompare(
      currentNav: currentNav,
      currentYearKey: currentYearKey,
      prior: prior,
      liveUsdt: liveUsdt,
      currentNavUsd: currentNavUsd,
    );
  }
}

/// Ascending year-end + live NAV series for dual-currency annual growth chart.
List<SeriesPoint> yearNavGrowthSeries({
  required List<YearNavEntry> history,
  required double currentNav,
  required String currentYearKey,
  required String calendar,
  double? liveUsdt,
  double? currentNavUsd,
}) {
  final sorted = [...history]
    ..sort((a, b) => a.yearKey.compareTo(b.yearKey));
  final out = <SeriesPoint>[];
  for (final e in sorted) {
    out.add(
      SeriesPoint(
        date: YearNavList.yearEndIso(e.yearKey, calendar),
        value: e.navToman,
        usdValue: e.navUsdWith(liveUsdt),
      ),
    );
  }
  if (currentNav > 0 && currentYearKey.isNotEmpty) {
    final already = sorted.any((e) => e.yearKey == currentYearKey);
    if (!already) {
      out.add(
        SeriesPoint(
          date: todayIso(),
          value: currentNav,
          usdValue: currentNavUsd ?? tomanToUsd(currentNav, liveUsdt),
        ),
      );
    }
  }
  return out;
}

/// Parse a free-text Toman amount (Persian digits, optional میلیارد/میلیون).
double? parseTomanAmount(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return null;
  t = _asciiDigits(t)
      .replaceAll(',', '')
      .replaceAll('،', '')
      .replaceAll('٬', '')
      .replaceAll(' ', '');
  var mult = 1.0;
  if (t.contains('میلیارد') || t.toLowerCase().contains('b')) {
    mult = 1e9;
    t = t
        .replaceAll('میلیارد', '')
        .replaceAll(RegExp(r'[bB]'), '')
        .trim();
  } else if (t.contains('میلیون') || t.toLowerCase().contains('m')) {
    mult = 1e6;
    t = t
        .replaceAll('میلیون', '')
        .replaceAll(RegExp(r'[mM]'), '')
        .trim();
  }
  final n = double.tryParse(t);
  if (n == null || n <= 0) return null;
  return n * mult;
}

/// Parse a free-text USD amount (optional k/m suffixes).
double? parseUsdAmount(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return null;
  t = _asciiDigits(t)
      .replaceAll(',', '')
      .replaceAll('،', '')
      .replaceAll('٬', '')
      .replaceAll(r'$', '')
      .replaceAll(' ', '');
  var mult = 1.0;
  if (t.toLowerCase().endsWith('m') || t.contains('میلیون')) {
    mult = 1e6;
    t = t
        .replaceAll(RegExp(r'[mM]$'), '')
        .replaceAll('میلیون', '')
        .trim();
  } else if (t.toLowerCase().endsWith('k') || t.contains('هزار')) {
    mult = 1e3;
    t = t
        .replaceAll(RegExp(r'[kK]$'), '')
        .replaceAll('هزار', '')
        .trim();
  }
  final n = double.tryParse(t);
  if (n == null || n <= 0) return null;
  return n * mult;
}

String _asciiDigits(String s) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final buf = StringBuffer();
  for (final c in s.split('')) {
    final fi = fa.indexOf(c);
    if (fi >= 0) {
      buf.write(fi);
      continue;
    }
    final ai = ar.indexOf(c);
    if (ai >= 0) {
      buf.write(ai);
      continue;
    }
    buf.write(c);
  }
  return buf.toString();
}

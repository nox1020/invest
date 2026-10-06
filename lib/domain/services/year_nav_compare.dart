import 'package:invest/domain/models/year_nav_entry.dart';
import 'package:invest/domain/utils/money.dart';

/// Compare live NAV against a prior year-end figure for annual growth.
class YearNavCompare {
  const YearNavCompare({
    required this.currentNav,
    required this.currentYearKey,
    this.prior,
    this.liveUsdt,
  });

  final double currentNav;
  final String currentYearKey;
  final YearNavEntry? prior;
  final double? liveUsdt;

  bool get hasPrior => prior != null && prior!.navToman > 0;

  String get priorYearKey => prior?.yearKey ?? '';

  double get deltaToman =>
      hasPrior ? currentNav - prior!.navToman : 0;

  double get pct =>
      hasPrior && prior!.navToman > 0 ? deltaToman / prior!.navToman * 100 : 0;

  double? get deltaUsd {
    if (!hasPrior) return null;
    final priorUsd = prior!.navUsdWith(liveUsdt);
    final currentUsd = tomanToUsd(currentNav, liveUsdt);
    if (priorUsd == null || currentUsd == null) return null;
    return currentUsd - priorUsd;
  }

  static YearNavCompare fromHistory({
    required double currentNav,
    required String currentYearKey,
    required List<YearNavEntry> history,
    double? liveUsdt,
  }) {
    final priorKey = YearNavList.priorYearKey(currentYearKey);
    final prior =
        priorKey.isEmpty ? null : YearNavList.find(history, priorKey);
    return YearNavCompare(
      currentNav: currentNav,
      currentYearKey: currentYearKey,
      prior: prior,
      liveUsdt: liveUsdt,
    );
  }
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

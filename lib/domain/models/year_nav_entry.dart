import 'dart:convert';

import 'package:invest/domain/utils/money.dart';

/// Year-end portfolio NAV entered as a single Toman figure.
///
/// USD is derived from [usdtRate] captured when the row was saved (or a
/// live fallback supplied by the caller).
class YearNavEntry {
  const YearNavEntry({
    required this.yearKey,
    required this.navToman,
    this.usdtRate,
    this.updatedAt = '',
  });

  /// Calendar year key (`1403`, `2024`, …) matching [yearPeriodKey].
  final String yearKey;
  final double navToman;

  /// USDT/TMN rate frozen at save time so the dollar leg stays stable.
  final double? usdtRate;
  final String updatedAt;

  double? get navUsd => tomanToUsd(navToman, usdtRate);

  double? navUsdWith(double? fallbackUsdt) =>
      tomanToUsd(navToman, (usdtRate != null && usdtRate! > 0) ? usdtRate : fallbackUsdt);

  YearNavEntry copyWith({
    String? yearKey,
    double? navToman,
    double? usdtRate,
    String? updatedAt,
    bool clearUsdtRate = false,
  }) {
    return YearNavEntry(
      yearKey: yearKey ?? this.yearKey,
      navToman: navToman ?? this.navToman,
      usdtRate: clearUsdtRate ? null : (usdtRate ?? this.usdtRate),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'year': yearKey,
        'nav_toman': navToman,
        if (usdtRate != null) 'usdt_tmn': usdtRate,
        if (updatedAt.isNotEmpty) 'updated_at': updatedAt,
      };

  factory YearNavEntry.fromJson(Map<String, dynamic> m) {
    final year = '${m['year'] ?? m['year_key'] ?? ''}'.trim();
    final nav = _d(m['nav_toman'] ?? m['nav'] ?? m['total_value']) ?? 0;
    return YearNavEntry(
      yearKey: year,
      navToman: nav,
      usdtRate: _d(m['usdt_tmn'] ?? m['usdt_rate'] ?? m['usdtTmn']),
      updatedAt: '${m['updated_at'] ?? ''}'.trim(),
    );
  }

  static double? _d(dynamic v) {
    if (v == null || v == '') return null;
    if (v is num) return v.toDouble();
    final t = '$v'.trim().replaceAll(',', '').replaceAll('،', '');
    return double.tryParse(_toAsciiDigits(t));
  }

  static String _toAsciiDigits(String s) {
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
}

/// JSON list codec for settings / backups / Vinor extras.
class YearNavList {
  static List<YearNavEntry> parse(dynamic v) {
    if (v == null) return [];
    dynamic raw = v;
    if (raw is String) {
      final t = raw.trim();
      if (t.isEmpty) return [];
      try {
        raw = jsonDecode(t);
      } catch (_) {
        return [];
      }
    }
    if (raw is! List) return [];
    final out = <YearNavEntry>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final e = YearNavEntry.fromJson(Map<String, dynamic>.from(item));
      if (e.yearKey.isEmpty || e.navToman <= 0) continue;
      if (!seen.add(e.yearKey)) continue;
      out.add(e);
    }
    out.sort((a, b) => b.yearKey.compareTo(a.yearKey));
    return out;
  }

  static String encode(List<YearNavEntry> rows) =>
      jsonEncode(rows.map((e) => e.toJson()).toList());

  static List<YearNavEntry> upsert(
    List<YearNavEntry> rows,
    YearNavEntry entry,
  ) {
    final next = [
      for (final e in rows)
        if (e.yearKey != entry.yearKey) e,
      entry,
    ];
    next.sort((a, b) => b.yearKey.compareTo(a.yearKey));
    return next;
  }

  static List<YearNavEntry> remove(List<YearNavEntry> rows, String yearKey) {
    return [
      for (final e in rows)
        if (e.yearKey != yearKey) e,
    ];
  }

  static YearNavEntry? find(List<YearNavEntry> rows, String yearKey) {
    for (final e in rows) {
      if (e.yearKey == yearKey) return e;
    }
    return null;
  }

  /// Year key immediately before [yearKey] (Jalali or Gregorian digit year).
  static String priorYearKey(String yearKey) {
    final y = int.tryParse(yearKey.trim());
    if (y == null) return '';
    return (y - 1).toString().padLeft(4, '0');
  }
}

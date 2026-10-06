import 'dart:convert';

import 'package:invest/config/app_config.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:shamsi_date/shamsi_date.dart';

/// Year-end portfolio NAV: Toman required, USD optional (manual or derived).
class YearNavEntry {
  const YearNavEntry({
    required this.yearKey,
    required this.navToman,
    this.navUsd,
    this.usdtRate,
    this.updatedAt = '',
  });

  /// Calendar year key (`1403`, `2024`, …) matching [yearPeriodKey].
  final String yearKey;
  final double navToman;

  /// Optional manual USD NAV. When set, takes priority over rate conversion.
  final double? navUsd;

  /// USDT/TMN rate used when [navUsd] is absent (auto or implied from edit).
  final double? usdtRate;
  final String updatedAt;

  /// Prefer manual USD, else Toman ÷ stored rate.
  double? get resolvedUsd {
    if (navUsd != null && navUsd! > 0) return navUsd;
    return tomanToUsd(navToman, usdtRate);
  }

  double? navUsdWith(double? fallbackUsdt) {
    if (navUsd != null && navUsd! > 0) return navUsd;
    final rate =
        (usdtRate != null && usdtRate! > 0) ? usdtRate : fallbackUsdt;
    return tomanToUsd(navToman, rate);
  }

  YearNavEntry copyWith({
    String? yearKey,
    double? navToman,
    double? navUsd,
    double? usdtRate,
    String? updatedAt,
    bool clearNavUsd = false,
    bool clearUsdtRate = false,
  }) {
    return YearNavEntry(
      yearKey: yearKey ?? this.yearKey,
      navToman: navToman ?? this.navToman,
      navUsd: clearNavUsd ? null : (navUsd ?? this.navUsd),
      usdtRate: clearUsdtRate ? null : (usdtRate ?? this.usdtRate),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'year': yearKey,
        'nav_toman': navToman,
        if (navUsd != null) 'nav_usd': navUsd,
        if (usdtRate != null) 'usdt_tmn': usdtRate,
        if (updatedAt.isNotEmpty) 'updated_at': updatedAt,
      };

  factory YearNavEntry.fromJson(Map<String, dynamic> m) {
    final year = YearNavList.normalizeYearKey(
      '${m['year'] ?? m['year_key'] ?? ''}',
    );
    final nav = _d(m['nav_toman'] ?? m['nav'] ?? m['total_value']) ?? 0;
    final usd = _d(m['nav_usd'] ?? m['usd'] ?? m['navUsd']);
    var rate = _d(m['usdt_tmn'] ?? m['usdt_rate'] ?? m['usdtTmn']);
    // Legacy rows: imply rate from manual USD when missing.
    if ((rate == null || rate <= 0) &&
        usd != null &&
        usd > 0 &&
        nav > 0) {
      rate = nav / usd;
    }
    return YearNavEntry(
      yearKey: year,
      navToman: nav,
      navUsd: (usd != null && usd > 0) ? usd : null,
      usdtRate: (rate != null && rate > 0) ? rate : null,
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
    final y = int.tryParse(normalizeYearKey(yearKey));
    if (y == null) return '';
    return (y - 1).toString().padLeft(4, '0');
  }

  /// Normalize free-text year to a 4-digit key (`۱۴۰۴` → `1404`).
  static String normalizeYearKey(String raw) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    const ar = '٠١٢٣٤٥٦٧٨٩';
    final buf = StringBuffer();
    for (final c in raw.trim().split('')) {
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
      if (RegExp(r'[0-9]').hasMatch(c)) buf.write(c);
    }
    final digits = buf.toString();
    if (digits.isEmpty) return '';
    final y = int.tryParse(digits);
    if (y == null || y <= 0) return '';
    return y.toString().padLeft(4, '0');
  }

  /// Gregorian ISO for the last day of [yearKey] in [calendar].
  static String yearEndIso(String yearKey, String calendar) {
    final y = int.tryParse(normalizeYearKey(yearKey));
    if (y == null) return todayIso();
    if (calendar == AppConfig.calendarJalali) {
      try {
        final last = Jalali(y, 12, 1).monthLength;
        return toIsoDate(Jalali(y, 12, last).toDateTime());
      } catch (_) {
        return toIsoDate(Jalali(y, 12, 29).toDateTime());
      }
    }
    return '${y.toString().padLeft(4, '0')}-12-31';
  }
}

import 'package:invest/config/app_config.dart';
import 'package:shamsi_date/shamsi_date.dart';

const jalaliMonthNamesFa = [
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];

String toIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String todayIso() => toIsoDate(DateTime.now());

String nowIso() => DateTime.now().toUtc().toIso8601String().split('.').first;

DateTime parseIsoDate(String value) {
  if (value.isEmpty) return DateTime.now();
  final s = value.contains('T') ? value.split('T').first : value.substring(0, 10);
  return DateTime.parse(s);
}

/// Normalize free-text or ISO dates to `YYYY-MM-DD` when possible.
///
/// Accepts Gregorian ISO and common Jalali `1402/05/01` / `1402-05-01` forms.
String? tryNormalizeToIso(String? raw) {
  if (raw == null) return null;
  final t = _asciiDateDigits(raw).trim();
  if (t.isEmpty) return null;
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
  if (iso != null) {
    final y = int.parse(iso.group(1)!);
    // Years > 1500 are treated as Gregorian ISO.
    if (y > 1500) return '${iso.group(1)}-${iso.group(2)}-${iso.group(3)}';
  }
  final slash = RegExp(r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$').firstMatch(t);
  if (slash == null) return null;
  final y = int.parse(slash.group(1)!);
  final m = int.parse(slash.group(2)!);
  final d = int.parse(slash.group(3)!);
  if (y > 1500) {
    return toIsoDate(DateTime(y, m, d));
  }
  try {
    final j = Jalali(y, m, d);
    return toIsoDate(j.toDateTime());
  } catch (_) {
    return null;
  }
}

/// Yearly period key matching desktop `period_key(..., "yearly", calendar)`.
String yearPeriodKey(String isoDate, String calendar) {
  final d = parseIsoDate(isoDate);
  if (calendar == AppConfig.calendarJalali) {
    final j = Jalali.fromDateTime(d);
    return j.year.toString().padLeft(4, '0');
  }
  return d.year.toString().padLeft(4, '0');
}

String formatDisplayDate(String? iso, String calendar) {
  if (iso == null || iso.isEmpty) return '—';
  final d = parseIsoDate(iso);
  if (calendar == AppConfig.calendarJalali) {
    final j = Jalali.fromDateTime(d);
    return '${j.day.toString().padLeft(2, '0')} ${jalaliMonthNamesFa[j.month - 1]} ${j.year}';
  }
  return toIsoDate(d);
}

/// Display helper for ISO or legacy free-text dates (asset meta, etc.).
String formatFlexibleDisplayDate(String? value, String calendar) {
  if (value == null || value.trim().isEmpty) return '—';
  final iso = tryNormalizeToIso(value);
  if (iso != null) return formatDisplayDate(iso, calendar);
  return value.trim();
}

/// Compact tick label for charts (`۱۵/۰۵` style).
String formatChartTickDate(String iso, String calendar) {
  if (iso.isEmpty) return '—';
  final d = parseIsoDate(iso);
  if (calendar == AppConfig.calendarJalali) {
    final j = Jalali.fromDateTime(d);
    return '${j.day.toString().padLeft(2, '0')}/${j.month.toString().padLeft(2, '0')}';
  }
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

int holdingDays(String buyDate, String sellDate) {
  final a = parseIsoDate(buyDate);
  final b = parseIsoDate(sellDate);
  return b.difference(a).inDays;
}

/// Calendar days an open lot has been held, never negative.
String _asciiDateDigits(String raw) {
  final buf = StringBuffer();
  for (final rune in raw.runes) {
    final ch = String.fromCharCode(rune);
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final pi = persian.indexOf(ch);
    if (pi >= 0) {
      buf.write(pi);
      continue;
    }
    final ai = arabic.indexOf(ch);
    if (ai >= 0) {
      buf.write(ai);
      continue;
    }
    buf.write(ch);
  }
  return buf.toString();
}

/// Tehran is UTC+3:30 all year (Iran dropped daylight saving in 2022).
const Duration kTehranUtcOffset = Duration(hours: 3, minutes: 30);

/// Today's `YYYY-MM-DD` on the Tehran calendar, whatever the device zone.
String tehranTodayIso({DateTime? now}) => toIsoDate((now ?? DateTime.now()).toUtc().add(kTehranUtcOffset));

/// Whole Tehran calendar days an open lot has been held: 0 on its buy day,
/// 1 from the next midnight in Tehran. Reads ISO (`2026-01-05`, with or
/// without a time) and Jalali (`1404/10/15`, Persian digits) buy dates;
/// null when the date can't be read. Never negative (a future date is 0).
/// Counted on UTC dates, so device daylight-saving shifts can't drop a day.
int? lotOpenDays(String? buyDate, {DateTime? now}) {
  final iso = tryNormalizeToIso(buyDate);
  if (iso == null) return null;
  DateTime day(String s) {
    final p = s.split('-');
    return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  final d = day(tehranTodayIso(now: now)).difference(day(iso)).inDays;
  return d < 0 ? 0 : d;
}

int openHoldingDays(String buyDate, {String? asOf}) {
  if (buyDate.trim().isEmpty) return 0;
  final days = holdingDays(buyDate, asOf ?? todayIso());
  return days < 0 ? 0 : days;
}

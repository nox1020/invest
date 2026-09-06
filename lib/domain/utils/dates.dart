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
  final t = raw.trim();
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
int openHoldingDays(String buyDate, {String? asOf}) {
  if (buyDate.trim().isEmpty) return 0;
  final days = holdingDays(buyDate, asOf ?? todayIso());
  return days < 0 ? 0 : days;
}

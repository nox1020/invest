import 'package:shamsi_date/shamsi_date.dart';

/// Parses a Jalali date the way vinor biz_api does (Y/M/D or D/M/Y,
/// Persian/Arabic digits ok, year 1300–1600). Null when invalid.
Jalali? parseBizDate(String raw) {
  const fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final r in raw.trim().runes) {
    final ch = String.fromCharCode(r);
    final i = fa.indexOf(ch), k = ar.indexOf(ch);
    b.write(i >= 0 ? '$i' : k >= 0 ? '$k' : ch);
  }
  final m = RegExp(r'^(\d{1,4})[/\-.](\d{1,2})[/\-.](\d{1,4})$').firstMatch(b.toString());
  if (m == null) return null;
  final a = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), c = int.parse(m.group(3)!);
  final y = a > 31 ? a : c, d = a > 31 ? c : a;
  if (y < 1300 || y > 1600 || mo < 1 || mo > 12 || d < 1) return null;
  try {
    final j = Jalali(y, mo, d);
    if (d > j.monthLength) return null;
    return j;
  } catch (_) {
    return null;
  }
}

/// 'YYYY/MM/DD' (the server's canonical form).
String bizDateText(Jalali j) =>
    '${j.year.toString().padLeft(4, '0')}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';

/// Canonical 'YYYY/MM/DD' for a parsable date; trimmed input otherwise
/// (empty stays empty, so the server can still reject a bad value).
String normalizeBizDate(Object? raw) {
  final s = '${raw ?? ''}'.trim();
  if (s.isEmpty) return '';
  final j = parseBizDate(s);
  return j == null ? s : bizDateText(j);
}

/// Jalali month key 'YYYY/MM' of a biz date, or null when empty/invalid.
String? bizMonthKey(String raw) {
  final j = raw.trim().isEmpty ? null : parseBizDate(raw);
  return j == null ? null : bizMonthKeyOf(j.year, j.month);
}

String bizMonthKeyOf(int year, int month) =>
    '${year.toString().padLeft(4, '0')}/${month.toString().padLeft(2, '0')}';

/// The phone's current Jalali year (sent to the server so its timezone
/// never decides which year is "this year").
int currentJalaliYear([DateTime? now]) => Jalali.fromDateTime(now ?? DateTime.now()).year;

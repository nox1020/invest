import 'package:shamsi_date/shamsi_date.dart';

String todayIso() {
  final n = DateTime.now().toUtc();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

String nowIso() => DateTime.now().toUtc().toIso8601String().split('.').first;

DateTime parseIsoDate(String value) {
  if (value.isEmpty) return DateTime.now();
  final s = value.contains('T') ? value.split('T').first : value.substring(0, 10);
  return DateTime.parse(s);
}

/// Yearly period key matching desktop `period_key(..., "yearly", calendar)`.
String yearPeriodKey(String isoDate, String calendar) {
  final d = parseIsoDate(isoDate);
  if (calendar == 'jalali') {
    final j = Jalali.fromDateTime(d);
    return j.year.toString().padLeft(4, '0');
  }
  return d.year.toString().padLeft(4, '0');
}

String formatDisplayDate(String? iso, String calendar) {
  if (iso == null || iso.isEmpty) return '—';
  final d = parseIsoDate(iso);
  if (calendar == 'jalali') {
    final j = Jalali.fromDateTime(d);
    const months = [
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
    return '${j.day.toString().padLeft(2, '0')} ${months[j.month - 1]} ${j.year}';
  }
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

int holdingDays(String buyDate, String sellDate) {
  final a = parseIsoDate(buyDate);
  final b = parseIsoDate(sellDate);
  return b.difference(a).inDays;
}

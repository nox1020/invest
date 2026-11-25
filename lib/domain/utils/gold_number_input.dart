// Number parsing for the «صندوق طلا» inputs (Persian, Arabic or Latin
// digits; Persian keyboards send «٫» as the decimal mark and «٬» as the
// thousands mark, some keyboards send «,» as the decimal mark).

const _persian = '۰۱۲۳۴۵۶۷۸۹';
const _arabic = '٠١٢٣٤٥٦٧٨٩';

/// Latin digits; other characters unchanged; spaces and bidi marks dropped.
String _latinDigits(String raw) {
  final b = StringBuffer();
  for (final r in raw.trim().runes) {
    final ch = String.fromCharCode(r);
    final p = _persian.indexOf(ch);
    if (p >= 0) {
      b.write(p);
      continue;
    }
    final a = _arabic.indexOf(ch);
    if (a >= 0) {
      b.write(a);
      continue;
    }
    if (ch == ' ' || ch == '\u200f' || ch == '\u200e' || ch == '\u200c' || ch == '\u00a0') continue;
    b.write(ch);
  }
  return b.toString();
}

final _thousandsGroups = RegExp(r'^\d{1,3}([.,]\d{3})+$');

/// A weight, percent or other decimal value. «٫», «.» and a lone «,» are the
/// decimal mark («2,5» is 2.5 g, never 25 g); «٬» and «,» between groups of
/// three digits next to a «.» are thousands marks. Null when not a number.
double? parseGoldDecimal(String? raw) {
  if (raw == null) return null;
  var t = _latinDigits(raw).replaceAll('٬', '').replaceAll('٫', '.');
  if (t.isEmpty) return null;
  final commas = ','.allMatches(t).length;
  if (commas > 0) {
    if (t.contains('.') || commas > 1) {
      t = t.replaceAll(',', ''); // «1,234.5» or «1,234,567»
    } else {
      t = t.replaceAll(',', '.'); // «2,5»
    }
  }
  final v = double.tryParse(t);
  return v != null && v.isFinite ? v : null;
}

/// A Toman amount. Every «,» «٬» and a «.»/«٫» that only splits groups of
/// three digits («100.000.000») are thousands marks; any other «.»/«٫» is a
/// decimal mark. Null when not a number.
double? parseGoldToman(String? raw) {
  if (raw == null) return null;
  var t = _latinDigits(raw).replaceAll('٫', '.').replaceAll(',', '').replaceAll('٬', '');
  if (t.isEmpty) return null;
  if (_thousandsGroups.hasMatch(t)) t = t.replaceAll('.', '');
  final v = double.tryParse(t);
  return v != null && v.isFinite ? v : null;
}

/// `1234567` → `1,234,567` (Latin digits, for an LTR money field). Only the
/// integer part is kept.
String groupTomanDigits(String raw) {
  final digits = _latinDigits(raw).replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (digits.isEmpty) return '';
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return b.toString();
}

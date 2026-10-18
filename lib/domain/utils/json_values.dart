/// JSON values from Vinor are not always the Dart type the field name suggests.
///
/// A whole number may arrive as a [double] (`1.0`), and a quantity may arrive
/// as a string. Calling `as int` or `toDouble()` on those throws and used to
/// abort the dashboard load.
int? jsonInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final text = _foldNumericText(value.toString());
  if (text.isEmpty) return null;
  return int.tryParse(text) ?? double.tryParse(text)?.toInt();
}

double? jsonDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final text = _foldNumericText(value.toString());
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

/// Persian and Arabic-Indic digits, plus the Arabic decimal separator.
String _foldNumericText(String raw) {
  final buf = StringBuffer();
  for (final code in raw.trim().runes) {
    if (code >= 0x06F0 && code <= 0x06F9) {
      buf.writeCharCode(0x30 + (code - 0x06F0));
    } else if (code >= 0x0660 && code <= 0x0669) {
      buf.writeCharCode(0x30 + (code - 0x0660));
    } else if (code == 0x066B) {
      buf.write('.');
    } else if (code == 0x066C || code == 0x060C || code == 0x2C) {
      continue;
    } else {
      buf.writeCharCode(code);
    }
  }
  return buf.toString().replaceAll('٬', '').trim();
}

String jsonText(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return fallback;
}

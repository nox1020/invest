/// JSON values from Vinor are not always the Dart type the field name suggests.
///
/// A whole number may arrive as a [double] (`1.0`), and a quantity may arrive
/// as a string. Calling `as int` or `toDouble()` on those throws and used to
/// abort the dashboard load.
int? jsonInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return int.tryParse(text) ?? double.tryParse(text)?.toInt();
}

double? jsonDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final text = value.toString().trim().replaceAll(',', '').replaceAll('٬', '');
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

String jsonText(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return fallback;
}

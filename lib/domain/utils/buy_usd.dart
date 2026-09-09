/// Optional USD buy price and USDT/TMN rate packed into trade `buy_note`.
///
/// Format: `[buy_usd:12.34] [buy_fx:100000]` prefixes, then free-text note.
/// `buy_fx` is Toman per 1 USD (the dollar's Toman price on the buy date).
final _buyUsdRe =
    RegExp(r'\[buy_usd:([0-9]+(?:\.[0-9]+)?)\]\s*', caseSensitive: false);
final _buyFxRe =
    RegExp(r'\[buy_fx:([0-9]+(?:\.[0-9]+)?)\]\s*', caseSensitive: false);

({double? usd, double? fx, String note}) parseBuyNoteUsd(String? raw) {
  var text = (raw ?? '').trim();
  if (text.isEmpty) return (usd: null, fx: null, note: '');
  double? usd;
  double? fx;
  final um = _buyUsdRe.firstMatch(text);
  if (um != null) {
    usd = double.tryParse(um.group(1)!);
    text = text.replaceFirst(_buyUsdRe, '').trim();
  }
  final fm = _buyFxRe.firstMatch(text);
  if (fm != null) {
    fx = double.tryParse(fm.group(1)!);
    text = text.replaceFirst(_buyFxRe, '').trim();
  }
  // Tags may appear in either order; strip leftover usd tag after fx.
  final um2 = _buyUsdRe.firstMatch(text);
  if (um2 != null) {
    usd ??= double.tryParse(um2.group(1)!);
    text = text.replaceFirst(_buyUsdRe, '').trim();
  }
  return (usd: usd, fx: fx, note: text);
}

String encodeBuyNoteUsd({double? usd, double? fx, String note = ''}) {
  final free = note.trim();
  final parts = <String>[];
  if (usd != null && usd > 0) {
    parts.add('[buy_usd:${_packNum(usd)}]');
  }
  if (fx != null && fx > 0) {
    parts.add('[buy_fx:${_packNum(fx)}]');
  }
  if (free.isNotEmpty) parts.add(free);
  return parts.join(' ');
}

String _packNum(double v) {
  if ((v - v.roundToDouble()).abs() < 1e-12) return '${v.round()}';
  return v.toString();
}

double? readBuyPriceUsd({
  Object? columnValue,
  String? buyNote,
}) {
  if (columnValue is num && columnValue.toDouble() > 0) {
    return columnValue.toDouble();
  }
  if (columnValue is String) {
    final parsed = double.tryParse(columnValue);
    if (parsed != null && parsed > 0) return parsed;
  }
  return parseBuyNoteUsd(buyNote).usd;
}

/// Toman per 1 USD implied by unit Toman price ÷ unit USD price.
double? impliedBuyUsdTmn({required double buyToman, double? buyUsd}) {
  if (buyUsd == null || buyUsd <= 0 || buyToman <= 0) return null;
  return buyToman / buyUsd;
}

/// Stored `[buy_fx]` rate, else Toman ÷ registered USD.
double? resolveBuyUsdTmn({
  double? storedFx,
  required double buyToman,
  double? buyUsd,
}) {
  if (storedFx != null && storedFx > 0) return storedFx;
  return impliedBuyUsdTmn(buyToman: buyToman, buyUsd: buyUsd);
}

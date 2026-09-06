/// Optional USD buy price packed into trade `buy_note` for Vinor round-trip.
///
/// Format: `[buy_usd:12.34]` prefix, then free-text note.
final _buyUsdRe = RegExp(r'\[buy_usd:([0-9]+(?:\.[0-9]+)?)\]\s*', caseSensitive: false);

({double? usd, String note}) parseBuyNoteUsd(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return (usd: null, note: '');
  final m = _buyUsdRe.firstMatch(text);
  if (m == null) return (usd: null, note: text);
  final usd = double.tryParse(m.group(1)!);
  final note = text.replaceFirst(_buyUsdRe, '').trim();
  return (usd: usd, note: note);
}

String encodeBuyNoteUsd({double? usd, String note = ''}) {
  final free = note.trim();
  final parts = <String>[];
  if (usd != null && usd > 0) {
    final s = (usd - usd.roundToDouble()).abs() < 1e-12
        ? '${usd.round()}'
        : usd.toString();
    parts.add('[buy_usd:$s]');
  }
  if (free.isNotEmpty) parts.add(free);
  return parts.join(' ');
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

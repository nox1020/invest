import 'dart:math';

/// Hidden marker on trades recorded from the «صندوق طلا» page.
///
/// `[gf:<id>]` sits in the free-text part of `buy_note` (buy) or `sell_note`
/// (sell). The fund's cash moves are derived from tagged trades, so the cash
/// balance can never drift from the trades themselves. The id groups the
/// pieces of one operation (a partial close copies the buy note; a sale over
/// several lots writes the same id on each closed piece).
///
/// The marker is never shown: `Trade.buyNoteDisplay` / `sellNoteDisplay`
/// strip it, and editing a note keeps it (see [carryGoldFundTag]).
final RegExp _gfRe = RegExp(r'\[gf(?::([a-z0-9]+))?\]\s*', caseSensitive: false);

/// True when [note] carries a gold-fund marker.
bool hasGoldFundTag(String? note) => note != null && _gfRe.hasMatch(note);

/// The operation id inside the marker (`''` for a bare `[gf]`), or null.
String? goldFundTagId(String? note) {
  if (note == null) return null;
  final m = _gfRe.firstMatch(note);
  if (m == null) return null;
  return (m.group(1) ?? '').toLowerCase();
}

/// [note] without the marker.
String stripGoldFundTag(String? note) => (note ?? '').replaceAll(_gfRe, '').trim();

/// `[gf:<id>] note` (one marker, first).
String withGoldFundTag(String note, String id) {
  final free = stripGoldFundTag(note);
  final tag = '[gf:${id.toLowerCase()}]';
  return free.isEmpty ? tag : '$tag $free';
}

/// Keeps the marker of [previous] on an edited free-text [next].
String carryGoldFundTag(String? previous, String next) {
  final id = goldFundTagId(previous);
  if (id == null) return next;
  if (hasGoldFundTag(next)) return next;
  final free = next.trim();
  final tag = id.isEmpty ? '[gf]' : '[gf:$id]';
  return free.isEmpty ? tag : '$tag $free';
}

final Random _rnd = Random();

/// Short unique id for one fund operation (base36 time + random).
String newGoldFundOpId([DateTime? now]) {
  final t = (now ?? DateTime.now()).microsecondsSinceEpoch.toRadixString(36);
  final r = _rnd.nextInt(1 << 30).toRadixString(36).padLeft(6, '0');
  return '$t$r';
}

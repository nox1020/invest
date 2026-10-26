/// Persian-friendly text folding for search: Arabic ي/ك/ة/أإآ → Persian,
/// Persian/Arabic digits → Latin, ZWNJ/tatweel/diacritics removed, spaces
/// collapsed, lower-case.
String foldFa(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    var c = r;
    if (c >= 0x06F0 && c <= 0x06F9) c = 0x30 + c - 0x06F0; // ۰-۹
    if (c >= 0x0660 && c <= 0x0669) c = 0x30 + c - 0x0660; // ٠-٩
    switch (c) {
      case 0x064A || 0x0649 || 0x06CC: c = 0x06CC; // ي ى → ی
      case 0x0643: c = 0x06A9; // ك → ک
      case 0x0629: c = 0x0647; // ة → ه
      case 0x0623 || 0x0625 || 0x0622 || 0x0671: c = 0x0627; // أ إ آ → ا
      case 0x0624: c = 0x0648; // ؤ → و
    }
    if (c == 0x200C || c == 0x200D || c == 0x0640 || c == 0x200F || c == 0x200E) {
      b.write(' ');
      continue;
    }
    if (c >= 0x064B && c <= 0x065F) continue; // harakat
    b.writeCharCode(c);
  }
  return b.toString().toLowerCase().replaceAll(RegExp(r'[\s,،٬_\-/]+'), ' ').trim();
}

enum SearchKind { cheque, asset, trade, property, project, pwo, withdrawal, ads, sms, alert }

extension SearchKindX on SearchKind {
  String get label => switch (this) {
        SearchKind.cheque => 'چک‌ها',
        SearchKind.asset => 'دارایی‌ها',
        SearchKind.trade => 'معاملات',
        SearchKind.property => 'معاملات ملک',
        SearchKind.project => 'پروژه‌ها',
        SearchKind.pwo => 'PWO',
        SearchKind.withdrawal => 'برداشت سیستم',
        SearchKind.ads => 'تبلیغات',
        SearchKind.sms => 'پیامک بانکی',
        SearchKind.alert => 'هشدار قیمت',
      };
}

/// One searchable record. [fields] are matched; [ref] is the source object
/// the UI uses to open its page.
class SearchItem {
  SearchItem({required this.kind, required this.title, this.subtitle = '', required List<String> fields, this.ref})
      : _hay = foldFa(fields.join(' | ')),
        _hayTight = foldFa(fields.join(' | ')).replaceAll(' ', '');
  final SearchKind kind;
  final String title;
  final String subtitle;
  final Object? ref;
  final String _hay;
  final String _hayTight;

  /// Every query word must appear (order free). Digits also match with
  /// spaces/commas removed, so «۱۲۳ ۴۵۶» finds «123456».
  bool matches(String query) {
    final q = foldFa(query);
    if (q.isEmpty) return false;
    final words = q.split(' ');
    if (words.every(_hay.contains)) return true;
    return _hayTight.contains(q.replaceAll(' ', ''));
  }
}

/// Matches grouped by kind (kind order kept), at most [perKind] each.
Map<SearchKind, List<SearchItem>> searchAll(Iterable<SearchItem> items, String query, {int perKind = 30}) {
  final out = <SearchKind, List<SearchItem>>{};
  for (final k in SearchKind.values) {
    final hits = [for (final i in items) if (i.kind == k && i.matches(query)) i];
    if (hits.isNotEmpty) out[k] = hits.take(perKind).toList();
  }
  return out;
}

import 'package:invest/data/local_platform.dart';

/// Per-account offline cache in SharedPreferences, shared by PWO, ملک و دفتر
/// and the cheque book. Keys are exactly the ones each store used before.
///
/// The account a write belongs to is always passed in explicitly (never read
/// from mutable store state after an `await`), so a switch of account during
/// a network call can never write one account's data under another's key.
class AccountCache {
  const AccountCache({required this.keyOf, this.lastAccountKey});

  /// Cache key for [account] and an optional sub-key (e.g. a year).
  final String Function(String account, Object? sub) keyOf;

  /// Pref that remembers the last bound account (null: not tracked).
  final String? lastAccountKey;

  static String norm(String? account) => (account ?? '').trim();

  Future<String?> read(String account, [Object? sub]) async {
    final prefs = await LocalPrefs.open();
    return prefs?.getString(keyOf(norm(account), sub));
  }

  Future<void> write(String account, String value, [Object? sub]) async {
    // Key computed before the await: [account] is the owner of [value].
    final key = keyOf(norm(account), sub);
    final prefs = await LocalPrefs.open();
    if (prefs == null) return;
    await LocalPrefs.setString(prefs, key, value);
  }

  Future<String?> lastAccount() async {
    final k = lastAccountKey;
    if (k == null) return null;
    final prefs = await LocalPrefs.open();
    final v = norm(prefs?.getString(k));
    return v.isEmpty ? null : v;
  }

  Future<void> setLastAccount(String account) async {
    final k = lastAccountKey;
    final a = norm(account);
    if (k == null || a.isEmpty) return;
    final prefs = await LocalPrefs.open();
    if (prefs != null) await LocalPrefs.setString(prefs, k, a);
  }

  Future<void> clearLastAccount() async {
    final k = lastAccountKey;
    if (k == null) return;
    final prefs = await LocalPrefs.open();
    await prefs?.remove(k);
  }
}

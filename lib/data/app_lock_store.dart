import 'package:shared_preferences/shared_preferences.dart';

/// Local app-lock hash (independent of Vinor OTP session).
class AppLockStore {
  static const _key = 'app_lock_hash';

  static Future<String?> loadHash() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  static Future<void> saveHash(String hash) async {
    final prefs = await SharedPreferences.getInstance();
    if (hash.trim().isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, hash);
    }
  }
}

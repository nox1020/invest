import 'package:invest/data/local_platform.dart';

/// Local app-lock preferences (independent of Vinor OTP session).
class AppLockStore {
  static const _hashKey = 'app_lock_hash';
  static const _biometricKey = 'app_lock_biometric';

  static Future<String?> loadHash() async {
    final prefs = await LocalPrefs.open();
    if (prefs == null) return null;
    final value = prefs.getString(_hashKey);
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  static Future<void> saveHash(String hash) async {
    final prefs = await LocalPrefs.open();
    if (prefs == null) return;
    if (hash.trim().isEmpty) {
      await prefs.remove(_hashKey);
      await prefs.remove(_biometricKey);
    } else {
      await prefs.setString(_hashKey, hash);
    }
  }

  static Future<bool> loadBiometricEnabled() async {
    final prefs = await LocalPrefs.open();
    if (prefs == null) return false;
    return prefs.getBool(_biometricKey) ?? false;
  }

  static Future<void> saveBiometricEnabled(bool enabled) async {
    final prefs = await LocalPrefs.open();
    if (prefs == null) return;
    if (enabled) {
      await prefs.setBool(_biometricKey, true);
    } else {
      await prefs.remove(_biometricKey);
    }
  }
}

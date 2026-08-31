import 'package:shared_preferences/shared_preferences.dart';

import 'package:invest/config/app_config.dart';

/// Persists Vinor session cookie, server URL, and logged-in phone.
class SessionStore {
  SessionStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<SessionStore> load() async {
    return SessionStore._(await SharedPreferences.getInstance());
  }

  String get baseUrl =>
      _prefs.getString(AppConfig.prefBaseUrl) ?? AppConfig.defaultBaseUrl;

  Future<void> setBaseUrl(String url) async {
    await _prefs.setString(AppConfig.prefBaseUrl, _normalizeBaseUrl(url));
  }

  String? get sessionCookie => _prefs.getString(AppConfig.prefSessionCookie);

  Future<void> setSessionCookie(String? cookie) async {
    if (cookie == null || cookie.isEmpty) {
      await _prefs.remove(AppConfig.prefSessionCookie);
    } else {
      await _prefs.setString(AppConfig.prefSessionCookie, cookie);
    }
  }

  String? get phone => _prefs.getString(AppConfig.prefUserPhone);

  Future<void> setPhone(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(AppConfig.prefUserPhone);
    } else {
      await _prefs.setString(AppConfig.prefUserPhone, value);
    }
  }

  Future<void> clearAuth() async {
    await setSessionCookie(null);
    await setPhone(null);
  }

  String? get apiVersion => _prefs.getString(AppConfig.prefApiVersion);

  Future<void> setApiVersion(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(AppConfig.prefApiVersion);
    } else {
      await _prefs.setString(AppConfig.prefApiVersion, value);
    }
  }

  static String _normalizeBaseUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }
}

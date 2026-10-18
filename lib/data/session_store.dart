import 'package:shared_preferences/shared_preferences.dart';

import 'package:invest/config/app_config.dart';

/// Persists Vinor session cookie, server URL, and logged-in phone.
class SessionStore {
  SessionStore._(this._prefs) : _memory = null;

  /// Used when plugin storage throws, so login can still call Vinor.
  SessionStore._memory()
      : _prefs = null,
        _memory = <String, Object?>{};

  final SharedPreferences? _prefs;
  final Map<String, Object?>? _memory;

  static Future<SessionStore> load() async {
    try {
      return SessionStore._(await SharedPreferences.getInstance());
    } catch (_) {
      return SessionStore._memory();
    }
  }

  String get baseUrl {
    final stored = _string(AppConfig.prefBaseUrl)?.trim() ?? '';
    if (stored.isEmpty) return AppConfig.defaultBaseUrl;
    return stored;
  }

  Future<void> setBaseUrl(String url) async {
    final normalized = _normalizeBaseUrl(url);
    await _setString(
      AppConfig.prefBaseUrl,
      normalized.isEmpty ? null : normalized,
    );
  }

  String? get sessionCookie => _string(AppConfig.prefSessionCookie);

  Future<void> setSessionCookie(String? cookie) async {
    await _setString(
      AppConfig.prefSessionCookie,
      (cookie == null || cookie.isEmpty) ? null : cookie,
    );
  }

  String? get phone => _string(AppConfig.prefUserPhone);

  Future<void> setPhone(String? value) async {
    await _setString(
      AppConfig.prefUserPhone,
      (value == null || value.isEmpty) ? null : value,
    );
  }

  Future<void> clearAuth() async {
    await setSessionCookie(null);
    await setPhone(null);
  }

  String? get apiVersion => _string(AppConfig.prefApiVersion);

  Future<void> setApiVersion(String? value) async {
    await _setString(
      AppConfig.prefApiVersion,
      (value == null || value.isEmpty) ? null : value,
    );
  }

  /// A value stored under the wrong type must not take down login.
  String? _string(String key) {
    try {
      final Object? value =
          _memory != null ? _memory[key] : _prefs!.get(key);
      if (value is String && value.trim().isNotEmpty) return value;
    } catch (_) {}
    return null;
  }

  Future<void> _setString(String key, String? value) async {
    if (_memory != null) {
      if (value == null) {
        _memory.remove(key);
      } else {
        _memory[key] = value;
      }
      return;
    }
    if (value == null) {
      await _prefs!.remove(key);
    } else {
      await _prefs!.setString(key, value);
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

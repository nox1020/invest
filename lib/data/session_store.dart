import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/local_platform.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secure = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

const _authKeys = <String>[
  AppConfig.prefSessionCookie,
  AppConfig.prefUserPhone,
  AppConfig.prefBaseUrl,
  AppConfig.prefApiVersion,
];

/// Persists the Vinor cookie, the logged-in phone, and the server URL.
///
/// Writes go to encrypted storage, SharedPreferences, and a file. A failure
/// in one layer must not drop the session into memory only. The values are
/// removed only by [clearAuth] (the «خروج از حساب» action).
class SessionStore {
  SessionStore._(this._values);

  final Map<String, String> _values;

  /// Test hook. When set, the file copy is stored here instead of app support.
  static Directory? debugStoreDirectory;

  /// Tests that drive a [FakeAsync] clock cannot wait on unregistered plugins.
  /// Production leaves this true. [FLUTTER_TEST] also skips the plugins,
  /// because a timer timeout is not elapsed by `pumpAndSettle`.
  static bool debugUsePlugins = true;

  static bool get _pluginsEnabled {
    if (!debugUsePlugins) return false;
    return Platform.environment['FLUTTER_TEST'] != 'true';
  }

  static Future<SessionStore> load() async {
    final prefsFuture = _readPrefs();
    final external = _readExternal();
    final prefs = await prefsFuture;
    final sources = await external;
    final secure = sources.$1;
    final file = sources.$2;
    final values = <String, String>{};
    for (final key in _authKeys) {
      final value = _firstNonEmpty([secure, file, prefs], key);
      if (value != null) values[key] = value;
    }
    final store = SessionStore._(values);
    await store._backfill(secure: secure, file: file, prefs: prefs);
    return store;
  }

  String get baseUrl {
    final stored = _values[AppConfig.prefBaseUrl]?.trim() ?? '';
    if (stored.isEmpty) return AppConfig.defaultBaseUrl;
    return stored;
  }

  Future<void> setBaseUrl(String url) async {
    final normalized = _normalizeBaseUrl(url);
    await _put(
      AppConfig.prefBaseUrl,
      normalized.isEmpty ? null : normalized,
    );
  }

  String? get sessionCookie => _values[AppConfig.prefSessionCookie];

  Future<void> setSessionCookie(String? cookie) async {
    await _put(
      AppConfig.prefSessionCookie,
      (cookie == null || cookie.trim().isEmpty) ? null : cookie.trim(),
    );
  }

  String? get phone => _values[AppConfig.prefUserPhone];

  Future<void> setPhone(String? value) async {
    await _put(
      AppConfig.prefUserPhone,
      (value == null || value.trim().isEmpty) ? null : value.trim(),
    );
  }

  Future<void> clearAuth() async {
    await setSessionCookie(null);
    await setPhone(null);
  }

  String? get apiVersion => _values[AppConfig.prefApiVersion];

  Future<void> setApiVersion(String? value) async {
    await _put(
      AppConfig.prefApiVersion,
      (value == null || value.trim().isEmpty) ? null : value.trim(),
    );
  }

  Future<void> _put(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    await _writeSecure(key, value);
    await _writePrefs(key, value);
    await _writeFile();
  }

  /// Copy a value that exists in only one layer into the others.
  Future<void> _backfill({
    required Map<String, String> secure,
    required Map<String, String> file,
    required Map<String, String> prefs,
  }) async {
    for (final key in _authKeys) {
      final value = _values[key];
      if (value == null) continue;
      if (secure[key] != value) await _writeSecure(key, value);
      if (prefs[key] != value) await _writePrefs(key, value);
    }
    if (file.length != _values.length ||
        _authKeys.any((key) => file[key] != _values[key])) {
      await _writeFile();
    }
  }

  static String? _firstNonEmpty(List<Map<String, String>> sources, String key) {
    for (final source in sources) {
      final value = source[key]?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  /// Plugin calls that never answer must not trap login. SharedPreferences
  /// is always read. Encrypted storage and the file are best-effort.
  static Future<(Map<String, String>, Map<String, String>)> _readExternal() {
    if (!_pluginsEnabled && debugStoreDirectory == null) {
      return Future.value((<String, String>{}, <String, String>{}));
    }
    return Future.wait<Map<String, String>>([
      _readSecure().timeout(
        const Duration(seconds: 2),
        onTimeout: () => {},
      ),
      _readFile().timeout(
        const Duration(seconds: 2),
        onTimeout: () => {},
      ),
    ]).then<(Map<String, String>, Map<String, String>)>(
      (pair) => (pair[0], pair[1]),
    );
  }

  static Future<Map<String, String>> _readSecure() async {
    if (!_pluginsEnabled) return {};
    final out = <String, String>{};
    try {
      for (final key in _authKeys) {
        final value = await _secure.read(key: key);
        if (value != null && value.trim().isNotEmpty) out[key] = value.trim();
      }
    } catch (e, st) {
      _logPlugin(e, st, 'session-secure-read');
    }
    return out;
  }

  static Future<void> _writeSecure(String key, String? value) async {
    if (!_pluginsEnabled) return;
    try {
      if (value == null) {
        await _secure.delete(key: key).timeout(const Duration(seconds: 2));
      } else {
        await _secure
            .write(key: key, value: value)
            .timeout(const Duration(seconds: 2));
      }
    } catch (e, st) {
      _logPlugin(e, st, 'session-secure-write');
    }
  }

  static Future<Map<String, String>> _readPrefs() async {
    final out = <String, String>{};
    final SharedPreferences? prefs;
    try {
      prefs = await LocalPrefs.open();
    } catch (e, st) {
      logLocalFailure('session-prefs-read', e, st);
      return out;
    }
    if (prefs == null) return out;
    for (final key in _authKeys) {
      try {
        final value = prefs.get(key);
        if (value is String && value.trim().isNotEmpty) {
          out[key] = value.trim();
        }
      } catch (e, st) {
        logLocalFailure('session-prefs-key', e, st);
      }
    }
    return out;
  }

  static Future<void> _writePrefs(String key, String? value) async {
    try {
      final prefs = await LocalPrefs.open();
      if (prefs == null) return;
      if (value == null) {
        await prefs.remove(key);
      } else {
        await LocalPrefs.setString(prefs, key, value);
      }
    } catch (e, st) {
      logLocalFailure('session-prefs-write', e, st);
    }
  }

  static Future<File?> _file() async {
    try {
      final Directory dir;
      final override = debugStoreDirectory;
      if (override != null) {
        dir = override;
      } else if (!_pluginsEnabled) {
        return null;
      } else {
        dir = await getApplicationSupportDirectory().timeout(
          const Duration(seconds: 2),
        );
      }
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File('${dir.path}/vinor_session.json');
    } catch (e, st) {
      _logPlugin(e, st, 'session-file');
      return null;
    }
  }

  static Future<Map<String, String>> _readFile() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      final out = <String, String>{};
      for (final key in _authKeys) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) {
          out[key] = value.trim();
        }
      }
      return out;
    } catch (e, st) {
      _logPlugin(e, st, 'session-file-read');
      return {};
    }
  }

  Future<void> _writeFile() async {
    try {
      final file = await _file();
      if (file == null) return;
      await file.writeAsString(jsonEncode(_values), flush: true);
    } catch (e, st) {
      _logPlugin(e, st, 'session-file-write');
    }
  }

  static void _logPlugin(Object error, StackTrace stack, String where) {
    if (error is MissingPluginException) return;
    logLocalFailure(where, error, stack);
  }

  static String _normalizeBaseUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }
}

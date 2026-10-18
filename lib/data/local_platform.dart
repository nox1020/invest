import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite/sqflite.dart';

/// Keys whose payload can blow the Android binder limit on `getAll`.
/// Dropping them lets session and lock prefs load again. Server data is
/// never stored here.
const localPrefsHeavyKeys = <String>[
  'offline_portfolio_snapshot_v1',
  'offline_commodity_index_v2',
  'offline_wallex_markets_v1',
];

void logLocalFailure(String where, Object error, [StackTrace? stack]) {
  final detail = error is PlatformException
      ? 'PlatformException/${error.code} ${(error.message ?? '').replaceAll(RegExp(r'\s+'), ' ').trim()}'
      : '$error';
  debugPrint(
    'Invest local $where: $detail${stack == null ? '' : '\n$stack'}',
  );
}

/// SQLite / path_provider failures. A prefs `PlatformException` is not one.
bool isDatabaseFailure(Object error) {
  if (error is DatabaseException) return true;
  final text = error is PlatformException
      ? '${error.code} ${error.message ?? ''}'.toLowerCase()
      : error.toString().toLowerCase();
  return text.contains('sqlite') ||
      text.contains('database') ||
      text.contains('malformed');
}

/// SharedPreferences that survives a poisoned `getAll`.
///
/// Android sends every pref across the binder on open. A large snapshot
/// throws `PlatformException` for every later reader, including settings,
/// the phone book merge, quote prefs, and the next snapshot. The heavy
/// cache keys are removed and the open is retried once. Auth keys stay.
class LocalPrefs {
  LocalPrefs._();

  static Future<SharedPreferences?> open() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e, st) {
      logLocalFailure('shared_preferences', e, st);
      await dropHeavyKeys();
      try {
        return await SharedPreferences.getInstance();
      } catch (e2, st2) {
        logLocalFailure('shared_preferences-retry', e2, st2);
        return null;
      }
    }
  }

  static Future<bool> setString(
    SharedPreferences prefs,
    String key,
    String value,
  ) async {
    try {
      return await prefs.setString(key, value);
    } catch (e, st) {
      logLocalFailure('shared_preferences-write', e, st);
      return false;
    }
  }

  static Future<void> dropHeavyKeys() async {
    final store = SharedPreferencesStorePlatform.instance;
    for (final key in localPrefsHeavyKeys) {
      try {
        await store.remove('flutter.$key');
      } catch (e, st) {
        logLocalFailure('shared_preferences-remove', e, st);
      }
    }
  }
}

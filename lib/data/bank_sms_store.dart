import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:invest/domain/services/bank_sms_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android permission / popup capability as reported by the platform side.
class BankSmsCaps {
  const BankSmsCaps({
    this.supported = false,
    this.read = false,
    this.receive = false,
    this.notify = true,
    this.fullScreen = true,
    this.sdk = 0,
    this.error,
  });
  final bool supported, read, receive, notify, fullScreen;
  final int sdk;

  /// Why the status could not be read (no SMS text; just the error kind).
  final String? error;

  /// Live detection needs RECEIVE_SMS; READ_SMS only adds the inbox scan.
  bool get granted => receive;
  bool get unknown => error != null;

  /// A permission is really denied (not just "status unknown").
  bool get denied => supported && !unknown && !receive;

  static BankSmsCaps fromMap(Object? m) {
    if (m is! Map) return const BankSmsCaps();
    bool b(String k, [bool d = false]) => m[k] is bool ? m[k] as bool : d;
    return BankSmsCaps(
      supported: true,
      read: b('read'),
      receive: b('receive'),
      notify: b('notify', true),
      fullScreen: b('fullScreen', true),
      sdk: (m['sdk'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Bank-SMS withdrawals waiting for one-tap confirmation.
///
/// Privacy: raw SMS text only lives in memory while parsing; only parsed
/// fields (amount, bank, date, card tail) and a hash are kept on the device.
/// Nothing here is sent anywhere — only a confirmed withdrawal is recorded.
class BankSmsStore extends ChangeNotifier {
  BankSmsStore._();
  static BankSmsStore instance = BankSmsStore._();

  @visibleForTesting
  static void debugReset() => instance = BankSmsStore._();

  static const channel = MethodChannel('invest/sms');
  static const kEnabled = 'bank_sms_enabled'; // also read by SmsReceiver.kt
  static const _kLastScan = 'bank_sms_last_scan_ms';
  static const _kHandled = 'bank_sms_handled_v1';
  static const _kPending = 'bank_sms_pending_v1';
  static const _kWant = 'bank_sms_want_v1';
  static const _kCards = 'bank_sms_card_person_v1';
  static const _maxHandled = 600;

  /// Card/account tail → PWO person id (learned on confirm, editable).
  final Map<String, String> cardPerson = {};

  bool _loaded = false;
  bool enabled = false;

  /// The user tried to turn it on but a permission was missing; enabled
  /// automatically once the permissions are granted (e.g. after returning
  /// from Android's app settings).
  bool wantEnabled = false;
  int lastScanMs = 0;
  final List<String> _handled = [];
  final List<BankSmsItem> pending = [];
  BankSmsCaps caps = const BankSmsCaps();

  /// Fired for a withdrawal SMS that arrived (or was tapped) right now and
  /// should pop the confirm sheet.
  final _arrivals = StreamController<BankSmsItem>.broadcast();
  Stream<BankSmsItem> get arrivals => _arrivals.stream;
  bool _channelBound = false;

  bool get loaded => _loaded;

  Future<void>? _loading;
  Future<void> load() => _loaded ? Future.value() : (_loading ??= _load());

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool(kEnabled) ?? false;
    lastScanMs = p.getInt(_kLastScan) ?? 0;
    wantEnabled = p.getBool(_kWant) ?? false;
    _handled
      ..clear()
      ..addAll(p.getStringList(_kHandled) ?? const []);
    cardPerson.clear();
    try {
      final m = jsonDecode(p.getString(_kCards) ?? '{}');
      if (m is Map) {
        m.forEach((k, v) {
          if (k is String && v is String) cardPerson[k] = v;
        });
      }
    } catch (_) {}
    pending.clear();
    for (final s in p.getStringList(_kPending) ?? const <String>[]) {
      try {
        final it = BankSmsItem.fromJson(jsonDecode(s));
        if (it != null) pending.add(it);
      } catch (_) {}
    }
    _loaded = true;
    _bindChannel();
    notifyListeners();
  }

  void _bindChannel() {
    if (_channelBound) return;
    _channelBound = true;
    try {
      channel.setMethodCallHandler((call) async {
        if (call.method == 'smsArrived') {
          final items = await ingest([call.arguments]);
          for (final it in items) {
            _arrivals.add(it);
          }
        }
        return null;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kLastScan, lastScanMs);
    await p.setStringList(_kHandled, _handled);
    await p.setStringList(
        _kPending, [for (final it in pending) jsonEncode(it.toJson())]);
  }

  Future<void> setEnabled(bool v) async {
    await load();
    enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(kEnabled, v);
    if (v && lastScanMs == 0) {
      // Start from the last two days, not the whole inbox history.
      lastScanMs = DateTime.now()
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch;
    }
    if (!v) pending.clear();
    await _save();
    notifyListeners();
  }

  Future<void> setCardPerson(String card, String? personId) async {
    await load();
    if (personId == null) {
      cardPerson.remove(card);
    } else {
      cardPerson[card] = personId;
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCards, jsonEncode(cardPerson));
    notifyListeners();
  }

  bool isHandled(String fp) => _handled.contains(fp);

  /// Parses raw `{address, body, date}` maps; returns the newly added items.
  Future<List<BankSmsItem>> ingest(List<Object?> raw) async {
    await load();
    if (!enabled) return const [];
    final added = <BankSmsItem>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final addr = '${m['address'] ?? ''}';
      final body = '${m['body'] ?? ''}';
      final ms =
          (m['date'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
      if (body.isEmpty) continue;
      final it =
          parseBankSms(addr, body, DateTime.fromMillisecondsSinceEpoch(ms));
      if (it == null || isHandled(it.fp)) continue;
      final dup = pending.indexWhere((x) => x.fp == it.fp);
      if (dup >= 0) {
        added.add(pending[dup]);
        continue;
      }
      pending.add(it);
      added.add(it);
    }
    pending.sort((a, b) => b.at.compareTo(a.at));
    await _save();
    if (added.isNotEmpty) notifyListeners();
    return added;
  }

  /// Confirmed or rejected: never offered again.
  Future<void> markHandled(String fp) async {
    await load();
    pending.removeWhere((x) => x.fp == fp);
    _handled.remove(fp);
    _handled.add(fp);
    if (_handled.length > _maxHandled) {
      _handled.removeRange(0, _handled.length - _maxHandled);
    }
    await _save();
    notifyListeners();
    try {
      await channel.invokeMethod('cancel', {'fp': fp});
    } catch (_) {}
  }

  Future<void> _setWant(bool v) async {
    wantEnabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kWant, v);
  }

  /// Switch turned on: ask for permissions; enable (and persist) as soon as
  /// SMS permissions are granted, otherwise remember the intent.
  Future<bool> tryEnable() async {
    await load();
    var c = await refreshCaps();
    if (c.denied) c = await requestPermissions();
    if (c.denied) {
      await _setWant(true);
      notifyListeners();
      return false;
    }
    await _setWant(false);
    await setEnabled(true);
    await syncOnOpen();
    return true;
  }

  Future<void> disable() async {
    await _setWant(false);
    await setEnabled(false);
  }

  /// After coming back from system settings: auto-enable if requested.
  Future<void> recheck() async {
    await load();
    final c = await refreshCaps();
    if (wantEnabled && !enabled && c.supported && !c.denied) {
      await _setWant(false);
      await setEnabled(true);
      await syncOnOpen();
    }
  }

  Future<BankSmsCaps> refreshCaps() async {
    try {
      final m = await channel
          .invokeMethod<Object?>('status')
          .timeout(const Duration(seconds: 4));
      caps = m is Map
          ? BankSmsCaps.fromMap(m)
          : const BankSmsCaps(supported: true, error: 'empty');
    } on MissingPluginException {
      caps = const BankSmsCaps(); // not Android / no native side
    } on TimeoutException {
      caps = const BankSmsCaps(supported: true, error: 'timeout');
    } on PlatformException catch (e) {
      caps = BankSmsCaps(supported: true, error: e.code);
    } catch (e) {
      caps = BankSmsCaps(supported: true, error: e.runtimeType.toString());
    }
    notifyListeners();
    return caps;
  }

  Future<BankSmsCaps> requestPermissions() async {
    try {
      await channel.invokeMethod('request').timeout(const Duration(minutes: 2));
    } catch (_) {}
    return refreshCaps();
  }

  Future<void> openAppSettings() async {
    try {
      await channel.invokeMethod('openAppSettings');
    } catch (_) {}
  }

  Future<void> openFullScreenSettings() async {
    try {
      await channel.invokeMethod('openFullScreenSettings');
    } catch (_) {}
  }

  /// On app open / resume: SMS handed over by a tapped notification (popped
  /// right away) plus an inbox scan since the last check as a fallback.
  Future<List<BankSmsItem>> syncOnOpen() async {
    await load();
    if (!enabled) return const [];
    final popNow = <BankSmsItem>[];
    try {
      final rejected =
          await channel.invokeMethod<List<Object?>>('takeRejected');
      for (final fp in rejected ?? const <Object?>[]) {
        if (fp is String) await markHandled(fp);
      }
      final tapped = await channel.invokeMethod<List<Object?>>('takePending');
      if (tapped != null && tapped.isNotEmpty) {
        popNow.addAll(await ingest(tapped));
      }
      final since = lastScanMs;
      final now = DateTime.now().millisecondsSinceEpoch;
      final inbox =
          await channel.invokeMethod<List<Object?>>('inbox', {'since': since});
      if (inbox != null) await ingest(inbox);
      lastScanMs = now;
      await _save();
    } catch (_) {
      // No permission / not Android: nothing to scan.
    }
    return popNow;
  }
}

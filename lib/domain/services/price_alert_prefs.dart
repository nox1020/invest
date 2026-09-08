import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/price_alert.dart';
import 'package:invest/domain/services/price_alert_engine.dart';

/// Device-local price-alert prefs (not all backends persist extra settings keys).
class PriceAlertPrefs {
  PriceAlertPrefs._();

  static const snapshotKey = 'vplus_price_alert_prefs_v1';
  static const latchKey = 'vplus_price_alert_latches_v1';

  static Future<void> saveFrom(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      snapshotKey,
      jsonEncode({
        'notifications_enabled': s.notificationsEnabled,
        'notify_price_moves': s.notifyPriceMoves,
        'notify_background': s.notifyBackground,
        'wallex_url': s.wallexUrl,
        'persian_toolbox_url': s.persianToolboxUrl,
        'price_alerts': s.priceAlerts.map((e) => e.toJson()).toList(),
      }),
    );
  }

  static Future<void> overlayOnto(AppSettings s) async {
    final snap = await loadSnapshot();
    if (snap == null) return;
    s.notifyBackground = snap.notifyBackground;
    s.priceAlerts = snap.alerts.map((e) => e.copy()).toList();
  }

  static Future<PriceAlertSnapshot?> loadSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(snapshotKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      return PriceAlertSnapshot.fromJson(Map<String, dynamic>.from(map));
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, PriceAlertLatch>> loadLatches() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(latchKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return {};
      final out = <String, PriceAlertLatch>{};
      map.forEach((k, v) {
        if (v is Map) {
          out['$k'] = PriceAlertLatch.fromJson(Map<String, dynamic>.from(v));
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveLatches(Map<String, PriceAlertLatch> latches) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      latchKey,
      jsonEncode({
        for (final e in latches.entries) e.key: e.value.toJson(),
      }),
    );
  }
}

class PriceAlertSnapshot {
  PriceAlertSnapshot({
    required this.notificationsEnabled,
    required this.notifyPriceMoves,
    required this.notifyBackground,
    required this.wallexUrl,
    required this.persianToolboxUrl,
    required this.alerts,
  });

  final bool notificationsEnabled;
  final bool notifyPriceMoves;
  final bool notifyBackground;
  final String wallexUrl;
  final String persianToolboxUrl;
  final List<PriceAlert> alerts;

  factory PriceAlertSnapshot.fromJson(Map<String, dynamic> m) {
    return PriceAlertSnapshot(
      notificationsEnabled: m['notifications_enabled'] != false,
      notifyPriceMoves: m['notify_price_moves'] != false,
      notifyBackground: m['notify_background'] != false,
      wallexUrl: '${m['wallex_url'] ?? ''}',
      persianToolboxUrl: '${m['persian_toolbox_url'] ?? ''}',
      alerts: PriceAlertList.parse(m['price_alerts']),
    );
  }
}

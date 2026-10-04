import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:invest/domain/models/app_notification.dart';
import 'package:invest/domain/services/notification_service.dart';

/// Persists an in-app notification inbox and exposes unread count.
class NotificationInboxStore {
  NotificationInboxStore._();

  static const _key = 'vplus_notification_inbox_v1';
  static const _maxItems = 100;

  /// Reactive unread badge for the home AppBar.
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  static bool _hydrated = false;

  static Future<void> ensureHydrated() async {
    if (_hydrated) return;
    final items = await load();
    unreadCount.value = items.where((e) => !e.read).length;
    _hydrated = true;
  }

  static Future<List<AppNotification>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <AppNotification>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <AppNotification>[];
      return decoded
          .whereType<Map>()
          .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();
    } catch (_) {
      return <AppNotification>[];
    }
  }

  static Future<void> _save(List<AppNotification> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
    unreadCount.value = items.where((e) => !e.read).length;
    _hydrated = true;
  }

  static Future<void> add({
    required String title,
    required String body,
    required NotificationKind kind,
  }) async {
    final items = await load();
    final now = DateTime.now();
    items.insert(
      0,
      AppNotification(
        id: '${now.microsecondsSinceEpoch}',
        title: title.trim().isEmpty ? 'V+' : title.trim(),
        body: body.trim(),
        kind: kind,
        createdAt: now,
      ),
    );
    if (items.length > _maxItems) {
      items.removeRange(_maxItems, items.length);
    }
    await _save(items);
  }

  static Future<void> markAllRead() async {
    final items = await load();
    var changed = false;
    for (final e in items) {
      if (!e.read) {
        e.read = true;
        changed = true;
      }
    }
    if (changed) await _save(items);
  }

  static Future<void> markRead(String id) async {
    final items = await load();
    final i = items.indexWhere((e) => e.id == id);
    if (i < 0 || items[i].read) return;
    items[i].read = true;
    await _save(items);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    unreadCount.value = 0;
    _hydrated = true;
  }
}

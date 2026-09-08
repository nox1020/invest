import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local (device) notifications for trades, withdrawals, and price alerts.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  int _seq = 0;

  static const _channelTrades = 'vplus_trades';
  static const _channelWithdrawals = 'vplus_withdrawals';
  static const _channelPrices = 'vplus_price_alerts';
  static const _channelGeneral = 'vplus_general';

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _plugin.initialize(initSettings);
    await _ensureChannels();
    _ready = true;
  }

  Future<void> _ensureChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelTrades,
        'معاملات',
        description: 'خرید، فروش و ویرایش معاملات',
        importance: Importance.high,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelWithdrawals,
        'برداشت‌ها',
        description: 'ثبت و تغییر وضعیت برداشت',
        importance: Importance.high,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelPrices,
        'هشدار قیمت',
        description: 'عبور قیمت ارز از آستانه تنظیم‌شده',
        importance: Importance.high,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelGeneral,
        'عمومی',
        description: 'اعلان‌های عمومی V+',
        importance: Importance.defaultImportance,
      ),
    );
  }

  /// Requests Android 13+ notification permission. Returns whether allowed.
  Future<bool> requestPermission() async {
    await init();
    if (kIsWeb) return false;
    if (!Platform.isAndroid) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    final already = await android.areNotificationsEnabled();
    if (already == true) return true;
    final granted = await android.requestNotificationsPermission();
    if (granted == true) return true;
    return await android.areNotificationsEnabled() ?? false;
  }

  Future<bool> areNotificationsEnabled() async {
    await init();
    if (kIsWeb) return false;
    if (!Platform.isAndroid) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? true;
  }

  static int priceAlertId(String quoteId, String side) {
    final key = '$quoteId|$side';
    return 40000 + (key.hashCode.abs() % 20000);
  }

  static int profitAlertId(String id, String side) {
    final key = '$id|$side';
    return 60000 + (key.hashCode.abs() % 20000);
  }

  Future<void> show({
    required String title,
    required String body,
    NotificationKind kind = NotificationKind.general,
    int? id,
  }) async {
    await init();
    final channel = switch (kind) {
      NotificationKind.trades => _channelTrades,
      NotificationKind.withdrawals => _channelWithdrawals,
      NotificationKind.prices => _channelPrices,
      NotificationKind.general => _channelGeneral,
    };
    final channelName = switch (kind) {
      NotificationKind.trades => 'معاملات',
      NotificationKind.withdrawals => 'برداشت‌ها',
      NotificationKind.prices => 'هشدار قیمت',
      NotificationKind.general => 'عمومی',
    };
    final nid = id ?? (++_seq) % 100000;
    await _plugin.show(
      nid,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          channelName,
          channelDescription: 'V+',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  }

  Future<void> showTest() => show(
        title: 'V+ — اعلان آزمایشی',
        body: 'اعلان‌ها روی این دستگاه فعال هستند.',
        kind: NotificationKind.general,
      );
}

enum NotificationKind { trades, withdrawals, prices, general }

import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/price_alert.dart';
import 'package:invest/domain/services/commodity_index_service.dart';
import 'package:invest/domain/services/notification_service.dart';
import 'package:invest/domain/services/price_alert_engine.dart';
import 'package:invest/domain/services/price_alert_prefs.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:workmanager/workmanager.dart';

const priceAlertPeriodicUniqueName = 'vplus_price_alerts';
const priceAlertOneOffUniqueName = 'vplus_price_alerts_once';
const priceAlertTaskName = 'priceAlertCheck';

@pragma('vm:entry-point')
void priceAlertCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      await BackgroundPriceMonitor.runOnce();
      return true;
    } catch (_) {
      return false;
    }
  });
}

/// Schedules OS-level periodic price checks while the app is killed.
class BackgroundPriceWorker {
  BackgroundPriceWorker._();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    if (!Platform.isAndroid) return;
    try {
      await Workmanager().initialize(priceAlertCallbackDispatcher);
      _initialized = true;
    } catch (_) {}
  }

  static Future<void> sync(AppSettings settings) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await initialize();
    if (!_initialized) return;
    final armed = settings.priceAlertsOn &&
        settings.notifyBackground &&
        settings.priceAlerts.any((e) => e.isArmed);
    try {
      if (!armed) {
        await Workmanager().cancelByUniqueName(priceAlertPeriodicUniqueName);
        await Workmanager().cancelByUniqueName(priceAlertOneOffUniqueName);
        return;
      }
      await Workmanager().registerPeriodicTask(
        priceAlertPeriodicUniqueName,
        priceAlertTaskName,
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(minutes: 1),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 5),
      );
      await Workmanager().registerOneOffTask(
        priceAlertOneOffUniqueName,
        priceAlertTaskName,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        initialDelay: const Duration(seconds: 20),
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {}
  }
}

class BackgroundPriceMonitor {
  BackgroundPriceMonitor._();

  static Future<void> runOnce() async {
    final snap = await PriceAlertPrefs.loadSnapshot();
    if (snap == null) return;
    if (!snap.notificationsEnabled || !snap.notifyPriceMoves) return;
    if (!snap.notifyBackground) return;
    final alerts = snap.alerts.where((e) => e.isArmed).toList();
    if (alerts.isEmpty) return;

    final bundle = await CommodityIndexService().fetchAll(
      wallexUrl: snap.wallexUrl.trim().isEmpty
          ? AppConfig.defaultWallexUrl
          : snap.wallexUrl,
    );
    if (!bundle.hasAnyPrice) return;

    final prices = PriceAlertEngine.pricesFrom(
      quotes: [...bundle.essentials, ...bundle.wallexMarkets],
    );
    await dispatchHits(
      alerts: alerts,
      prices: prices,
    );
  }

  static Future<List<PriceAlertHit>> dispatchHits({
    required List<PriceAlert> alerts,
    required Map<String, double> prices,
  }) async {
    final latches = await PriceAlertPrefs.loadLatches();
    final hits = PriceAlertEngine.evaluate(
      alerts: alerts,
      prices: prices,
      latches: latches,
    );
    await PriceAlertPrefs.saveLatches(latches);
    if (hits.isEmpty) return hits;

    await NotificationService.instance.init();
    for (final hit in hits) {
      try {
        await NotificationService.instance.show(
          title: hit.side == PriceAlertSide.above
              ? '${hit.alert.displayName} بالاتر از آستانه'
              : '${hit.alert.displayName} پایین‌تر از آستانه',
          body:
              '${_formatHitPrice(hit.price, hit.alert.unit)} — آستانه ${_formatHitPrice(hit.threshold, hit.alert.unit)}',
          kind: NotificationKind.prices,
          id: NotificationService.priceAlertId(hit.alert.id, hit.side.name),
        );
      } catch (_) {}
    }
    return hits;
  }
}

String _formatHitPrice(double v, String unit) {
  switch (unit) {
    case 'usd':
      return formatUsd(v);
    case 'toman_per_gram':
      return '${formatNumber(v, decimals: 0)} ت/گرم';
    default:
      return formatMoney(v);
  }
}

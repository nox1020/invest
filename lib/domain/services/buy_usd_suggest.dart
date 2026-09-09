import 'package:invest/domain/services/market_history_service.dart';
import 'package:invest/domain/utils/money.dart';

/// USDT/TMN (Toman per 1 USD) on the buy date, with live-rate fallback.
Future<double?> suggestBuyUsdTmn({
  required String buyDateIso,
  double? liveUsdtFallback,
  MarketHistoryService? history,
}) async {
  final date = buyDateIso.trim();
  if (date.isEmpty) return null;
  final svc = history ?? MarketHistoryService();
  return svc.fetchUsdtTmnOnDate(date, fallback: liveUsdtFallback);
}

/// Suggests unit buy price in USD from Toman price + USDT/TMN on that date.
Future<double?> suggestBuyPriceUsd({
  required double buyPriceToman,
  required String buyDateIso,
  double? liveUsdtFallback,
  MarketHistoryService? history,
}) async {
  if (buyPriceToman <= 0) return null;
  final rate = await suggestBuyUsdTmn(
    buyDateIso: buyDateIso,
    liveUsdtFallback: liveUsdtFallback,
    history: history,
  );
  return tomanToUsd(buyPriceToman, rate);
}

String formatBuyUsdField(double usd) {
  if ((usd - usd.roundToDouble()).abs() < 1e-12) return '${usd.round()}';
  if (usd >= 1) return usd.toStringAsFixed(2);
  return usd.toStringAsFixed(4);
}

String formatBuyFxField(double fx) {
  if (!fx.isFinite || fx <= 0) return '';
  if ((fx - fx.roundToDouble()).abs() < 0.5) return '${fx.round()}';
  if (fx >= 100) return fx.toStringAsFixed(0);
  return fx.toStringAsFixed(2);
}

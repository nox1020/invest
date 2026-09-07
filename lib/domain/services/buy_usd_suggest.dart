import 'package:invest/domain/services/market_history_service.dart';
import 'package:invest/domain/utils/money.dart';

/// Suggests unit buy price in USD from Toman price + USDT/TMN on that date.
Future<double?> suggestBuyPriceUsd({
  required double buyPriceToman,
  required String buyDateIso,
  double? liveUsdtFallback,
  MarketHistoryService? history,
}) async {
  if (buyPriceToman <= 0) return null;
  final date = buyDateIso.trim();
  if (date.isEmpty) return null;

  final svc = history ?? MarketHistoryService();
  final rate = await svc.fetchUsdtTmnOnDate(
    date,
    fallback: liveUsdtFallback,
  );
  return tomanToUsd(buyPriceToman, rate);
}

String formatBuyUsdField(double usd) {
  if ((usd - usd.roundToDouble()).abs() < 1e-12) return '${usd.round()}';
  if (usd >= 1) return usd.toStringAsFixed(2);
  return usd.toStringAsFixed(4);
}

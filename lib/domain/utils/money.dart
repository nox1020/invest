import 'package:intl/intl.dart';

double realizedPnl({
  required double qty,
  required double buyPrice,
  required double sellPrice,
  double buyFee = 0,
  double sellFee = 0,
}) {
  return qty * (sellPrice - buyPrice) - buyFee - sellFee;
}

double returnPct({
  required double qty,
  required double buyPrice,
  required double sellPrice,
  double buyFee = 0,
  double sellFee = 0,
}) {
  final cost = qty * buyPrice + buyFee;
  if (cost == 0) return 0;
  return realizedPnl(
        qty: qty,
        buyPrice: buyPrice,
        sellPrice: sellPrice,
        buyFee: buyFee,
        sellFee: sellFee,
      ) /
      cost *
      100;
}

String formatNumber(num value, {int decimals = 0}) {
  final f = NumberFormat.decimalPattern('en');
  f.minimumFractionDigits = decimals;
  f.maximumFractionDigits = decimals;
  return f.format(value);
}

String formatMoney(num value, {bool showSign = false, int decimals = 0}) {
  final abs = value.abs();
  final body = '${formatNumber(abs, decimals: decimals)} تومان';
  if (!showSign) return value < 0 ? '−$body' : body;
  if (value > 0) return '+$body';
  if (value < 0) return '−$body';
  return body;
}

String formatGrams(num value) {
  final v = value.toDouble();
  if (v.abs() < 1e-9) return '0 گرم';
  if ((v - v.round()).abs() < 1e-6) {
    return '${formatNumber(v.roundToDouble(), decimals: 0)} گرم';
  }
  if (v.abs() < 10) return '${formatNumber(v, decimals: 4)} گرم';
  return '${formatNumber(v, decimals: 2)} گرم';
}

String formatPct(num value) {
  final sign = value > 0 ? '+' : '';
  return '$sign${formatNumber(value, decimals: 2)}٪';
}

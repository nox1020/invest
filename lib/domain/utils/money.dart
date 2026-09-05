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

String _signed(String body, num value, {required bool showSign}) {
  if (value < 0) return '−$body';
  if (showSign && value > 0) return '+$body';
  return body;
}

int _autoDecimals(double value) {
  if ((value - value.roundToDouble()).abs() < 0.049) return 0;
  return 1;
}

String formatMoney(num value, {bool showSign = false, int decimals = 0}) {
  final abs = value.abs();
  final body = '${formatNumber(abs, decimals: decimals)} تومان';
  return _signed(body, value, showSign: showSign);
}

/// Compact Toman like `182 میلیارد ت` for portfolio cards.
String formatCompactToman(num value, {bool showSign = false}) {
  final abs = value.abs();
  late final String body;
  if (abs >= 1e12) {
    final v = abs / 1e12;
    body = '${formatNumber(v, decimals: _autoDecimals(v))} هزار میلیارد ت';
  } else if (abs >= 1e9) {
    final v = abs / 1e9;
    body = '${formatNumber(v, decimals: _autoDecimals(v))} میلیارد ت';
  } else if (abs >= 1e6) {
    final v = abs / 1e6;
    body = '${formatNumber(v, decimals: _autoDecimals(v))} میلیون ت';
  } else if (abs >= 1e3) {
    final v = abs / 1e3;
    body = '${formatNumber(v, decimals: _autoDecimals(v))} هزار ت';
  } else {
    body = '${formatNumber(abs, decimals: 0)} ت';
  }
  return _signed(body, value, showSign: showSign);
}

/// USD from Toman using USDT/TMN rate. Null when rate is missing.
double? tomanToUsd(num toman, double? usdtTmn) {
  if (usdtTmn == null || usdtTmn <= 0) return null;
  return toman / usdtTmn;
}

String formatUsd(
  num value, {
  bool compact = false,
  bool showSign = false,
}) {
  final abs = value.abs();
  late final String body;
  if (compact && abs >= 1000) {
    if (abs >= 1e6) {
      final v = abs / 1e6;
      body = '\$${formatNumber(v, decimals: _autoDecimals(v))}M';
    } else {
      final v = abs / 1e3;
      body = '\$${formatNumber(v, decimals: _autoDecimals(v))}K';
    }
  } else {
    final decimals = abs == 0
        ? 0
        : abs < 0.01
            ? 6
            : abs < 1
                ? 4
                : abs < 100
                    ? 2
                    : 0;
    body = '\$${formatNumber(abs, decimals: decimals)}';
  }
  return _signed(body, value, showSign: showSign);
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

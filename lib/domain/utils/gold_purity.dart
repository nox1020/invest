import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/utils/money.dart';

/// Parse Iranian karat (`18`, `۲۴`) or millesimal (`750`, `900`) to a
/// fraction of 24k. Null when the field is empty or not a known purity.
double? parseGoldPurityFraction(String? raw) {
  if (raw == null) return null;
  var t = raw.trim();
  if (t.isEmpty) return null;
  t = t
      .replaceAll('عیار', '')
      .replaceAll('%', '')
      .replaceAll(RegExp('[kKک]'), '')
      .trim();
  final n = parseFlexibleNumber(t);
  if (n == null || n <= 0) return null;
  if (n > 24.5 && n <= 1000) {
    return (n / 1000).clamp(0.5, 1.0);
  }
  if (n >= 14 && n <= 24.5) {
    return (n / 24).clamp(0.5, 1.0);
  }
  return null;
}

/// Convert an 18k Toman/gram index quote to the holding's karat.
/// Empty/unknown purity stays 18k (identity).
double scaleGoldPriceFrom18k(double price18kPerGram, String? purityRaw) {
  if (price18kPerGram <= 0) return price18kPerGram;
  final frac = parseGoldPurityFraction(purityRaw);
  if (frac == null) return price18kPerGram;
  return price18kPerGram * (frac / k18GoldPurity);
}

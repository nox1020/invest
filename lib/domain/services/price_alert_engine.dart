import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/price_alert.dart';

enum PriceAlertSide { above, below }

class PriceAlertLatch {
  PriceAlertLatch({this.aboveFired = false, this.belowFired = false});

  bool aboveFired;
  bool belowFired;

  Map<String, dynamic> toJson() => {
        'above': aboveFired,
        'below': belowFired,
      };

  factory PriceAlertLatch.fromJson(Map<String, dynamic> m) => PriceAlertLatch(
        aboveFired: m['above'] == true,
        belowFired: m['below'] == true,
      );
}

class PriceAlertHit {
  const PriceAlertHit({
    required this.alert,
    required this.price,
    required this.side,
    required this.threshold,
  });

  final PriceAlert alert;
  final double price;
  final PriceAlertSide side;
  final double threshold;
}

/// Pure threshold evaluation with one-shot latches (no re-fire until recovery).
class PriceAlertEngine {
  static Map<String, double> pricesFrom({
    required Iterable<CommodityQuote> quotes,
    double? usdt,
    double? gold,
  }) {
    final out = <String, double>{};
    for (final q in quotes) {
      final p = q.price;
      if (p != null && p > 0 && q.id.isNotEmpty) {
        out[q.id] = p;
      }
    }
    if (usdt != null && usdt > 0) out['usdt'] = usdt;
    if (gold != null && gold > 0) out['gold'] = gold;
    return out;
  }

  static List<PriceAlertHit> evaluate({
    required List<PriceAlert> alerts,
    required Map<String, double> prices,
    required Map<String, PriceAlertLatch> latches,
  }) {
    final hits = <PriceAlertHit>[];
    for (final alert in alerts) {
      if (!alert.isArmed || alert.id.isEmpty) continue;
      final price = prices[alert.id];
      if (price == null || price <= 0) continue;
      final latch = latches.putIfAbsent(alert.id, PriceAlertLatch.new);

      final above = alert.above;
      if (above != null && above > 0) {
        if (price >= above) {
          if (!latch.aboveFired) {
            hits.add(
              PriceAlertHit(
                alert: alert,
                price: price,
                side: PriceAlertSide.above,
                threshold: above,
              ),
            );
          }
          latch.aboveFired = true;
        } else {
          latch.aboveFired = false;
        }
      } else {
        latch.aboveFired = false;
      }

      final below = alert.below;
      if (below != null && below > 0) {
        if (price <= below) {
          if (!latch.belowFired) {
            hits.add(
              PriceAlertHit(
                alert: alert,
                price: price,
                side: PriceAlertSide.below,
                threshold: below,
              ),
            );
          }
          latch.belowFired = true;
        } else {
          latch.belowFired = false;
        }
      } else {
        latch.belowFired = false;
      }
    }
    return hits;
  }
}

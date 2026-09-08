import 'package:invest/domain/models/profit_alert.dart';
import 'package:invest/domain/services/price_alert_engine.dart';

class ProfitPosition {
  const ProfitPosition({
    required this.id,
    required this.name,
    this.symbol = '',
    required this.pnl,
    required this.pnlPct,
    this.qty = 0,
    this.cost = 0,
    this.price = 0,
  });

  final String id;
  final String name;
  final String symbol;
  final double pnl;
  final double pnlPct;
  final double qty;
  final double cost;
  final double price;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'symbol': symbol,
        'pnl': pnl,
        'pnl_pct': pnlPct,
        'qty': qty,
        'cost': cost,
        'price': price,
      };

  factory ProfitPosition.fromJson(Map<String, dynamic> m) {
    final qty = (m['qty'] as num?)?.toDouble() ?? 0;
    final cost = (m['cost'] as num?)?.toDouble() ?? 0;
    final price = (m['price'] as num?)?.toDouble() ?? 0;
    final pnl = (m['pnl'] as num?)?.toDouble() ?? (qty * price - cost);
    final pct = (m['pnl_pct'] as num?)?.toDouble() ??
        (cost.abs() < 1e-12 ? 0.0 : pnl / cost * 100);
    return ProfitPosition(
      id: '${m['id'] ?? ''}',
      name: '${m['name'] ?? ''}',
      symbol: '${m['symbol'] ?? ''}',
      pnl: pnl,
      pnlPct: pct,
      qty: qty,
      cost: cost,
      price: price,
    );
  }

  ProfitPosition revalued(double nextPrice) {
    final nextPnl = qty * nextPrice - cost;
    final nextPct = cost.abs() < 1e-12 ? 0.0 : nextPnl / cost * 100;
    return ProfitPosition(
      id: id,
      name: name,
      symbol: symbol,
      pnl: nextPnl,
      pnlPct: nextPct,
      qty: qty,
      cost: cost,
      price: nextPrice,
    );
  }
}

class ProfitAlertHit {
  const ProfitAlertHit({
    required this.alert,
    required this.position,
    required this.side,
    required this.thresholdLabel,
  });

  final ProfitAlert alert;
  final ProfitPosition position;
  final PriceAlertSide side;
  final String thresholdLabel;
}

class ProfitAlertEngine {
  static List<ProfitAlertHit> evaluate({
    required List<ProfitAlert> alerts,
    required Map<String, ProfitPosition> positions,
    required Map<String, PriceAlertLatch> latches,
  }) {
    final hits = <ProfitAlertHit>[];
    for (final alert in alerts) {
      if (!alert.isArmed || alert.id.isEmpty) continue;
      final pos = positions[alert.id];
      if (pos == null) continue;
      final latch = latches.putIfAbsent(alert.id, PriceAlertLatch.new);

      final profit = _profitCrossed(alert, pos);
      if (profit != null) {
        if (!latch.aboveFired) {
          hits.add(
            ProfitAlertHit(
              alert: alert,
              position: pos,
              side: PriceAlertSide.above,
              thresholdLabel: profit,
            ),
          );
        }
        latch.aboveFired = true;
      } else {
        latch.aboveFired = false;
      }

      final loss = _lossCrossed(alert, pos);
      if (loss != null) {
        if (!latch.belowFired) {
          hits.add(
            ProfitAlertHit(
              alert: alert,
              position: pos,
              side: PriceAlertSide.below,
              thresholdLabel: loss,
            ),
          );
        }
        latch.belowFired = true;
      } else {
        latch.belowFired = false;
      }
    }
    return hits;
  }

  static String? _profitCrossed(ProfitAlert a, ProfitPosition p) {
    final parts = <String>[];
    if (a.profitToman != null && a.profitToman! > 0 && p.pnl >= a.profitToman!) {
      parts.add('سود');
    }
    if (a.profitPct != null && a.profitPct! > 0 && p.pnlPct >= a.profitPct!) {
      parts.add('٪');
    }
    if (parts.isEmpty) return null;
    return parts.join('+');
  }

  static String? _lossCrossed(ProfitAlert a, ProfitPosition p) {
    final parts = <String>[];
    if (a.lossToman != null && a.lossToman! > 0 && p.pnl <= -a.lossToman!) {
      parts.add('زیان');
    }
    if (a.lossPct != null && a.lossPct! > 0 && p.pnlPct <= -a.lossPct!) {
      parts.add('٪');
    }
    if (parts.isEmpty) return null;
    return parts.join('+');
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/dashboard_pnl.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/holding_metrics.dart';
import 'package:invest/domain/utils/buy_usd.dart';

void main() {
  group('sell FX lock', () {
    test('encode/parse sell_fx in sell note', () {
      final packed = encodeSellNoteFx(fx: 95000, note: 'broker A');
      expect(packed, contains('[sell_fx:95000]'));
      expect(parseSellNoteFx(packed).fx, closeTo(95000, 1e-9));
      expect(parseSellNoteFx(packed).note, 'broker A');
    });

    test('realized USD stays fixed when live USDT moves', () {
      final closed = [
        Trade(
          assetId: 1,
          status: AppConfig.tradeClosed,
          quantity: 1,
          buyPrice: 1e9,
          buyPriceUsd: 20000,
          buyUsdTmn: 50000,
          sellPrice: 1.2e9,
          sellFee: 0,
          sellDate: '2026-01-15',
          sellNote: encodeSellNoteFx(fx: 60000, note: ''),
          realizedPnl: 2e8,
        ),
      ];
      final atClose = DashboardCurrencyPnl.compute(
        assets: const [],
        openTrades: const [],
        closedTrades: closed,
        usdtTmn: 60000,
        yearKey: '2026',
        calendar: AppConfig.calendarGregorian,
      );
      final later = DashboardCurrencyPnl.compute(
        assets: const [],
        openTrades: const [],
        closedTrades: closed,
        usdtTmn: 90000, // live moved — must not change realized USD
        yearKey: '2026',
        calendar: AppConfig.calendarGregorian,
      );
      // 1.2e9/60k − 20k = 0
      expect(atClose.realizedUsd, closeTo(0, 1e-6));
      expect(later.realizedUsd, closeTo(atClose.realizedUsd!, 1e-6));
    });
  });

  group('USD buy fee', () {
    test('buyCostUsd includes fee at buy FX', () {
      final t = Trade(
        assetId: 1,
        status: AppConfig.tradeOpen,
        quantity: 2,
        buyPrice: 100,
        buyPriceUsd: 10,
        buyUsdTmn: 50,
        buyFee: 100, // 100 TMN / 50 = $2
      );
      expect(t.buyCostUsd, closeTo(22, 1e-9));
    });

    test('holding costBasisUsd includes buy fee', () {
      final asset = Asset(
        id: 1,
        name: 'X',
        quantity: 1,
        avgBuyPrice: 100000,
        currentPrice: 110000,
      );
      final open = [
        Trade(
          assetId: 1,
          status: AppConfig.tradeOpen,
          quantity: 1,
          buyPrice: 100000,
          buyPriceUsd: 2,
          buyUsdTmn: 50000,
          buyFee: 50000,
        ),
      ];
      final m = HoldingMetrics.forAsset(asset, open);
      expect(m.costBasisUsd, closeTo(3, 1e-9)); // 2 + 50000/50000
      expect(m.avgBuyPriceUsd, closeTo(2, 1e-9));
    });
  });

  group('total PnL % lifetime invested', () {
    test('fully closed book still reports ROI vs buy cost', () {
      final closed = [
        Trade(
          assetId: 1,
          status: AppConfig.tradeClosed,
          quantity: 1,
          buyPrice: 100,
          buyFee: 0,
          sellPrice: 150,
          realizedPnl: 50,
        ),
      ];
      final pct = DashboardCurrencyPnl.totalPnlPct(
        totalPnl: 50,
        assets: const [],
        openTrades: const [],
        closedTrades: closed,
      );
      expect(pct, closeTo(50, 1e-9));
    });
  });

  group('gold 18k-equivalent grams', () {
    test('24k lot scales to 18k-equivalent on dashboard', () {
      final snap = DashboardSnapshot.compute(
        assets: [
          Asset(
            id: 1,
            name: 'آبشده',
            symbol: 'GOLD',
            quantity: 10,
            avgBuyPrice: 1,
            currentPrice: 1,
            notes: '[kind:gold][meta:{"purity":"24"}]',
          ),
        ],
        openTrades: [
          Trade(
            assetId: 1,
            status: AppConfig.tradeOpen,
            quantity: 10,
            buyPrice: 1,
            assetName: 'آبشده',
            assetSymbol: 'GOLD',
          ),
        ],
        closedTrades: const [],
        usdtTmn: 100000,
        calendar: AppConfig.calendarJalali,
      );
      // 10g 24k → 10 / 0.75 = 13.333… g 18k-eq
      expect(snap.goldHoldingG, closeTo(10 / 0.75, 1e-9));
    });
  });
}

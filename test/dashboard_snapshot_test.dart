import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/state/app_state.dart';

void main() {
  test('dashboard market value follows live holding marks, not stale metrics', () {
    final assets = [
      Asset(
        id: 1,
        name: 'Bitcoin',
        symbol: 'BTC',
        quantity: 1,
        avgBuyPrice: 1e9,
        currentPrice: 8e9, // live overlay
      ),
    ];
    final open = [
      Trade(
        assetId: 1,
        status: AppConfig.tradeOpen,
        quantity: 1,
        buyPrice: 1e9,
        buyPriceUsd: 20000,
        currentPrice: 1e9, // stale lot mark
      ),
    ];
    final snap = DashboardSnapshot.compute(
      assets: assets,
      openTrades: open,
      closedTrades: const [],
      usdtTmn: 100000,
      calendar: AppConfig.calendarJalali,
    );
    expect(snap.marketValue, 8e9);
    expect(snap.unrealizedPnl, 7e9);
    expect(snap.marketValueUsd, closeTo(80000, 1e-6));
    expect(snap.unrealizedUsd, closeTo(60000, 1e-6));
    expect(snap.usdIncomplete, isFalse);
  });

  test('unrealized percent is vs open cost, not mixed with realized', () {
    final assets = [
      Asset(id: 1, name: 'A', quantity: 1, avgBuyPrice: 100, currentPrice: 120),
    ];
    final closed = [
      Trade(
        assetId: 1,
        status: AppConfig.tradeClosed,
        quantity: 1,
        buyPrice: 50,
        sellPrice: 200,
        realizedPnl: 150,
        sellDate: '2026-01-01',
      ),
    ];
    final snap = DashboardSnapshot.compute(
      assets: assets,
      openTrades: const [],
      closedTrades: closed,
      usdtTmn: 50,
      calendar: AppConfig.calendarGregorian,
    );
    expect(snap.unrealizedPnl, 20);
    expect(snap.unrealizedPct, closeTo(20, 1e-9));
    expect(snap.realizedPnl, 150);
    expect(snap.totalPnl, 170);
    // Must not be 170/100 = 170%.
    expect(snap.unrealizedPct, isNot(closeTo(170, 1e-9)));
  });

  test('gold holding sums open gold lots only', () {
    final snap = DashboardSnapshot.compute(
      assets: [
        Asset(id: 1, name: 'طلا', symbol: 'GOLD', quantity: 3, avgBuyPrice: 1, currentPrice: 1),
        Asset(id: 2, name: 'BTC', symbol: 'BTC', quantity: 1, avgBuyPrice: 1, currentPrice: 1),
      ],
      openTrades: [
        Trade(
          assetId: 1,
          status: AppConfig.tradeOpen,
          quantity: 3,
          buyPrice: 1,
          assetName: 'طلا',
          assetSymbol: 'GOLD',
        ),
        Trade(
          assetId: 2,
          status: AppConfig.tradeOpen,
          quantity: 1,
          buyPrice: 1,
          assetName: 'BTC',
          assetSymbol: 'BTC',
        ),
      ],
      closedTrades: const [],
      usdtTmn: 100000,
      calendar: AppConfig.calendarJalali,
    );
    expect(snap.goldHoldingG, 3);
    expect(snap.openLotCount, 2);
  });

  test('pending cheques move NAV and leave trading pnl unchanged', () {
    final snap = DashboardSnapshot.compute(
      assets: [
        Asset(
          id: 1,
          name: 'Bitcoin',
          quantity: 1,
          avgBuyPrice: 100,
          currentPrice: 140,
        ),
      ],
      openTrades: const [],
      closedTrades: const [],
      usdtTmn: 50,
      calendar: AppConfig.calendarGregorian,
      checks: [
        BankCheck(
          direction: checkDirectionReceivable,
          amount: 30,
          issueDate: '2026-10-01',
          dueDate: '2026-11-01',
          status: checkStatusPending,
        ),
        BankCheck(
          direction: checkDirectionPayable,
          amount: 10,
          issueDate: '2026-10-01',
          dueDate: '2026-11-01',
          status: checkStatusPending,
        ),
        BankCheck(
          direction: checkDirectionReceivable,
          amount: 999,
          issueDate: '2026-09-01',
          dueDate: '2026-09-15',
          status: checkStatusBounced,
        ),
        BankCheck(
          direction: checkDirectionPayable,
          amount: 888,
          issueDate: '2026-09-01',
          dueDate: '2026-09-15',
          status: checkStatusCleared,
        ),
        BankCheck(
          direction: checkDirectionReceivable,
          amount: 777,
          issueDate: '2026-08-01',
          dueDate: '2026-08-20',
          status: checkStatusCancelled,
        ),
        BankCheck(
          direction: checkDirectionReceivable,
          amount: 666,
          issueDate: '2026-08-01',
          dueDate: '2026-08-20',
          status: checkStatusEndorsed,
        ),
      ],
    );

    expect(snap.holdingsValue, 140);
    expect(snap.chequeNav.pendingReceivable, 30);
    expect(snap.chequeNav.pendingPayable, 10);
    expect(snap.chequeNav.net, 20);
    expect(snap.marketValue, 160);
    expect(snap.unrealizedPnl, 40);
    expect(snap.costBasis, 100);
    expect(snap.marketValueUsd, closeTo(3.2, 1e-9));
  });

  test('the capital chart stamps today with cheque-adjusted NAV', () {
    final state = AppState()
      ..assets = [
        Asset(
          id: 1,
          name: 'Bitcoin',
          quantity: 1,
          avgBuyPrice: 80,
          currentPrice: 100,
        ),
      ]
      ..checks = [
        BankCheck(
          direction: checkDirectionReceivable,
          amount: 25,
          issueDate: '2026-10-01',
          dueDate: '2026-12-01',
        ),
        BankCheck(
          direction: checkDirectionPayable,
          amount: 5,
          issueDate: '2026-10-01',
          dueDate: '2026-12-01',
        ),
      ]
      ..metrics = const DashboardMetrics(
        totalValue: 100,
        totalPnl: 20,
        totalPnlPct: 25,
        realizedPnl: 0,
        unrealizedPnl: 20,
        openCount: 1,
        closedCount: 0,
        yearRealizedPnl: 0,
        yearKey: '2026',
        goldFund: GoldFundMetrics(goldInG: 0, goldOutG: 0, goldHoldingG: 0),
        growthSeries: [SeriesPoint(date: '2020-01-01', value: 80)],
      );

    expect(state.capitalGrowthSeries.last.value, 120);
  });
}

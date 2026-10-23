import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/dashboard_digest.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/portfolio_valuation.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:invest/ui/widgets/portfolio_value_card.dart';

Trade lot(int asset, double qty, double buy, {String date = '2026-01-01', String? sold, double? sellPrice, String name = 'x'}) => Trade(
      assetId: asset,
      status: sold == null ? AppConfig.tradeOpen : AppConfig.tradeClosed,
      quantity: qty,
      buyPrice: buy,
      buyDate: date,
      sellDate: sold,
      sellPrice: sellPrice,
      assetName: name,
    );

BankCheck chq(String dir, double amount, String due, {String status = checkStatusPending}) => BankCheck(
      direction: dir,
      amount: amount,
      issueDate: '2026-10-01',
      dueDate: due,
      status: status,
    );

final gold = Asset(id: 1, name: 'طلای ۱۸', symbol: 'GOLD', quantity: 10, avgBuyPrice: 90, currentPrice: 100);
final btc = Asset(id: 2, name: 'Bitcoin', symbol: 'BTC', quantity: 1, avgBuyPrice: 300, currentPrice: 400, notes: '[kind:crypto]');
final noPrice = Asset(id: 3, name: 'Fund', symbol: 'FND', quantity: 2, avgBuyPrice: 50, currentPrice: 0);

void main() {
  group('PortfolioValuation', () {
    test('NAV = holdings + open cheques; groups, gold and unpriced', () {
      final v = PortfolioValuation.of(
        assets: [gold, btc, noPrice],
        openTrades: [lot(1, 10, 90), lot(2, 1, 300), Trade(assetId: 3, status: AppConfig.tradeOpen, quantity: 2, buyPrice: 50, currentPrice: 50, assetName: 'Fund')],
        checks: [
          chq(checkDirectionReceivable, 70, '2026-11-01'),
          chq(checkDirectionPayable, 20, '2026-11-01'),
          chq(checkDirectionReceivable, 999, '2026-11-01', status: checkStatusCleared),
        ],
      );
      expect(v.holdingsValue, 1000 + 400 + 100); // fund falls back to the lot price
      expect(v.cheques.net, 50);
      expect(v.nav, 1550);
      expect(v.goldValue, 1000);
      expect(v.groups.first.kind, AssetKind.gold);
      expect(v.unpriced.map((a) => a.id), [3]);
    });

    test('dashboard snapshot uses the same valuation', () {
      final snap = DashboardSnapshot.compute(
        assets: [gold, btc],
        openTrades: [lot(1, 10, 90), lot(2, 1, 300)],
        closedTrades: const [],
        usdtTmn: 100,
        calendar: AppConfig.calendarGregorian,
        checks: [chq(checkDirectionPayable, 100, '2026-11-01')],
      );
      expect(snap.holdingsValue, snap.valuation!.holdingsValue);
      expect(snap.marketValue, snap.valuation!.nav);
      expect(snap.marketValue, 1300);
    });
  });

  group('PortfolioTrend (30 days, like for like)', () {
    const today = '2026-10-23';
    final series = [
      const SeriesPoint(date: '2026-09-01', value: 900),
      const SeriesPoint(date: '2026-09-20', value: 1000), // last point at/before the window start
      const SeriesPoint(date: '2026-10-10', value: 1040),
    ];

    test('baseline is the last point at or before the window start', () {
      final t = PortfolioTrend.window(series: series, todayValue: 1100, today: today);
      expect(t.baseDate, '2026-09-20');
      expect(t.pct, closeTo(10, 1e-9));
      expect(t.points.first.date, '2026-09-20');
      expect(t.points.last.value, 1100);
      expect(t.points.length, 3);
    });

    test('a buy inside the window is not counted as growth', () {
      final t = PortfolioTrend.window(
        series: series,
        todayValue: 1300,
        today: today,
        openTrades: [lot(2, 1, 200, date: '2026-10-15')],
      );
      expect(t.netFlows, 200);
      expect(t.pct, closeTo(10, 1e-9));
    });

    test('a sale inside the window counts its gain, not the cash taken out', () {
      // Lot bought before the window for 100, sold inside for 150.
      final t = PortfolioTrend.window(
        series: series,
        todayValue: 850,
        today: today,
        closedTrades: [lot(2, 1, 100, date: '2026-08-01', sold: '2026-10-12', sellPrice: 150)],
      );
      expect(t.netFlows, -150);
      expect(t.pct, closeTo(0, 1e-9));
    });

    test('cheques never move the trend (today is holdings only)', () {
      final a = PortfolioTrend.window(series: series, todayValue: 1100, today: today);
      final v = PortfolioValuation.of(
        assets: [Asset(id: 1, name: 'X', quantity: 1, avgBuyPrice: 1, currentPrice: 1100)],
        openTrades: const [],
        checks: [chq(checkDirectionReceivable, 5000, '2026-11-01')],
      );
      final b = PortfolioTrend.window(series: series, todayValue: v.holdingsValue, today: today);
      expect(b.pct, a.pct);
    });

    test('no usable baseline → no percentage', () {
      final t = PortfolioTrend.window(series: const [], todayValue: 1000, today: today);
      expect(t.pct, isNull);
      expect(t.points.length, 1);
      final z = PortfolioTrend.window(
          series: const [SeriesPoint(date: '2026-10-01', value: 0)], todayValue: 10, today: today);
      expect(z.pct, isNull);
    });

    test('young history uses its first point inside the window', () {
      final t = PortfolioTrend.window(
          series: const [SeriesPoint(date: '2026-10-20', value: 500)], todayValue: 550, today: today);
      expect(t.baseDate, '2026-10-20');
      expect(t.pct, closeTo(10, 1e-9));
    });
  });

  group('dashboard digest', () {
    const today = '2026-10-23';
    test('upcoming cheques: open only, nearest (overdue) first', () {
      final list = upcomingCheques([
        chq(checkDirectionReceivable, 1, '2026-11-20'),
        chq(checkDirectionPayable, 2, '2026-10-26'),
        chq(checkDirectionPayable, 3, '2026-10-20'),
        chq(checkDirectionPayable, 4, '2026-10-24', status: checkStatusCleared),
      ], today: today);
      expect(list.map((u) => u.daysLeft), [-3, 3, 28]);
    });

    test('alerts: overdue, payable due soon, unpriced; most urgent first', () {
      final alerts = dashboardAlerts(
        checks: [
          chq(checkDirectionPayable, 62600000, '2026-10-26'),
          chq(checkDirectionReceivable, 1, '2026-10-01'),
          chq(checkDirectionReceivable, 1, '2026-12-30'),
        ],
        today: today,
        unpriced: [noPrice],
        bizMismatchMonths: 1,
      );
      expect(alerts.map((a) => a.kind), [
        DashAlertKind.chequeOverdue,
        DashAlertKind.chequeDueSoon,
        DashAlertKind.unpriced,
        DashAlertKind.bizMismatch,
      ]);
      expect(alerts[1].title, contains('3 روز دیگر'));
    });

    test('nothing to report → no alerts', () {
      expect(dashboardAlerts(checks: const [], today: today), isEmpty);
    });

    test('PWO summary: latest month, people, met count and streak', () {
      final l = PwoLedger(target: 100, months: {
        pwoMonthKey(1405, 5): PwoMonth(year: 1405, month: 5, amounts: {'p0': 120}),
        pwoMonthKey(1405, 6): PwoMonth(year: 1405, month: 6, amounts: {'p0': 50, 'p1': 10}),
        pwoMonthKey(1405, 7): PwoMonth(year: 1405, month: 7, amounts: {'p0': 60, 'p2': 20}),
      });
      final s = PwoMonthSummary.of(l)!;
      expect(s.month.month, 7);
      expect(s.total, 80);
      expect(s.monthsMet, 1);
      expect(s.monthsWithData, 3);
      expect(s.belowStreak, 2);
      expect(s.people.map((p) => p.amount), [60, 0, 20]);
      final a = dashboardAlerts(checks: const [], today: today, pwo: s, pwoMonthLabel: 'مهر');
      expect(a.single.kind, DashAlertKind.pwoBelowTarget);
      expect(a.single.title, 'برداشت مهر 20٪ زیر هدف');
      expect(PwoMonthSummary.of(PwoLedger()), isNull);
    });
  });

  group('text helpers', () {
    test('Persian digits and separators, signs kept in front', () {
      expect(fa('1,250.5 تومان'), '۱٬۲۵۰٫۵ تومان');
      expect(fa('a, b. 3'), 'a, b. ۳');
      expect(faSigned('+120 میلیون ت'), '\u2066+۱۲۰\u2069 میلیون ت');
      expect(signFix('بدون علامت'), 'بدون علامت');
    });
  });

  group('PortfolioValueCard', () {
    DashboardSnapshot snap() => DashboardSnapshot.compute(
          assets: [gold, btc, noPrice],
          openTrades: [lot(1, 10, 90, name: 'طلای ۱۸'), lot(2, 1, 300)],
          closedTrades: const [],
          usdtTmn: 50,
          calendar: AppConfig.calendarGregorian,
          checks: [chq(checkDirectionReceivable, 70, '2026-11-01'), chq(checkDirectionPayable, 20, '2026-11-01')],
        );

    Future<void> pump(WidgetTester t, Widget w, {double width = 390, double scale = 1}) async {
      t.view.physicalSize = Size(width, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 1400), textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(12), child: w))),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    final now = DateTime(2026, 10, 23, 9, 30);
    PortfolioValueCard card({bool live = true, bool offline = false, bool expanded = false}) => PortfolioValueCard(
          snap: snap(),
          trend: PortfolioTrend.window(
            series: const [SeriesPoint(date: '2026-09-20', value: 1200)],
            todayValue: snap().holdingsValue,
            today: '2026-10-23',
          ),
          usdIsLive: live,
          pricesAsOf: now.subtract(const Duration(minutes: 5)),
          offline: offline,
          lastSyncedAt: DateTime(2026, 10, 23, 8, 42),
          initiallyExpanded: expanded,
          now: now,
        );

    testWidgets('collapsed: live tag, rate, freshness, gold chip, trend, unpriced', (t) async {
      await pump(t, card());
      expect(find.byKey(const ValueKey('pv-live')), findsOneWidget);
      expect(find.text('۱٬۴۵۰ تومان'), findsOneWidget); // 1000+400+0 + 70 − 20
      expect(find.textContaining('نرخ زنده'), findsOneWidget);
      expect(find.text('قیمت‌ها: ۵ دقیقه پیش'), findsOneWidget);
      expect(find.byKey(const ValueKey('pv-gold-chip')), findsOneWidget);
      expect(find.text('روند ۳۰ روز'), findsOneWidget);
      expect(find.byKey(const ValueKey('pv-unpriced')), findsOneWidget);
      expect(find.text('سود دلاری'), findsOneWidget);
      expect(find.byKey(const ValueKey('pv-breakdown')), findsNothing);
      await t.tap(find.byKey(const ValueKey('pv-toggle')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pv-gold-section')), findsOneWidget);
      expect(find.text('موجودی طلا · پوشش تورم'), findsOneWidget);
      expect(find.text('جزو جمع ارزش پورتفو حساب شده است'), findsOneWidget);
    });

    testWidgets('offline: last sync tag and stored rate', (t) async {
      await pump(t, card(live: false, offline: true));
      expect(find.text('آفلاین · آخرین همگام‌سازی ۰۸:۴۲'), findsOneWidget);
      expect(find.textContaining('نرخ ذخیره‌شده'), findsOneWidget);
      expect(find.byKey(const ValueKey('pv-live')), findsNothing);
    });

    testWidgets('no overflow at 320 px with large text', (t) async {
      await pump(t, card(expanded: true), width: 320, scale: 1.6);
      expect(t.takeException(), isNull);
    });
  });
}

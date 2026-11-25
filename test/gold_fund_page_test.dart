import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/gold_cash_entry.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/gold_price_log.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/gold/gold_format.dart';
import 'package:invest/ui/pages/capital_chart_page.dart';
import 'package:invest/ui/pages/dashboard_page.dart';
import 'package:invest/ui/pages/gold_fund_page.dart';
import 'package:invest/ui/pages/trades_page.dart';
import 'package:invest/ui/widgets/asset_delete.dart';
import 'package:invest/ui/widgets/gold_calc_sheet.dart';
import 'package:invest/ui/widgets/gold_cash_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<GoldPricePoint> _log() {
  final out = <GoldPricePoint>[];
  final today = DateTime.now();
  for (var i = 120; i >= 0; i--) {
    final d = DateTime(today.year, today.month, today.day).subtract(Duration(days: i));
    final iso = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    out.add(GoldPricePoint(date: iso, mid: 13000000 + i * -9000 + (i % 7) * 40000 + 1100000));
  }
  return out;
}

String _daysAgo(int n) {
  final d = DateTime.now().subtract(Duration(days: n));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

AppState _state({bool empty = false}) {
  final s = AppState()
    ..loading = false
    ..authenticated = true
    ..liveGold = 14280000
    ..liveGoldBid = 14210000
    ..liveGoldAsk = 14350000
    ..liveGoldChange24h = 1.2
    ..settings = AppSettings(calendar: AppConfig.calendarJalali, goldTmnPerGram: 14280000);
  if (empty) return s;
  s
    ..goldPriceLog = _log()
    ..assets = [
      Asset(id: 1, name: 'طلای آب‌شده', symbol: 'GOLD', quantity: 30, avgBuyPrice: 11000000, currentPrice: 14280000),
      Asset(
          id: 2,
          name: 'طلای ۲۴ عیار',
          symbol: 'GOLD',
          quantity: 3,
          avgBuyPrice: 15000000,
          currentPrice: 19040000,
          notes: '[meta:{"purity":"24"}]'),
      Asset(
          id: 3,
          name: 'Bitcoin',
          symbol: 'BTC',
          quantity: 1,
          avgBuyPrice: 1e9,
          currentPrice: 1.2e9,
          notes: '[kind:crypto]'),
    ]
    ..openTrades = [
      Trade(
          id: 10,
          assetId: 1,
          status: AppConfig.tradeOpen,
          quantity: 8,
          buyPrice: 9850000,
          buyDate: _daysAgo(500),
          assetName: 'طلای آب‌شده'),
      Trade(
          id: 11,
          assetId: 1,
          status: AppConfig.tradeOpen,
          quantity: 12.5,
          buyPrice: 12400000,
          buyFee: 62000,
          buyDate: _daysAgo(80),
          buyNote: '[gf:op1]',
          assetName: 'طلای آب‌شده'),
      Trade(
          id: 12,
          assetId: 1,
          status: AppConfig.tradeOpen,
          quantity: 9.5,
          buyPrice: 12361400,
          buyDate: _daysAgo(20),
          assetName: 'طلای آب‌شده'),
      Trade(
          id: 13,
          assetId: 2,
          status: AppConfig.tradeOpen,
          quantity: 3,
          buyPrice: 15000000,
          buyDate: _daysAgo(60),
          assetName: 'طلای ۲۴ عیار'),
      Trade(id: 14, assetId: 3, status: AppConfig.tradeOpen, quantity: 1, buyPrice: 1e9, assetName: 'Bitcoin'),
    ]
    ..closedTrades = [
      Trade(
        id: 20,
        assetId: 1,
        status: AppConfig.tradeClosed,
        quantity: 6,
        buyPrice: 10000000,
        buyDate: _daysAgo(400),
        sellPrice: 14139000,
        sellFee: 424170,
        sellDate: _daysAgo(10),
        sellNote: '[gf:op2]',
        realizedPnl: 6 * 4139000 - 424170,
        assetName: 'طلای آب‌شده',
      ),
    ]
    ..settings.goldFundLedger = [
      GoldCashEntry(id: 'a', kind: GoldCashKind.opening, amount: 300000000, date: _daysAgo(200)),
      GoldCashEntry(id: 'b', kind: GoldCashKind.withdraw, amount: -40000000, date: _daysAgo(30), note: 'خرج خانه'),
    ]
    ..metrics = const DashboardMetrics(
      totalValue: 0,
      totalPnl: 0,
      totalPnlPct: 0,
      realizedPnl: 0,
      unrealizedPnl: 0,
      openCount: 5,
      closedCount: 1,
      yearRealizedPnl: 0,
      yearKey: '1405',
      goldFund: GoldFundMetrics(goldInG: 0, goldOutG: 0, goldHoldingG: 0),
    );
  return s;
}

Future<void> _pump(WidgetTester tester, AppState s, Widget home,
    {Size size = const Size(320, 5000), double text = 1.3}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(
      locale: const Locale('fa', 'IR'),
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(text)),
          child: child!,
        ),
      ),
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('fund page: every section, no overflow at 320 px and 1.3× text', (tester) async {
    final s = _state();
    await _pump(tester, s, const GoldFundPage());
    expect(tester.takeException(), isNull);
    for (final k in [
      'gf-ribbon',
      'gf-ask',
      'gf-bid',
      'gf-mazaneh',
      'gf-hero',
      'gf-total',
      'gf-split-chip',
      'gf-pocket-gold',
      'gf-pocket-cash',
      'gf-buy',
      'gf-sell',
      'gf-deposit',
      'gf-withdraw',
      'gf-calc',
      'gf-avg',
      'gf-unrealized',
      'gf-breakeven',
      'gf-realized',
      'gf-flow',
      'gf-chart',
      'gf-chart-paint',
      'gf-scenario',
      'gf-lots',
      'gf-cash',
    ]) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    expect(find.byKey(const ValueKey('gf-estimated')), findsNothing); // real WallGold sides
    expect(find.text('۱۴٬۳۵۰٬۰۰۰'), findsWidgets); // ask
    expect(find.textContaining('خودکار'), findsWidgets); // tagged trade rows
    expect(find.textContaining('خرج خانه'), findsOneWidget);
    // Fund total = gold value (18k + 24k) + cash.
    final book = s.goldFund;
    expect(book.cash, closeTo(300000000 - 40000000 - (12.5 * 12400000 + 62000) + 6 * 14139000 - 424170, 1));
    expect(find.textContaining('مانده'), findsWidgets);

    // Range switch keeps the chart.
    await tester.tap(find.text('۱ ماه'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gf-chart-paint')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fund page also fits a normal phone and plain text', (tester) async {
    await _pump(tester, _state(), const GoldFundPage(), size: const Size(390, 4000), text: 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty fund: guidance, no chart history, sell disabled', (tester) async {
    final s = _state(empty: true);
    await _pump(tester, s, const GoldFundPage());
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('gf-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('gf-chart-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('gf-lots')), findsNothing);
    final sell = tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('gf-sell')));
    expect(sell.onPressed, isNull);
  });

  testWidgets('«ارزش پورتفو» gold block opens the fund', (tester) async {
    final s = _state();
    await _pump(tester, s, const CapitalChartPage(), size: const Size(320, 4000));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('pv-gold-fund-cash')), findsOneWidget);
    expect(find.byKey(const ValueKey('pv-group-gold-fund-cash')), findsOneWidget);
    expect(find.byKey(const ValueKey('pv-holdings-fund-total')), findsOneWidget);
    expect(find.byKey(const ValueKey('vp-gold-fund-cash')), findsOneWidget);
    expect(find.text('صندوق طلا و ماشین‌حساب خرید و فروش'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('pv-gold-open-fund')));
    await tester.tap(find.byKey(const ValueKey('pv-gold-open-fund')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gf-title')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fund cash alone still shows the gold block', (tester) async {
    final s = _state(empty: true)
      ..assets = [
        Asset(
            id: 3, name: 'Bitcoin', symbol: 'BTC', quantity: 1, avgBuyPrice: 1, currentPrice: 2, notes: '[kind:crypto]')
      ]
      ..openTrades = [Trade(id: 1, assetId: 3, status: AppConfig.tradeOpen, quantity: 1, buyPrice: 1)];
    s.settings.goldFundLedger = [
      const GoldCashEntry(id: 'a', kind: GoldCashKind.deposit, amount: 5000000, date: '2026-01-01')
    ];
    await _pump(tester, s, const CapitalChartPage(), size: const Size(320, 4000));
    expect(find.byKey(const ValueKey('pv-gold-section')), findsOneWidget);
    expect(find.byKey(const ValueKey('pv-gold-fund-cash')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard gold section opens the fund', (tester) async {
    resetDashboardExpandCache();
    SharedPreferences.setMockInitialValues({
      'dash_open_v1': ['gold']
    });
    final s = _state();
    await _pump(tester, s, const Scaffold(body: DashboardPage()), size: const Size(320, 6000));
    final row = find.byKey(const ValueKey('dash-gold-fund'));
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gf-title')), findsOneWidget);
  });

  testWidgets('calculator: buy online by amount, jewelry by weight, sell FIFO and manual', (tester) async {
    final s = _state();
    await _pump(tester, s, const GoldFundPage(), size: const Size(320, 900));
    await tester.tap(find.byKey(const ValueKey('gf-buy')));
    await tester.pumpAndSettle();
    expect(find.byType(GoldCalcSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('gc-record')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('gc-input')), '100000000');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gc-result')), findsOneWidget);
    expect(find.text('طلایی که می‌گیرید'), findsOneWidget);
    expect(find.byKey(const ValueKey('gc-enough')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Jewelry by weight: hidden cost warning.
    await tester.tap(find.text('زینتی'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('با وزن'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('gc-input')), '12');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gc-making')), findsOneWidget);
    expect(find.byKey(const ValueKey('gc-warn-cost')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Very large weight → shortfall and the deposit-the-gap button.
    await tester.enterText(find.byKey(const ValueKey('gc-input')), '100');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gc-shortfall')), findsOneWidget);
    expect(find.text('واریز کسری و ثبت خرید'), findsOneWidget);

    // مظنه price input.
    await tester.ensureVisible(find.byKey(const ValueKey('gc-price-mazaneh')));
    await tester.tap(find.byKey(const ValueKey('gc-price-mazaneh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gc-mazaneh-input')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('gc-mazaneh-input')), '43318000');
    await tester.pumpAndSettle();
    expect(find.text('۱۰٬۰۰۰٬۰۰۰'), findsWidgets); // 18k gram from مظنه

    // Sell 10 g FIFO: two lots.
    await tester.ensureVisible(find.byKey(const ValueKey('gc-side')));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('gc-side')), matching: find.text('فروش')));
    await tester.pumpAndSettle();
    expect(find.textContaining('موجودی'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('gc-input')), '10');
    await tester.pumpAndSettle();
    expect(find.text('نقدی که می‌گیرید'), findsOneWidget);
    expect(find.byKey(const ValueKey('gc-takes')), findsOneWidget);
    expect(find.textContaining('لات‌هایی که فروخته می‌شوند (۲)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Too much.
    await tester.enterText(find.byKey(const ValueKey('gc-input')), '500');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gc-exceeds')), findsOneWidget);
    final rec = tester.widget<FilledButton>(find.byKey(const ValueKey('gc-record')));
    expect(rec.onPressed, isNull);

    // Manual lot choice: the weight comes from the picks.
    await tester.ensureVisible(find.byKey(const ValueKey('gc-order')));
    await tester.tap(find.byKey(const ValueKey('gc-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انتخاب دستی').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gc-manual')), findsOneWidget);
    expect(find.byKey(const ValueKey('gc-input')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('gc-manual-12')), '2');
    await tester.pumpAndSettle();
    expect(find.textContaining('لات‌هایی که فروخته می‌شوند (۱)'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('gc-record'))).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calculator inputs: grouped Toman, «2,5» g is 2.5 g, Persian digits', (tester) async {
    final s = _state();
    await _pump(tester, s, const GoldFundPage(), size: const Size(320, 900));
    await tester.tap(find.byKey(const ValueKey('gf-buy')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('gc-input')), '۱۰۰۰۰۰۰۰۰');
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(find.byKey(const ValueKey('gc-input')));
    expect(input.controller!.text, '100,000,000');
    expect(find.byKey(const ValueKey('gc-result')), findsOneWidget);
    // Weight with a comma decimal mark.
    await tester.tap(find.text('با وزن'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('gc-input')), '2,5');
    await tester.pumpAndSettle();
    expect(find.text('ثبت خرید ۲٫۵ گرم'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calculator only-calc mode has no record button', (tester) async {
    final s = _state();
    await _pump(tester, s, const GoldFundPage(), size: const Size(320, 900));
    await tester.tap(find.byKey(const ValueKey('gf-calc')));
    await tester.pumpAndSettle();
    expect(find.byType(GoldCalcSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('gc-record')), findsNothing);
    expect(find.text('بستن'), findsOneWidget);
  });

  testWidgets('cash sheet: withdraw over balance is refused, mirror toggle', (tester) async {
    final s = _state();
    await _pump(tester, s, const GoldFundPage(), size: const Size(320, 900));
    await tester.ensureVisible(find.byKey(const ValueKey('gf-withdraw')));
    await tester.tap(find.byKey(const ValueKey('gf-withdraw')));
    await tester.pumpAndSettle();
    expect(find.byType(GoldCashSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('gcs-mirror')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('gcs-amount')), '99999999999');
    await tester.pumpAndSettle();
    expect(find.textContaining('بیشتر است'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('gcs-save'))).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('gcs-amount')), '10000000');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('gcs-save'))).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    // Adjust mode hides chips and the mirror.
    await tester.tap(find.text('تنظیم مانده'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gcs-mirror')), findsNothing);
  });

  testWidgets('deleting a closed fund trade or its asset warns about fund cash', (tester) async {
    final s = _state();
    await _pump(
      tester,
      s,
      Scaffold(
        body: Builder(
          builder: (ctx) => Column(children: [
            TextButton(
                onPressed: () => confirmDeleteClosedTrade(ctx, s.closedTrades.first), child: const Text('trade')),
            TextButton(onPressed: () => confirmDeleteAsset(ctx, s.assets.first), child: const Text('asset')),
          ]),
        ),
      ),
      size: const Size(400, 900),
      text: 1,
    );
    await tester.tap(find.text('trade'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trade-delete-gold-fund')), findsOneWidget);
    expect(find.textContaining('نقد صندوق از'), findsOneWidget);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('asset'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('asset-delete-gold-fund')), findsOneWidget);
  });

  testWidgets('open lots show how many days they have been open, sheet picker too', (tester) async {
    final s = _state();
    // A lot bought today and the open remainder of a partly sold lot.
    s.openTrades = [
      ...s.openTrades,
      Trade(
          id: 15,
          assetId: 1,
          status: AppConfig.tradeOpen,
          quantity: 1.25,
          buyPrice: 14300000,
          buyDate: todayIso(),
          assetName: 'طلای آب‌شده'),
    ];
    await _pump(tester, s, const GoldFundPage());
    expect(find.byKey(const ValueKey('gf-lot-15')), findsOneWidget); // 5 lots: all shown
    String label(int id) =>
        tester.widget<Text>(find.descendant(of: find.byKey(ValueKey('gf-lot-days-$id')), matching: find.byType(Text))).data!;
    for (final t in s.openTrades.where((t) => t.assetId != 3)) {
      expect(label(t.id!), gDays(lotOpenDays(t.buyDate)!), reason: 'lot ${t.id}');
    }
    expect(label(15), 'امروز');
    expect(label(10), matches(RegExp(r'^[۰-۹٬]+ روز$'))); // Persian digits, about 500 days
    // Closed lots and non-gold trades get no chip.
    expect(find.byKey(const ValueKey('gf-lot-days-20')), findsNothing);
    expect(find.byKey(const ValueKey('gf-lot-days-14')), findsNothing);
    // The chip sits on the buy-date line of its row.
    final chip = tester.getRect(find.byKey(const ValueKey('gf-lot-days-12')));
    final row = tester.getRect(find.byKey(const ValueKey('gf-lot-12')));
    expect(row.contains(chip.center), isTrue);
    expect(tester.takeException(), isNull);

    // Manual lot picker in the calculator.
    await tester.ensureVisible(find.byKey(const ValueKey('gf-sell')));
    await tester.tap(find.byKey(const ValueKey('gf-sell')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('gc-order')));
    await tester.tap(find.byKey(const ValueKey('gc-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انتخاب دستی').last);
    await tester.pumpAndSettle();
    for (final id in [10, 11, 12, 15]) {
      expect(find.byKey(ValueKey('gc-manual-days-$id')), findsOneWidget, reason: 'picker lot $id');
    }
    expect(find.descendant(of: find.byKey(const ValueKey('gc-manual-days-15')), matching: find.text('امروز')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('bottom area: system nav bar and keyboard', () {
    const navBar = 48.0;
    const keyboard = 300.0;

    /// A phone with a 48 px gesture/nav bar under the app (edge-to-edge),
    /// optionally with the keyboard open.
    void phone(WidgetTester tester, {bool keyboardOpen = false}) {
      tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
      // Android reports no bottom padding while the keyboard covers the bar.
      tester.view.padding = FakeViewPadding(bottom: keyboardOpen ? 0 : navBar);
      tester.view.viewInsets = FakeViewPadding(bottom: keyboardOpen ? keyboard : 0);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewInsets);
    }

    void expectAbove(WidgetTester tester, Finder f, double limit, String what) {
      final r = tester.getRect(f);
      expect(r.bottom, lessThanOrEqualTo(limit + 0.01), reason: '$what bottom ${r.bottom} > $limit');
    }

    void expectApart(WidgetTester tester, Finder a, Finder b) {
      final ra = tester.getRect(a), rb = tester.getRect(b);
      expect(ra.intersect(rb).width > 0 && ra.intersect(rb).height > 0, isFalse,
          reason: 'buttons overlap: $ra / $rb');
    }

    for (final (size, text) in const [(Size(320, 568), 1.3), (Size(360, 640), 1.3), (Size(360, 640), 1.0)]) {
      final tag = '${size.width.toInt()}x${size.height.toInt()} @${text}x';

      testWidgets('page: last rows clear the nav bar ($tag)', (tester) async {
        phone(tester);
        await _pump(tester, _state(), const GoldFundPage(), size: size, text: text);
        final pos = tester
            .state<ScrollableState>(
                find.descendant(of: find.byKey(const ValueKey('gf-list')), matching: find.byType(Scrollable)).first)
            .position;
        for (var i = 0; i < 8; i++) {
          pos.jumpTo(pos.maxScrollExtent); // lazy list: the extent firms up as it lays out
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expectAbove(tester, find.byKey(const ValueKey('gf-cash')), size.height - navBar, 'cash ledger');
        expect(tester.takeException(), isNull);
      });

      testWidgets('calculator footer clears the nav bar and the keyboard ($tag)', (tester) async {
        phone(tester);
        final s = _state();
        await _pump(tester, s, const GoldFundPage(), size: size, text: text);
        await tester.ensureVisible(find.byKey(const ValueKey('gf-buy')));
        await tester.tap(find.byKey(const ValueKey('gf-buy')));
        await tester.pumpAndSettle();
        final close = find.byKey(const ValueKey('gc-close'));
        final rec = find.byKey(const ValueKey('gc-record'));
        expectAbove(tester, close, size.height - navBar, 'فقط محاسبه');
        expectAbove(tester, rec, size.height - navBar, 'ثبت خرید');
        expectApart(tester, close, rec);
        expect(tester.takeException(), isNull);

        // Keyboard up: the footer sits on the keyboard, the field stays visible.
        phone(tester, keyboardOpen: true);
        await tester.pumpAndSettle();
        expectAbove(tester, close, size.height - keyboard, 'فقط محاسبه (keyboard)');
        expectAbove(tester, rec, size.height - keyboard, 'ثبت خرید (keyboard)');
        expectApart(tester, close, rec);
        await tester.showKeyboard(find.byKey(const ValueKey('gc-input')));
        await tester.pumpAndSettle();
        final input = tester.getRect(find.byKey(const ValueKey('gc-input')));
        expect(input.bottom, lessThanOrEqualTo(tester.getRect(close).top + 0.01), reason: 'input under the footer');
        expect(tester.takeException(), isNull);
      });

      testWidgets('cash sheet save clears the nav bar and the keyboard ($tag)', (tester) async {
        phone(tester);
        await _pump(tester, _state(), const GoldFundPage(), size: size, text: text);
        await tester.ensureVisible(find.byKey(const ValueKey('gf-deposit')));
        await tester.tap(find.byKey(const ValueKey('gf-deposit')));
        await tester.pumpAndSettle();
        final save = find.byKey(const ValueKey('gcs-save'));
        expect(save.hitTestable(), findsOneWidget, reason: 'save visible without scrolling');
        expectAbove(tester, save, size.height - navBar, 'ثبت');
        phone(tester, keyboardOpen: true);
        await tester.showKeyboard(find.byKey(const ValueKey('gcs-amount')));
        await tester.pumpAndSettle();
        expect(save.hitTestable(), findsOneWidget, reason: 'save visible with the keyboard up');
        expectAbove(tester, save, size.height - keyboard, 'ثبت (keyboard)');
        final amount = tester.getRect(find.byKey(const ValueKey('gcs-amount')));
        expect(amount.bottom, lessThanOrEqualTo(tester.getRect(save).top + 0.01), reason: 'amount under save');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the sheets\' result snackbar floats above the nav bar', (tester) async {
      phone(tester);
      await _pump(tester, _state(), const GoldFundPage(), size: const Size(360, 640), text: 1.3);
      // Same call the sheets make after closing.
      ScaffoldMessenger.of(tester.element(find.byKey(const ValueKey('gf-list'))))
          .showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('نقد صندوق ثبت شد.')));
      await tester.pumpAndSettle();
      expectAbove(tester, find.byType(SnackBar), 640 - navBar, 'snackbar');
    });
  });
}

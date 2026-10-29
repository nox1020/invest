import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/dashboard_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('dashboard avoids duplicating assets allocation desk',
      (tester) async {
    resetDashboardExpandCache();
    SharedPreferences.setMockInitialValues({'dash_open_v1': ['value', 'pnl', 'pwo', 'cheques', 'mix', 'alerts', 'gold']});
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: AppConfig.calendarGregorian)
      ..commodityIndex = [
        const CommodityQuote(
          id: 'usdt',
          name: 'تتر',
          symbol: 'USDT',
          unit: 'TMN',
          price: 100000,
          change24h: 0.2,
        ),
        const CommodityQuote(
          id: 'gold',
          name: 'طلا',
          symbol: 'GOLD',
          unit: 'TMN',
          price: 32000000,
          change24h: -0.4,
        ),
        const CommodityQuote(
          id: 'btc',
          name: 'بیت‌کوین',
          symbol: 'BTC',
          unit: 'TMN',
          price: 8e9,
          change24h: 1.2,
        ),
      ]
      ..assets = [
        Asset(
          id: 1,
          name: 'Bitcoin',
          symbol: 'BTC',
          quantity: 1,
          avgBuyPrice: 1e9,
          currentPrice: 1.2e9,
          notes: '[kind:crypto]',
        ),
      ]
      ..openTrades = [
        Trade(
          assetId: 1,
          status: AppConfig.tradeOpen,
          quantity: 1,
          buyPrice: 1e9,
          buyPriceUsd: 20000,
          assetName: 'Bitcoin',
          assetSymbol: 'BTC',
          currentPrice: 1.2e9,
        ),
      ]
      ..metrics = const DashboardMetrics(
        totalValue: 1.2e9,
        totalPnl: 2e8,
        totalPnlPct: 20,
        realizedPnl: 0,
        unrealizedPnl: 2e8,
        openCount: 1,
        closedCount: 0,
        yearRealizedPnl: 0,
        yearKey: '2026',
        goldFund: GoldFundMetrics(goldInG: 0, goldOutG: 0, goldHoldingG: 0),
      );

    tester.view.physicalSize = const Size(420, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          locale: Locale('fa', 'IR'),
          home: Scaffold(body: DashboardPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('داشبورد'), findsNothing);
    final dateHeader = find.byKey(const ValueKey('dash-date-header'));
    expect(dateHeader, findsOneWidget);
    expect(tester.widget<Center>(dateHeader).alignment, Alignment.center);
    expect(tester.getCenter(dateHeader).dx, closeTo(210, 0.5));
    expect(find.text('ارزش پورتفو'), findsOneWidget);
    expect(find.byKey(const ValueKey('cd-value-hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('pv-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('cd-summary')), findsNothing);
    expect(find.text('ارزش کل سبد'), findsNothing);
    expect(find.byKey(const ValueKey('cd-sec-value-head')), findsNothing);
    expect(find.text('سود و زیان'), findsOneWidget);
    expect(find.text('جزئیات تخصیص در تب معاملات'), findsOneWidget);
    expect(find.text('ترکیب دارایی'), findsNothing);
    expect(find.text('بیت‌کوین'), findsNothing); // crypto tape on Index only
    expect(find.text('تتر'), findsOneWidget);
    expect(find.text('طلا'), findsOneWidget);
    expect(find.text('قابل برداشت'), findsOneWidget);
  });

  testWidgets('dashboard hero names the open-cheque contribution', (tester) async {
    resetDashboardExpandCache();
    SharedPreferences.setMockInitialValues({'dash_open_v1': ['value', 'pnl', 'pwo', 'cheques', 'mix', 'alerts', 'gold']});
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: AppConfig.calendarGregorian)
      ..assets = [
        Asset(
          id: 1,
          name: 'Cash',
          quantity: 1,
          avgBuyPrice: 1000,
          currentPrice: 1000,
        ),
      ]
      ..checks = [
        BankCheck(
          direction: checkDirectionReceivable,
          amount: 400,
          issueDate: '2026-10-01',
          dueDate: '2026-12-01',
        ),
        BankCheck(
          direction: checkDirectionPayable,
          amount: 150,
          issueDate: '2026-10-01',
          dueDate: '2026-12-01',
        ),
      ];

    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          locale: Locale('fa', 'IR'),
          home: Scaffold(body: DashboardPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // One line on the card: assets · cheques in · cheques out (signs kept
    // in front of their numbers in right-to-left text).
    final line = tester.widget<Text>(find.byKey(const ValueKey('pv-cheque-line'))).data!;
    expect(line, contains('چک دریافتی \u2066+۴۰۰'));
    expect(line, contains('پرداختی \u2066−۱۵۰'));
    expect(find.text('۱٬۲۵۰ تومان'), findsWidgets);
  });

  testWidgets('redesigned dashboard fits 320 px with large text', (tester) async {
    resetDashboardExpandCache();
    SharedPreferences.setMockInitialValues({'dash_open_v1': ['value', 'pnl', 'pwo', 'cheques', 'mix', 'alerts', 'gold']});
    final today = DateTime.now();
    String iso(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: AppConfig.calendarJalali)
      ..commodityIndex = [
        const CommodityQuote(id: 'usdt', name: 'تتر', symbol: 'USDT', unit: 'TMN', price: 84020, change24h: 0.3),
        const CommodityQuote(id: 'gold', name: 'طلا', symbol: 'GOLD', unit: 'TMN', price: 11306000, change24h: -0.4),
      ]
      ..assets = [
        Asset(id: 1, name: 'طلای آب‌شده', symbol: 'GOLD', quantity: 124, avgBuyPrice: 9800000, currentPrice: 11306452),
        Asset(id: 2, name: 'Fund', symbol: 'FND', quantity: 15000, avgBuyPrice: 28500, currentPrice: 0),
      ]
      ..openTrades = [
        Trade(assetId: 1, status: AppConfig.tradeOpen, quantity: 124, buyPrice: 9800000, assetName: 'طلای آب‌شده', assetSymbol: 'GOLD', currentPrice: 11306452),
        Trade(assetId: 2, status: AppConfig.tradeOpen, quantity: 15000, buyPrice: 28500, assetName: 'Fund', assetSymbol: 'FND', currentPrice: 32170),
      ]
      ..checks = [
        BankCheck(direction: checkDirectionPayable, amount: 62600000, issueDate: iso(today), dueDate: iso(today.add(const Duration(days: 3))), counterparty: 'یک نام خیلی خیلی طولانی برای آزمون'),
        BankCheck(direction: checkDirectionReceivable, amount: 120000000, issueDate: iso(today), dueDate: iso(today.add(const Duration(days: 20)))),
      ];
    tester.view.physicalSize = const Size(320, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: Directionality(textDirection: TextDirection.rtl, child: child!),
          ),
          home: const Scaffold(body: DashboardPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('نیازمند توجه'), findsOneWidget);
    expect(find.byKey(const ValueKey('fab-main')), findsOneWidget);
    expect(find.byKey(const ValueKey('cd-value-hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('cd-today-strip')), findsOneWidget);
    expect(find.byKey(const ValueKey('cd-chip-cheques')), findsOneWidget);
    expect(find.byKey(const ValueKey('cd-sec-gold-body')), findsOneWidget);
    expect(find.byKey(const ValueKey('cd-updated')), findsOneWidget);
    expect(find.byKey(const ValueKey('dash-mode-full')), findsNothing);
    expect(find.byKey(const ValueKey('pv-gold-chip')), findsOneWidget);
    expect(find.byKey(const ValueKey('pv-unpriced')), findsOneWidget);
    expect(find.byKey(const ValueKey('dash-upcoming')), findsOneWidget);
    expect(find.byKey(const ValueKey('dash-withdrawable')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pv-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pv-gold-section')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('cd-sec-gold-head')));
    await tester.tap(find.byKey(const ValueKey('cd-sec-gold-head')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cd-sec-gold-body')), findsNothing);
    final p = await SharedPreferences.getInstance();
    expect(p.getStringList('dash_open_v1'), isNot(contains('gold')));
    // A rebuilt page keeps the in-memory state (no flash, no overwrite).
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state, child: const MaterialApp(home: Scaffold(body: DashboardPage()))));
    await tester.pump();
    expect(find.byKey(const ValueKey('cd-sec-gold-body')), findsNothing);
    expect(find.byKey(const ValueKey('pv-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

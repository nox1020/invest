import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/app.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/home_tabs.dart';
import 'package:invest/ui/pages/dashboard_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('«شاخص» tab replaced by «عملکرد»; index lives on the dashboard', (t) async {
    resetDashboardExpandCache();
    SharedPreferences.setMockInitialValues({'dash_open_v1': ['index']});
    t.view.physicalSize = const Size(420, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: AppConfig.calendarJalali)
      ..commodityIndex = const [
        CommodityQuote(id: 'usdt', name: 'تتر', symbol: 'USDT', unit: 'TMN', price: 84000, change24h: 0.3),
        CommodityQuote(id: 'gold', name: 'طلا', symbol: 'GOLD', unit: 'TMN', price: 11300000, change24h: -0.4),
      ]
      ..assets = [Asset(id: 1, name: 'طلا', symbol: 'GOLD', quantity: 10, avgBuyPrice: 9e6, currentPrice: 11.3e6)]
      ..openTrades = [Trade(assetId: 1, status: AppConfig.tradeOpen, quantity: 10, buyPrice: 9e6, assetName: 'طلا', assetSymbol: 'GOLD', currentPrice: 11.3e6)];
    await t.pumpWidget(ChangeNotifierProvider.value(
        value: s, child: const MaterialApp(home: HomeShell())));
    for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
    final nav = find.byType(BottomNavigationBar);
    expect(find.descendant(of: nav, matching: find.text('شاخص')), findsNothing);
    expect(find.descendant(of: nav, matching: find.text('عملکرد')), findsOneWidget);
    expect(HomeTabs.performance, 3);
    // dashboard section with every quote + link to the full index page
    expect(find.byKey(const ValueKey('cd-index-usdt')), findsOneWidget);
    expect(find.byKey(const ValueKey('cd-index-gold')), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey('cd-index-open')));
    await t.tap(find.byKey(const ValueKey('cd-index-open')));
    for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
    expect(find.byKey(const ValueKey('index-page')), findsOneWidget);
    // from a pushed page, jump to «عملکرد»: pops back to the shell
    final ctx = t.element(find.byKey(const ValueKey('index-page')));
    openHomeTab(ctx, HomeTabs.performance, popToRoot: true);
    for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
    expect(find.byKey(const ValueKey('index-page')), findsNothing);
    expect(t.widget<BottomNavigationBar>(nav).currentIndex, 3);
    expect(find.byKey(const ValueKey('perf-months')), findsOneWidget);
    // back to dashboard via bottom tab
    await t.tap(find.descendant(of: nav, matching: find.text('داشبورد')));
    await t.pump();
    expect(t.widget<BottomNavigationBar>(nav).currentIndex, 0);
  });
}

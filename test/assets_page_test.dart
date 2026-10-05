import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/assets_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('assets economist desk shows exposure and ledger', (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..offline = false
      ..settings = AppSettings(calendar: AppConfig.calendarGregorian)
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
        Asset(
          id: 2,
          name: 'طلا',
          symbol: 'GOLD',
          quantity: 10,
          avgBuyPrice: 3e7,
          currentPrice: 3.2e7,
          notes: '[kind:gold]',
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
        Trade(
          assetId: 2,
          status: AppConfig.tradeOpen,
          quantity: 10,
          buyPrice: 3e7,
          assetName: 'طلا',
          assetSymbol: 'GOLD',
          currentPrice: 3.2e7,
        ),
      ];

    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          locale: Locale('fa', 'IR'),
          home: Scaffold(body: AssetsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('میز دارایی'), findsOneWidget);
    expect(find.textContaining('موقعیت · دفتر تخصیص'), findsOneWidget);
    expect(find.text('تخصیص دارایی'), findsOneWidget);
    expect(find.text('موقعیت‌های باز'), findsOneWidget);
    expect(find.text('Bitcoin'), findsOneWidget);
    expect(find.text('طلا'), findsWidgets);
    expect(find.textContaining('تمرکز بالا'), findsOneWidget);
    expect(find.text('ارز دیجیتال'), findsWidgets);
    expect(find.text('ارزش موقعیت‌های باز'), findsNothing);
  });

  testWidgets('empty assets desk shows empty state', (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: AssetsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('میز دارایی'), findsOneWidget);
    expect(find.text('دفتر دارایی خالی است'), findsOneWidget);
  });
}

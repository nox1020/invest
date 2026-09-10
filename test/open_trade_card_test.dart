import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/trades_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('open trade card is compact and shows buy vs live',
      (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..openTrades = [
        Trade(
          id: 1,
          assetId: 1,
          status: AppConfig.tradeOpen,
          quantity: 2,
          buyPrice: 100,
          buyFee: 10,
          buyDate: '2026-01-01',
          buyPriceUsd: 80,
          currentPrice: 130,
          assetName: 'بیت‌کوین',
          assetSymbol: 'BTC',
        ),
      ];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          locale: const Locale('fa', 'IR'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const Scaffold(body: TradesPage(open: true)),
        ),
      ),
    );

    expect(find.text('خرید'), findsOneWidget);
    expect(find.text('اکنون'), findsOneWidget);
    expect(find.text('فروش'), findsOneWidget);
    expect(find.text('ویرایش'), findsOneWidget);
    expect(find.text('بیت‌کوین'), findsOneWidget);

    expect(find.text('قیمت خرید'), findsNothing);
    expect(find.text('مدت باز بودن'), findsNothing);
    expect(find.text('قیمت لحظه‌ای'), findsNothing);
    expect(find.text('هزینه خرید'), findsNothing);
    expect(find.text('کارمزد خرید'), findsNothing);
  });

  testWidgets('tapping the open card opens trade details', (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..openTrades = [
        Trade(
          id: 1,
          assetId: 1,
          status: AppConfig.tradeOpen,
          quantity: 2,
          buyPrice: 100,
          buyFee: 10,
          buyDate: '2026-01-01',
          buyPriceUsd: 80,
          currentPrice: 130,
          assetName: 'بیت‌کوین',
          assetSymbol: 'BTC',
        ),
      ];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          locale: const Locale('fa', 'IR'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const Scaffold(body: TradesPage(open: true)),
        ),
      ),
    );

    await tester.tap(find.text('بیت‌کوین'));
    await tester.pumpAndSettle();

    expect(find.text('جزئیات معامله'), findsOneWidget);
    expect(find.text('هزینه خرید'), findsOneWidget);
    expect(find.text('مدت باز بودن'), findsOneWidget);
    expect(find.text('کارمزد خرید'), findsOneWidget);
    expect(find.text('ارزش فعلی'), findsOneWidget);
  });
}

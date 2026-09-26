import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/metrics.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/withdrawals_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('withdrawals page shows annual inflow quota and history',
      (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(
        annualWithdrawalPct: 10,
        calendar: AppConfig.calendarGregorian,
      )
      ..openTrades = [
        Trade(
          assetId: 1,
          status: AppConfig.tradeOpen,
          quantity: 1,
          buyPrice: 1000000,
        ),
      ]
      ..metrics = const DashboardMetrics(
        totalValue: 1200000,
        totalPnl: 200000,
        totalPnlPct: 20,
        realizedPnl: 400000,
        unrealizedPnl: 0,
        openCount: 1,
        closedCount: 0,
        yearRealizedPnl: 400000,
        yearKey: '2026',
        goldFund: GoldFundMetrics(
          goldInG: 0,
          goldOutG: 0,
          goldHoldingG: 0,
        ),
      )
      ..withdrawals = [
        Withdrawal(
          id: 1,
          amount: 20000,
          note: 'بانک',
          createdAt: '2026-04-01',
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
          home: const Scaffold(body: WithdrawalsPage()),
        ),
      ),
    );

    expect(find.text('مبلغ قابل برداشت'), findsOneWidget);
    expect(find.text('80,000 تومان'), findsWidgets);
    expect(find.text('سود تحقق‌یافته'), findsOneWidget);
    expect(find.text('400,000 تومان'), findsOneWidget);
    expect(find.text('اضافه برداشت'), findsOneWidget);
    expect(find.text('0 تومان'), findsOneWidget);
    expect(find.textContaining('۱۰٪ از ورودی'), findsWidgets);
    expect(find.text('کل ورودی پرتفو'), findsOneWidget);
    expect(find.text('سقف سالانه (۱۰٪)'), findsOneWidget);
    expect(find.text('برداشت امسال'), findsOneWidget);
    expect(find.text('باقیمانده سقف سالانه'), findsOneWidget);
    expect(find.text('تغییر درصد در تنظیمات'), findsOneWidget);
    expect(find.text('انجام‌شده'), findsOneWidget);
    expect(find.text('بانک'), findsOneWidget);
    expect(find.text('20,000 تومان'), findsWidgets);
    expect(find.byTooltip('ویرایش'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('ویرایش'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ویرایش'));
    await tester.pumpAndSettle();
    expect(find.text('ویرایش برداشت'), findsOneWidget);
    expect(find.text('تاریخ برداشت'), findsOneWidget);
    expect(find.text('20000'), findsOneWidget);
    expect(find.text('مبلغ می‌تواند بیشتر از قابل برداشت باشد.'), findsOneWidget);

    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
  });

  testWidgets('withdrawal dialog opens when nothing is withdrawable',
      (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(
        annualWithdrawalPct: 10,
        calendar: AppConfig.calendarGregorian,
      )
      ..metrics = const DashboardMetrics(
        totalValue: 0,
        totalPnl: 0,
        totalPnlPct: 0,
        realizedPnl: 0,
        unrealizedPnl: 0,
        openCount: 0,
        closedCount: 0,
        yearRealizedPnl: 0,
        yearKey: '2026',
        goldFund: GoldFundMetrics(
          goldInG: 0,
          goldOutG: 0,
          goldHoldingG: 0,
        ),
      );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          locale: const Locale('fa', 'IR'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRecordWithdrawalDialog(context),
                child: const Text('ثبت جدید'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('ثبت جدید'));
    await tester.pumpAndSettle();

    expect(find.text('ثبت برداشت'), findsOneWidget);
    expect(find.text('مبلغ قابل برداشت صفر است'), findsNothing);
    expect(find.text('مبلغ می‌تواند بیشتر از قابل برداشت باشد.'), findsOneWidget);
    expect(find.text('قابل برداشت: 0 تومان'), findsOneWidget);
  });
}

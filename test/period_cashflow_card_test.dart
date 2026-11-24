import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/bank_sms_parser.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/withdrawals_page.dart';
import 'package:invest/ui/widgets/period_cashflow_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final now = DateTime(2026, 11, 24, 15, 30);

Widget wrap(Widget child, {AppState? state}) {
  return ChangeNotifierProvider.value(
    value: state ??
        (AppState()
          ..loading = false
          ..authenticated = true),
    child: MaterialApp(
      locale: const Locale('fa', 'IR'),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(body: child),
    ),
  );
}

BankSmsItem item({
  required double toman,
  bool isIn = false,
  DateTime? at,
  String fp = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) {
  return BankSmsItem(
    fp: fp,
    bank: 'بانک ملت',
    toman: toman,
    at: at ?? now,
    direction: isIn ? bankSmsDirectionIn : bankSmsDirectionOut,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BankSmsStore.debugReset();
    PwoStore.instance.debugSetLoaded();
    CurrencyMode.reset();
  });
  tearDown(CurrencyMode.reset);

  testWidgets('empty state shows zeros and switches روز/ماه/سال captions',
      (tester) async {
    await tester.pumpWidget(wrap(PeriodCashflowCard(
      now: now,
      smsOverride: const [],
      smsUnavailableOverride: false,
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('period-cashflow-card')), findsOneWidget);
    expect(find.text('گردش پول'), findsOneWidget);
    expect(find.text('آذر ۱۴۰۵'), findsOneWidget);
    expect(find.text('ورودی'), findsOneWidget);
    expect(find.text('خروجی'), findsOneWidget);
    expect(find.text('تراز این ماه'), findsOneWidget);
    expect(find.text('۰ ت'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('period-cashflow-day')));
    await tester.pumpAndSettle();
    expect(find.text('امروز ۳ آذر ۱۴۰۵'), findsOneWidget);
    expect(find.text('تراز این روز'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('period-cashflow-year')));
    await tester.pumpAndSettle();
    expect(find.text('۱۴۰۵'), findsOneWidget);
    expect(find.text('تراز این سال'), findsOneWidget);
    expect(find.text('آذر ۱۴۰۵'), findsNothing);
  });

  testWidgets('formats totals in Persian digits', (tester) async {
    await tester.pumpWidget(wrap(
      PeriodCashflowCard(
        now: now,
        smsOverride: [
          item(
              toman: 186000000,
              isIn: true,
              fp: '1111111111111111111111111111111111111111'),
          item(
              toman: 214000000, fp: '2222222222222222222222222222222222222222'),
        ],
        smsUnavailableOverride: false,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('۱۸۶ میلیون ت'), findsWidgets);
    expect(find.textContaining('۲۱۴ میلیون ت'), findsWidgets);
    // Net uses faSigned, which isolates the signed number from the unit.
    expect(find.textContaining('۲۸'), findsWidgets);
  });

  testWidgets('permission-off path shows the SMS hint and still counts txs',
      (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..withdrawals = [
        Withdrawal(amount: 5000000, createdAt: '2026-11-24'),
      ];
    await tester.pumpWidget(wrap(
      PeriodCashflowCard(
        now: now,
        smsOverride: const [],
        smsUnavailableOverride: true,
      ),
      state: state,
    ));
    await tester.pumpAndSettle();
    expect(find.text('پیامک در دسترس نیست'), findsOneWidget);
    expect(find.textContaining('۵ میلیون ت'), findsWidgets);
  });

  testWidgets('withdrawals page hosts the card', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(const WithdrawalsPage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('period-cashflow-card')), findsOneWidget);
    expect(find.text('گردش پول'), findsOneWidget);
    expect(find.text('ظرفیت قابل برداشت'), findsOneWidget);
  });
}

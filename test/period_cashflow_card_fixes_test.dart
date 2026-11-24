// Fake SMS only. Card behaviour fixed after review: race, refresh, signs,
// hints, duplicates sheet, accessible segments.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/bank_sms_parser.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/widgets/period_cashflow_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final fixedNow = DateTime(2026, 11, 24, 15, 30); // 3 Azar 1405

Widget wrap(Widget child, {AppState? state}) => ChangeNotifierProvider.value(
      value: state ??
          (AppState()
            ..loading = false
            ..authenticated = true),
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );

String? textOf(WidgetTester t, String key) =>
    (t.widget(find.byKey(ValueKey(key))) as Text).data;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final inbox = <Map<String, Object>>[];
  Completer<void>? gate;
  var cashflowCalls = 0;
  var readGranted = true;
  var cashflowFails = false;
  var nativeOn = true;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BankSmsStore.debugReset();
    PwoStore.instance.debugSetLoaded();
    CurrencyMode.reset();
    inbox.clear();
    gate = null;
    cashflowCalls = 0;
    readGranted = true;
    cashflowFails = false;
    nativeOn = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BankSmsStore.channel, (c) async {
      switch (c.method) {
        case 'cashflowInbox':
          cashflowCalls++;
          final since = (c.arguments as Map)['since'] as int;
          final g = gate;
          if (g != null) await g.future;
          if (cashflowFails) throw PlatformException(code: 'boom');
          return inbox.where((m) => (m['date'] as int) > since).toList();
        case 'takePending':
        case 'takeRejected':
        case 'inbox':
          return <Object?>[];
        case 'getEnabled':
          return nativeOn;
        case 'setEnabled':
          return true;
        case 'status':
          return {
            'read': readGranted,
            'receive': true,
            'notify': true,
            'fullScreen': false,
            'sdk': 34
          };
      }
      return null;
    });
  });
  tearDown(CurrencyMode.reset);

  Map<String, Object> sms(String body, DateTime at) =>
      {'address': 'Mellat', 'body': body, 'date': at.millisecondsSinceEpoch};

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
  }

  testWidgets('period switch and store change during a scan are not lost',
      (tester) async {
    await tester.runAsync(() async {
      await BankSmsStore.instance.setEnabled(true);
      await BankSmsStore.instance.refreshCaps();
    });
    // 40 days ago: in this Jalali year, not in this month.
    inbox.add(sms('بانک ملت\nبرداشت: 10,000,000\nمانده: 5,000,000',
        DateTime.now().subtract(const Duration(days: 40))));
    gate = Completer<void>();
    await tester.pumpWidget(wrap(const PeriodCashflowCard()));
    await tester.pump(); // first scan starts and blocks
    await tester.tap(find.byKey(const ValueKey('period-cashflow-year')));
    await tester.pump();
    // A deposit lands while the scan is still running.
    inbox.add(
        sms('بانک ملت\nواریز: 30,000,000\nمانده: 35,000,000', DateTime.now()));
    await tester.runAsync(() => BankSmsStore.instance.setCardPerson('12', 'p'));
    gate!.complete();
    gate = null;
    await settle(tester);
    expect(find.text('پیامک ۱ میلیون ت\nتراکنش ۰ ت'), findsOneWidget);
    expect(find.text('پیامک ۳ میلیون ت\nتراکنش ۰ ت'), findsOneWidget);
    // Switching periods afterwards does not rescan the inbox.
    final calls = cashflowCalls;
    await tester.tap(find.byKey(const ValueKey('period-cashflow-month')));
    await tester.tap(find.byKey(const ValueKey('period-cashflow-day')));
    await settle(tester);
    expect(cashflowCalls, calls);
  });

  testWidgets('reloads on app resume and after midnight', (tester) async {
    await tester.runAsync(() async {
      await BankSmsStore.instance.setEnabled(true);
      await BankSmsStore.instance.refreshCaps();
    });
    await tester.pumpWidget(wrap(const PeriodCashflowCard()));
    await settle(tester);
    final first = cashflowCalls;
    expect(first, greaterThan(0));
    for (final st in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(st);
    }
    await settle(tester);
    expect(cashflowCalls, greaterThan(first));
    final afterResume = cashflowCalls;
    await tester.pump(const Duration(hours: 25));
    await settle(tester);
    expect(cashflowCalls, greaterThan(afterResume));
  });

  testWidgets('no «unavailable» flash before the first load', (tester) async {
    // SMS switch off → unavailable, but only shown once loading finished.
    nativeOn = false;
    await tester.pumpWidget(wrap(const PeriodCashflowCard()));
    expect(find.byKey(const ValueKey('period-cashflow-sms-off')), findsNothing);
    await settle(tester);
    expect(
        find.byKey(const ValueKey('period-cashflow-sms-off')), findsOneWidget);
  });

  testWidgets('partial permission and scan errors are shown', (tester) async {
    readGranted = false;
    await tester.runAsync(() async {
      await BankSmsStore.instance.setEnabled(true);
      await BankSmsStore.instance.refreshCaps();
    });
    await tester.pumpWidget(wrap(const PeriodCashflowCard()));
    await settle(tester);
    expect(find.byKey(const ValueKey('period-cashflow-sms-partial')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('period-cashflow-sms-error')), findsNothing);

    readGranted = true;
    cashflowFails = true;
    await tester.runAsync(() => BankSmsStore.instance.refreshCaps());
    await settle(tester);
    expect(find.byKey(const ValueKey('period-cashflow-sms-partial')),
        findsNothing);
    expect(find.byKey(const ValueKey('period-cashflow-sms-error')),
        findsOneWidget);
  });

  testWidgets('outflow total has no «+»; net keeps its sign', (tester) async {
    await tester.pumpWidget(wrap(PeriodCashflowCard(
      now: fixedNow,
      smsOverride: [
        BankSmsItem(
            fp: 'a' * 40, bank: 'بانک ملت', toman: 2000000, at: fixedNow),
        BankSmsItem(
            fp: 'b' * 40,
            bank: 'بانک ملت',
            toman: 5000000,
            at: fixedNow,
            direction: bankSmsDirectionIn),
      ],
      smsUnavailableOverride: false,
    )));
    await tester.pumpAndSettle();
    final out = textOf(tester, 'period-cashflow-total-خروجی')!;
    final inn = textOf(tester, 'period-cashflow-total-ورودی')!;
    expect(out.contains('+'), isFalse);
    expect(out.contains('−'), isFalse);
    expect(inn.contains('+'), isFalse);
    expect(textOf(tester, 'period-cashflow-net'), contains('+'));
  });

  testWidgets('likely duplicates line opens the pairs', (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..withdrawals = [
        Withdrawal(amount: 5000000, note: 'دستی', createdAt: '2026-11-23'),
      ];
    await tester.pumpWidget(wrap(
      PeriodCashflowCard(
        now: fixedNow,
        smsOverride: [
          BankSmsItem(
              fp: 'c' * 40, bank: 'بانک ملت', toman: 5000000, at: fixedNow),
        ],
        smsUnavailableOverride: false,
      ),
      state: state,
    ));
    await tester.pumpAndSettle();
    expect(find.text('احتمال تکرار: ۱ مورد'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('period-cashflow-dups')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('period-cashflow-dups-sheet')),
        findsOneWidget);
    expect(find.textContaining('برداشت · دستی'), findsOneWidget);
  });

  testWidgets('day view flags PWO entries that have no day', (tester) async {
    final pwo = PwoStore.instance;
    pwo.debugSetLoaded(PwoLedger(people: [], months: {
      pwoMonthKey(1405, 9):
          PwoMonth(year: 1405, month: 9, amounts: {'p0': 1000000}),
    }, tags: {
      pwoSeedTag
    }));
    await tester.pumpWidget(wrap(PeriodCashflowCard(
      now: fixedNow,
      smsOverride: const [],
      smsUnavailableOverride: false,
      pwoOverride: pwo,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('period-cashflow-pwo-day')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('period-cashflow-day')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('period-cashflow-pwo-day')), findsOneWidget);
  });

  testWidgets('segments are 40px+ selectable buttons for screen readers',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap(PeriodCashflowCard(
      now: fixedNow,
      smsOverride: const [],
      smsUnavailableOverride: false,
    )));
    await tester.pumpAndSettle();
    for (final k in ['day', 'month', 'year']) {
      final size = tester.getSize(find.byKey(ValueKey('period-cashflow-$k')));
      expect(size.height, greaterThanOrEqualTo(40));
      expect(size.width, greaterThanOrEqualTo(40));
    }
    expect(
      tester.getSemantics(find.byKey(const ValueKey('period-cashflow-month'))),
      matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          label: 'گردش پول ماه'),
    );
    handle.dispose();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/checks_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('cheque book shows debts, receivables, and due dates',
      (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: 'gregorian')
      ..checks = [
        BankCheck(
          id: 1,
          direction: checkDirectionReceivable,
          amount: 2000000,
          issueDate: '2026-10-01',
          dueDate: '2026-10-20',
          checkNumber: '101',
          bankName: 'ملت',
          counterparty: 'رضا',
          status: checkStatusPending,
        ),
        BankCheck(
          id: 2,
          direction: checkDirectionPayable,
          amount: 500000,
          issueDate: '2026-09-01',
          dueDate: '2026-10-01',
          checkNumber: '202',
          bankName: 'ملی',
          counterparty: 'شرکت آریا',
          status: checkStatusPending,
        ),
      ];

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ChecksPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مدیریت چک‌ها'), findsOneWidget);
    expect(find.text('در انتظار'), findsWidgets);
    expect(find.text('رضا'), findsOneWidget);
    expect(find.text('شرکت آریا'), findsOneWidget);
    expect(find.text('دریافتی'), findsWidgets);
    expect(find.text('پرداختی'), findsWidgets);
    expect(find.textContaining('سررسید'), findsWidgets);

    await tester.tap(find.text('پرداختی').first);
    await tester.pumpAndSettle();
    expect(find.text('رضا'), findsNothing);
    expect(find.text('شرکت آریا'), findsOneWidget);

    await tester.tap(find.text('ثبت چک'));
    await tester.pumpAndSettle();
    expect(find.text('مبلغ (تومان)'), findsOneWidget);
    expect(find.text('تاریخ سررسید'), findsOneWidget);
    expect(find.text('شناسه صیادی (۱۶ رقم)'), findsOneWidget);

    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('مبلغ چک باید بزرگ‌تر از صفر باشد.'), findsOneWidget);
  });

  testWidgets('jalali dates and status actions are on the cheque',
      (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: AppConfig.calendarJalali)
      ..checks = [
        BankCheck(
          id: 1,
          direction: checkDirectionReceivable,
          amount: 2500000,
          issueDate: '2026-10-01',
          dueDate: '2026-10-20',
          checkNumber: '101',
          bankName: 'ملت',
          counterparty: 'رضا',
          status: checkStatusPending,
        ),
      ];

    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ChecksPage()),
      ),
    );
    await tester.pumpAndSettle();

    final due = formatDisplayDate('2026-10-20', AppConfig.calendarJalali);
    expect(find.textContaining(due), findsWidgets);
    expect(find.textContaining('2026-10-20'), findsNothing);
    expect(find.text('2,500,000 تومان'), findsWidgets);

    await tester.tap(find.text('رضا'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'وصول شده'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'برگشتی'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'باطل'), findsOneWidget);
    expect(find.text('نزد صندوق'), findsWidgets);
  });

  test('cheque amounts accept grouped toman entry', () {
    expect(parseCheckAmount('۱/۵۰۰/۰۰۰'), 1500000);
    expect(parseCheckAmount('1.500.000'), 1500000);
    expect(parseCheckAmount('2,000,000'), 2000000);
    expect(parseCheckAmount('12.5'), 12.5);
  });
}
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/checks_page.dart';
import 'package:invest/ui/pages/settings_page.dart';
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

    final payable = find.byKey(const ValueKey('check-filter-payable'));
    await tester.ensureVisible(payable);
    await tester.pumpAndSettle();
    await tester.tap(payable);
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

  testWidgets('settings drops the cheque section and the dashboard card still opens the book',
      (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..checks = [
        BankCheck(
          id: 1,
          direction: checkDirectionReceivable,
          amount: 1000,
          issueDate: '2026-10-01',
          dueDate: '2026-11-01',
          checkNumber: '1',
        ),
      ];

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مدیریت چک‌ها'), findsNothing);
    expect(find.text('چک‌ها'), findsNothing);
    expect(find.text('پشتیبان‌گیری'), findsOneWidget);
    expect(find.text('صدور پشتیبان'), findsOneWidget);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: ChecksDashboardCard())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('مدیریت چک‌ها'));
    await tester.pumpAndSettle();
    expect(find.byType(ChecksPage), findsOneWidget);
    expect(find.text('ثبت چک'), findsOneWidget);
  });

  testWidgets('cheque details scroll on small, typical, and large phones',
      (tester) async {
    const sizes = <Size>[
      Size(320, 568),
      Size(360, 800),
      Size(840, 1200),
    ];
    const scales = <double>[1, 1.3, 1.5];
    final note = '${'یادداشت خیلی طولانی برای شرح چک و طرف حساب. ' * 12}پایان یادداشت';
    final bank = 'بانک ${'سپه صادرات ملت ' * 8}';
    final payee = 'شرکت ${'بازرگانی بین المللی پارس ' * 6}';
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: 'gregorian')
      ..checks = [
        BankCheck(
          id: 7,
          direction: checkDirectionReceivable,
          amount: 12345678901234,
          issueDate: '2026-01-02',
          dueDate: '2026-12-31',
          checkNumber: '99887766554433221100',
          sayadId: '1234567890123456',
          bankName: bank,
          branch: 'شعبه مرکزی میدان ولیعصر ساختمان شماره ۱۲۳۴۵۶۷۸۹۰',
          counterparty: payee,
          purpose: 'بابت ${'تسویه قرارداد فروش کالا و خدمات ' * 4}',
          note: 'مبلغ به حروف: ۱۲۳۴۵۶۷۸۹۰۱۲۳۴ تومان. $note',
          status: checkStatusPending,
          statusLabelFromServer:
              'نزد صندوق — ${'در انتظار وصول از شعبه ' * 3}',
        ),
      ];

    for (final size in sizes) {
      for (final scale in scales) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: state,
            child: const MaterialApp(
              locale: Locale('fa', 'IR'),
              home: ChecksPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        if (find.text('ویرایش').evaluate().isNotEmpty) {
          final navigator = tester.state<NavigatorState>(find.byType(Navigator));
          navigator.pop();
          await tester.pumpAndSettle();
        }
        await tester.scrollUntilVisible(
          find.textContaining('بازرگانی'),
          280,
          scrollable: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );
        await tester.tap(find.textContaining('بازرگانی').first);
        await tester.pumpAndSettle();

        expect(find.text('ویرایش'), findsOneWidget);
        expect(find.text('حذف'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'وصول شده'), findsOneWidget);
        expect(tester.takeException(), isNull);

        final edit = tester.getRect(
          find.widgetWithText(ElevatedButton, 'ویرایش'),
        );
        expect(edit.bottom, lessThanOrEqualTo(size.height));
        expect(edit.top, greaterThanOrEqualTo(0));
        expect(edit.height, greaterThanOrEqualTo(36));
        expect(edit.right, lessThanOrEqualTo(size.width));
        expect(edit.left, greaterThanOrEqualTo(0));

        final headline = tester.widget<Text>(
          find.byKey(const Key('check-detail-amount')),
        );
        expect(headline.style?.fontSize, greaterThanOrEqualTo(18));
        final headlineBox = tester.renderObject<RenderBox>(
          find.byKey(const Key('check-detail-amount')),
        );
        expect(headlineBox.size.width, lessThanOrEqualTo(size.width));
        expect(headlineBox.size.height, greaterThanOrEqualTo(18 * scale));

        final scrollable = find.descendant(
          of: find.byKey(const Key('check-detail-scroll')),
          matching: find.byType(Scrollable),
        );
        expect(scrollable, findsOneWidget);
        await tester.scrollUntilVisible(
          find.textContaining('پایان یادداشت'),
          400,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('پایان یادداشت'), findsWidgets);
        expect(find.textContaining('مبلغ به حروف'), findsWidgets);
        expect(find.textContaining('۱۲۳۴۵۶۷۸'), findsWidgets);
        expect(find.textContaining('12,345,678,901,234'), findsWidgets);
        final noteBox = tester
            .renderObjectList<RenderBox>(find.textContaining('پایان یادداشت'))
            .last;
        expect(noteBox.size.width, lessThanOrEqualTo(size.width));
        expect(find.text('ویرایش'), findsOneWidget);
        final editAfter = tester.getRect(
          find.widgetWithText(ElevatedButton, 'ویرایش'),
        );
        expect(editAfter.top, greaterThanOrEqualTo(0));
        expect(editAfter.bottom, lessThanOrEqualTo(size.height));
        expect(editAfter.height, greaterThanOrEqualTo(36));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('cheque details stay above the keyboard and the gesture bar',
      (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: 'gregorian')
      ..checks = [
        BankCheck(
          id: 8,
          direction: checkDirectionPayable,
          amount: 9876543210,
          issueDate: '2026-02-02',
          dueDate: '2026-08-08',
          checkNumber: '445566',
          bankName: 'ملت',
          counterparty: 'علی رضایی',
          note: 'یادداشت کوتاه',
          status: checkStatusPending,
        ),
      ];

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ChecksPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('علی رضایی'));
    await tester.pumpAndSettle();

    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final edit = tester.getRect(find.text('ویرایش'));
    const visibleBottom = 800 - 280;
    expect(edit.bottom, lessThanOrEqualTo(visibleBottom));
    expect(edit.top, greaterThanOrEqualTo(0));
    expect(find.widgetWithText(OutlinedButton, 'پاس شده'), findsOneWidget);
  });

  testWidgets('small phone, large text, and keyboard keep cheque actions visible',
      (tester) async {
    final note = '${'شرح بسیار طولانی قرارداد و یادداشت چک. ' * 10}پایان شرح';
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: 'gregorian')
      ..checks = [
        BankCheck(
          id: 9,
          direction: checkDirectionReceivable,
          amount: 99999999999999,
          issueDate: '2026-03-03',
          dueDate: '2026-09-09',
          checkNumber: '11223344556677889900',
          sayadId: '9988776655443322',
          bankName: 'بانک ${'اقتصاد نوین پاسارگاد ' * 6}',
          branch: 'شعبه ${'میدان آزادی برج ' * 4}',
          counterparty: 'گیرنده ${'شرکت توسعه بازرگانی ' * 5}',
          purpose: 'بابت ${'خرید مواد اولیه خط تولید ' * 4}',
          note: 'مبلغ به حروف: ۹۹۹۹۹۹۹۹۹۹۹۹۹۹ تومان. $note',
          status: checkStatusPending,
          statusLabelFromServer: 'نزد صندوق — در انتظار وصول از شعبه مرکزی',
        ),
      ];

    const size = Size(320, 568);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          locale: Locale('fa', 'IR'),
          home: ChecksPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('بازرگانی'),
      280,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.tap(find.textContaining('بازرگانی').first);
    await tester.pumpAndSettle();

    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final edit = tester.getRect(
      find.widgetWithText(ElevatedButton, 'ویرایش'),
    );
    const visibleBottom = 568 - 220;
    expect(edit.top, greaterThanOrEqualTo(0));
    expect(edit.bottom, lessThanOrEqualTo(visibleBottom));
    expect(edit.height, greaterThanOrEqualTo(36));
    expect(edit.right, lessThanOrEqualTo(size.width));
    expect(find.text('حذف'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'وصول شده'), findsOneWidget);

    final scrollable = find.descendant(
      of: find.byKey(const Key('check-detail-scroll')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.textContaining('پایان شرح'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('پایان شرح'), findsOneWidget);
    expect(find.textContaining('۹۹۹۹۹۹۹۹'), findsWidgets);
    final still = tester.getRect(
      find.widgetWithText(ElevatedButton, 'ویرایش'),
    );
    expect(still.top, greaterThanOrEqualTo(0));
    expect(still.bottom, lessThanOrEqualTo(visibleBottom));
    expect(tester.takeException(), isNull);
  });

  test('cheque amounts accept grouped toman entry', () {
    expect(parseCheckAmount('۱/۵۰۰/۰۰۰'), 1500000);
    expect(parseCheckAmount('1.500.000'), 1500000);
    expect(parseCheckAmount('2,000,000'), 2000000);
    expect(parseCheckAmount('12.5'), 12.5);
  });
}
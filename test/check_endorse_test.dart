import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/services/check_ledger.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/checks_page.dart';
import 'package:invest/ui/pages/global_search_page.dart';
import 'package:provider/provider.dart';

BankCheck _c(int id, {String status = checkStatusPending, String to = '', String what = ''}) => BankCheck(
      id: id,
      direction: checkDirectionReceivable,
      amount: 2000000,
      issueDate: '2026-10-01',
      dueDate: '2026-10-25',
      checkNumber: '$id',
      bankName: 'ملت',
      counterparty: 'طرف $id',
      status: status,
      endorsedTo: to,
      endorsedFor: what,
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<AppState> _pump(WidgetTester tester, List<BankCheck> book) async {
  final state = AppState()
    ..loading = false
    ..authenticated = true
    ..settings = AppSettings(calendar: 'gregorian')
    ..checks = book;
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: state,
    child: const MaterialApp(home: ChecksPage()),
  ));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  test('fields round-trip, clean up, and an older server cannot erase them', () {
    final a = prepareBankCheck(_c(1, status: checkStatusEndorsed, to: ' فروشگاه  نمونه ', what: 'مصالح'));
    expect(a.endorsedTo, 'فروشگاه نمونه');
    expect(a.endorseSummary, 'به فروشگاه نمونه · بابت مصالح');
    final back = BankCheck.fromMap(a.toMap());
    expect(back.endorsedTo, a.endorsedTo);
    expect(back.endorsedFor, a.endorsedFor);

    final legacy = Map<String, Object?>.from(a.toMap())
      ..remove('endorsed_to')
      ..remove('endorsed_for');
    final fromOld = BankCheck.fromMap(legacy);
    expect(fromOld.endorseFromServer, isFalse);
    expect(sameCheckContent(a, fromOld), isTrue, reason: 'no endless resend');
    final merged = mergeRemoteBook(local: [a], remote: [fromOld]).single;
    expect(merged.endorsedTo, 'فروشگاه نمونه');
    expect(merged.endorsedFor, 'مصالح');
  });

  test('an old spent cheque without the fields still loads and validates', () {
    final old = BankCheck.fromMap({
      'id': 9, 'direction': 'receivable', 'amount': 5, 'issue_date': '2026-01-01',
      'due_date': '2026-02-01', 'check_number': '9', 'status': 'endorsed',
    });
    expect(old.isEndorsed, isTrue);
    expect(old.endorseSummary, '');
    expect(prepareBankCheck(old).status, checkStatusEndorsed);
  });

  testWidgets('marking «خرج شده» asks to whom and for what, then shows and searches it', (tester) async {
    final state = await _pump(tester, [_c(1)]);
    await tester.tap(find.text('طرف 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'خرج شده'));
    await tester.pumpAndSettle();
    expect(find.text('به چه کسی خرج شد؟'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('endorse-save')));
    await tester.pumpAndSettle();
    expect(find.text('الزامی است'), findsNWidgets(2));
    expect(state.checks.single.status, checkStatusPending);

    await tester.enterText(find.byKey(const ValueKey('endorse-to')), 'آقای نمونه');
    await tester.enterText(find.byKey(const ValueKey('endorse-for')), 'خرید مصالح');
    await tester.tap(find.byKey(const ValueKey('endorse-save')));
    await _settle(tester);

    final c = state.checks.single;
    expect(c.status, checkStatusEndorsed);
    expect(c.endorsedTo, 'آقای نمونه');
    expect(c.endorsedFor, 'خرید مصالح');
    expect(find.text('خرج شده به آقای نمونه · بابت خرید مصالح'), findsOneWidget);

    final hits = buildSearchItems(state)
        .where((i) => i.matches('مصالح'))
        .toList();
    expect(hits, hasLength(1));
  });

  testWidgets('cancelling the dialog leaves the cheque unchanged', (tester) async {
    final state = await _pump(tester, [_c(1)]);
    await tester.tap(find.text('طرف 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'خرج شده'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    expect(state.checks.single.status, checkStatusPending);
  });

  testWidgets('detail of an old spent cheque says «ثبت نشده»', (tester) async {
    await _pump(tester, [_c(1, status: checkStatusEndorsed)]);
    await tester.tap(find.text('طرف 1'));
    await tester.pumpAndSettle();
    expect(find.text('خرج شده به'), findsOneWidget);
    expect(find.text('ثبت نشده'), findsNWidgets(2));
  });
}

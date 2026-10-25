// Fake SMS only (invented banks/amounts); nothing real in this public repo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/bank_sms_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object> sms(String body, {String addr = 'Mellat'}) => {
      'address': addr,
      'body': body,
      'date': DateTime.now().millisecondsSinceEpoch,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  var granted = true;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BankSmsStore.debugReset();
    PwoStore.instance.debugReset();
    calls.clear();
    granted = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BankSmsStore.channel, (c) async {
      calls.add(c.method);
      switch (c.method) {
        case 'inbox':
          return [sms('بانک ملت\nبرداشت: 1,000,000\nمانده: 5,000,000')];
        case 'takePending':
        case 'takeRejected':
          return <Object?>[];
        case 'status':
          return {
            'read': granted,
            'receive': granted,
            'notify': true,
            'fullScreen': false,
            'sdk': 34
          };
      }
      return null;
    });
  });

  test('off by default: nothing is read or kept', () async {
    final s = BankSmsStore.instance;
    await s.load();
    expect(s.enabled, isFalse);
    expect(await s.syncOnOpen(), isEmpty);
    expect(calls, isNot(contains('inbox')));
    expect(await s.ingest([sms('برداشت: 2,000,000')]), isEmpty);
  });

  test('scan on open adds once; handled never comes back; raw text not stored',
      () async {
    final s = BankSmsStore.instance;
    await s.setEnabled(true);
    await s.syncOnOpen();
    expect(s.pending, hasLength(1));
    expect(s.pending.single.toman, 100000);
    await s.syncOnOpen(); // same SMS again
    expect(s.pending, hasLength(1));
    final p = await SharedPreferences.getInstance();
    final all = p.getKeys().map((k) => '${p.get(k)}').join();
    expect(all.contains('مانده: 5,000,000'), isFalse);
    await s.markHandled(s.pending.single.fp);
    await s.syncOnOpen();
    expect(s.pending, isEmpty);
    expect(calls, contains('cancel'));
  });

  test('non-withdrawal SMS are ignored', () async {
    final s = BankSmsStore.instance;
    await s.setEnabled(true);
    final r = await s.ingest([
      sms('واریز: 1,000,000 مانده 3,000,000'),
      sms('رمز پویا 556677 برای خرید 90,000'),
    ]);
    expect(r, isEmpty);
  });

  testWidgets('card → prefilled confirm → personal PWO tx recorded, red amount',
      (tester) async {
    final s = BankSmsStore.instance;
    await tester.runAsync(() async {
      await PwoStore.instance.load();
      await s.setEnabled(true);
      await s.ingest([sms('بانک ملت\nکارت 6037**4321\nبرداشت: 2,500,000')]);
    });
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Directionality(
                textDirection: TextDirection.rtl, child: BankSmsCard()))));
    await tester.pump();
    expect(find.text('برداشت‌های بانکی جدید'), findsOneWidget);
    await tester.tap(find.textContaining('ثبت').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sms-confirm')), findsOneWidget);
    final label =
        tester.widget<Text>(find.byKey(const ValueKey('sms-amount-label')));
    expect(label.style!.color, AppTheme.negative);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sms-amount')))
            .controller!
            .text,
        '250000');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('sms-save')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sms-confirm')), findsNothing);
    expect(s.pending, isEmpty);
    final txs =
        PwoStore.instance.ledger.months.values.expand((m) => m.txs).toList();
    expect(txs.where((t) => t.amount == 250000), hasLength(1));
    expect(s.cardPerson['4321'], isNotNull);
    expect(find.byKey(const ValueKey('bank-sms-card')), findsNothing);
  });

  testWidgets('duplicate warning and reject', (tester) async {
    final s = BankSmsStore.instance;
    await tester.runAsync(() async {
      await PwoStore.instance.load();
      final j = PwoStore.instance;
      await s.setEnabled(true);
      final it = (await s.ingest([sms('برداشت: 3,000,000')])).single;
      final jal = it.jalali;
      await j.addTx(
          jal.year, jal.month, j.ledger.activePeople.first.id, 300000);
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: BankSmsConfirmSheet(item: s.pending.single))));
    await tester.pump();
    expect(find.byKey(const ValueKey('sms-dup')), findsOneWidget);
    // System target has no matching withdrawal → no warning.
    await tester.tap(find.text('سیستم'));
    await tester.pump();
    expect(find.byKey(const ValueKey('sms-dup')), findsNothing);
    expect(find.byKey(const ValueKey('sms-person')), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('sms-reject')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(s.pending, isEmpty);
  });

  test('switch on with permissions granted persists', () async {
    final s = BankSmsStore.instance;
    expect(await s.tryEnable(), isTrue);
    expect(s.enabled, isTrue);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool(BankSmsStore.kEnabled), isTrue);
    BankSmsStore.debugReset();
    await BankSmsStore.instance.load();
    expect(BankSmsStore.instance.enabled, isTrue);
  });

  test('missing permission → remembered, auto-enabled after grant', () async {
    granted = false;
    final s = BankSmsStore.instance;
    expect(await s.tryEnable(), isFalse);
    expect(s.enabled, isFalse);
    expect(s.wantEnabled, isTrue);
    expect(calls, contains('request'));
    await s.recheck();
    expect(s.enabled, isFalse);
    granted = true; // user allowed it in Android settings and came back
    await s.recheck();
    expect(s.enabled, isTrue);
    expect(s.wantEnabled, isFalse);
    await s.disable();
    expect(s.enabled, isFalse);
    await s.recheck();
    expect(s.enabled, isFalse, reason: 'turned off by user stays off');
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: MediaQueryData(
                    size: Size(400, 800),
                    viewPadding: EdgeInsets.only(bottom: 48),
                    padding: EdgeInsets.only(bottom: 48)),
                child: BankSmsSettingsSheet()))));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }

  testWidgets('settings: guide hidden when granted; switch reflects state',
      (tester) async {
    await pumpSettings(tester);
    expect(find.byKey(const ValueKey('bank-sms-guide')), findsNothing);
    expect(find.byKey(const ValueKey('bank-sms-app-settings')), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('bank-sms-switch')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(BankSmsStore.instance.enabled, isTrue);
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('bank-sms-switch')))
            .value,
        isTrue);
  });

  testWidgets(
      'settings: guide + button shown when SMS permission missing, '
      'clear of the navigation bar', (tester) async {
    granted = false;
    await pumpSettings(tester);
    expect(find.byKey(const ValueKey('bank-sms-guide')), findsOneWidget);
    final btn = find.byKey(const ValueKey('bank-sms-app-settings'));
    await tester.ensureVisible(btn);
    await tester.pump();
    expect(tester.getRect(btn).bottom, lessThanOrEqualTo(800 - 48));
  });
}

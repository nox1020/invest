// Fake SMS only (invented banks/amounts); nothing real in this public repo.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/domain/services/bank_sms_parser.dart';
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
  var readGranted = true;
  var statusFails = false;
  var statusHangs = false;
  bool? nativeOn;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BankSmsStore.debugReset();
    PwoStore.instance.debugReset();
    calls.clear();
    BankSmsStore.recordedLookup = null;
    granted = true;
    readGranted = true;
    statusFails = false;
    statusHangs = false;
    nativeOn = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BankSmsStore.channel, (c) async {
      calls.add(c.method);
      switch (c.method) {
        case 'inbox':
          return [sms('بانک ملت\nبرداشت: 1,000,000\nمانده: 5,000,000')];
        case 'takePending':
        case 'takeRejected':
          return <Object?>[];
        case 'getEnabled':
          return nativeOn;
        case 'setEnabled':
          nativeOn = (c.arguments as Map)['on'] as bool;
          return true;
        case 'status':
          if (statusHangs) return Completer<Object?>().future;
          if (statusFails) {
            throw PlatformException(code: 'status_failed');
          }
          return {
            'read': granted && readGranted,
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

  testWidgets('system → تبلیغات: recorded as an ads cost only (offline-first)',
      (tester) async {
    final s = BankSmsStore.instance;
    late BankSmsItem it;
    await tester.runAsync(() async {
      await PwoStore.instance.load();
      await s.setEnabled(true);
      await s.ingest([sms('بانک ملت\nبرداشت: 3,000,000')]);
      it = s.pending.single;
    });
    final y = it.jalali.year, m = it.jalali.month;
    BizStore.instance.debugReset();
    BizStore.instance.debugSet(
        BizSnapshot({
          'year': y,
          'years': [y],
          'trades': [],
          'months': [
            for (var i = 1; i <= 12; i++)
              {'year': y, 'month': i, 'staff': 0.0, 'pwo': 0.0, 'ads': i == m ? 50000.0 : 0.0, 'income': 0.0, 'note': '', 'has_ops': i == m}
          ],
        }),
        account: '0912');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Directionality(
                textDirection: TextDirection.rtl,
                child: BankSmsConfirmSheet(item: it)))));
    await tester.pump();
    expect(find.byKey(const ValueKey('sms-system-kind')), findsNothing);
    await tester.tap(find.text('سیستم'));
    await tester.pump();
    await tester.tap(find.text('تبلیغات'));
    await tester.pump();
    expect(find.byKey(const ValueKey('sms-ads-hint')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('sms-save')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    final q = BizStore.instance.queue.items;
    expect(q, hasLength(1)); // one ads write, no system withdrawal
    expect(q.single.request.path, endsWith('/months/$y/$m'));
    expect(q.single.request.body!['ads'], 350000); // added to existing 50,000
    expect(BizStore.instance.snap.months[m - 1].ads, 350000); // shown at once
    expect(s.pending, isEmpty);
    expect(s.history.first.target, 'ads');
    expect(bankSmsIsRecorded(it.tag, null, PwoStore.instance), isTrue);
    BizStore.instance.debugReset();
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

  test(
      'missing permission: switch still on and persisted; request shown; '
      'auto-clears after grant; off stays off', () async {
    granted = false;
    final s = BankSmsStore.instance;
    expect(await s.tryEnable(), isFalse);
    expect(s.enabled, isTrue);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool(BankSmsStore.kEnabled), isTrue);
    expect(s.wantEnabled, isTrue);
    expect(calls, contains('request'));
    expect(s.diagnostics, contains('RECEIVE NO'));
    granted = true; // user allowed it in Android settings and came back
    await s.recheck();
    expect(s.enabled, isTrue);
    expect(s.wantEnabled, isFalse);
    await s.disable();
    expect(s.enabled, isFalse);
    await s.recheck();
    expect(s.enabled, isFalse, reason: 'turned off by user stays off');
  });

  test('native channel missing entirely: still enables and persists', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BankSmsStore.channel, null);
    final s = BankSmsStore.instance;
    await s.tryEnable();
    expect(s.enabled, isTrue);
    expect(s.diagnostics, contains('native: none'));
  });

  test('status error is surfaced in diagnostics', () async {
    statusFails = true;
    final s = BankSmsStore.instance;
    await s.tryEnable();
    expect(s.enabled, isTrue);
    expect(s.diagnostics, contains('status_failed'));
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

  test('RECEIVE_SMS alone is enough to enable (scan needs READ_SMS)', () async {
    readGranted = false;
    final s = BankSmsStore.instance;
    expect(await s.tryEnable(), isTrue);
    expect(s.enabled, isTrue);
    expect(s.caps.read, isFalse);
    expect(s.caps.denied, isFalse);
  });

  testWidgets(
      'status read error: checklist shown as unknown, no guide, '
      'switch still turns on and persists', (tester) async {
    statusFails = true;
    await pumpSettings(tester);
    expect(find.byKey(const ValueKey('bank-sms-unknown')), findsOneWidget);
    expect(find.text('دریافت پیامک (تشخیص لحظه‌ای)'), findsOneWidget);
    expect(find.byKey(const ValueKey('bank-sms-guide')), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('bank-sms-switch')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(BankSmsStore.instance.enabled, isTrue);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool(BankSmsStore.kEnabled), isTrue);
  });

  testWidgets('granted: checklist always visible with real status',
      (tester) async {
    readGranted = false;
    await pumpSettings(tester);
    expect(find.text('اعلان‌ها'), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded),
        findsNWidgets(2)); // READ + full-screen
    expect(find.byKey(const ValueKey('bank-sms-guide')), findsNothing);
  });

  testWidgets(
      'status never answers: checking… then timeout shown; switch '
      'turns on immediately and persists', (tester) async {
    statusHangs = true;
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BankSmsSettingsSheet())));
    await tester.pump();
    expect(find.byKey(const ValueKey('bank-sms-checking')), findsOneWidget);
    expect(find.byKey(const ValueKey('bank-sms-diag')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bank-sms-switch')));
    await tester.pump();
    expect(BankSmsStore.instance.enabled, isTrue);
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('bank-sms-switch')))
            .value,
        isTrue);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const ValueKey('bank-sms-checking')), findsNothing);
    expect(find.byKey(const ValueKey('bank-sms-unknown')), findsOneWidget);
    expect(find.textContaining('timeout'), findsWidgets);
    final p = await tester.runAsync(SharedPreferences.getInstance);
    expect(p!.getBool(BankSmsStore.kEnabled), isTrue);
  });

  test('restart keeps it on (store recreated)', () async {
    await BankSmsStore.instance.tryEnable();
    expect(nativeOn, isTrue);
    BankSmsStore.debugReset();
    await BankSmsStore.instance.load();
    expect(BankSmsStore.instance.enabled, isTrue);
  });

  test(
      'restart with Flutter prefs lost (process killed before write): '
      'native committed flag wins', () async {
    await BankSmsStore.instance.tryEnable();
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    BankSmsStore.debugReset();
    await BankSmsStore.instance.load();
    expect(BankSmsStore.instance.enabled, isTrue);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool(BankSmsStore.kEnabled), isTrue, reason: 'resynced');
  });

  test('permission denied then restart: still on', () async {
    granted = false;
    await BankSmsStore.instance.tryEnable();
    BankSmsStore.debugReset();
    await BankSmsStore.instance.recheck();
    expect(BankSmsStore.instance.enabled, isTrue);
  });

  test('tap during an in-flight load is not overwritten by the old value',
      () async {
    final s = BankSmsStore.instance;
    final loading = s.load(); // reads "off"
    final tap = s.setEnabled(true);
    await loading;
    await tap;
    expect(s.enabled, isTrue);
    BankSmsStore.debugReset();
    await BankSmsStore.instance.load();
    expect(BankSmsStore.instance.enabled, isTrue);
  });

  test('only an explicit off turns it off, and that survives restart',
      () async {
    await BankSmsStore.instance.tryEnable();
    await BankSmsStore.instance.disable();
    BankSmsStore.debugReset();
    await BankSmsStore.instance.recheck();
    await BankSmsStore.instance.syncOnOpen();
    expect(BankSmsStore.instance.enabled, isFalse);
    expect(nativeOn, isFalse);
  });

  testWidgets(
      'saved SMS disappears at once, card hides, fields deleted, '
      'never offered again after restart', (tester) async {
    final s = BankSmsStore.instance;
    late String fp;
    await tester.runAsync(() async {
      await PwoStore.instance.load();
      await s.setEnabled(true);
      fp = (await s
              .ingest([sms('بانک ملت\nبرداشت: 4,000,000\nمانده: 9,000,000')]))
          .single
          .fp;
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      const BankSmsCard(),
      Expanded(child: BankSmsConfirmSheet(item: s.pending.single)),
    ]))));
    await tester.pump();
    expect(find.byKey(const ValueKey('bank-sms-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('sms-dup')), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('sms-save')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(s.pending, isEmpty);
    expect(find.byKey(const ValueKey('bank-sms-card')), findsNothing);
    expect(calls, contains('cancel'));
    final p = await tester.runAsync(SharedPreferences.getInstance);
    expect(p!.getStringList('bank_sms_pending_v1'), isEmpty);
    // Same SMS again (inbox scan after restart): ignored.
    await tester.runAsync(() async {
      BankSmsStore.debugReset();
      final again = await BankSmsStore.instance
          .ingest([sms('بانک ملت\nبرداشت: 4,000,000\nمانده: 9,000,000')]);
      expect(again, isEmpty);
      expect(BankSmsStore.instance.isHandled(fp), isTrue);
    });
  });

  test('rejected SMS is removed the same way', () async {
    final s = BankSmsStore.instance;
    await s.setEnabled(true);
    final it = (await s.ingest([sms('برداشت: 7,000,000')])).single;
    await s.markHandled(it.fp);
    expect(s.pending, isEmpty);
    expect(await s.ingest([sms('برداشت: 7,000,000')]), isEmpty);
  });

  testWidgets(
      'page: pending ثبت/رد, history, rescan, reset keeps recorded '
      'withdrawals', (tester) async {
    final s = BankSmsStore.instance;
    await tester.runAsync(() async {
      await PwoStore.instance.load();
      await s.setEnabled(true);
      await s.ingest([
        sms('بانک ملت\nبرداشت: 1,500,000\nمانده: 9,000,000'),
        sms('بانک سامان\nبرداشت: 2,200,000\nمانده: 8,000,000', addr: 'Saman'),
      ]);
    });
    await tester.pumpWidget(const MaterialApp(home: BankSmsPage()));
    await tester.pump();
    expect(find.byKey(const ValueKey('bank-sms-page')), findsOneWidget);
    expect(find.textContaining('در انتظار تأیید'), findsOneWidget);
    final first = s.pending.firstWhere((x) => x.toman == 150000);
    final second = s.pending.firstWhere((x) => x.toman == 220000);
    // رد → history (rejected), no SMS text kept.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey('bank-sms-reject-${second.fp}')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(s.pending, hasLength(1));
    expect(s.history.single.status, 'rejected');
    expect(find.text('رد شده'), findsOneWidget);
    // ثبت → confirm sheet → saved in history.
    await tester.tap(find.byKey(ValueKey('bank-sms-save-${first.fp}')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('sms-save')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(s.pending, isEmpty);
    expect(s.history.first.saved, isTrue);
    expect(s.history.first.target, 'personal');
    expect(find.text('ثبت‌شده · شخصی'), findsOneWidget);
    final p = await tester.runAsync(SharedPreferences.getInstance);
    final hist = p!.getStringList('bank_sms_history_v1')!.join();
    expect(hist.contains('برداشت:'), isFalse);
    final txBefore =
        PwoStore.instance.ledger.months.values.expand((m) => m.txs).length;
    expect(txBefore, 1);
    // Reset (danger, with confirmation): local SMS state only.
    await tester.ensureVisible(find.byKey(const ValueKey('bank-sms-reset')));
    await tester.tap(find.byKey(const ValueKey('bank-sms-reset')));
    await tester.pumpAndSettle();
    expect(find.textContaining('روی سرور می‌مانند'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('bank-sms-reset-confirm')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(s.history, isEmpty);
    expect(s.pending, isEmpty);
    expect(s.lastScanMs, 0);
    expect(s.isHandled(first.fp), isFalse);
    expect(calls, contains('reset'));
    expect(PwoStore.instance.ledger.months.values.expand((m) => m.txs).length,
        txBefore,
        reason: 'recorded withdrawals untouched');
    // Rescan offers SMS again.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('bank-sms-rescan')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(s.pending, isNotEmpty);
  });

  testWidgets('header «ریست همه»: dialog then local state cleared',
      (tester) async {
    final s = BankSmsStore.instance;
    await tester.runAsync(() async {
      await s.setEnabled(true);
      final it = (await s.ingest([sms('برداشت: 3,300,000')])).single;
      await s.markHandled(it.fp);
      await s.ingest([sms('برداشت: 4,400,000')]);
    });
    await tester.pumpWidget(const MaterialApp(home: BankSmsPage()));
    await tester.pump();
    final btn = find.byKey(const ValueKey('bank-sms-reset-header'));
    expect(btn, findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: btn),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.text('ریست همه')),
        findsOneWidget);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(find.textContaining('روی سرور می‌مانند'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('bank-sms-reset-confirm')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(s.pending, isEmpty);
    expect(s.history, isEmpty);
    expect(s.enabled, isTrue, reason: 'switch kept');
  });

  testWidgets(
      'saved note carries the SMS tag; after reset the same SMS is '
      'recognised as recorded and never offered (no double entry)',
      (tester) async {
    final s = BankSmsStore.instance;
    const body = 'بانک ملت\nبرداشت: 6,000,000\nمانده: 9,000,000';
    await tester.runAsync(() async {
      await PwoStore.instance.load();
      await s.setEnabled(true);
      await s.ingest([sms(body)]);
    });
    final it = s.pending.single;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: BankSmsConfirmSheet(item: it))));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('sms-save')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    final txs =
        PwoStore.instance.ledger.months.values.expand((m) => m.txs).toList();
    expect(txs.single.note, endsWith(it.tag));
    BankSmsStore.recordedLookup =
        (tag) => bankSmsIsRecorded(tag, null, PwoStore.instance);
    await tester.runAsync(() async {
      await s.reset();
      final again = await s.ingest([sms(body)]);
      expect(again, isEmpty);
    });
    expect(s.pending, isEmpty);
    expect(s.history.single.status, 'recorded');
    // Even if offered by an old sheet, a second save is refused.
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: BankSmsConfirmSheet(item: it))));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('sms-save')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(
        PwoStore.instance.ledger.months.values.expand((m) => m.txs).length, 1);
  });

  testWidgets('«رد همه» clears the pending list in one go', (tester) async {
    final s = BankSmsStore.instance;
    await tester.runAsync(() async {
      await s.setEnabled(true);
      await s.ingest([
        for (var i = 1; i <= 30; i++)
          sms('برداشت: $i,000,000 مانده: 9,000,000'),
      ]);
    });
    expect(s.pending.length, 30);
    await tester.pumpWidget(const MaterialApp(home: BankSmsPage()));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bank-sms-reject-all')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester
          .tap(find.byKey(const ValueKey('bank-sms-reject-all-confirm')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(s.pending, isEmpty);
    expect(s.history.length, 30);
    expect(
        await tester.runAsync(
            () => s.ingest([sms('برداشت: 1,000,000 مانده: 9,000,000')])),
        isEmpty);
  });

  testWidgets('confirm sheet buttons stay above a 48px navigation bar',
      (tester) async {
    final s = BankSmsStore.instance;
    await tester.runAsync(() async {
      await PwoStore.instance.load();
      await s.setEnabled(true);
      await s.ingest([sms('بانک ملت\nبرداشت: 1,000,000\nمانده: 2,000,000')]);
    });
    tester.view.physicalSize = const Size(400, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (c) => Scaffold(
                body: TextButton(
                    onPressed: () => showBankSmsConfirm(c, s.pending.single),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final save = tester.getRect(find.byKey(const ValueKey('sms-save')));
    expect(save.bottom, lessThanOrEqualTo(640 - 48));
    expect(tester.getRect(find.byKey(const ValueKey('sms-reject'))).bottom,
        lessThanOrEqualTo(640 - 48));
  });
}

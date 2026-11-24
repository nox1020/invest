// Fake SMS only. Cashflow index in BankSmsStore: incremental scan, no cap,
// rejected SMS, live deposits, errors and partial permission.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final inbox = <Map<String, Object>>[];
  final sinces = <int>[];
  final methods = <String>[];
  var readGranted = true;
  var cashflowFails = false;
  var rejectedNative = <Object?>[];

  Map<String, Object> sms(String body, DateTime at, {String addr = 'Mellat'}) =>
      {'address': addr, 'body': body, 'date': at.millisecondsSinceEpoch};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BankSmsStore.debugReset();
    inbox.clear();
    sinces.clear();
    methods.clear();
    readGranted = true;
    cashflowFails = false;
    rejectedNative = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BankSmsStore.channel, (c) async {
      methods.add(c.method);
      switch (c.method) {
        case 'cashflowInbox':
          if (cashflowFails) throw PlatformException(code: 'cashflow_failed');
          final since = (c.arguments as Map)['since'] as int;
          sinces.add(since);
          return inbox.where((m) => (m['date'] as int) > since).toList();
        case 'inbox':
          final since = (c.arguments as Map)['since'] as int;
          return inbox
              .where((m) => (m['date'] as int) > since)
              .take(300)
              .toList();
        case 'takePending':
          return <Object?>[];
        case 'takeRejected':
          final r = rejectedNative;
          rejectedNative = [];
          return r;
        case 'getEnabled':
          return true;
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

  Future<BankSmsStore> ready() async {
    final s = BankSmsStore.instance;
    await s.setEnabled(true);
    await s.refreshCaps();
    return s;
  }

  test('no 300 cap: a year of SMS (parsed off the UI isolate) is all counted',
      () async {
    final s = await ready();
    final start = DateTime.now().subtract(const Duration(days: 200));
    for (var i = 0; i < 450; i++) {
      inbox.add(sms('بانک ملت\nبرداشت: 1,000,000\nمانده: ${i + 1},000,000',
          start.add(Duration(hours: i * 5))));
    }
    final moves =
        await s.movementsSince(start.subtract(const Duration(days: 1)));
    expect(moves, hasLength(450));
    expect(methods, contains('cashflowInbox'));
  });

  test('incremental: later scans read only since the last scan', () async {
    final s = await ready();
    final yearStart = DateTime.now().subtract(const Duration(days: 100));
    inbox.add(sms('بانک ملت\nواریز: 2,000,000\nمانده: 3,000,000',
        DateTime.now().subtract(const Duration(days: 50))));
    expect(await s.movementsSince(yearStart), hasLength(1));
    expect(sinces.single, yearStart.millisecondsSinceEpoch);

    inbox.add(
        sms('بانک ملت\nبرداشت: 500,000\nمانده: 2,500,000', DateTime.now()));
    final again = await s.movementsSince(yearStart);
    expect(again, hasLength(2));
    // Second read starts near the previous scan, not at the year start.
    expect(
        sinces.last,
        greaterThan(DateTime.now()
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch));

    // The index survives a restart: still 2 without rereading the year.
    BankSmsStore.debugReset();
    final s2 = await ready();
    sinces.clear();
    expect(await s2.movementsSince(yearStart), hasLength(2));
    expect(sinces.single, greaterThan(yearStart.millisecondsSinceEpoch));
  });

  test('rejected SMS («رد», «رد همه», notification رد) are not counted',
      () async {
    final s = await ready();
    final a =
        sms('بانک ملت\nخرید: 3,000,000\nمانده: 5,000,000', DateTime.now());
    final b =
        sms('بانک ملت\nخرید: 4,000,000\nمانده: 1,000,000', DateTime.now());
    final c =
        sms('بانک ملت\nخرید: 6,000,000\nمانده: 9,000,000', DateTime.now());
    final d =
        sms('بانک ملت\nخرید: 7,000,000\nمانده: 2,000,000', DateTime.now());
    inbox.addAll([a, b, c, d]);
    await s.ingest([a, b]);
    final since = DateTime.now().subtract(const Duration(days: 1));
    expect(await s.movementsSince(since), hasLength(4));

    await s.markHandled(s.pending.firstWhere((x) => x.toman == 300000).fp);
    var moves = await s.movementsSince(since);
    expect(moves.map((m) => m.toman), isNot(contains(300000)));

    await s.rejectAll();
    moves = await s.movementsSince(since);
    expect(moves.map((m) => m.toman), isNot(contains(400000)));

    // Rejected from the notification while the app was closed.
    final fpC =
        (await s.movementsSince(since)).firstWhere((m) => m.toman == 600000).fp;
    rejectedNative = [fpC];
    await s.syncOnOpen();
    moves = await s.movementsSince(since);
    expect(moves.map((m) => m.toman), [700000]);
  });

  test('saved SMS stays counted once', () async {
    final s = await ready();
    final a =
        sms('بانک ملت\nخرید: 3,000,000\nمانده: 5,000,000', DateTime.now());
    inbox.add(a);
    await s.ingest([a]);
    await s.markHandled(s.pending.single.fp, status: 'saved', target: 'system');
    final moves = await s
        .movementsSince(DateTime.now().subtract(const Duration(days: 1)));
    expect(moves, hasLength(1));
  });

  test('a live deposit notifies and counts before it reaches the inbox',
      () async {
    final s = await ready();
    var notified = 0;
    s.addListener(() => notified++);
    final dep = sms('بلو\n۱۰۰,۰۰۰ تومان به حساب شما واریز شد', DateTime.now(),
        addr: 'blu');
    final added = await s.ingest([dep]);
    expect(added, isEmpty); // never offered as a withdrawal
    expect(notified, greaterThan(0));
    final moves = await s
        .movementsSince(DateTime.now().subtract(const Duration(days: 1)));
    expect(moves.single.isIn, isTrue);
  });

  test('scan failure is surfaced; partial permission is reported', () async {
    final s = await ready();
    cashflowFails = true;
    await s.movementsSince(DateTime.now().subtract(const Duration(days: 1)));
    expect(s.cashflowError, 'cashflow_failed');
    cashflowFails = false;
    await s.movementsSince(DateTime.now().subtract(const Duration(days: 1)));
    expect(s.cashflowError, isNull);

    readGranted = false;
    await s.refreshCaps();
    expect(s.smsAvailable, isTrue);
    expect(s.smsInboxUnreadable, isTrue);
    methods.clear();
    await s.movementsSince(DateTime.now().subtract(const Duration(days: 1)));
    expect(methods, isNot(contains('cashflowInbox')));
  });

  test(
      'withdrawal scan (syncOnOpen) still uses the capped inbox and lastScanMs',
      () async {
    final s = await ready();
    inbox.add(
        sms('بانک ملت\nبرداشت: 1,000,000\nمانده: 5,000,000', DateTime.now()));
    final before = s.lastScanMs;
    await s.syncOnOpen();
    expect(methods, contains('inbox'));
    expect(methods, isNot(contains('cashflowInbox')));
    expect(s.lastScanMs, greaterThan(before));
    expect(s.pending, hasLength(1));
    // The cashflow scan never moves lastScanMs.
    final last = s.lastScanMs;
    await s.movementsSince(DateTime.now().subtract(const Duration(days: 3)));
    expect(s.lastScanMs, last);
  });
}

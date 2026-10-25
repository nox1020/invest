import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/ui/pages/permissions_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var granted = false;
  var battery = false;
  final calls = <String>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BankSmsStore.debugReset();
    granted = false;
    battery = false;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BankSmsStore.channel, (c) async {
      calls.add(c.method);
      switch (c.method) {
        case 'status':
          return {
            'read': granted,
            'receive': granted,
            'notify': granted,
            'fullScreen': false,
            'battery': battery,
            'sdk': 34,
          };
        case 'request':
          granted = true;
          return true;
        case 'requestBattery':
          battery = true;
          return null;
        case 'inbox':
        case 'takePending':
        case 'takeRejected':
          return <Object?>[];
      }
      return null;
    });
  });

  Future<void> host(WidgetTester t) async {
    t.view.physicalSize = const Size(420, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (c) => Scaffold(
                body: Center(
                    child: TextButton(
                        onPressed: () => maybeShowPermissionsOnboarding(c),
                        child: const Text('open')))))));
    await t.tap(find.text('open'));
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
  }

  testWidgets(
      'first launch shows the screen; «اجازه بده» requests all and '
      'turns bank SMS on; never shown again', (t) async {
    await host(t);
    expect(find.byKey(const ValueKey('perm-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('perm-fullscreen')), findsOneWidget);
    expect(find.byKey(const ValueKey('perm-restricted')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const ValueKey('perm-sms-state'))).data,
        'داده نشده');
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('perm-allow')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await t.pump();
    expect(calls, containsAll(['request', 'requestBattery']));
    expect(t.widget<Text>(find.byKey(const ValueKey('perm-sms-state'))).data,
        'داده شده');
    expect(BankSmsStore.instance.enabled, isTrue);
    expect(find.byKey(const ValueKey('perm-restricted')), findsNothing);
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('perm-done')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('perm-page')), findsNothing);
    await t.tap(find.text('open'));
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('perm-page')), findsNothing);
  });

  testWidgets('«بعداً» skips without blocking; SMS stays off', (t) async {
    await host(t);
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('perm-later')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('perm-page')), findsNothing);
    expect(BankSmsStore.instance.enabled, isFalse);
    final p = await t.runAsync(SharedPreferences.getInstance);
    expect(p!.getInt('perm_onboarding_seen_v'), kPermOnboardingVersion);
  });

  testWidgets('not shown when the native side is absent', (t) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BankSmsStore.channel, null);
    await host(t);
    expect(find.byKey(const ValueKey('perm-page')), findsNothing);
  });
}

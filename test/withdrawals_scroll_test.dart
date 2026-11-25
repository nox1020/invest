// Vertical scrolling on the «برداشت» tab: reach the last row above the FAB,
// pull-to-refresh with little content, no overflow on small / landscape
// screens, position kept across rebuilds, scroll-to-top on tab re-tap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/home_tabs.dart';
import 'package:invest/ui/pages/withdrawals_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RefreshCountingState extends AppState {
  int refreshes = 0;
  @override
  Future<void> refreshAll({
    bool includeQuotes = true,
    bool fetchSettings = true,
    bool checkApiVersion = true,
  }) async {
    refreshes++;
  }
}

_RefreshCountingState _state({int rows = 0}) {
  final s = _RefreshCountingState()
    ..loading = false
    ..authenticated = true
    ..settings = AppSettings(calendar: AppConfig.calendarGregorian)
    ..withdrawals = [
      for (var i = 0; i < rows; i++)
        Withdrawal(
          id: i + 1,
          amount: 12345678900.0 + i, // 12 billion toman
          note: 'یادداشت بلند برای ردیف شماره ${i + 1} که چند خط می‌شود ' * 2,
          createdAt: '2026-04-01',
          status: i.isEven ? 'completed' : 'pending',
        ),
    ];
  return s;
}

/// Mirrors HomeShell: FAB «ثبت برداشت» at startFloat + bottom navigation.
Widget _shell(AppState state, {double textScale = 1}) {
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('برداشت')),
        body: const WithdrawalsPage(),
        floatingActionButton: FloatingActionButton.extended(
          key: const ValueKey('fab'),
          onPressed: () {},
          icon: const Icon(Icons.south_west_rounded),
          label: const Text('ثبت برداشت'),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: 1,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.dashboard), label: 'داشبورد'),
            BottomNavigationBarItem(
                icon: Icon(Icons.payments), label: 'برداشت'),
            BottomNavigationBarItem(
                icon: Icon(Icons.swap_horiz), label: 'معاملات'),
          ],
        ),
      ),
    ),
  );
}

Future<void> _size(WidgetTester t, Size s) async {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Finder get _scrollable => find
    .descendant(
        of: find.byType(WithdrawalsPage), matching: find.byType(Scrollable))
    .first;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BankSmsStore.debugReset();
    PwoStore.instance.debugSetLoaded();
    CurrencyMode.reset();
  });

  for (final c in [
    (name: 'small phone 320×568', size: const Size(320, 568), scale: 1.0),
    (name: 'small phone, large text', size: const Size(320, 568), scale: 1.3),
    (name: 'landscape 640×320', size: const Size(640, 320), scale: 1.0),
  ]) {
    testWidgets('${c.name}: no overflow, last row clears the FAB', (t) async {
      await _size(t, c.size);
      final state = _state(rows: 40);
      await t.pumpWidget(_shell(state, textScale: c.scale));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);

      final pos = t.state<ScrollableState>(_scrollable).position;
      pos.jumpTo(pos.maxScrollExtent);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final last = find.text('#40');
      expect(last, findsOneWidget);
      final fabTop = t.getRect(find.byKey(const ValueKey('fab'))).top;
      // The whole last tile (its amount row and note) sits above the FAB.
      final tile = find.byKey(const ValueKey('withdrawal-tile-40'));
      final bottom = tile.evaluate().isEmpty
          ? t.getRect(last).bottom
          : t.getRect(tile).bottom;
      expect(bottom, lessThanOrEqualTo(fabTop));
    });
  }

  testWidgets('pull-to-refresh works when the content is short', (t) async {
    await _size(t, const Size(400, 3000)); // everything fits, nothing to scroll
    final state = _state(rows: 0);
    await t.pumpWidget(_shell(state));
    await t.pumpAndSettle();
    final g =
        await t.startGesture(t.getTopLeft(_scrollable) + const Offset(200, 40));
    for (var i = 0; i < 50; i++) {
      await g.moveBy(const Offset(0, 40));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(state.refreshes, 1);
  });

  testWidgets('scroll position survives rebuilds and data refreshes',
      (t) async {
    await _size(t, const Size(360, 640));
    final state = _state(rows: 30);
    await t.pumpWidget(_shell(state));
    await t.pumpAndSettle();
    final pos = t.state<ScrollableState>(_scrollable).position;
    pos.jumpTo(1500);
    await t.pumpAndSettle();
    state.withdrawals = [...state.withdrawals];
    state.notifyListeners();
    PwoStore.instance.notifyListeners();
    await t.pumpAndSettle();
    expect(t.state<ScrollableState>(_scrollable).position.pixels, 1500);
  });

  testWidgets('re-tapping the «برداشت» tab scrolls back to the top', (t) async {
    await _size(t, const Size(360, 640));
    final state = _state(rows: 30);
    await t.pumpWidget(_shell(state));
    await t.pumpAndSettle();
    final pos = t.state<ScrollableState>(_scrollable).position;
    pos.jumpTo(2000);
    await t.pumpAndSettle();
    homeTabReselect.fire(HomeTabs.dashboard); // other tab: ignored
    await t.pumpAndSettle();
    expect(pos.pixels, 2000);
    homeTabReselect.fire(HomeTabs.withdrawals);
    await t.pumpAndSettle();
    expect(pos.pixels, 0);
  });

  testWidgets('long history is built lazily', (t) async {
    await _size(t, const Size(360, 640));
    await t.pumpWidget(_shell(_state(rows: 500)));
    await t.pumpAndSettle();
    expect(find.text('#500', skipOffstage: false), findsNothing);
  });
}

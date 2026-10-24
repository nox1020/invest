import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/dashboard_page.dart';
import 'package:invest/ui/widgets/dash_speed_dial.dart';
import 'package:provider/provider.dart';

class _Obs extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
}

const _ids = ['qa-trade', 'qa-check', 'qa-withdraw', 'qa-project', 'qa-export'];

Widget _host({required Widget home, NavigatorObserver? obs}) => MaterialApp(
      navigatorObservers: [if (obs != null) obs],
      builder: (c, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: home,
    );

void main() {
  testWidgets('dial opens, scrim closes, back closes', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_host(
      home: Scaffold(
        body: DashSpeedDial(
          actions: [
            for (final id in _ids)
              SpeedDialAction(
                  id: id, icon: Icons.add, label: id, onTap: () => tapped++),
          ],
          child: ListView(children: const [SizedBox(height: 3000)]),
        ),
      ),
    ));
    for (final id in _ids) {
      expect(find.byKey(ValueKey(id)), findsNothing);
    }
    expect(find.bySemanticsLabel('میان‌برها'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fab-main')));
    await tester.pumpAndSettle();
    for (final id in _ids) {
      expect(find.byKey(ValueKey(id)), findsOneWidget);
    }
    expect(find.bySemanticsLabel('بستن میان‌برها'), findsWidgets);

    await tester.tapAt(const Offset(400, 100)); // scrim
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qa-trade')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('fab-main')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qa-trade')), findsNothing);
    expect(find.byKey(const ValueKey('fab-main')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fab-main')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('qa-withdraw')));
    await tester.pumpAndSettle();
    expect(tapped, 1);
    expect(find.byKey(const ValueKey('qa-withdraw')), findsNothing);
  });

  testWidgets('dial is pinned bottom-left and hides on scroll down',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(
      home: Scaffold(
        body: DashSpeedDial(
          actions: const [],
          child: ListView(children: const [SizedBox(height: 3000)]),
        ),
      ),
    ));
    final r = tester.getRect(find.byKey(const ValueKey('fab-main')));
    expect(r.left, lessThan(40));
    expect(r.bottom, greaterThan(700));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final hidden = tester.getRect(find.byKey(const ValueKey('fab-main')));
    expect(hidden.top, greaterThan(r.top + 50));
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('fab-main'))).top,
        closeTo(r.top, 1));
  });

  testWidgets('dashboard shortcut navigates to projects page', (tester) async {
    final obs = _Obs();
    final state = AppState()
      ..loading = false
      ..authenticated = true
      ..settings = AppSettings(calendar: AppConfig.calendarGregorian)
      ..assets = [
        Asset(
            id: 1,
            name: 'Gold',
            symbol: 'GOLD',
            quantity: 1,
            avgBuyPrice: 1,
            currentPrice: 2),
      ];
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: _host(obs: obs, home: const Scaffold(body: DashboardPage())),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('میان‌بر'), findsNothing); // old section removed
    final before = obs.pushed.length;
    await tester.tap(find.byKey(const ValueKey('fab-main')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.byKey(const ValueKey('qa-project')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(obs.pushed.length, before + 1);
    expect(find.byKey(const ValueKey('qa-project')), findsNothing);
  });
}

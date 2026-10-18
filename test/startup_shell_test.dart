import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/app.dart';
import 'package:invest/domain/services/notification_service.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/dashboard_page.dart';
import 'package:provider/provider.dart';

void main() {
  test('notification icon is a bare drawable so startup cannot abort', () {
    const name = NotificationService.androidNotificationIcon;
    expect(name, 'ic_stat_invest');
    expect(name.contains('@'), isFalse);
    expect(name.contains('/'), isFalse);
    expect(
      File('android/app/src/main/res/drawable/$name.png').existsSync(),
      isTrue,
    );
    final keep = File('android/app/src/main/res/raw/keep.xml').readAsStringSync();
    expect(keep.contains('@drawable/$name'), isTrue);
  });

  testWidgets('first frame is the loading screen before init finishes',
      (tester) async {
    final state = AppState();
    expect(state.loading, isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const InvestApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('empty home still builds the cheque card', (tester) async {
    final state = AppState()
      ..loading = false
      ..authenticated = true;

    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('پورتفوی خالی است'), findsOneWidget);
    expect(find.text('مدیریت چک‌ها'), findsOneWidget);
  });
}

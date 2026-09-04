import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/ui/widgets/connection_status_title.dart';

void main() {
  Widget wrap(AppConnectionStatus status) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: ConnectionStatusTitle(
            pageTitle: 'داشبورد',
            status: status,
          ),
        ),
      ),
    );
  }

  test('resolve prefers updating over offline', () {
    expect(
      AppConnectionStatus.resolve(offline: true, updating: true),
      AppConnectionStatus.updating,
    );
    expect(
      AppConnectionStatus.resolve(offline: true, updating: false),
      AppConnectionStatus.offline,
    );
    expect(
      AppConnectionStatus.resolve(offline: false, updating: false),
      AppConnectionStatus.connected,
    );
  });

  testWidgets('shows connected subtitle', (tester) async {
    await tester.pumpWidget(wrap(AppConnectionStatus.connected));
    expect(find.text('داشبورد'), findsOneWidget);
    expect(find.text('متصل'), findsOneWidget);
  });

  testWidgets('shows offline subtitle', (tester) async {
    await tester.pumpWidget(wrap(AppConnectionStatus.offline));
    expect(find.text('آفلاین'), findsOneWidget);
    expect(find.text('متصل'), findsNothing);
  });

  testWidgets('shows updating subtitle', (tester) async {
    await tester.pumpWidget(wrap(AppConnectionStatus.updating));
    expect(find.text('در حال به‌روزرسانی...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}

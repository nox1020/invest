import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/services/dashboard_digest.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_compact.dart';

PwoMonthSummary _s(double spent, double target) => PwoMonthSummary(
      month: PwoMonth(year: 1405, month: 8, amounts: {'a': spent}),
      target: target,
      people: const [],
      monthsWithData: 1,
      monthsWithin: 1,
      average: spent,
      overStreak: 0,
    );

Widget _wrap(Widget w) => MaterialApp(
    home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: w)));

void main() {
  testWidgets('PWO progress: at target is green, above is red', (t) async {
    await t.pumpWidget(_wrap(PwoProgressCard(summary: _s(100, 100), monthLabel: 'آبان', onTap: () {})));
    expect(find.byKey(const ValueKey('cd-pwo-ok')), findsOneWidget);
    var bar = t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.color, AppTheme.positive);
    await t.pumpWidget(_wrap(PwoProgressCard(summary: _s(130, 100), monthLabel: 'آبان', onTap: () {})));
    expect(find.byKey(const ValueKey('cd-pwo-over')), findsOneWidget);
    bar = t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.color, AppTheme.negative);
    expect(bar.value, 1.0);
  });

  testWidgets('today strip hides when empty and chips open their page', (t) async {
    await t.pumpWidget(_wrap(const TodayStrip(chips: [])));
    expect(find.byKey(const ValueKey('cd-today-strip')), findsNothing);
    var tapped = '';
    await t.pumpWidget(_wrap(TodayStrip(chips: [
      TodayChip(id: 'sms', icon: Icons.sms, label: '3 پیامک', color: Colors.red, onTap: () => tapped = 'sms'),
    ])));
    await t.tap(find.byKey(const ValueKey('cd-chip-sms')));
    expect(tapped, 'sms');
  });

  test('signed numbers are isolated left-to-right', () {
    expect(signedPct(6.2).startsWith('\u2066+'), isTrue);
    expect(signedToman(-1200000).startsWith('\u2066'), isTrue);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/services/dashboard_digest.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_sections.dart';

Future<Color?> _checkColor(WidgetTester t, double amount) async {
  final l = PwoLedger(target: 100, months: {
    pwoMonthKey(1405, 7):
        PwoMonth(year: 1405, month: 7, amounts: {'p0': amount}),
  });
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DashPwoCard(
          summary: PwoMonthSummary.of(l),
          withdrawable: 0,
          capBaseLabel: '',
          onOpenPwo: () {},
          onOpenWithdrawals: () {},
        ),
      ),
    ),
  ));
  return t.widget<Icon>(find.byKey(const ValueKey('dash-pwo-check'))).color;
}

void main() {
  testWidgets('dashboard PWO card: check icon green within, red above',
      (t) async {
    expect(await _checkColor(t, 80), AppTheme.positive);
    expect(await _checkColor(t, 100), AppTheme.positive); // equal = within
    expect(await _checkColor(t, 130), AppTheme.negative);
    expect(find.text('ماه‌های در محدودهٔ هدف'), findsOneWidget);
  });
}

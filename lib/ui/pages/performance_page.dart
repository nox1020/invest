import 'package:flutter/material.dart';
import 'package:invest/ui/pages/biz_page.dart';

/// «عملکرد» tab: the office monthly table (income, staff, PWO, ads, net),
/// formerly the second tab of «ملک و دفتر».
class PerformancePage extends StatelessWidget {
  const PerformancePage({super.key});

  @override
  Widget build(BuildContext context) => const Directionality(
        textDirection: TextDirection.rtl,
        child: BizMonthsPane(key: ValueKey('perf-months')),
      );
}

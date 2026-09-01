import 'package:flutter_test/flutter_test.dart';
import 'package:invest/services/refresh_coordinator.dart';

void main() {
  test('merges overlapping refresh flags into one follow-up run', () async {
    final coordinator = RefreshCoordinator();
    final runs = <RefreshPlan>[];

    Future<void> action(RefreshPlan plan) async {
      runs.add(plan);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }

    final first = coordinator.run(
      action,
      includeQuotes: false,
      fetchSettings: true,
    );

    await coordinator.run(
      action,
      includeQuotes: true,
      fetchSettings: false,
      checkApiVersion: false,
    );

    await first;

    expect(runs.length, 2);
    expect(runs[0].includeQuotes, isFalse);
    expect(runs[0].fetchSettings, isTrue);
    expect(runs[1].includeQuotes, isTrue);
    expect(runs[1].fetchSettings, isFalse);
    expect(runs[1].checkApiVersion, isFalse);
  });

  test('merge skips settings when any caller opts out', () {
    final merged = RefreshPlan(fetchSettings: true, checkApiVersion: true)
        .merge(RefreshPlan(fetchSettings: false, checkApiVersion: false));
    expect(merged.fetchSettings, isFalse);
    expect(merged.checkApiVersion, isFalse);
    expect(
      RefreshPlan(includeQuotes: false)
          .merge(RefreshPlan(includeQuotes: true))
          .includeQuotes,
      isTrue,
    );
  });
}

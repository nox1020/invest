import 'package:flutter_test/flutter_test.dart';
import 'package:invest/services/refresh_coordinator.dart';

void main() {
  test('merges overlapping refresh flags into one follow-up run', () async {
    final coordinator = RefreshCoordinator();
    final runs = <RefreshPlan>[];

    final first = coordinator.run(
      (plan) async {
        runs.add(plan);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await coordinator.run(
          (inner) async => runs.add(inner),
          includeQuotes: true,
          fetchSettings: false,
        );
      },
      includeQuotes: false,
      fetchSettings: true,
    );

    await coordinator.run(
      (plan) async => runs.add(plan),
      includeQuotes: true,
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
}

import 'package:flutter_test/flutter_test.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/withdrawal_allowance.dart';

void main() {
  const j = AppConfig.calendarJalali;
  const g = AppConfig.calendarGregorian;

  Withdrawal w(double a, String at, {String status = 'completed'}) =>
      Withdrawal(amount: a, note: '', status: status, createdAt: at);

  test('PWO this year reduces remaining annual quota and capacity', () {
    final a = WithdrawalAllowance.compute(
      realizedPnl: 1e9,
      openTrades: const [],
      closedTrades: const [],
      withdrawals: [w(1e8, '2026-10-01')],
      annualPct: 10,
      calendar: j,
      asOfIso: '2026-10-22',
      pwoYearWithdrawn: 2e8,
      pwoAllTime: 3e8,
    );
    expect(a.yearWithdrawn, 3e8);
    expect(a.withdrawnAllTime, 4e8);
    expect(a.remainingRealized, 6e8);
    expect(a.pwoYearWithdrawn, 2e8);
  });

  test('capacity never negative when PWO exceeds cap/profit', () {
    final a = WithdrawalAllowance.compute(
      realizedPnl: 1e8,
      openTrades: const [],
      closedTrades: const [],
      withdrawals: const [],
      annualPct: 10,
      calendar: j,
      asOfIso: '2026-10-22',
      pwoYearWithdrawn: 5e9,
      pwoAllTime: 5e9,
    );
    expect(a.available, 0);
    expect(a.remainingAnnual, 0);
    expect(a.excessOverRealized, 49e8);
    expect(a.usedAnnualFraction, 1);
  });

  test('garbage/short/Jalali-text dates do not crash and count this year', () {
    final s = WithdrawalAllowance.withdrawnInYear(
      withdrawals: [w(1, '1405'), w(2, 'abc'), w(4, '1405/07/01'), w(8, '')],
      yearKey: '1405',
      calendar: j,
      asOfIso: '2026-10-22',
    );
    expect(s, 15);
  });

  test('UTC stamp just after Nowruz midnight (Tehran) is in the new year', () {
    // 1405-01-01 00:30 Tehran = 2026-03-20T21:00Z (UTC+3:30).
    final key = WithdrawalAllowance.withdrawnInYear(
      withdrawals: [w(7, '2026-03-20T21:00:00Z')],
      yearKey: '1405',
      calendar: j,
      asOfIso: '2026-10-22',
    );
    // Box/CI timezone may differ; only assert when local offset is Tehran's.
    final off = DateTime.parse('2026-03-20T21:00:00Z').toLocal().timeZoneOffset;
    if (off == const Duration(hours: 3, minutes: 30)) expect(key, 7);
  });

  test('PWO Jalali month maps to Gregorian year by month start', () {
    expect(WithdrawalAllowance.pwoYearKey(1405, 10, j), '1405');
    expect(WithdrawalAllowance.pwoYearKey(1404, 10, g), '2025'); // Dey 1404 starts Dec 2025
    expect(WithdrawalAllowance.pwoYearKey(1404, 11, g), '2026');
  });
}

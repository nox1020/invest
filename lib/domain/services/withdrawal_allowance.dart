import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/utils/dates.dart';

/// Snapshot of how much profit may be withdrawn this calendar year.
///
/// Annual cap = [annualPct]% of total portfolio inflows (sum of trade buy
/// costs). Available cash is the lesser of remaining realized profit and
/// remaining annual quota.
class WithdrawalAllowance {
  const WithdrawalAllowance({
    required this.inflows,
    required this.annualPct,
    required this.annualCap,
    required this.yearWithdrawn,
    required this.withdrawnAllTime,
    required this.realizedPnl,
    required this.remainingRealized,
    required this.remainingAnnual,
    required this.available,
    required this.yearKey,
    required this.calendar,
  });

  final double inflows;
  final int annualPct;
  final double annualCap;
  final double yearWithdrawn;
  final double withdrawnAllTime;
  final double realizedPnl;
  final double remainingRealized;
  final double remainingAnnual;
  final double available;
  final String yearKey;
  final String calendar;

  double get usedAnnualFraction {
    if (annualCap <= 1e-9) return yearWithdrawn > 1e-9 ? 1 : 0;
    final v = yearWithdrawn / annualCap;
    if (v < 0) return 0;
    if (v > 1) return 1;
    return v;
  }

  static double totalInflows({
    required Iterable<Trade> openTrades,
    required Iterable<Trade> closedTrades,
  }) {
    var sum = 0.0;
    for (final t in openTrades) {
      sum += t.buyCost;
    }
    for (final t in closedTrades) {
      sum += t.buyCost;
    }
    return sum;
  }

  static double withdrawnInYear({
    required Iterable<Withdrawal> withdrawals,
    required String yearKey,
    required String calendar,
    String? asOfIso,
  }) {
    final asOf = asOfIso ?? todayIso();
    var sum = 0.0;
    for (final w in withdrawals) {
      if (w.status == 'rejected') continue;
      final iso = w.createdAt.trim().isEmpty ? asOf : w.createdAt;
      if (yearPeriodKey(iso, calendar) != yearKey) continue;
      sum += w.amount;
    }
    return sum;
  }

  static WithdrawalAllowance compute({
    required double realizedPnl,
    required Iterable<Trade> openTrades,
    required Iterable<Trade> closedTrades,
    required Iterable<Withdrawal> withdrawals,
    required int annualPct,
    required String calendar,
    String? asOfIso,
    String? yearKey,
  }) {
    final asOf = asOfIso ?? todayIso();
    final key = yearKey ?? yearPeriodKey(asOf, calendar);
    final pct = AppSettings.clampAnnualWithdrawalPct(annualPct);
    final inflows = totalInflows(
      openTrades: openTrades,
      closedTrades: closedTrades,
    );
    var allTime = 0.0;
    for (final w in withdrawals) {
      if (w.status == 'rejected') continue;
      allTime += w.amount;
    }
    final yearWithdrawn = withdrawnInYear(
      withdrawals: withdrawals,
      yearKey: key,
      calendar: calendar,
      asOfIso: asOf,
    );
    final annualCap = inflows * pct / 100.0;
    final remainingRealized = computeWithdrawableAmount(
      realizedPnl: realizedPnl,
      withdrawnTotal: allTime,
    );
    final remainingAnnual = annualCap > yearWithdrawn
        ? annualCap - yearWithdrawn
        : 0.0;
    final available = remainingRealized < remainingAnnual
        ? remainingRealized
        : remainingAnnual;
    return WithdrawalAllowance(
      inflows: inflows,
      annualPct: pct,
      annualCap: annualCap,
      yearWithdrawn: yearWithdrawn,
      withdrawnAllTime: allTime,
      realizedPnl: realizedPnl,
      remainingRealized: remainingRealized,
      remainingAnnual: remainingAnnual,
      available: available,
      yearKey: key,
      calendar: calendar,
    );
  }

  static String yearCaption(String yearKey, String calendar) {
    if (calendar == AppConfig.calendarGregorian) return yearKey;
    return 'سال $yearKey';
  }
}

import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:shamsi_date/shamsi_date.dart';

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
    this.pwoYearWithdrawn = 0,
    this.pwoAllTime = 0,
    this.capBase = AppConfig.capBaseInflows,
    double? capBaseAmount,
    this.capBaseFallback = false,
  }) : capBaseAmount = capBaseAmount ?? inflows;

  /// Which base the annual cap uses (see [AppConfig.capBases]).
  final String capBase;

  /// Amount the [annualPct] is applied to.
  final double capBaseAmount;

  /// The chosen base had no value (e.g. no live NAV); fell back to inflows.
  final bool capBaseFallback;

  /// PWO personal withdrawals included in [yearWithdrawn] / [withdrawnAllTime].
  final double pwoYearWithdrawn;
  final double pwoAllTime;

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

  /// Withdrawals beyond realized profit. A loss counts as zero profit.
  double get excessOverRealized {
    final base = realizedPnl > 0 ? realizedPnl : 0.0;
    final v = withdrawnAllTime - base;
    return v > 0 ? v : 0;
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

  /// Calendar year of a withdrawal timestamp, in the user's local time.
  /// Null when the value cannot be read as a date.
  static String? _yearOf(String raw, String calendar) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    DateTime? d;
    if (v.contains('T')) {
      // UTC stamps (…Z) near midnight belong to the local day.
      d = DateTime.tryParse(v)?.toLocal();
    }
    if (d == null) {
      final iso = tryNormalizeToIso(v);
      if (iso != null) d = DateTime.tryParse(iso);
    }
    if (d == null) return null;
    if (calendar == AppConfig.calendarJalali) {
      return Jalali.fromDateTime(d).year.toString().padLeft(4, '0');
    }
    return d.year.toString().padLeft(4, '0');
  }

  /// Year key of a Jalali PWO month in [calendar] (Gregorian: month start).
  static String pwoYearKey(int jYear, int jMonth, String calendar) {
    if (calendar == AppConfig.calendarJalali) {
      return jYear.toString().padLeft(4, '0');
    }
    return Jalali(jYear, jMonth, 1).toDateTime().year.toString().padLeft(4, '0');
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
      // Unknown/unreadable date: count it this year (never over-state room).
      final y = _yearOf(w.createdAt, calendar) ?? yearPeriodKey(asOf, calendar);
      if (y != yearKey) continue;
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
    double pwoYearWithdrawn = 0,
    double pwoAllTime = 0,
    String capBase = AppConfig.capBaseInflows,
    double? navValue,
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
    final pwoYear = pwoYearWithdrawn.isFinite && pwoYearWithdrawn > 0 ? pwoYearWithdrawn : 0.0;
    final pwoAll = pwoAllTime.isFinite && pwoAllTime > pwoYear ? pwoAllTime : pwoYear;
    allTime += pwoAll;
    final yearWithdrawnTotal = yearWithdrawn + pwoYear;
    var base = AppSettings.parseCapBase(capBase);
    var baseAmount = inflows;
    var fallback = false;
    if (base == AppConfig.capBaseOpenCost) {
      baseAmount = openTrades.fold(0.0, (a, t) => a + t.buyCost);
    } else if (base == AppConfig.capBaseNav) {
      if (navValue != null && navValue.isFinite && navValue > 0) {
        baseAmount = navValue;
      } else {
        fallback = true;
        base = AppConfig.capBaseInflows;
      }
    }
    final annualCap = baseAmount * pct / 100.0;
    final remainingRealized = computeWithdrawableAmount(
      realizedPnl: realizedPnl,
      withdrawnTotal: allTime,
    );
    final remainingAnnual = annualCap > yearWithdrawnTotal
        ? annualCap - yearWithdrawnTotal
        : 0.0;
    final available = remainingRealized < remainingAnnual
        ? remainingRealized
        : remainingAnnual;
    return WithdrawalAllowance(
      inflows: inflows,
      annualPct: pct,
      annualCap: annualCap,
      yearWithdrawn: yearWithdrawnTotal,
      withdrawnAllTime: allTime,
      realizedPnl: realizedPnl,
      remainingRealized: remainingRealized,
      remainingAnnual: remainingAnnual,
      available: available,
      yearKey: key,
      calendar: calendar,
      pwoYearWithdrawn: pwoYear,
      pwoAllTime: pwoAll,
      capBase: base,
      capBaseAmount: baseAmount,
      capBaseFallback: fallback,
    );
  }

  static String yearCaption(String yearKey, String calendar) {
    if (calendar == AppConfig.calendarGregorian) return yearKey;
    return 'سال $yearKey';
  }
}

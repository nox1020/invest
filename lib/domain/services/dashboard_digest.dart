import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/money.dart';

enum DashAlertKind { chequeOverdue, chequeBounced, chequeDueSoon, pwoBelowTarget, unpriced, bizMismatch }

/// One line in «نیازمند توجه». Severity 2 = act now, 1 = check, 0 = info.
class DashAlert {
  const DashAlert({required this.kind, required this.severity, required this.title, required this.sub});
  final DashAlertKind kind;
  final int severity;
  final String title;
  final String sub;
}

/// An open cheque with its days to due (negative = overdue).
class UpcomingCheque {
  const UpcomingCheque(this.check, this.daysLeft);
  final BankCheck check;
  final int daysLeft;
}

DateTime? _day(String? iso) {
  if (iso == null || iso.length < 10) return null;
  final d = DateTime.tryParse(iso.substring(0, 10));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// Open cheques still waiting on a due date, nearest first (overdue on top).
List<UpcomingCheque> upcomingCheques(Iterable<BankCheck> checks, {required String today, int limit = 3}) {
  final t = _day(today);
  if (t == null) return const [];
  final out = <UpcomingCheque>[];
  for (final c in checks) {
    if (c.status != checkStatusPending || c.isArchived) continue;
    final due = _day(c.dueDate);
    if (due == null) continue;
    out.add(UpcomingCheque(c, due.difference(t).inDays));
  }
  out.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
  return out.take(limit).toList();
}

/// Latest PWO month with any entry, against the monthly target.
class PwoMonthSummary {
  const PwoMonthSummary({
    required this.month,
    required this.target,
    required this.people,
    required this.monthsWithData,
    required this.monthsMet,
    required this.average,
    required this.belowStreak,
  });

  final PwoMonth month;
  final double target;

  /// Active people (plus anyone with an amount this month) and their totals.
  final List<({String name, double amount})> people;
  final int monthsWithData;
  final int monthsMet;
  final double average;

  /// Consecutive latest months below target (0 when the latest met it).
  final int belowStreak;

  double get total => month.total;
  double get ratio => target <= 0 ? 0 : total / target;
  bool get met => target > 0 && total >= target;

  static PwoMonthSummary? of(PwoLedger ledger) {
    final months = [
      for (final m in ledger.months.values)
        if (m.total > 0) m,
    ]..sort((a, b) => a.key.compareTo(b.key));
    if (months.isEmpty) return null;
    final last = months.last;
    final target = ledger.target;
    final ids = <String>[
      for (final p in ledger.people)
        if (p.active || last.of(p.id) > 0) p.id,
    ];
    var streak = 0;
    for (final m in months.reversed) {
      if (target > 0 && m.total < target) {
        streak++;
      } else {
        break;
      }
    }
    return PwoMonthSummary(
      month: last,
      target: target,
      people: [
        for (final id in ids) (name: ledger.personById(id)?.name ?? id, amount: last.of(id)),
      ],
      monthsWithData: months.length,
      monthsMet: target <= 0 ? 0 : months.where((m) => m.total >= target).length,
      average: months.fold<double>(0, (a, m) => a + m.total) / months.length,
      belowStreak: streak,
    );
  }
}

/// Everything that needs a look, most urgent first. Real data only: a source
/// that is missing simply adds nothing.
List<DashAlert> dashboardAlerts({
  required Iterable<BankCheck> checks,
  required String today,
  List<Asset> unpriced = const [],
  PwoMonthSummary? pwo,
  String pwoMonthLabel = '',
  int bizMismatchMonths = 0,
  int dueSoonDays = 7,
}) {
  final out = <DashAlert>[];
  final t = _day(today);
  var overdue = 0, overdueSum = 0.0;
  final soon = <UpcomingCheque>[];
  var bounced = 0;
  if (t != null) {
    for (final c in checks) {
      if (c.isArchived) continue;
      if (c.isBounced) bounced++;
      if (c.status != checkStatusPending) continue;
      final due = _day(c.dueDate);
      if (due == null) continue;
      final d = due.difference(t).inDays;
      if (d < 0) {
        overdue++;
        overdueSum += c.amount;
      } else if (d <= dueSoonDays) {
        soon.add(UpcomingCheque(c, d));
      }
    }
  }
  if (overdue > 0) {
    out.add(DashAlert(
      kind: DashAlertKind.chequeOverdue,
      severity: 2,
      title: '$overdue چک سررسیدگذشته',
      sub: 'جمع ${formatCompactToman(overdueSum)} — وضعیتش را در چک‌ها ثبت کنید',
    ));
  }
  if (bounced > 0) {
    out.add(DashAlert(
      kind: DashAlertKind.chequeBounced,
      severity: 2,
      title: '$bounced چک برگشتی',
      sub: 'هنوز باز است و در بدهی یا طلب حساب می‌شود',
    ));
  }
  soon.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
  for (final u in soon.take(2)) {
    final c = u.check;
    final when = u.daysLeft == 0 ? 'امروز' : '${u.daysLeft} روز دیگر';
    out.add(DashAlert(
      kind: DashAlertKind.chequeDueSoon,
      severity: c.isPayable ? 2 : 1,
      title: '${c.isPayable ? 'چک پرداختی' : 'چک دریافتی'} ${formatCompactToman(c.amount)} · $when',
      sub: c.isPayable
          ? 'موجودی حساب را برای سررسید آماده کنید'
          : (c.counterparty.trim().isEmpty ? 'وصول را پیگیری کنید' : 'از ${c.counterparty.trim()}'),
    ));
  }
  if (pwo != null && pwo.target > 0 && !pwo.met) {
    final gap = ((1 - pwo.ratio) * 100).round();
    out.add(DashAlert(
      kind: DashAlertKind.pwoBelowTarget,
      severity: 1,
      title: 'برداشت $pwoMonthLabel $gap٪ زیر هدف'.replaceAll('  ', ' '),
      sub: '${formatCompactToman(pwo.total)} از ${formatCompactToman(pwo.target)}'
          '${pwo.belowStreak > 1 ? ' · ${pwo.belowStreak} ماه پیاپی زیر هدف' : ''}',
    ));
  }
  if (unpriced.isNotEmpty) {
    final names = unpriced.map((a) => a.symbol.trim().isEmpty ? a.name : a.symbol).take(2).join('، ');
    out.add(DashAlert(
      kind: DashAlertKind.unpriced,
      severity: 1,
      title: '${unpriced.length} دارایی بدون قیمت زنده',
      sub: '$names با قیمت خرید یا صفر حساب شد — قیمت را به‌روز کنید',
    ));
  }
  if (bizMismatchMonths > 0) {
    out.add(DashAlert(
      kind: DashAlertKind.bizMismatch,
      severity: 0,
      title: '$bizMismatchMonths ماه مغایرت در دفتر',
      sub: 'سود معاملهٔ ملک با درآمد ثبت‌شدهٔ دفتر نمی‌خواند',
    ));
  }
  out.sort((a, b) => b.severity.compareTo(a.severity));
  return out;
}

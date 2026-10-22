import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:shamsi_date/shamsi_date.dart';

/// Definitions shown to the user next to the warning.
const doubleCountDefinitions =
    '«دفتر برداشت» = پولی که از سود سرمایه‌گذاری برداشته شده. '
    '«PWO» = برداشت شخصی ماهانهٔ افراد. هر دو از سقف برداشت کم می‌شوند؛ '
    'پس هر پرداخت را فقط در یکی ثبت کنید.';

/// A completed withdrawal whose amount equals a PWO amount in the same
/// Jalali month — probably the same money recorded twice. Warning only.
class DoubleCountHit {
  DoubleCountHit({
    required this.withdrawal,
    required this.year,
    required this.month,
    required this.match,
    required this.pwoAmount,
  });
  final Withdrawal withdrawal;
  final int year;
  final int month;
  final String match;
  final double pwoAmount;

  /// Stable id for "not a duplicate" dismissal.
  String get key =>
      '${withdrawal.id ?? withdrawal.createdAt}|${withdrawal.amount.round()}|$year/$month';
}

Jalali? _jalaliOf(String createdAt) {
  final d = DateTime.tryParse(createdAt.trim());
  if (d == null) return null;
  return Jalali.fromDateTime(d.isUtc ? d.toLocal() : d);
}

bool _same(double a, double b) {
  if (a <= 0 || b <= 0) return false;
  final tol = (a.abs() * 0.005).clamp(1000.0, double.infinity);
  return (a - b).abs() <= tol;
}

List<DoubleCountHit> findDoubleCounts(
    Iterable<Withdrawal> withdrawals, PwoLedger ledger) {
  final names = {for (final p in ledger.people) p.id: p.name};
  final out = <DoubleCountHit>[];
  for (final w in withdrawals) {
    if (!w.isCompleted || !(w.amount > 0)) continue;
    final j = _jalaliOf(w.createdAt);
    if (j == null) continue;
    final m = ledger.months[pwoMonthKey(j.year, j.month)];
    if (m == null || !(m.total > 0)) continue;
    String? what;
    double amt = 0;
    for (final t in m.txs) {
      if (_same(w.amount, t.amount)) {
        what = 'برداشت تکی ${names[t.personId] ?? ''}'.trim();
        amt = t.amount;
        break;
      }
    }
    if (what == null) {
      for (final id in m.personIds) {
        for (final v in [m.of(id), m.baseOf(id)]) {
          if (_same(w.amount, v)) {
            what = 'مبلغ ماه ${names[id] ?? ''}'.trim();
            amt = v;
            break;
          }
        }
        if (what != null) break;
      }
    }
    if (what == null && _same(w.amount, m.total)) {
      what = 'جمع PWO ماه';
      amt = m.total;
    }
    if (what != null) {
      out.add(DoubleCountHit(
          withdrawal: w, year: j.year, month: j.month, match: what, pwoAmount: amt));
    }
  }
  return out;
}

import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/bank_sms_parser.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:shamsi_date/shamsi_date.dart';

/// Window for the withdrawals-tab cashflow card.
enum CashflowPeriod { day, month, year }

/// One already-parsed bank SMS movement used for period totals.
class CashflowSms {
  const CashflowSms({
    required this.at,
    required this.toman,
    required this.isIn,
    this.tag = '',
    this.bank = '',
  });

  final DateTime at;
  final double toman;
  final bool isIn;
  final String tag;
  final String bank;

  factory CashflowSms.fromItem(BankSmsItem it) => CashflowSms(
        at: it.at,
        toman: it.toman,
        isIn: it.isIn,
        tag: it.tag,
        bank: it.bank,
      );
}

/// Totals for one Jalali day / month / year.
class PeriodCashflow {
  const PeriodCashflow({
    this.smsIn = 0,
    this.smsOut = 0,
    this.txIn = 0,
    this.txOut = 0,
    this.smsUnavailable = false,
  });

  final double smsIn;
  final double smsOut;
  final double txIn;
  final double txOut;

  /// SMS is off, or the device has no receive/read permission.
  final bool smsUnavailable;

  double get inflow => smsIn + txIn;
  double get outflow => smsOut + txOut;
  double get net => inflow - outflow;
}

/// Inclusive start of the selected Jalali [period] containing [now].
DateTime cashflowPeriodStart(CashflowPeriod period, DateTime now) {
  final n = Jalali.fromDateTime(now);
  final j = switch (period) {
    CashflowPeriod.day => Jalali(n.year, n.month, n.day),
    CashflowPeriod.month => Jalali(n.year, n.month, 1),
    CashflowPeriod.year => Jalali(n.year, 1, 1),
  };
  return j.toDateTime();
}

bool isInCashflowPeriod(DateTime at, CashflowPeriod period, DateTime now) {
  final a = Jalali.fromDateTime(at);
  final n = Jalali.fromDateTime(now);
  return switch (period) {
    CashflowPeriod.day =>
      a.year == n.year && a.month == n.month && a.day == n.day,
    CashflowPeriod.month => a.year == n.year && a.month == n.month,
    CashflowPeriod.year => a.year == n.year,
  };
}

bool cashflowMonthInPeriod(
  int year,
  int month,
  CashflowPeriod period,
  DateTime now,
) {
  if (period == CashflowPeriod.day) return false;
  final n = Jalali.fromDateTime(now);
  if (period == CashflowPeriod.month) {
    return year == n.year && month == n.month;
  }
  return year == n.year;
}

/// «امروز ۳ آذر ۱۴۰۵» / «آذر ۱۴۰۵» / «۱۴۰۵» — digits stay Latin; UI applies [fa].
String cashflowPeriodCaption(CashflowPeriod period, DateTime now) {
  final j = Jalali.fromDateTime(now);
  final month = jalaliMonthNamesFa[j.month - 1];
  return switch (period) {
    CashflowPeriod.day => 'امروز ${j.day} $month ${j.year}',
    CashflowPeriod.month => '$month ${j.year}',
    CashflowPeriod.year => '${j.year}',
  };
}

String cashflowNetLabel(CashflowPeriod period) => switch (period) {
      CashflowPeriod.day => 'تراز این روز',
      CashflowPeriod.month => 'تراز این ماه',
      CashflowPeriod.year => 'تراز این سال',
    };

final _smsTagRe = RegExp(r'#[0-9a-f]{8}');

DateTime? _dateOf(String? raw) {
  final iso = tryNormalizeToIso(raw);
  if (iso == null) return null;
  return parseIsoDate(iso);
}

bool _sameJalaliDay(DateTime a, DateTime b) {
  final x = Jalali.fromDateTime(a);
  final y = Jalali.fromDateTime(b);
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// Combine bank SMS and recorded transactions for [period] containing [now].
///
/// SMS is preferred when a withdrawal / PWO note carries that SMS tag.
/// Untagged same-amount/same-day pairs are both counted.
PeriodCashflow computePeriodCashflow({
  required CashflowPeriod period,
  required DateTime now,
  required List<CashflowSms> sms,
  required List<Withdrawal> withdrawals,
  required List<BankCheck> checks,
  required PwoLedger pwo,
  bool smsUnavailable = false,
}) {
  final source = smsUnavailable ? const <CashflowSms>[] : sms;
  var smsIn = 0.0;
  var smsOut = 0.0;
  for (final it in source) {
    if (!isInCashflowPeriod(it.at, period, now)) continue;
    if (it.isIn) {
      smsIn += it.toman;
    } else {
      smsOut += it.toman;
    }
  }

  final tags = <String>{
    for (final it in source)
      if (it.tag.isNotEmpty) it.tag,
  };

  bool skipTagged(String note, double amount, DateTime at) {
    for (final tag in tags) {
      if (BankSmsItem.noteHasTag(note, tag)) return true;
    }
    if (!_smsTagRe.hasMatch(note)) return false;
    for (final it in source) {
      if ((it.toman - amount).abs() < 1 && _sameJalaliDay(it.at, at)) {
        return true;
      }
    }
    return false;
  }

  var txIn = 0.0;
  var txOut = 0.0;

  for (final w in withdrawals) {
    if (!w.isCompleted) continue;
    final at = _dateOf(w.createdAt);
    if (at == null || !isInCashflowPeriod(at, period, now)) continue;
    if (skipTagged(w.note, w.amount, at)) continue;
    txOut += w.amount;
  }

  for (final c in checks) {
    if (c.status == checkStatusBounced || c.status == checkStatusCancelled) {
      continue;
    }
    if (c.payments.isNotEmpty) {
      for (final p in c.payments) {
        final at = _dateOf(p.paidAt);
        if (at == null || !isInCashflowPeriod(at, period, now)) continue;
        if (skipTagged(p.note, p.amount, at)) continue;
        if (c.isReceivable) {
          txIn += p.amount;
        } else if (c.isPayable) {
          txOut += p.amount;
        }
      }
      continue;
    }
    if (c.status == checkStatusEndorsed) continue;
    if (c.status != checkStatusCleared) continue;
    final raw =
        (c.settledDate ?? '').trim().isNotEmpty ? c.settledDate : c.dueDate;
    final at = _dateOf(raw);
    if (at == null || !isInCashflowPeriod(at, period, now)) continue;
    if (skipTagged(c.note, c.amount, at)) continue;
    if (c.isReceivable) {
      txIn += c.amount;
    } else if (c.isPayable) {
      txOut += c.amount;
    }
  }

  for (final month in pwo.months.values) {
    if (!cashflowMonthInPeriod(month.year, month.month, period, now)) {
      continue;
    }
    for (final amount in month.amounts.values) {
      txOut += amount;
    }
    for (final t in month.txs) {
      // Month-level: use the first day of that Jalali month as the date.
      final at = Jalali(month.year, month.month, 1).toDateTime();
      if (skipTagged(t.note, t.amount, at)) continue;
      txOut += t.amount;
    }
  }

  return PeriodCashflow(
    smsIn: smsIn,
    smsOut: smsOut,
    txIn: txIn,
    txOut: txOut,
    smsUnavailable: smsUnavailable,
  );
}

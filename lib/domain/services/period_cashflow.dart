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

/// An SMS and an untagged app row with the same direction and amount on the
/// same or adjacent day: both are counted, but it may be one payment twice.
class CashflowDupPair {
  const CashflowDupPair({
    required this.isIn,
    required this.toman,
    required this.smsAt,
    required this.smsBank,
    required this.rowAt,
    required this.rowLabel,
  });

  final bool isIn;
  final double toman;
  final DateTime smsAt;
  final String smsBank;
  final DateTime rowAt;
  final String rowLabel;
}

/// Totals for one Jalali day / month / year.
class PeriodCashflow {
  const PeriodCashflow({
    this.smsIn = 0,
    this.smsOut = 0,
    this.txIn = 0,
    this.txOut = 0,
    this.smsUnavailable = false,
    this.duplicates = const [],
    this.pwoMonthOnly = false,
  });

  final double smsIn;
  final double smsOut;
  final double txIn;
  final double txOut;

  /// SMS is off, or the device has no receive/read permission.
  final bool smsUnavailable;

  /// Likely double entries (SMS vs untagged app row); both stay counted.
  final List<CashflowDupPair> duplicates;

  /// Day view only: this month has PWO entries without a day, which are
  /// counted in the month/year views but cannot be placed on a day.
  final bool pwoMonthOnly;

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

final _smsTagRe = RegExp(r'#([0-9a-f]{8})(?![0-9a-zA-Z])');

/// Local calendar instant of a stored date.
///
/// * `YYYY-MM-DD` / Jalali `1405/09/03` → that local day.
/// * Timestamps with a zone (`…Z`, `+03:30`) → converted to local time.
/// * Timestamps with a time but no zone are UTC: the app writes them with
///   `nowIso()` (UTC, zone suffix stripped), so a withdrawal at 01:00 Tehran
///   is not pushed back to the previous day / month / year.
DateTime? cashflowDateOf(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  final ts = RegExp(r'^(\d{4})-\d{2}-\d{2}[T ]\d{2}:\d{2}').firstMatch(t);
  if (ts != null && int.parse(ts.group(1)!) > 1500) {
    final norm = t.replaceFirst(' ', 'T');
    final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(norm);
    final parsed = DateTime.tryParse(hasZone ? norm : '${norm}Z');
    if (parsed != null) return parsed.toLocal();
  }
  final iso = tryNormalizeToIso(t);
  if (iso == null) return null;
  return parseIsoDate(iso);
}

int _dayNumber(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

class _Row {
  _Row(this.at, this.amount, this.isIn, this.label);
  final DateTime at;
  final double amount;
  final bool isIn;
  final String label;
}

String _short(String s, [int max = 28]) {
  final t = s.replaceAll(RegExp(r'#[0-9a-f]{8}'), '').trim();
  return t.length > max ? '${t.substring(0, max)}…' : t;
}

/// Combine bank SMS and recorded transactions for [period] containing [now].
///
/// A withdrawal / PWO / cheque note carrying the exact tag of an SMS in [sms]
/// is represented by that SMS (counted once, on the SMS date). Untagged rows
/// are always counted; same-amount SMS within ±1 day are reported in
/// [PeriodCashflow.duplicates] instead of being dropped.
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
  final inPeriod = <CashflowSms>[];
  for (final it in source) {
    if (!isInCashflowPeriod(it.at, period, now)) continue;
    inPeriod.add(it);
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

  /// Exact tag match only: a note that merely looks like it has a tag, or
  /// whose SMS is not in [source], is counted as a normal row.
  bool representedBySms(String note) {
    if (tags.isEmpty || !note.contains('#')) return false;
    for (final m in _smsTagRe.allMatches(note)) {
      if (tags.contains('#${m.group(1)}')) return true;
    }
    return false;
  }

  var txIn = 0.0;
  var txOut = 0.0;
  final rows = <_Row>[];

  void addRow(DateTime at, double amount, bool isIn, String label) {
    if (amount <= 0) return;
    if (isIn) {
      txIn += amount;
    } else {
      txOut += amount;
    }
    rows.add(_Row(at, amount, isIn, label));
  }

  for (final w in withdrawals) {
    if (!w.isCompleted) continue;
    final at = cashflowDateOf(w.createdAt);
    if (at == null || !isInCashflowPeriod(at, period, now)) continue;
    if (representedBySms(w.note)) continue;
    final n = _short(w.note);
    addRow(at, w.amount, false, n.isEmpty ? 'برداشت' : 'برداشت · $n');
  }

  for (final c in checks) {
    if (!c.isReceivable && !c.isPayable) continue;
    final isIn = c.isReceivable;
    final who =
        _short(c.counterparty.trim().isNotEmpty ? c.counterparty : c.note);
    final label = who.isEmpty ? c.kindLabel : '${c.kindLabel} · $who';
    // Recorded payments are real money whatever the cheque became later
    // (bounced / cancelled / endorsed after a partial payment).
    var paid = 0.0;
    DateTime? lastPaid;
    for (final p in c.payments) {
      paid += p.amount;
      final at = cashflowDateOf(p.paidAt);
      if (at == null) continue;
      if (lastPaid == null || at.isAfter(lastPaid)) lastPaid = at;
      if (!isInCashflowPeriod(at, period, now)) continue;
      if (representedBySms(p.note) || representedBySms(c.note)) continue;
      addRow(at, p.amount, isIn, label);
    }
    // Cleared: whatever was not recorded as a payment moved on settlement.
    if (c.status != checkStatusCleared) continue;
    final rest = c.amount - paid;
    if (rest <= 0.5) continue;
    final raw =
        (c.settledDate ?? '').trim().isNotEmpty ? c.settledDate : c.dueDate;
    final at = cashflowDateOf(raw) ?? lastPaid;
    if (at == null || !isInCashflowPeriod(at, period, now)) continue;
    if (representedBySms(c.note)) continue;
    addRow(at, rest, isIn, label);
  }

  var pwoMonthOnly = false;
  final n = Jalali.fromDateTime(now);
  for (final month in pwo.months.values) {
    if (period == CashflowPeriod.day) {
      // PWO rows have a month but no day: they cannot be put on a day.
      if (month.year == n.year &&
          month.month == n.month &&
          (month.amounts.values.any((a) => a > 0) ||
              month.txs.any((t) => !representedBySms(t.note)))) {
        pwoMonthOnly = true;
      }
      continue;
    }
    if (!cashflowMonthInPeriod(month.year, month.month, period, now)) {
      continue;
    }
    for (final amount in month.amounts.values) {
      txOut += amount;
    }
    for (final t in month.txs) {
      if (representedBySms(t.note)) continue;
      txOut += t.amount;
    }
  }

  return PeriodCashflow(
    smsIn: smsIn,
    smsOut: smsOut,
    txIn: txIn,
    txOut: txOut,
    smsUnavailable: smsUnavailable,
    duplicates: _findDuplicates(inPeriod, rows),
    pwoMonthOnly: pwoMonthOnly,
  );
}

/// SMS ↔ app row pairs: same direction, amount within 1 toman, day ±1.
/// Hash-indexed (no SMS × row loop); each SMS pairs at most once.
List<CashflowDupPair> _findDuplicates(List<CashflowSms> sms, List<_Row> rows) {
  if (sms.isEmpty || rows.isEmpty) return const [];
  final byKey = <String, List<CashflowSms>>{};
  for (final it in sms) {
    byKey.putIfAbsent('${it.isIn}|${it.toman.round()}', () => []).add(it);
  }
  final used = <CashflowSms>{};
  final out = <CashflowDupPair>[];
  for (final r in rows) {
    final list = byKey['${r.isIn}|${r.amount.round()}'];
    if (list == null) continue;
    final day = _dayNumber(r.at);
    for (final it in list) {
      if (used.contains(it)) continue;
      if ((_dayNumber(it.at) - day).abs() > 1) continue;
      used.add(it);
      out.add(CashflowDupPair(
        isIn: r.isIn,
        toman: it.toman,
        smsAt: it.at,
        smsBank: it.bank,
        rowAt: r.at,
        rowLabel: r.label,
      ));
      break;
    }
  }
  return out;
}
